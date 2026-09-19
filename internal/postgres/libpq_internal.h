#ifndef LUNANEXA_PG_INTERNAL_H
#define LUNANEXA_PG_INTERNAL_H

#include "moonbit.h"

#if __has_include(<libpq-fe.h>)
#include <libpq-fe.h>
#elif __has_include(<postgresql/libpq-fe.h>)
#include <postgresql/libpq-fe.h>
#else
#error "libpq headers are required to build LunaNexa PostgreSQL support"
#endif

/* Owns one libpq connection. */
typedef struct {
  PGconn *connection;
} lunanexa_pg_connection_t;

/* Owns one result. `connection` is borrowed and only read for error text when
   the result itself carries no message; `owned_error` is freed with the
   result. A pooled worker fills `owned_error` on the worker thread so the
   event loop never touches a connection another thread may be resetting. */
typedef struct {
  PGconn *connection;
  PGresult *result;
  char *owned_error;
} lunanexa_pg_result_t;

/* Allocates a MoonBit result object. Must be called from the MoonBit thread:
   the pool hands raw PGresult pointers back to it rather than allocating from
   a worker thread. */
lunanexa_pg_result_t *lunanexa_pg_result_adopt(PGconn *connection, PGresult *result);

/* As above, taking ownership of a malloc'd error message as well. */
lunanexa_pg_result_t *lunanexa_pg_result_adopt_error(
  PGconn *connection,
  PGresult *result,
  char *owned_error
);

/* Copies an encoded parameter block into `values`/`lengths`, or returns 0 when
   the block is malformed. The caller owns the allocation and frees it with
   lunanexa_pg_release_parameters. */
int32_t lunanexa_pg_parse_parameters(
  moonbit_bytes_t encoded_parameters,
  int32_t parameter_count,
  const char ***values_out,
  int32_t **lengths_out
);

void lunanexa_pg_release_parameters(
  const char **values,
  int32_t *lengths,
  int32_t parameter_count
);

#endif
