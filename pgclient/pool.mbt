///|
/// A pool of PostgreSQL connections that never blocks the event loop.
///
/// libpq is a blocking C library, so this package runs each statement on a
/// worker thread that owns one connection and awaits a completion pipe instead
/// of the statement itself. Two properties follow:
///
/// - awaiting a statement yields to the runtime, so other tasks keep running:
///   a pool of N workers really does run N statements at the same time;
/// - one connection serves one statement at a time, so callers that need
///   session affinity (transactions, advisory locks) take a lease with
///   `PgPool::acquire` instead of sharing a connection implicitly.
///
/// A note on errors: these functions do not declare `raise PgError`, because
/// they await runtime primitives that can raise cancellation, and a declared
/// error type may not be widened to the runtime's own error. Failures are
/// still `PgError` values and are caught by matching the sub-error:
///
/// ```moonbit
/// try pool.execute("SELECT 1") catch {
///   @postgres.PgError::QueryRejected(message) => ..
///   @postgres.PgError::ConnectionUnavailable(message) => ..
/// } noraise { result => .. }
/// ```
pub struct PgPool {
  driver : @postgres.Pool
  wakes : Array[@raw_fd.RawFd]
  leases : Array[@async.Mutex]
  mut next_worker : Int
  mut closed : Bool
}

///|
/// A worker connection held exclusively by its caller. Statements issued
/// through it run on one connection in order, which is what `BEGIN`/`COMMIT`
/// and session-scoped state such as `pg_try_advisory_lock` require.
pub struct PgConnection {
  pool : PgPool
  index : Int
  mut released : Bool
}

///|
/// Opens a pool of `workers` connections. Connections are established lazily
/// by their worker on first use, so this only starts threads and pipes.
pub async fn PgPool::connect(url : String, workers? : Int = 4) -> PgPool {
  let driver = @postgres.pool_create(url, workers~) catch {
    @postgres.PostgresError::InvalidParameter(message) =>
      raise InvalidArgument(message)
    @postgres.PostgresError::ConnectionFailed(message) =>
      raise ConnectionUnavailable(message)
    @postgres.PostgresError::QueryFailed(message) =>
      raise QueryRejected(message)
  }
  let started = driver.worker_count()
  if started <= 0 {
    raise ConnectionUnavailable("database pool started no workers")
  }
  let wakes : Array[@raw_fd.RawFd] = []
  for index in 0..<started {
    let fd = driver.take_wake_fd(index)
    if fd < 0 {
      raise ConnectionUnavailable("database completion pipe is unavailable")
    }
    wakes.push(@raw_fd.RawFd(fd))
  }
  let leases : Array[@async.Mutex] = []
  for _ in 0..<started {
    leases.push(@async.Mutex())
  }
  { driver, wakes, leases, next_worker: 0, closed: false, }
}

///|
pub fn PgPool::worker_count(self : PgPool) -> Int {
  self.wakes.length()
}

///|
/// Stops handing out work. Statements already running still finish; this only
/// prevents new ones, so shutdown cannot race a worker mid-statement.
pub fn PgPool::close(self : PgPool) -> Unit {
  self.closed = true
}

///|
fn PgPool::claim(self : PgPool) -> Int raise PgError {
  if self.closed {
    raise Closed
  }
  let index = self.next_worker
  self.next_worker = if index + 1 >= self.wakes.length() {
    0
  } else {
    index + 1
  }
  index
}

///|
/// Runs one statement on whichever worker is free. Yields while the statement
/// runs, so other tasks on the event loop keep making progress.
pub async fn PgPool::execute(
  self : PgPool,
  sql : String,
  parameters? : Array[String?] = [],
) -> PgResult {
  let count = self.wakes.length()
  let start = self.claim()
  let mut chosen : Int? = None
  for attempt in 0..<count {
    let index = (start + attempt) % count
    if self.leases[index].try_acquire() {
      chosen = Some(index)
      break
    }
  }
  let index = match chosen {
    Some(value) => value
    None => {
      // Every worker is busy: wait for one instead of failing, which is the
      // normal case under concurrency.
      let index = (start + 1) % count
      self.leases[index].acquire()
      index
    }
  }
  defer self.leases[index].release()
  self.run_on(index, sql, parameters)
}

///|
/// Takes a worker for a sequence of statements. The connection stays yours
/// until `PgConnection::release`.
pub async fn PgPool::acquire(self : PgPool) -> PgConnection {
  let count = self.wakes.length()
  let start = self.claim()
  let mut chosen : Int? = None
  for attempt in 0..<count {
    let index = (start + attempt) % count
    if self.leases[index].try_acquire() {
      chosen = Some(index)
      break
    }
  }
  let index = match chosen {
    Some(value) => value
    None => {
      let index = (start + 1) % count
      self.leases[index].acquire()
      index
    }
  }
  { pool: self, index, released: false, }
}

///|
/// Submits one statement to `index`, waits for its completion byte, and turns
/// the reply into a result. Only one statement runs per worker at a time, which
/// the caller guarantees by holding that worker's lease.
async fn PgPool::run_on(
  self : PgPool,
  index : Int,
  sql : String,
  parameters : Array[String?],
) -> PgResult {
  self.driver.submit(index, sql, parameters) catch {
    @postgres.PostgresError::InvalidParameter(message) =>
      raise InvalidArgument(message)
    _ => raise ConnectionUnavailable("database worker rejected the statement")
  }
  let buffer = FixedArray::make(1, b'\x00')
  for ;; {
    let _ = self.wakes[index].read(buffer)
    match self.driver.take(index) {
      Some(handle) => {
        let result : PgResult = { handle, }
        if result.handle.is_ok() {
          return result
        }
        raise QueryRejected(result.handle.error_message())
      }
      // A byte left over from an earlier statement wakes us without a result;
      // waiting again is correct because completion is counted, not queued.
      None => continue
    }
  }
}

///|
/// Runs a statement on this connection. A second call on the same connection
/// waits for the first, which is what makes a transaction correct.
pub async fn PgConnection::execute(
  self : PgConnection,
  sql : String,
  parameters? : Array[String?] = [],
) -> PgResult {
  if self.released {
    raise Closed
  }
  self.pool.run_on(self.index, sql, parameters)
}

///|
/// Returns the connection to the pool.
pub fn PgConnection::release(self : PgConnection) -> Unit {
  if !self.released {
    self.released = true
    self.pool.leases[self.index].release()
  }
}

///|
/// Runs `body` on this connection inside a transaction. Commits when the body
/// returns and rolls back when it raises, so a failure cannot leave a
/// half-applied batch behind.
pub async fn PgConnection::transaction(
  self : PgConnection,
  body : async (PgConnection) -> Unit,
) -> Unit {
  let _ = self.execute("BEGIN")
  let mut failure : Error? = None
  let committed = try {
    body(self)
    true
  } catch {
    error => {
      failure = Some(error)
      false
    }
  } noraise {
    _ => false
  }
  if committed {
    let _ = self.execute("COMMIT")
  } else {
    ignore(self.execute("ROLLBACK")) catch {
      _ => ()
    } noraise {
      _ => ()
    }
    match failure {
      Some(error) => raise error
      None => ()
    }
  }
}

///|
/// Runs `body` with one pooled connection and always gives it back, including
/// when the body raises.
pub async fn PgPool::with_connection(
  self : PgPool,
  body : async (PgConnection) -> Unit,
) -> Unit {
  let connection = self.acquire()
  defer connection.release()
  body(connection)
}

///|
/// True when the named worker still holds a live connection. Readiness checks
/// use this to tell "the database is reachable" from "the pool is up".
pub fn PgPool::is_connected(self : PgPool, index : Int) -> Bool {
  if index < 0 || index >= self.wakes.length() {
    false
  } else {
    self.driver.is_connected(index)
  }
}
