///|
fn test_config(origin : String) -> BridgeConfig {
  {
    client_id: "comfyui",
    public_origin: origin,
    maximum_sessions: 16,
    maximum_request_bytes: 4096,
    maximum_socket_message_bytes: 4096,
    request_timeout_ms: 2000,
    authorization_interval_ms: 100,
  }
}

///|
test "session capabilities use operating system entropy" {
  let first = random_token()
  let second = random_token()
  assert_eq(first.length(), 64)
  assert_true(first != second)
}

///|
test "model-free terminal grants require explicit bridge profile" {
  let make = (enabled : Bool) => {
    Bridge::new(
      test_config("http://127.0.0.1:8188"),
      _ => test_grant("alice"),
      _ => true,
      (_, _) => {
        http_url: "http://127.0.0.1:8189",
        websocket_url: "ws://127.0.0.1:8189",
      },
      allow_model_free_workspace=enabled,
    )
  }
  let grant = { ..test_grant("alice"), allowed_models: [], }
  assert_false(make(false).valid_grant(grant, @async.now()))
  assert_true(make(true).valid_grant(grant, @async.now()))
  assert_false(
    make(true).valid_grant({ ..grant, expires_unix_ms: 0L, }, @async.now()),
  )
}

///|
fn test_grant(subject : String) -> Grant {
  {
    delivery_id: None,
    client_id: "comfyui",
    tenant_ref: "tenant-a",
    subject_ref: subject,
    organization_id: "org-a",
    project_id: "project-a",
    api_secret: "lnx_test_secret_never_send_to_the_browser",
    allowed_models: ["video.h3"],
    expires_unix_ms: @async.now() + 60000L,
  }
}

///|
test "workspace identities include every authority dimension without delimiter collisions" {
  let first = test_grant("alice")
  assert_eq(workspace_id(first), workspace_id(test_grant("alice")))
  for
    other in [
      { ..first, subject_ref: "bob", },
      { ..first, tenant_ref: "tenant-b", },
      { ..first, organization_id: "org-b", },
      { ..first, project_id: "project-b", },
    ] {
    assert_true(workspace_id(first) != workspace_id(other))
  }
  assert_false(workspace_id(first).contains("alice"))
  assert_false(workspace_id(first).contains("secret"))
  let desktop = { ..first, client_id: "desktop-workspace", }
  assert_true(workspace_id(desktop) != workspace_id(first))
  assert_true(workspace_storage_id(desktop) != workspace_storage_id(first))
  assert_true(
    workspace_storage_id(desktop) !=
    workspace_storage_id({ ..desktop, subject_ref: "bob", }),
  )
}

///|
test "personal desktop routes never turn another client into an open proxy" {
  assert_true(
    allowed_path(Post, "/api/mooncode/chat", client_id="desktop-workspace"),
  )
  assert_true(
    allowed_path(Get, "/api/mooncode/sessions", client_id="desktop-workspace"),
  )
  assert_false(allowed_path(Get, "/api/mooncode/sessions"))
  assert_false(
    allowed_path(Get, "/api/../secrets", client_id="desktop-workspace"),
  )
}

///|
test "managed route policy rejects traversal, administration and arbitrary tunnels" {
  for
    path in [
      "/", "/api/queue", "/assets/main.js", "/history/123", "/view?filename=a%20b.mp4",
      "/ws?clientId=123", "/api/v2/userdata?dir=workflows", "/userdata/workflows%2Fhello%20world.json",
      "/api/jobs", "/api/node_replacements",
    ] {
    assert_true(allowed_path(Get, path))
  }
  for
    path in [
      "//evil.test/", "/%2e%2e/etc/passwd", "/api/../manager/install", "/manager/install",
      "/internal/files", "https://evil.test/", "/api\\queue", "/queue#fragment",
      "/queue\r\nInjected:true", "/userdata/%252e%252e%252fsecret", "/userdata/%2e%2e/secret",
      "/userdata/a%00b", "/userdata/%5csecret",
    ] {
    assert_false(allowed_path(Get, path))
    assert_false(allowed_path(Post, path))
  }
  assert_true(allowed_path(Post, "/prompt"))
  assert_true(allowed_path(Post, "/userdata/workflows%2Fhello%20world.json"))
  assert_false(allowed_path(Post, "/assets/main.js"))
  assert_true(allowed_path(Get, "/api/assets?include_tags=output&limit=50"))
  assert_false(allowed_path(Post, "/api/assets/seed"))
  assert_false(allowed_path(Post, "/api/assets/download"))
  assert_false(allowed_path(Delete, "/api/assets/123"))
  assert_false(allowed_path(Connect, "/"))
}

///|
test "cookie parser rejects duplicate names and malformed capabilities" {
  let token = "a".repeat(64)
  assert_eq(
    cookie({ "cookie": "other=x; webide-session=\{token}" }, "webide-session"),
    Some(token),
  )
  assert_eq(
    cookie(
      { "cookie": "webide-session=\{token}; webide-session=\{token}" },
      "webide-session",
    ),
    None,
  )
  assert_eq(
    cookie({ "cookie": "webide-session=short" }, "webide-session"),
    None,
  )
  assert_eq(
    cookie(
      {
        "Cookie": "webide-session=\{token}",
        "cookie": "webide-session=\{token}",
      },
      "webide-session",
    ),
    None,
  )
}

///|
test "bridge configuration refuses unsafe origins and unbounded limits" {
  for
    origin in [
      "http://0.0.0.0:5000", "https://good.test/evil", "https://user@host", "https://a?b",
      "http://127.0.0.1:5000/", "https://a\r\n",
    ] {
    assert_false(valid_origin(origin))
  }
  assert_true(valid_origin("https://comfy.example.test"))
  assert_true(valid_origin("http://127.0.0.1:5010"))
  let config = {
    ..test_config("https://comfy.example.test"),
    maximum_sessions: 0,
  }
  try {
    ignore(
      Bridge::new(config, _ => test_grant("alice"), _ => true, (_, _) => {
        http_url: "http://127.0.0.1:8188",
        websocket_url: "ws://127.0.0.1:8188",
      }),
    )
    fail("unbounded configuration accepted")
  } catch {
    BridgeError::InvalidConfiguration => ()
    error => fail("unexpected configuration error: \{error}")
  }
}

///|
async test "WebSocket relay supports binary and text and closes on live authority loss" {
  let public = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let backend = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer public.close()
  defer backend.close()
  let origin = "http://\{public.addr}"
  let active = { "value": true, "outage": false }
  let bridge = Bridge::new(
    test_config(origin),
    _ => test_grant("alice"),
    _ => {
      if active["outage"] {
        raise BridgeError::AuthorityUnavailable
      }
      active["value"]
    },
    (_, _) => {
      http_url: "http://\{backend.addr}",
      websocket_url: "ws://\{backend.addr}",
    },
  )
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      public.run_forever((req, body, conn) => bridge.handle(req, body, conn))
    })
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      backend.run_forever((req, _body, conn) => {
        let socket = @websocket.Conn::from_http_server(req, conn)
        defer socket.close()
        while true {
          let message = socket.recv()
          let bytes = read_bounded(message, 4096)
          match message.kind {
            Text => socket.send_text(@utf8.decode(bytes))
            Binary => socket.send_binary(bytes)
          }
        }
      })
    })
    let (cookies, _) = launch_test(origin, "lnxc_alice")
    let socket = @websocket.Conn::connect(
      "ws://\{public.addr}/ws?clientId=test",
      headers={ "origin": origin, "cookie": cookies },
    )
    defer socket.close()
    socket.send_text("progress")
    let text_message = @async.with_timeout(2000, () => socket.recv())
    assert_true(text_message.kind is Text)
    assert_eq(@utf8.decode(read_bounded(text_message, 4096)), "progress")
    socket.send_binary(b"\x00\xff\x80")
    let binary = @async.with_timeout(2000, () => socket.recv())
    assert_true(binary.kind is Binary)
    assert_eq(read_bounded(binary, 4096), b"\x00\xff\x80")
    active["outage"] = true
    try {
      ignore(@async.with_timeout(2000, () => socket.recv()))
      fail("socket remained open without current authority")
    } catch {
      @websocket.WebSocketError::ConnectionClosed(PolicyViolation, _) => ()
      error => fail("expected a clean policy close: \{error}")
    }
    active["outage"] = false
    let recovered = @websocket.Conn::connect(
      "ws://\{public.addr}/ws?clientId=recovered",
      headers={ "origin": origin, "cookie": cookies },
    )
    defer recovered.close()
    recovered.send_text("reconnected")
    let resumed = @async.with_timeout(2000, () => recovered.recv())
    assert_eq(@utf8.decode(read_bounded(resumed, 4096)), "reconnected")
    active["value"] = false
    try {
      ignore(@async.with_timeout(2000, () => recovered.recv()))
      fail("revoked socket remained open")
    } catch {
      @websocket.WebSocketError::ConnectionClosed(PolicyViolation, _) => ()
      error => fail("expected a clean policy close: \{error}")
    }
  }
}

///|
async fn launch_test(origin : String, code : String) -> (String, String) {
  let (page, content) = @http.get(origin + "/connect", headers={
    "sec-fetch-site": "cross-site",
  })
  assert_eq(page.code, 200)
  assert_true(content.text().contains("lunanexa_handoff"))
  assert_false(content.text().contains("lnx_test_secret"))
  let challenge = page.cookies[0]
  assert_true(content.text().contains("nonce=\"\{challenge.value}\""))
  assert_true(content.text().contains("'X-WebIDE-CSRF':'\{challenge.value}'"))
  assert_true(challenge.http_only)
  let headers = {
    "origin": origin,
    "cookie": "\{challenge.name}=\{challenge.value}",
    "x-webide-csrf": challenge.value,
    "content-type": "application/json",
  }
  let payload : Json = { "handoff_code": code }
  let (response, _) = @http.post(origin + "/connect", payload, headers~)
  assert_eq(response.code, 204)
  let session = response.cookies[0]
  assert_true(session.http_only)
  assert_true(session.extensions.contains("SameSite=Strict"))
  let (replayed, _) = @http.post(origin + "/connect", payload, headers~)
  assert_eq(replayed.code, 401)
  ("\{session.name}=\{session.value}", session.value)
}

///|
async test "real HTTP bridge keeps credentials private, isolates workspaces and rechecks revocation" {
  let public = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let alice = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let bob = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer public.close()
  defer alice.close()
  defer bob.close()
  let origin = "http://\{public.addr}"
  let active = { "alice": true, "bob": true, "outage": false }
  let redeemed : Array[String] = []
  let bridge = Bridge::new(
    test_config(origin),
    code => {
      redeemed.push(code)
      test_grant(if code == "lnxc_alice" { "alice" } else { "bob" })
    },
    grant => {
      if active["outage"] {
        raise BridgeError::AuthorityUnavailable
      }
      active.get(grant.subject_ref).unwrap_or(false)
    },
    (_id, grant) => {
      let address = if grant.subject_ref == "alice" {
        alice.addr
      } else {
        bob.addr
      }
      { http_url: "http://\{address}", websocket_url: "ws://\{address}", }
    },
  )
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      public.run_forever((req, body, conn) => bridge.handle(req, body, conn))
    })
    for entry in [(alice, "alice"), (bob, "bob")] {
      let (server, name) = entry
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        server.run_forever((req, _body, conn) => {
          assert_eq(header(req.headers, "cookie"), None)
          assert_eq(header(req.headers, "authorization"), None)
          conn.send_response(200, "OK", extra_headers={
            "content-type": "text/plain",
            "set-cookie": "evil=upstream",
          })
          conn.write_string(name)
          conn.end_response()
        })
      })
    }
    let (anonymous, _) = @http.get(origin + "/queue")
    assert_eq(anonymous.code, 401)
    let (alice_cookie, _) = launch_test(origin, "lnxc_alice")
    let (bob_cookie, _) = launch_test(origin, "lnxc_bob")
    assert_eq(redeemed.length(), 2)
    for entry in [(alice_cookie, "alice"), (bob_cookie, "bob")] {
      let (cookies, name) = entry
      let (response, content) = @http.get(origin + "/queue", headers={
        "cookie": cookies,
        "authorization": "Bearer browser-poison",
      })
      assert_eq(response.code, 200)
      assert_eq(content.text(), name)
      assert_eq(response.cookies.length(), 0)
      assert_eq(header(response.headers, "cache-control"), Some("no-store"))
    }
    let (csrf, _) = @http.post(origin + "/prompt", "{}", headers={
      "cookie": alice_cookie,
      "origin": "https://evil.test",
    })
    assert_eq(csrf.code, 403)
    let (no_origin, _) = @http.post(origin + "/prompt", "{}", headers={
      "cookie": alice_cookie,
    })
    assert_eq(no_origin.code, 403)
    let (admin, _) = @http.post(origin + "/manager/install", "{}", headers={
      "cookie": alice_cookie,
      "origin": origin,
    })
    assert_eq(admin.code, 403)
    let (large, _) = @http.post(origin + "/prompt", "x".repeat(4097), headers={
      "cookie": alice_cookie,
      "origin": origin,
    })
    assert_eq(large.code, 413)
    active["outage"] = true
    let (unavailable, _) = @http.get(origin + "/queue", headers={
      "cookie": alice_cookie,
    })
    assert_eq(unavailable.code, 503)
    active["outage"] = false
    let (recovered, recovered_body) = @http.get(origin + "/queue", headers={
      "cookie": alice_cookie,
    })
    assert_eq(recovered.code, 200)
    assert_eq(recovered_body.text(), "alice")
    active["alice"] = false
    let (revoked, _) = @http.get(origin + "/queue", headers={
      "cookie": alice_cookie,
    })
    assert_eq(revoked.code, 401)
    let (still_active, _) = @http.get(origin + "/queue", headers={
      "cookie": bob_cookie,
    })
    assert_eq(still_active.code, 200)
    let (logout, _) = @http.post(origin + "/logout", "", headers={
      "cookie": bob_cookie,
      "origin": origin,
    })
    assert_eq(logout.code, 204)
    let (after_logout, _) = @http.get(origin + "/queue", headers={
      "cookie": bob_cookie,
    })
    assert_eq(after_logout.code, 401)
  }
}
