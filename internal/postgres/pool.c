/* Asynchronous PostgreSQL driver.
 *
 * libpq is a blocking C library and the control plane runs on a
 * single-threaded cooperative event loop, so calling PQexecParameters from a
 * request path stalls every other task in flight. Each worker in this pool
 * owns one libpq connection and runs at most one statement at a time on its
 * own thread; finishing a statement writes one byte to a pipe the MoonBit side
 * awaits, so the event loop only ever waits on a file descriptor.
 *
 * The worker never allocates a MoonBit object and never reads MoonBit memory:
 * submit copies the statement and its parameters into malloc'd buffers, and
 * take builds the result object back on the MoonBit thread. */

#include "libpq_internal.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define LUNANEXA_PG_MAX_WORKERS 32

typedef struct {
  char *sql;
  char **values;
  int32_t *lengths;
  int32_t count;
} lunanexa_pg_job_t;

typedef struct {
  pthread_t thread;
  pthread_mutex_t lock;
  pthread_cond_t cond;
  int wake_read;
  int wake_write;
  char *url;
  PGconn *connection;
  lunanexa_pg_job_t job;
  int has_job;
  int stop;
  int started;
  PGresult *result;
  char *error;
  int32_t connected;
  int32_t completed;
  int32_t taken;
} lunanexa_pg_worker_t;

typedef struct {
  int32_t count;
  lunanexa_pg_worker_t *workers;
} lunanexa_pg_pool_t;

static int32_t lunanexa_pg_set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0) {
    return 0;
  }
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}

static void lunanexa_pg_job_free(lunanexa_pg_job_t *job) {
  free(job->sql);
  job->sql = NULL;
  if (job->values != NULL) {
    for (int32_t index = 0; index < job->count; index += 1) {
      free(job->values[index]);
    }
    free(job->values);
    job->values = NULL;
  }
  free(job->lengths);
  job->lengths = NULL;
  job->count = 0;
}

/* Signals completion. The pipe holds at most one unconsumed byte because a
   worker is only handed another statement after its previous one was taken,
   but a lost wake-up would hang the caller forever, so a full pipe is retried
   rather than dropped. */
static void lunanexa_pg_worker_signal(lunanexa_pg_worker_t *worker) {
  char byte = 1;
  for (int attempt = 0; attempt < 1000; attempt += 1) {
    ssize_t written = write(worker->wake_write, &byte, 1);
    if (written == 1 || (written < 0 && errno != EAGAIN)) {
      return;
    }
    struct timespec pause = { 0, 1000000 };
    nanosleep(&pause, NULL);
  }
}

static void lunanexa_pg_worker_connect(lunanexa_pg_worker_t *worker) {
  if (worker->connection == NULL) {
    worker->connection = PQconnectdb(worker->url);
    return;
  }
  if (PQstatus(worker->connection) != CONNECTION_OK) {
    /* A reset drops any session state, including advisory locks. Callers that
       depend on session state observe a different backend_pid and stand down,
       which is the same outcome as the previous behaviour of reporting a
       broken connection as "not current". */
    PQreset(worker->connection);
  }
}

static void *lunanexa_pg_worker_main(void *argument) {
  lunanexa_pg_worker_t *worker = (lunanexa_pg_worker_t *)argument;
  pthread_mutex_lock(&worker->lock);
  for (;;) {
    while (!worker->has_job && !worker->stop) {
      pthread_cond_wait(&worker->cond, &worker->lock);
    }
    if (worker->stop) {
      break;
    }
    lunanexa_pg_job_t job = worker->job;
    worker->has_job = 0;
    worker->job.sql = NULL;
    worker->job.values = NULL;
    worker->job.lengths = NULL;
    worker->job.count = 0;
    pthread_mutex_unlock(&worker->lock);

    lunanexa_pg_worker_connect(worker);
    PGresult *result = NULL;
    if (worker->connection != NULL &&
        PQstatus(worker->connection) == CONNECTION_OK) {
      if (job.count == 0) {
        result = PQexec(worker->connection, job.sql);
      } else {
        result = PQexecParams(
          worker->connection,
          job.sql,
          job.count,
          NULL,
          (const char *const *)job.values,
          job.lengths,
          NULL,
          0
        );
      }
    }
    lunanexa_pg_job_free(&job);

    char *error = NULL;
    int32_t connected = 0;
    if (worker->connection != NULL) {
      connected = PQstatus(worker->connection) == CONNECTION_OK;
      if (result == NULL) {
        /* Copied here because only the event loop may read a connection that
           no worker is touching, and only it may allocate MoonBit objects. */
        const char *text = PQerrorMessage(worker->connection);
        if (text != NULL && text[0] != '\0') {
          size_t length = strlen(text);
          error = (char *)malloc(length + 1);
          if (error != NULL) {
            memcpy(error, text, length + 1);
          }
        }
      }
    }

    pthread_mutex_lock(&worker->lock);
    worker->result = result;
    worker->error = error;
    worker->connected = connected;
    worker->completed += 1;
    lunanexa_pg_worker_signal(worker);
  }
  pthread_mutex_unlock(&worker->lock);
  return NULL;
}

static void lunanexa_pg_pool_finalize(void *pointer) {
  lunanexa_pg_pool_t *pool = (lunanexa_pg_pool_t *)pointer;
  if (pool->workers == NULL) {
    return;
  }
  for (int32_t index = 0; index < pool->count; index += 1) {
    lunanexa_pg_worker_t *worker = &pool->workers[index];
    if (worker->started) {
      pthread_mutex_lock(&worker->lock);
      worker->stop = 1;
      pthread_cond_signal(&worker->cond);
      pthread_mutex_unlock(&worker->lock);
      pthread_join(worker->thread, NULL);
    }
    if (worker->connection != NULL) {
      PQfinish(worker->connection);
      worker->connection = NULL;
    }
    if (worker->result != NULL) {
      PQclear(worker->result);
      worker->result = NULL;
    }
    free(worker->error);
    worker->error = NULL;
    lunanexa_pg_job_free(&worker->job);
    if (worker->wake_write >= 0) {
      /* The read end is owned by the MoonBit RawFd once it is handed out, so
         only close it when that never happened. */
      close(worker->wake_write);
      worker->wake_write = -1;
    }
    if (worker->wake_read >= 0) {
      close(worker->wake_read);
      worker->wake_read = -1;
    }
    pthread_cond_destroy(&worker->cond);
    pthread_mutex_destroy(&worker->lock);
    free(worker->url);
  }
  free(pool->workers);
  pool->workers = NULL;
}

MOONBIT_FFI_EXPORT
lunanexa_pg_pool_t *lunanexa_pg_pool_create(
  moonbit_bytes_t connection_url,
  int32_t workers
) {
  /* sizeof of the struct itself: a hand-summed size ignores the padding
     between the count and the pointer and corrupts the heap. */
  lunanexa_pg_pool_t *pool =
    (lunanexa_pg_pool_t *)moonbit_make_external_object(
      lunanexa_pg_pool_finalize,
      sizeof(lunanexa_pg_pool_t)
    );
  pool->count = 0;
  pool->workers = NULL;
  if (workers <= 0 || workers > LUNANEXA_PG_MAX_WORKERS ||
      connection_url == NULL) {
    return pool;
  }
  lunanexa_pg_worker_t *array =
    (lunanexa_pg_worker_t *)calloc((size_t)workers, sizeof(lunanexa_pg_worker_t));
  if (array == NULL) {
    return pool;
  }
  pool->workers = array;
  pool->count = workers;
  for (int32_t index = 0; index < workers; index += 1) {
    lunanexa_pg_worker_t *worker = &array[index];
    worker->wake_read = -1;
    worker->wake_write = -1;
    worker->result = NULL;
    worker->connection = NULL;
    worker->started = 0;
    if (pthread_mutex_init(&worker->lock, NULL) != 0) {
      pool->count = index;
      return pool;
    }
    if (pthread_cond_init(&worker->cond, NULL) != 0) {
      pthread_mutex_destroy(&worker->lock);
      pool->count = index;
      return pool;
    }
    int fds[2];
    if (pipe(fds) != 0) {
      pthread_cond_destroy(&worker->cond);
      pthread_mutex_destroy(&worker->lock);
      pool->count = index;
      return pool;
    }
    worker->wake_read = fds[0];
    worker->wake_write = fds[1];
    if (!lunanexa_pg_set_nonblocking(worker->wake_read) ||
        !lunanexa_pg_set_nonblocking(worker->wake_write)) {
      close(fds[0]);
      close(fds[1]);
      worker->wake_read = -1;
      pthread_cond_destroy(&worker->cond);
      pthread_mutex_destroy(&worker->lock);
      pool->count = index;
      return pool;
    }
    size_t length = strlen((const char *)connection_url);
    worker->url = (char *)malloc(length + 1);
    if (worker->url == NULL) {
      close(fds[0]);
      close(fds[1]);
      worker->wake_read = -1;
      pthread_cond_destroy(&worker->cond);
      pthread_mutex_destroy(&worker->lock);
      pool->count = index;
      return pool;
    }
    memcpy(worker->url, connection_url, length + 1);
    if (pthread_create(&worker->thread, NULL, lunanexa_pg_worker_main, worker) !=
        0) {
      free(worker->url);
      worker->url = NULL;
      close(fds[0]);
      close(fds[1]);
      worker->wake_read = -1;
      pthread_cond_destroy(&worker->cond);
      pthread_mutex_destroy(&worker->lock);
      pool->count = index;
      return pool;
    }
    worker->started = 1;
  }
  return pool;
}

/* Stops every worker and closes its connection. Session-scoped state such as
   an advisory lock lives on those connections, so a controller that steps down
   must be able to drop them deterministically instead of waiting for the pool
   object to be collected. */
MOONBIT_FFI_EXPORT
void lunanexa_pg_pool_shutdown(lunanexa_pg_pool_t *pool) {
  if (pool == NULL || pool->workers == NULL) {
    return;
  }
  for (int32_t index = 0; index < pool->count; index += 1) {
    lunanexa_pg_worker_t *worker = &pool->workers[index];
    if (worker->started) {
      pthread_mutex_lock(&worker->lock);
      worker->stop = 1;
      pthread_cond_signal(&worker->cond);
      pthread_mutex_unlock(&worker->lock);
      pthread_join(worker->thread, NULL);
      worker->started = 0;
    }
    if (worker->connection != NULL) {
      PQfinish(worker->connection);
      worker->connection = NULL;
    }
    if (worker->result != NULL) {
      PQclear(worker->result);
      worker->result = NULL;
    }
    free(worker->error);
    worker->error = NULL;
    lunanexa_pg_job_free(&worker->job);
    if (worker->wake_write >= 0) {
      close(worker->wake_write);
      worker->wake_write = -1;
    }
  }
  free(pool->workers);
  pool->workers = NULL;
  pool->count = 0;
}

MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_pool_worker_count(lunanexa_pg_pool_t *pool) {
  return pool == NULL ? 0 : pool->count;
}

/* Hands the worker's completion pipe read end to the caller exactly once. */
MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_pool_take_wake_fd(lunanexa_pg_pool_t *pool, int32_t index) {
  if (pool == NULL || index < 0 || index >= pool->count) {
    return -1;
  }
  lunanexa_pg_worker_t *worker = &pool->workers[index];
  int fd = worker->wake_read;
  worker->wake_read = -1;
  return fd;
}

/* Runs one statement on the worker. Returns 0 when it was accepted, -1 when
   the worker is busy or the pool is not usable. */
MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_pool_submit(
  lunanexa_pg_pool_t *pool,
  int32_t index,
  moonbit_bytes_t sql,
  moonbit_bytes_t encoded_parameters,
  int32_t parameter_count
) {
  if (pool == NULL || index < 0 || index >= pool->count || sql == NULL) {
    return -1;
  }
  if (parameter_count < 0 || parameter_count > 64) {
    return -1;
  }
  lunanexa_pg_worker_t *worker = &pool->workers[index];
  if (!worker->started) {
    return -1;
  }
  size_t sql_length = strlen((const char *)sql);
  char *sql_copy = (char *)malloc(sql_length + 1);
  if (sql_copy == NULL) {
    return -1;
  }
  memcpy(sql_copy, sql, sql_length + 1);

  const char **values = NULL;
  int32_t *lengths = NULL;
  if (parameter_count > 0) {
    if (!lunanexa_pg_parse_parameters(
          encoded_parameters, parameter_count, &values, &lengths)) {
      free(sql_copy);
      return -1;
    }
  }

  pthread_mutex_lock(&worker->lock);
  if (worker->has_job || worker->stop) {
    pthread_mutex_unlock(&worker->lock);
    free(sql_copy);
    lunanexa_pg_release_parameters(values, lengths, parameter_count);
    return -1;
  }
  if (worker->completed != worker->taken) {
    /* The previous result was not taken; the caller must take it first. */
    pthread_mutex_unlock(&worker->lock);
    free(sql_copy);
    lunanexa_pg_release_parameters(values, lengths, parameter_count);
    return -1;
  }
  worker->job.sql = sql_copy;
  worker->job.values = (char **)values;
  worker->job.lengths = lengths;
  worker->job.count = parameter_count;
  worker->has_job = 1;
  pthread_cond_signal(&worker->cond);
  pthread_mutex_unlock(&worker->lock);
  return 0;
}

/* Builds the MoonBit result for a finished statement. Returns NULL when
   nothing completed. The raw PGresult is transferred out of the worker, so it
   is cleared exactly once, by the MoonBit result's finalizer. */
MOONBIT_FFI_EXPORT
lunanexa_pg_result_t *lunanexa_pg_pool_take(
  lunanexa_pg_pool_t *pool,
  int32_t index
) {
  if (pool == NULL || index < 0 || index >= pool->count) {
    return NULL;
  }
  lunanexa_pg_worker_t *worker = &pool->workers[index];
  pthread_mutex_lock(&worker->lock);
  if (worker->completed == worker->taken) {
    pthread_mutex_unlock(&worker->lock);
    return NULL;
  }
  PGresult *result = worker->result;
  char *error = worker->error;
  worker->result = NULL;
  worker->error = NULL;
  worker->taken = worker->completed;
  pthread_mutex_unlock(&worker->lock);
  /* The connection is deliberately not handed to the result: a worker may
     reset it at any moment, so error text travels as its own copy. */
  return lunanexa_pg_result_adopt_error(NULL, result, error);
}

/* Records and clears a broken connection so the next submit reconnects. */
MOONBIT_FFI_EXPORT
int32_t lunanexa_pg_pool_is_connected(lunanexa_pg_pool_t *pool, int32_t index) {
  if (pool == NULL || index < 0 || index >= pool->count) {
    return 0;
  }
  lunanexa_pg_worker_t *worker = &pool->workers[index];
  pthread_mutex_lock(&worker->lock);
  int32_t connected = worker->connected;
  pthread_mutex_unlock(&worker->lock);
  return connected;
}
