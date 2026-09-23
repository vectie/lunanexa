///|
test "HTTP opt-in is exact and same-origin only" {
  let origin = "http://platform.example:5003"
  assert_false(@browser_transport.allows(origin, origin, ""))
  assert_true(@browser_transport.allows(origin, origin, origin))
  assert_true(@browser_transport.allows(origin + "/", origin, origin))
  assert_true(
    @browser_transport.allows(
      origin,
      origin,
      "http://internal.example:4174," + origin,
    ),
  )
  assert_false(
    @browser_transport.allows(
      "http://internal.example:4174",
      origin,
      "http://internal.example:4174," + origin,
    ),
  )
  for
    endpoint in [
      "http://other.example:5003",
      "http://platform.example:5005",
      "http://platform.example:5003@evil.example",
      "http://user:password@platform.example:5003",
      origin + "/api",
      origin + "?allow_http=true",
      origin + "#token",
      "javascript:alert(1)",
      "not a URL",
    ] {
    assert_false(@browser_transport.allows(endpoint, origin, origin))
  }
  assert_false(
    @browser_transport.allows(origin, "http://other.example", origin),
  )
  assert_false(@browser_transport.allows(origin, origin, origin + "/"))
  assert_false(@browser_transport.allows(origin, origin, "true"))
}

///|
test "HTTPS and loopback remain supported without opt-in" {
  for
    endpoint in [
      "https://platform.example", "http://localhost:8080", "http://127.0.0.1:8080",
      "http://[::1]:8080",
    ] {
    assert_true(@browser_transport.allows(endpoint, "", ""))
  }
  assert_false(
    @browser_transport.allows("https://user:secret@platform.example", "", ""),
  )
  assert_true(
    @browser_transport.allows(
      "https://platform.example/mana", "https://platform.example", "",
    ),
  )
  assert_true(
    @browser_transport.allows(
      "https://platform.example/user", "https://platform.example", "",
    ),
  )
  assert_false(
    @browser_transport.allows(
      "https://other.example/mana", "https://platform.example", "",
    ),
  )
  assert_false(
    @browser_transport.allows(
      "https://platform.example/private", "https://platform.example", "",
    ),
  )
  assert_false(@browser_transport.endpoint_allowed("http://platform.example"))
}

///|
extern "js" fn with_http_metadata(check : () -> Bool) -> Bool =
  #| check => {
  #|   const document = globalThis.document;
  #|   const location = globalThis.location;
  #|   try {
  #|     globalThis.location = {origin: 'http://platform.example:5003'};
  #|     globalThis.document = {querySelector: selector => selector === 'meta[name="lunanexa-public-http-origin"]' ? {getAttribute: name => name === 'content' ? 'http://platform.example:5003' : null} : null};
  #|     return check();
  #|   } finally {
  #|     if (document === undefined) delete globalThis.document; else globalThis.document = document;
  #|     if (location === undefined) delete globalThis.location; else globalThis.location = location;
  #|   }
  #| }

///|
test "deployment metadata enables only the page API origin" {
  assert_true(
    with_http_metadata(() => {
      @browser_transport.endpoint_allowed("http://platform.example:5003") &&
      !@browser_transport.endpoint_allowed("http://platform.example:5005") &&
      !@browser_transport.endpoint_allowed("http://other.example:5003")
    }),
  )
  assert_false(
    @browser_transport.endpoint_allowed("http://platform.example:5003"),
  )
}
