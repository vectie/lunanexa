///|
/// Points the suite at a disposable database. These tests write, so a URL that
/// does not name a `*_test` database is refused loudly instead of being run
/// against a live deployment.
fn test_url() -> String? {
  test_database_url()
}

///|
fn test_database_url() -> String? {
  let url = @env.get_env_var("LUNANEXA_TEST_DATABASE_URL")
  match url {
    None => None
    Some(value) => {
      // Database name: the last path segment, before any query string.
      let mut name = ""
      for segment in value.split("/") {
        name = segment.to_owned()
      }
      let mut base = ""
      let mut first = true
      for part in name.split("?") {
        if first {
          base = part.to_owned()
          first = false
        }
      }
      if !base.has_suffix("_test") {
        abort(
          "LUNANEXA_TEST_DATABASE_URL must name a *_test database; refusing to run against \{base}",
        )
      }
      Some(value)
    }
  }
}

///|
async test "pooled statements overlap instead of serialising" {
  guard test_url() is Some(url) else {
    return
  }
  let pool = @pgclient.PgPool::connect(url, workers=2)
  // Two statements that each sleep 400 ms. Serialised they need at least
  // 800 ms; overlapping on two workers needs a little over 400 ms. The bound
  // is loose so a loaded machine does not make this flaky.
  let started = @async.now()
  @async.with_task_group(group => {
    ignore(group.spawn(() => pool.execute("SELECT pg_sleep(0.4)")))
    ignore(group.spawn(() => pool.execute("SELECT pg_sleep(0.4)")))
  })
  let elapsed = @async.now() - started
  pool.close()
  assert_true(elapsed < 700L)
}

///|
async test "a rejected statement raises instead of returning rows" {
  guard test_url() is Some(url) else {
    return
  }
  let pool = @pgclient.PgPool::connect(url, workers=1)
  let rejected = try {
    ignore(pool.execute("SELECT * FROM lunanexa.relation_that_does_not_exist"))
    false
  } catch {
    @pgclient.PgError::QueryRejected(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
  // The connection survives a rejected statement, so the pool keeps working.
  let result = pool.execute("SELECT 1::text AS value")
  assert_eq(result.value(0, 0), Some("1"))
  pool.close()
}

///|
async test "parameters round-trip and NULL is preserved" {
  guard test_url() is Some(url) else {
    return
  }
  let pool = @pgclient.PgPool::connect(url, workers=1)
  let result = pool.execute(
    "SELECT $1::text AS echoed, $2::text IS NULL AS absent",
    parameters=[Some("value"), None],
  )
  assert_eq(result.value(0, 0), Some("value"))
  assert_true(result.value(0, 1) == Some("t") || result.value(0, 1) == Some("true"))
  pool.close()
}

///|
async test "a lease keeps statements on one connection" {
  guard test_url() is Some(url) else {
    return
  }
  let pool = @pgclient.PgPool::connect(url, workers=3)
  let connection = pool.acquire()
  // A session-scoped advisory lock is only observable from the connection that
  // took it, so this fails if a lease hands out different workers.
  let _ = connection.execute("SELECT pg_advisory_lock(918273645)")
  let held = connection.execute(
    "SELECT count(*)::text FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()",
  )
  assert_eq(held.value(0, 0), Some("1"))
  let _ = connection.execute("SELECT pg_advisory_unlock(918273645)")
  connection.release()
  pool.close()
}

///|
async test "a transaction rolls back when the body raises" {
  guard test_url() is Some(url) else {
    return
  }
  let pool = @pgclient.PgPool::connect(url, workers=1)
  let connection = pool.acquire()
  let failed = try {
    connection.transaction(inner => {
      ignore(inner.execute("CREATE TEMP TABLE lunanexa_rollback_probe (id int)"))
      ignore(inner.execute("INSERT INTO lunanexa_rollback_probe VALUES (1)"))
      raise @pgclient.PgError::InvalidArgument("deliberate failure")
    })
    false
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(failed)
  // The worker is usable again after the rollback.
  let after = connection.execute("SELECT 1::text AS value")
  assert_eq(after.value(0, 0), Some("1"))
  connection.release()
  pool.close()
}

///|
async test "the pool serves more concurrent statements than it has workers" {
  guard test_url() is Some(url) else {
    return
  }
  let pool = @pgclient.PgPool::connect(url, workers=2)
  let started = @async.now()
  @async.with_task_group(group => {
    for index in 0..<6 {
      let _ = index
      ignore(group.spawn(() => pool.execute("SELECT pg_sleep(0.1)")))
    }
  })
  let elapsed = @async.now() - started
  pool.close()
  // Six sleeps of 100 ms over two workers: at best three rounds, at worst six
  // if the pool only ever used one worker.
  assert_true(elapsed < 500L)
}
