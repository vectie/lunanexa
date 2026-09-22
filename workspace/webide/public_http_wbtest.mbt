///|
test "public HTTP workspace deployment requires explicit opt-in and exact IPv4 port" {
  let origin = "http://198.51.100.5:5000"
  assert_false(valid_origin(origin))
  assert_true(valid_origin(origin, allow_insecure_public_http=true))
  assert_true(valid_origin("https://workspace.example.test"))
  for
    invalid in [
      "http://workspace.example.test:5000", "http://0.0.0.0:5000", "http://198.51.100.5",
      "http://198.51.100.5:0", "http://198.51.100.5:65536", "http://198.51.100.256:5000",
      "http://198.51.100.05:5000", "http://198.51.100.5:05000", "http://198.51.100.5:5000/path",
      "http://user@198.51.100.5:5000", "http://198.51.100.5:5000#fragment", "http://198.51.100.5:5000?query",
    ] {
    assert_false(valid_origin(invalid, allow_insecure_public_http=true))
  }
  try
    Bridge::new(test_config(origin), _ => test_grant("alice"), _ => true, (_, _) => {
      http_url: "http://127.0.0.1:8188",
      websocket_url: "ws://127.0.0.1:8188",
    })
  catch {
    InvalidConfiguration => ()
    error => fail("Unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("public HTTP was silently enabled")
  }
  let bridge = Bridge::new(
    test_config(origin),
    _ => test_grant("alice"),
    _ => true,
    (_, _) => {
      http_url: "http://127.0.0.1:8188",
      websocket_url: "ws://127.0.0.1:8188",
    },
    allow_insecure_public_http=true,
  )
  assert_eq(bridge.config.public_origin, origin)
  assert_eq(bridge.cookie_name(false), "webide-session")
}

///|
async test "HTTP opt-in preserves exact host origin and one-time challenge checks" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let origin = "http://198.51.100.5:5000"
  let bridge = Bridge::new(
    test_config(origin),
    _ => test_grant("alice"),
    _ => true,
    (_, _) => {
      http_url: "http://127.0.0.1:8188",
      websocket_url: "ws://127.0.0.1:8188",
    },
    allow_insecure_public_http=true,
  )
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((request, body, connection) => {
        // Simulate the ingress preserving the externally observed authority.
        // The test client connects to loopback, so its native Host is different.
        if header(request.headers, "x-fixture-forwarded-host") is Some(host) {
          for name, _ in request.headers.copy() {
            if name.to_lower() == "host" {
              request.headers.remove(name)
            }
          }
          request.headers["host"] = host
        }
        bridge.handle(request, body, connection)
      })
    })
    let url = "http://\{server.addr}/connect"
    let (wrong_host, _) = @http.get(url)
    assert_eq(wrong_host.code, 403)
    let (page, _) = @http.get(url, headers={
      "x-fixture-forwarded-host": "198.51.100.5:5000",
    })
    assert_eq(page.code, 200)
    let nonce = page.cookies[0]
    assert_true(nonce.http_only)
    let headers = {
      "x-fixture-forwarded-host": "198.51.100.5:5000",
      "origin": "http://198.51.100.5:5001",
      "cookie": "\{nonce.name}=\{nonce.value}",
      "x-webide-csrf": nonce.value,
      "content-type": "application/json",
    }
    let body : Json = { "handoff_code": "lnxc_fixture_only" }
    let (wrong_origin, _) = @http.post(url, body, headers~)
    assert_eq(wrong_origin.code, 403)
    headers["origin"] = origin
    let (accepted, _) = @http.post(url, body, headers~)
    assert_eq(accepted.code, 204)
    assert_true(accepted.cookies[0].http_only)
    assert_true(accepted.cookies[0].extensions.contains("SameSite=Strict"))
    let (replayed, _) = @http.post(url, body, headers~)
    assert_eq(replayed.code, 401)
  }
}
