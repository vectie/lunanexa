///|
test "enterprise workbench bootstrap exposes only exact read-only routes" {
  let request : @http.Request = {
    meth: Get,
    path: "/v1/workspace/self",
    headers: {},
  }
  for path in ["/v1/workspace/self", "/v1/settings/effective"] {
    assert_true(enterprise_request_allowed(request, path))
    for
      denied in [
        { ..request, meth: Post, },
        { ..request, meth: Put, },
        { ..request, meth: Patch, },
        { ..request, meth: Delete, },
        { ..request, meth: Head, },
        { ..request, meth: Options, },
      ] {
      assert_false(enterprise_request_allowed(denied, path))
    }
  }
  for
    path in [
      "/v1/workspace/self/", "/v1/workspace/self/leases", "/v1/workspace/self-evil",
      "/v1/workspace/users", "/v1/workspace/leases", "/v1/settings/effective/", "/v1/settings/effective/override",
      "/v1/settings/effective-evil", "/v1/settings", "/v1/workloads", "/v1/operator/accounts",
    ] {
    assert_false(enterprise_request_allowed(request, path))
    assert_false(enterprise_request_allowed({ ..request, meth: Post, }, path))
  }
  assert_true(
    enterprise_request_allowed(
      { ..request, meth: Post, },
      "/v1/portal/self/trial/workloads",
    ),
  )
  assert_eq(canonical_api_path("/v1/workspace/%73elf"), None)
  assert_eq(canonical_api_path("/v1/workspace/../operator/accounts"), None)
}

///|
test "workbench bootstrap forwards only explicit bound bearer not incoming identity" {
  let request : @http.Request = {
    meth: Get,
    path: "/v1/workspace/self",
    headers: {
      "Cookie": "session=untrusted",
      "Authorization": "Bearer forged",
      "X-LunaNexa-Subject": "another-user",
      "X-LunaNexa-Identity-Subject": "another-user",
      "X-LunaNexa-Organization": "organization-a",
    },
  }
  let stripped = forward_request_headers(request)
  assert_eq(stripped.get("Authorization"), None)
  assert_eq(stripped.get("Cookie"), None)
  assert_eq(stripped.get("X-LunaNexa-Subject"), None)
  assert_eq(stripped.get("X-LunaNexa-Identity-Subject"), None)
  let bound = forward_request_headers(
    request,
    authorization="Bearer lnxs_cookie_bound",
  )
  assert_eq(bound.get("Authorization"), Some("Bearer lnxs_cookie_bound"))
  assert_eq(bound.get("X-LunaNexa-Organization"), Some("organization-a"))
  assert_false(exact_origin(request, "enterprise.example"))
  assert_false(safe_session_fetch(request))
}
