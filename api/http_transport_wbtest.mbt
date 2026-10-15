///|
test "HTTP header adapter preserves values and case-insensitive authority" {
  let incoming : @http.Headers = {
    "aUtHoRiZaTiOn": "Bearer transport-fixture",
    "X-LunaNexa-Subject": "subject-fixture",
    "cOnTeNt-TyPe": "application/json; charset=utf-8",
  }
  let headers = application_headers(incoming)
  assert_true(bearer_authorized(headers, "transport-fixture"))
  assert_false(bearer_authorized(headers, "another-token"))
  assert_eq(header(headers, "x-lunanexa-subject"), Some("subject-fixture"))
  assert_eq(
    header(headers, "Content-Type"),
    Some("application/json; charset=utf-8"),
  )
  assert_eq(header(headers, "Origin"), None)
}
