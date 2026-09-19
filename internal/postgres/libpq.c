#include "libpq_internal.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static void lunanexa_pg_connection_finalize(void *pointer) {
  lunanexa_pg_connection_t *value = (lunanexa_pg_connection_t *)pointer;
  if (value->connection != NULL) {
    PQfinish(value->connection);
    value->connection = NULL;
  }
}

static void lunanexa_pg_result_finalize(void *pointer) {
  lunanexa_pg_result_t *value = (lunanexa_pg_result_t *)pointer;
  if (value->result != NULL) {
    PQclear(value->result);
    value->result = NULL;
  }
  if (value->owned_error != NULL) {
    free(value->owned_error);
    value->owned_error = NULL;
  }
}

lunanexa_pg_result_t *lunanexa_pg_result_adopt_error(
  PGconn *connection,
  PGresult *result,
  char *owned_error
) {
  lunanexa_pg_result_t *output =
    (lunanexa_pg_result_t *)moonbit_make_external_object(
      lunanexa_pg_result_finalize,
      sizeof(PGconn *) + sizeof(PGresult *) + sizeof(char *)
    );
  output->connection = connection;
  output->result = result;
  output->owned_error = owned_error;
  return output;
}

lunanexa_pg_result_t *lunanexa_pg_result_adopt(
  PGconn *connection,
  PGresult *result
) {
  return lunanexa_pg_result_adopt_error(connection, result, NULL);
}

static moonbit_bytes_t lunanexa_pg_copy_bytes(const char *value, size_t length) {
  moonbit_bytes_t output = moonbit_make_bytes((int32_t)length, 0);
  if (length > 0 && value != NULL) {
    memcpy(output, value, length);
  }
  return output;
}

MOONBIT_FFI_EXPORT
lunanexa_pg_connection_t *lunanexa_pg_connect(moonbit_bytes_t connection_url) {
  lunanexa_pg_connection_t *value =
    (lunanexa_pg_connection_t *)moonbit_make_external_object(
      lunanexa_pg_connection_finalize,
      sizeof(PGconn *)
    );
  value->connection = PQconnectdb((const char *)connection_url);
  return value;
}

MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_connection_ok(lunanexa_pg_connection_t *value) {
  return value != NULL && value->connection != NULL &&
    PQstatus(value->connection) == CONNECTION_OK;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t lunanexa_pg_connection_error(lunanexa_pg_connection_t *value) {
  if (value == NULL || value->connection == NULL) {
    const char *message = "PostgreSQL connection is unavailable";
    return lunanexa_pg_copy_bytes(message, strlen(message));
  }
  const char *message = PQerrorMessage(value->connection);
  return lunanexa_pg_copy_bytes(message, message == NULL ? 0 : strlen(message));
}

MOONBIT_FFI_EXPORT
void lunanexa_pg_close(lunanexa_pg_connection_t *value) {
  if (value != NULL && value->connection != NULL) {
    PQfinish(value->connection);
    value->connection = NULL;
  }
}

static int32_t lunanexa_pg_read_length(const uint8_t *value) {
  return (int32_t)(((uint32_t)value[0] << 24) |
    ((uint32_t)value[1] << 16) |
    ((uint32_t)value[2] << 8) |
    (uint32_t)value[3]);
}

MOONBIT_FFI_EXPORT
lunanexa_pg_result_t *lunanexa_pg_execute(
  lunanexa_pg_connection_t *connection,
  moonbit_bytes_t sql,
  moonbit_bytes_t encoded_parameters,
  int32_t parameter_count
) {
  PGconn *handle = connection == NULL ? NULL : connection->connection;
  if (handle == NULL || parameter_count < 0 || parameter_count > 64) {
    return lunanexa_pg_result_adopt(handle, NULL);
  }

  if (parameter_count == 0) {
    return lunanexa_pg_result_adopt(handle, PQexec(handle, (const char *)sql));
  }

  const char **values = NULL;
  int32_t *lengths = NULL;
  PGresult *result = NULL;
  if (lunanexa_pg_parse_parameters(
        encoded_parameters, parameter_count, &values, &lengths)) {
    result = PQexecParams(
      handle, (const char *)sql, parameter_count, NULL, values, lengths, NULL, 0
    );
  }
  lunanexa_pg_release_parameters(values, lengths, parameter_count);
  return lunanexa_pg_result_adopt(handle, result);
}

int32_t lunanexa_pg_parse_parameters(
  moonbit_bytes_t encoded_parameters,
  int32_t parameter_count,
  const char ***values_out,
  int32_t **lengths_out
) {
  const char **values =
    (const char **)calloc((size_t)parameter_count, sizeof(char *));
  char **owned = (char **)calloc((size_t)parameter_count, sizeof(char *));
  int32_t *lengths =
    (int32_t *)calloc((size_t)parameter_count, sizeof(int32_t));
  if (values == NULL || owned == NULL || lengths == NULL) {
    free(values);
    free(owned);
    free(lengths);
    return 0;
  }

  const uint8_t *cursor = (const uint8_t *)encoded_parameters;
  size_t remaining = (size_t)Moonbit_array_length(encoded_parameters);
  int valid = 1;
  for (int32_t index = 0; index < parameter_count; index += 1) {
    if (remaining < 4) {
      valid = 0;
      break;
    }
    int32_t length = lunanexa_pg_read_length(cursor);
    cursor += 4;
    remaining -= 4;
    if (length == -1) {
      values[index] = NULL;
      continue;
    }
    if (length < 0 || (size_t)length > remaining) {
      valid = 0;
      break;
    }
    owned[index] = (char *)malloc((size_t)length + 1);
    if (owned[index] == NULL) {
      valid = 0;
      break;
    }
    memcpy(owned[index], cursor, (size_t)length);
    owned[index][length] = '\0';
    values[index] = owned[index];
    lengths[index] = length;
    cursor += length;
    remaining -= (size_t)length;
  }
  if (remaining != 0) {
    valid = 0;
  }
  if (!valid) {
    for (int32_t index = 0; index < parameter_count; index += 1) {
      free(owned[index]);
    }
    free(values);
    free(owned);
    free(lengths);
    return 0;
  }
  /* The owned strings are reachable through `values`, so the ownership array
     itself can go; release walks `values` and frees each non-NULL entry. */
  free(owned);
  *values_out = values;
  *lengths_out = lengths;
  return 1;
}

void lunanexa_pg_release_parameters(
  const char **values,
  int32_t *lengths,
  int32_t parameter_count
) {
  if (values != NULL) {
    for (int32_t index = 0; index < parameter_count; index += 1) {
      free((void *)values[index]);
    }
    free((void *)values);
  }
  free(lengths);
}

/* Distinguishes "a statement finished" from "the handle is NULL", which the
   pooled path uses because a worker reports completion through a pipe and the
   result object is built afterwards on the MoonBit thread. */
MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_result_present(lunanexa_pg_result_t *value) {
  return value == NULL ? 0 : 1;
}

MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_result_ok(lunanexa_pg_result_t *value) {
  if (value == NULL || value->result == NULL) {
    return 0;
  }
  ExecStatusType status = PQresultStatus(value->result);
  return status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t lunanexa_pg_result_error(lunanexa_pg_result_t *value) {
  const char *message = NULL;
  if (value != NULL && value->result != NULL) {
    message = PQresultErrorMessage(value->result);
  }
  if ((message == NULL || message[0] == '\0') && value != NULL &&
      value->owned_error != NULL) {
    message = value->owned_error;
  }
  if ((message == NULL || message[0] == '\0') && value != NULL &&
      value->connection != NULL) {
    message = PQerrorMessage(value->connection);
  }
  if (message == NULL || message[0] == '\0') {
    message = "PostgreSQL query failed";
  }
  return lunanexa_pg_copy_bytes(message, strlen(message));
}

MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_row_count(lunanexa_pg_result_t *value) {
  return value == NULL || value->result == NULL ? 0 : PQntuples(value->result);
}

MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_column_count(lunanexa_pg_result_t *value) {
  return value == NULL || value->result == NULL ? 0 : PQnfields(value->result);
}

MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_is_null(
  lunanexa_pg_result_t *value,
  int32_t row,
  int32_t column
) {
  if (value == NULL || value->result == NULL || row < 0 || column < 0 ||
      row >= PQntuples(value->result) || column >= PQnfields(value->result)) {
    return 1;
  }
  return PQgetisnull(value->result, row, column);
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t lunanexa_pg_value(
  lunanexa_pg_result_t *value,
  int32_t row,
  int32_t column
) {
  if (lunanexa_pg_is_null(value, row, column)) {
    return lunanexa_pg_copy_bytes("", 0);
  }
  const char *cell = PQgetvalue(value->result, row, column);
  int32_t length = PQgetlength(value->result, row, column);
  return lunanexa_pg_copy_bytes(cell, (size_t)length);
}

MOONBIT_FFI_EXPORT
int64_t lunanexa_pg_affected_rows(lunanexa_pg_result_t *value) {
  if (value == NULL || value->result == NULL) {
    return 0;
  }
  const char *count = PQcmdTuples(value->result);
  return count == NULL || count[0] == '\0' ? 0 : strtoll(count, NULL, 10);
}
