///|
async test "concurrent session checks coalesce without caching completed authority" {
  let calls = Ref(0)
  let allowed = Ref(true)
  let bridge = Bridge::new(
    test_config("http://127.0.0.1:8188"),
    _ => test_grant("alice"),
    _ => {
      calls.val += 1
      @async.sleep(20)
      allowed.val
    },
    (_, _) => {
      http_url: "http://127.0.0.1:8189",
      websocket_url: "ws://127.0.0.1:8189",
    },
  )
  bridge.sessions["session-a"] = {
    grant: test_grant("alice"),
    backend: {
      http_url: "http://127.0.0.1:8189",
      websocket_url: "ws://127.0.0.1:8189",
    },
  }
  @async.with_task_group(group => {
    for _ in 0..<32 {
      group.spawn_bg(() => ignore(bridge.session("session-a")))
    }
  })
  assert_eq(calls.val, 1)
  assert_true(bridge.authorizations.is_empty())
  allowed.val = false
  try bridge.session("session-a") catch {
    BridgeError::Unauthorized => ()
    error => raise error
  } noraise {
    _ => fail("cached authorization survived revocation")
  }
  assert_eq(calls.val, 2)
  assert_false(bridge.sessions.contains("session-a"))
}

///|
async test "failed flight releases all waiters and independent sessions never share decisions" {
  let calls = Ref(0)
  let unavailable = Ref(true)
  let bridge = Bridge::new(
    test_config("http://127.0.0.1:8188"),
    _ => test_grant("alice"),
    _ => {
      calls.val += 1
      @async.sleep(20)
      if unavailable.val {
        raise BridgeError::AuthorityUnavailable
      }
      true
    },
    (_, _) => {
      http_url: "http://127.0.0.1:8189",
      websocket_url: "ws://127.0.0.1:8189",
    },
  )
  let failures = Ref(0)
  @async.with_task_group(group => {
    for _ in 0..<32 {
      group.spawn_bg(() => {
        try bridge.authorize_session("a", test_grant("alice")) catch {
          BridgeError::AuthorityUnavailable => failures.val += 1
          error => raise error
        } noraise {
          _ => fail("unavailable authority accepted")
        }
      })
    }
  })
  assert_eq(failures.val, 32)
  assert_eq(calls.val, 1)
  assert_true(bridge.authorizations.is_empty())
  unavailable.val = false
  @async.with_task_group(group => {
    for token in ["a", "b"] {
      group.spawn_bg(() => {
        assert_true(bridge.authorize_session(token, test_grant(token)))
      })
    }
  })
  assert_eq(calls.val, 3)
}

///|
async test "cancelling flight leader releases followers and allows a fresh check" {
  let calls = Ref(0)
  let slow = Ref(true)
  let bridge = Bridge::new(
    test_config("http://127.0.0.1:8188"),
    _ => test_grant("alice"),
    _ => {
      calls.val += 1
      if slow.val {
        @async.sleep(1000)
      }
      true
    },
    (_, _) => {
      http_url: "http://127.0.0.1:8189",
      websocket_url: "ws://127.0.0.1:8189",
    },
  )
  let rejected = Ref(false)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      try
        @async.with_timeout(50, () => {
          ignore(bridge.authorize_session("a", test_grant("alice")))
        })
      catch {
        _ => ()
      } noraise {
        _ => fail("expected leader cancellation")
      }
    })
    group.spawn_bg(() => {
      while calls.val == 0 {
        @async.sleep(1)
      }
      try bridge.authorize_session("a", test_grant("alice")) catch {
        BridgeError::AuthorityUnavailable => rejected.val = true
        error => raise error
      } noraise {
        _ => fail("cancelled authorization accepted")
      }
    })
  })
  assert_true(rejected.val && bridge.authorizations.is_empty())
  slow.val = false
  assert_true(bridge.authorize_session("a", test_grant("alice")))
  assert_eq(calls.val, 2)
}
