///|
test "public HTTP is explicit and cookie namespaces cannot collide" {
  validate_browser_endpoint("https://login.example/realms/lunanexa", false)
  validate_browser_endpoint("http://192.0.2.1:5006/realms/lunanexa", true)
  for
    pair in [
      ("http://login.example/realm", false),
      ("https://login.example/realm", true),
      ("http://user@login.example/realm", true),
    ] {
    try validate_browser_endpoint(pair.0, pair.1) catch {
      _ => ()
    } noraise {
      _ => fail("invalid browser endpoint accepted")
    }
  }
  assert_true(valid_browser_cookie_name("__Host-enterprise", false))
  assert_false(valid_browser_cookie_name("__Host-enterprise", true))
  assert_true(valid_browser_cookie_name("lunanexa_http_enterprise", true))
  assert_false(valid_browser_cookie_name("lunanexa_http_enterprise", false))
  assert_false(valid_browser_cookie_name("lunanexa_http_x\r\nInjected", true))
}

///|
test "HTTP fetch fallback requires exact origin or slash-bounded referer" {
  let request : @http.Request = {
    meth: Get,
    path: "/auth/session",
    headers: {},
  }
  assert_false(http_same_origin(request, "192.0.2.1:5005"))
  let same = {
    ..request,
    headers: { "Referer": "http://192.0.2.1:5005/enterprise/" },
  }
  assert_true(http_same_origin(same, "192.0.2.1:5005"))
  assert_false(safe_session_fetch(same))
  for
    referer in [
      "http://192.0.2.1:5005.attacker/", "http://192.0.2.1:5003/", "https://192.0.2.1:5005/",
    ] {
    assert_false(
      http_same_origin(
        { ..request, headers: { "Referer": referer }, },
        "192.0.2.1:5005",
      ),
    )
  }
  let cross = {
    ..request,
    headers: {
      "Origin": "http://attacker",
      "Referer": "http://192.0.2.1:5005/",
    },
  }
  assert_false(http_same_origin(cross, "192.0.2.1:5005"))
  let origin = {
    ..request,
    meth: Post,
    headers: { "Origin": "http://192.0.2.1:5005" },
  }
  assert_true(exact_origin(origin, "192.0.2.1:5005", secure=false))
  assert_false(exact_origin(origin, "192.0.2.1:5005"))
  assert_false(
    http_same_origin(
      {
        ..request,
        headers: {
          "Referer": "http://192.0.2.1:5005/",
          "Sec-Fetch-Site": "cross-site",
        },
      },
      "192.0.2.1:5005",
    ),
  )
}
