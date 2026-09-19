
///|
type NativePool

///|
#borrow(connection_url)
extern "c" fn native_pool_create(
  connection_url : Bytes,
  workers : Int,
) -> NativePool = "lunanexa_pg_pool_create"

///|
#borrow(pool)
extern "c" fn native_pool_shutdown(pool : NativePool) -> Unit = "lunanexa_pg_pool_shutdown"

///|
#borrow(pool)
extern "c" fn native_pool_worker_count(pool : NativePool) -> Int = "lunanexa_pg_pool_worker_count"

///|
#borrow(pool)
extern "c" fn native_pool_take_wake_fd(pool : NativePool, index : Int) -> Int = "lunanexa_pg_pool_take_wake_fd"

///|
#borrow(pool, sql, encoded_parameters)
extern "c" fn native_pool_submit(
  pool : NativePool,
  index : Int,
  sql : Bytes,
  encoded_parameters : Bytes,
  parameter_count : Int,
) -> Int = "lunanexa_pg_pool_submit"

///|
#borrow(pool)
extern "c" fn native_pool_take(pool : NativePool, index : Int) -> NativeResult = "lunanexa_pg_pool_take"

///|
#borrow(pool)
extern "c" fn native_pool_is_connected(pool : NativePool, index : Int) -> Bool = "lunanexa_pg_pool_is_connected"

///|
/// A pool of worker connections. Each worker runs at most one statement at a
/// time on its own thread, so a caller can await a statement without holding
/// the event loop.
pub struct Pool {
  handle : NativePool
}

///|
/// Creates a pool of `workers` connections. The connections are opened lazily
/// by their worker on first use, so this does not block on the database.
pub fn pool_create(
  connection_url : String,
  workers? : Int = 4,
) -> Pool raise PostgresError {
  let value = connection_url.trim().to_owned()
  if value == "" || value.contains_char('\n') || value.contains_char('\u0000') {
    raise InvalidParameter("database connection URL is invalid")
  }
  if workers <= 0 || workers > 32 {
    raise InvalidParameter("database pool size is invalid")
  }
  { handle: native_pool_create(@utf8.encode(value), workers), }
}

///|
/// The number of workers the pool actually started. A short pool means the
/// operating system refused a thread or a pipe.
///| Stops the workers and closes their connections. Anything session-scoped on
/// those connections, such as an advisory lock, is released here.
pub fn Pool::shutdown(self : Pool) -> Unit {
  native_pool_shutdown(self.handle)
}

///|
pub fn Pool::worker_count(self : Pool) -> Int {
  native_pool_worker_count(self.handle)
}

///|
/// Transfers ownership of one worker's completion pipe read end. The caller
/// must take it exactly once and then await it; the pool keeps the write end.
pub fn Pool::take_wake_fd(self : Pool, index : Int) -> Int {
  native_pool_take_wake_fd(self.handle, index)
}

///|
/// Queues one statement on a worker. The statement and its parameters are
/// copied, so the caller may release them immediately.
pub fn Pool::submit(
  self : Pool,
  index : Int,
  sql : String,
  parameters : Array[String?],
) -> Unit raise PostgresError {
  if sql.trim() == "" || sql.contains_char('\u0000') || sql.length() > 16777216 {
    raise InvalidParameter("SQL statement is invalid")
  }
  let encoded = encode_parameters(parameters)
  if native_pool_submit(
      self.handle, index, @utf8.encode(sql), encoded, parameters.length(),
    ) != 0 {
    raise InvalidParameter("database worker rejected the statement")
  }
}

///|
/// Takes the finished statement's result, or `None` when the worker has
/// nothing waiting. Every `submit` must be followed by one successful `take`.
pub fn Pool::take(self : Pool, index : Int) -> QueryResult? {
  let handle = native_pool_take(self.handle, index)
  if native_result_present(handle) {
    Some({ handle, })
  } else {
    None
  }
}

///|
#borrow(result)
extern "c" fn native_result_present(result : NativeResult) -> Bool = "lunanexa_pg_result_present"

///|
pub fn Pool::is_connected(self : Pool, index : Int) -> Bool {
  native_pool_is_connected(self.handle, index)
}

///|
/// True when the statement succeeded. libpq reports failure through the result
/// object, so this is how a rejected statement is told apart from a transport
/// failure.
pub fn QueryResult::is_ok(self : QueryResult) -> Bool {
  native_result_ok(self.handle)
}

///|
/// The server's message for a rejected statement.
pub fn QueryResult::error_message(self : QueryResult) -> String {
  safe_error(native_result_error(self.handle))
}
