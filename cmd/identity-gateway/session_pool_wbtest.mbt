///|
async test "a blocked session refresh does not block other live session reads" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = url.split("/").last().unwrap().split("?").next().unwrap()
  guard database.has_suffix("_test") else {
    fail("Disposable *_test database required")
  }
  gateway_pool_scenario(url) catch {
    @pgclient.PgError::QueryRejected(message) =>
      fail("Session pool database test: " + message)
    error => raise error
  }
}

///|
async fn gateway_pool_scenario(url : String) -> Unit {
  let setup = @pgclient.PgPool::connect(url, workers=1)
  defer setup.close()
  ignore(setup.execute("CREATE SCHEMA IF NOT EXISTS lunanexa"))
  let store = GatewaySessionStore::open(url)
  defer store.close()
  let now = @async.now()
  let session : GatewayCookie = {
    kind: "session",
    audience: "enterprise",
    host: "pool.example.test",
    state: "",
    nonce: "",
    verifier: "",
    issuer: "pool-test",
    subject: "pool-test",
    email: "pool@example.test",
    display_name: "Pool test",
    bearer: "unusable-test-only",
    csrf: "",
    created_unix_ms: now,
    last_used_unix_ms: now,
    expires_unix_ms: now + 60000L,
  }
  let first = store.create(session)
  defer ignore(store.delete(first))
  let second = store.create({ ..session, subject: "independent", })
  defer ignore(store.delete(second))
  let blocker = setup.acquire()
  defer blocker.release()
  ignore(blocker.execute("BEGIN"))
  @async.with_task_group(group => {
    // This lock deliberately stalls one worker without holding an auth cache.
    ignore(
      blocker.execute(
        "SELECT session_id FROM lunanexa.identity_gateway_sessions WHERE session_id=$1 FOR UPDATE",
        parameters=[Some(first)],
      ),
    )
    group.spawn_bg(() => {
      store.replace(first, { ..session, last_used_unix_ms: now + 1L, })
    })
    @async.sleep(50)
    let other = @async.with_timeout(500, () => store.load(second)) catch {
      e => {
        ignore(blocker.execute("ROLLBACK"))
        raise e
      }
    }
    assert_true(other is Some({ subject: "independent", .. }))
    ignore(blocker.execute("ROLLBACK"))
  })
  assert_true(
    store.load(first) is Some({ last_used_unix_ms: stamp, .. }) &&
    stamp == now + 1L,
  )
  store.replace(first, session)
  assert_true(
    store.load(first) is Some({ last_used_unix_ms: stamp, .. }) &&
    stamp == now + 1L,
  )
  assert_true(store.delete(first))
  assert_true(store.load(first) is None)
  assert_false(store.delete(first))
}
