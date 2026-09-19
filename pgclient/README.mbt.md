# pgclient — a non-blocking PostgreSQL client

`pgclient` is the SQL client the control plane uses. It exists because libpq is
a blocking C library and the control plane runs on a single-threaded
cooperative event loop: calling `PQexec` inside a request keeps the whole loop
waiting for the round trip, so one slow statement stalls every other request.

## How it avoids blocking

Each worker owns one connection and runs at most one statement at a time on its
own thread. Submitting copies the statement and its parameters into memory the
worker owns; finishing writes one byte to a pipe. The event loop awaits that
pipe through `RawFd::read`, so it is only ever waiting on a file descriptor —
never on a database round trip. The result object is built back on the event
loop thread, because a worker thread must not allocate MoonBit objects.

Two consequences worth relying on:

- concurrency is real: a pool of N workers runs N statements at the same time,
  and `PgPool::execute` from N tasks overlaps instead of queueing;
- a connection serves one statement at a time, so session state (transactions,
  advisory locks) needs a lease rather than implicit sharing.

## Using it

```moonbit
let pool = @pgclient.PgPool::connect(url, workers=4)
let rows = pool.execute("SELECT 1::text AS value")
ignore(rows.value(0, 0))

// Session affinity: one connection for the whole group of statements.
let connection = pool.acquire()
defer connection.release()
connection.transaction(inner => {
  ignore(inner.execute("UPDATE accounts SET balance = balance - 1 WHERE id = $1", parameters=[Some(id)]))
  ignore(inner.execute("UPDATE accounts SET balance = balance + 1 WHERE id = $1", parameters=[Some(other)]))
})
```

`PgPool::close` stops handing out new work so shutdown cannot race a worker
mid-statement; statements already running finish normally.

## Errors

Failures are `PgError`. `QueryRejected` means the server answered and refused
the statement, so retrying it unchanged is pointless; `ConnectionUnavailable`
and `Timeout` are worth retrying. These functions do not declare `raise
PgError`, because they await runtime primitives that raise cancellation, and a
declared error type cannot be widened to the runtime's own error. Catch the
sub-error by matching it.

## Verification

`moon test pgclient --target native` needs `LUNANEXA_TEST_DATABASE_URL`. The
tests cover overlapping statements, a rejected statement leaving the connection
usable, parameter and NULL round-trips, a lease keeping statements on one
connection, and a transaction rolling back when its body raises.
