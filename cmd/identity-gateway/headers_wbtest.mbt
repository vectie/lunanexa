///|
test "mixed-case headers retain machine authority and cookie lookup" {
  let headers : @http.Headers = {
    "aUtHoRiZaTiOn": "Bearer lnx_fixture",
    "cOoKiE": "session=fixture-token",
  }
  assert_eq(header(headers, "Authorization"), Some("Bearer lnx_fixture"))
  assert_eq(cookie_value(headers, "session"), Some("fixture-token"))
  assert_true(
    enterprise_machine_request_allowed(Enterprise, Get, "/v1/models", headers),
  )
  headers["oRiGiN"] = "https://untrusted.invalid"
  assert_false(
    enterprise_machine_request_allowed(Enterprise, Get, "/v1/models", headers),
  )
}

///|
test "proxy forwards only allowed headers independent of input casing" {
  let request : @http.Request = {
    meth: Get,
    path: "/v1/models",
    headers: {
      "aCcEpT": "application/json",
      "rAnGe": "bytes=10-20",
      "x-LuNaNeXa-OrGaNiZaTiOn": "org-fixture",
      "aUtHoRiZaTiOn": "Bearer untrusted",
      "cOoKiE": "session=private",
      "x-LuNaNeXa-IdEnTiTy-SuBjEcT": "forged",
    },
  }
  let forwarded = forward_request_headers(
    request,
    authorization="Bearer trusted",
  )
  assert_eq(forwarded.get("Accept"), Some("application/json"))
  assert_eq(forwarded.get("Range"), Some("bytes=10-20"))
  assert_eq(forwarded.get("X-LunaNexa-Organization"), Some("org-fixture"))
  assert_eq(forwarded.get("Authorization"), Some("Bearer trusted"))
  assert_eq(forwarded.get("Cookie"), None)
  assert_eq(forwarded.get("X-LunaNexa-Identity-Subject"), None)
}
