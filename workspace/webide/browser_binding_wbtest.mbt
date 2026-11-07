///|
async test "browser identity mismatch removes only its own workspace session" {
  let bridge = Bridge::new(
    test_config("http://127.0.0.1:8188"),
    _ => test_grant("alice"),
    _ => true,
    (_, _) => {
      http_url: "http://127.0.0.1:8189",
      websocket_url: "ws://127.0.0.1:8189",
    },
    authorize_browser=Some((grant, cookie) => {
      cookie == "principal=" + grant.subject_ref
    }),
  )
  let alice = test_grant("alice")
  let bob = test_grant("bob")
  for (token, grant) in [("a", alice), ("b", bob)] {
    bridge.sessions[token] = {
      grant,
      backend: {
        http_url: "http://127.0.0.1:8189",
        websocket_url: "ws://127.0.0.1:8189",
      },
    }
  }
  bridge.check_bound_browser("a", alice, { "cookie": "principal=alice" })
  try
    bridge.check_bound_browser("a", alice, { "cookie": "principal=bob" })
  catch {
    BridgeError::Unauthorized => ()
    error => raise error
  } noraise {
    _ => fail("foreign browser principal reached a workspace")
  }
  assert_false(bridge.sessions.contains("a"))
  assert_true(bridge.sessions.contains("b"))
  bridge.check_bound_browser("b", bob, { "cookie": "principal=bob" })
}

///|
async test "identity outage denies access without destroying a valid workspace session" {
  let bridge = Bridge::new(
    test_config("http://127.0.0.1:8188"),
    _ => test_grant("alice"),
    _ => true,
    (_, _) => {
      http_url: "http://127.0.0.1:8189",
      websocket_url: "ws://127.0.0.1:8189",
    },
    authorize_browser=Some((_, _) => raise BridgeError::AuthorityUnavailable),
  )
  let grant = test_grant("alice")
  bridge.sessions["a"] = {
    grant,
    backend: {
      http_url: "http://127.0.0.1:8189",
      websocket_url: "ws://127.0.0.1:8189",
    },
  }
  try
    bridge.check_bound_browser("a", grant, { "cookie": "principal=alice" })
  catch {
    BridgeError::AuthorityUnavailable => ()
    error => raise error
  } noraise {
    _ => fail("identity outage allowed access")
  }
  assert_true(bridge.sessions.contains("a"))
}

///|
async test "trusted extension runs behind live browser binding and credentials never reach the workspace" {
  let workspace = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer workspace.close()
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let origin = "http://\{server.addr}"
  let backend : Backend = {
    http_url: "http://\{workspace.addr}",
    websocket_url: "ws://\{workspace.addr}",
  }
  let extension_calls = Ref(0)
  let workspace_calls = Ref(0)
  let unavailable = Ref(false)
  let token_for = (name : String) => {
    workspace_id({ ..test_grant(name), client_id: "moontown", })
    .strip_prefix("webide-")
    .unwrap()
    .to_owned()
  }
  let bridge = Bridge::new(
    { ..test_config(origin), client_id: "moontown", },
    _ => { ..test_grant("alice"), client_id: "moontown", },
    _ => true,
    (_, _) => backend,
    authorize_browser=Some((grant, cookie) => {
      if unavailable.val {
        raise BridgeError::AuthorityUnavailable
      }
      cookie.contains("principal=" + grant.subject_ref + ";")
    }),
    handle_authorized=Some((grant, request, conn) => {
      if request.path != "/account/self.json" {
        return false
      }
      extension_calls.val += 1
      reply(conn, 200, grant.subject_ref)
      true
    }),
  )
  for name in ["alice", "bob"] {
    bridge.sessions[token_for(name)] = {
      grant: { ..test_grant(name), client_id: "moontown", },
      backend,
    }
  }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      workspace.run_forever((request, _, conn) => {
        workspace_calls.val += 1
        for
          name in [
            "cookie", "authorization", "x-lunanexa-subject", "x-lunanexa-organization",
          ] {
          assert_true(request.headers.get(name) is None)
        }
        reply(conn, 200, "workspace asset")
      })
    })
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((request, body, conn) => {
        bridge.handle(request, body, conn)
      })
    })
    let headers = fn(owner : String, principal : String) -> @http.Headers {
      {
        "cookie": bridge.cookie_name(false) +
        "=" +
        token_for(owner) +
        "; principal=" +
        principal +
        ";",
        "authorization": "Bearer private-browser-bearer",
        "x-lunanexa-subject": "forged",
        "x-lunanexa-organization": "forged",
      }
    }
    assert_eq(@http.get(origin + "/account/self.json").0.code, 401)
    assert_eq(extension_calls.val, 0)
    let (response, content) = @http.get(
      origin + "/account/self.json",
      headers=headers("alice", "alice"),
    )
    assert_eq(response.code, 200)
    assert_eq(content.text(), "alice")
    assert_eq(workspace_calls.val, 0)
    assert_eq(
      @http.get(
        origin + "/tilemap/avatar.png",
        headers=headers("alice", "alice"),
      ).0.code,
      200,
    )
    assert_eq(workspace_calls.val, 1)
    unavailable.val = true
    assert_eq(
      @http.get(
        origin + "/account/self.json",
        headers=headers("alice", "alice"),
      ).0.code,
      503,
    )
    assert_true(bridge.sessions.contains(token_for("alice")))
    unavailable.val = false
    assert_eq(
      @http.get(origin + "/account/self.json", headers=headers("alice", "bob")).0.code,
      401,
    )
    assert_eq(extension_calls.val, 1)
    assert_false(bridge.sessions.contains(token_for("alice")))
    assert_eq(
      @http.get(origin + "/account/self.json", headers=headers("bob", "bob")).0.code,
      200,
    )
    assert_eq(extension_calls.val, 2)
  })
}

///|
async test "foreign browser cannot provision a redeemed workspace" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let origin = "http://\{server.addr}"
  let provisions = Ref(0)
  let bridge = Bridge::new(
    test_config(origin),
    _ => test_grant("alice"),
    _ => true,
    (_, _) => {
      provisions.val += 1
      { http_url: origin, websocket_url: "ws://\{server.addr}", }
    },
    authorize_browser=Some((_, _) => false),
  )
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((request, body, conn) => {
        bridge.handle(request, body, conn)
      })
    })
    let (page, _) = @http.get(origin + "/connect")
    let nonce = page.cookies[0]
    let (response, _) = @http.post(
      origin + "/connect",
      ({ "handoff_code": "lnxc_fixture" } : Json),
      headers={
        "origin": origin,
        "cookie": nonce.name + "=" + nonce.value,
        "x-webide-csrf": nonce.value,
        "content-type": "application/json",
      },
    )
    assert_eq(response.code, 401)
    assert_eq(provisions.val, 0)
    assert_true(bridge.sessions.is_empty())
  })
}
