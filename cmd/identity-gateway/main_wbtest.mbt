///|
test "form codec is strict and round trips UTF-8" {
  let encoded = form_encode("a+b 空格")
  assert_eq(encoded, "a%2Bb%20%E7%A9%BA%E6%A0%BC")
  assert_eq(form_decode(encoded), "a+b 空格")
  let query = parse_query("/callback?code=a%2Bb&state=xyz")
  assert_eq(query.get("code"), Some("a+b"))
  assert_eq(query.get("state"), Some("xyz"))
  try parse_query("/callback?state=a&state=b") catch {
    _ => ()
  } noraise {
    _ => fail("duplicate query key must fail")
  }
}

///|
test "API canonicalization rejects encoded and traversal paths" {
  assert_eq(canonical_api_path("/v1/auth/self"), Some("/v1/auth/self"))
  assert_eq(
    canonical_api_path("/v1/auth/self?view=short"),
    Some("/v1/auth/self"),
  )
  assert_eq(canonical_api_path("/v1/auth/%2e%2e/operator"), None)
  assert_eq(canonical_api_path("/v1/auth/../operator"), None)
  assert_eq(canonical_api_path("/v1//auth/self"), None)
  assert_eq(canonical_api_path("/v1/auth\\self"), None)
}

///|
test "opaque cookie reference is host-secret scoped and tamper evident" {
  let id = "A234567890123456789012345678901234567890123"
  let first = encode_cookie_reference(
    id, "operator-cookie-secret-at-least-32-bytes",
  )
  assert_eq(
    decode_cookie_reference(first, "operator-cookie-secret-at-least-32-bytes"),
    Some(id),
  )
  assert_eq(
    decode_cookie_reference(first, "enterprise-cookie-secret-at-least-32-bytes"),
    None,
  )
  assert_eq(
    decode_cookie_reference(
      "\{first}x",
      "operator-cookie-secret-at-least-32-bytes",
    ),
    None,
  )
}

///|
test "issuer endpoint confinement supports current HTTPS IP and port" {
  let issuer = "https://106.39.18.146:5006/realms/lunanexa"
  assert_true(
    same_issuer_endpoint(
      issuer, "https://106.39.18.146:5006/realms/lunanexa/protocol/openid-connect/token",
    ),
  )
  assert_false(
    same_issuer_endpoint(
      issuer, "https://attacker.invalid/realms/lunanexa/protocol/openid-connect/token",
    ),
  )
}

///|
test "ID token claims bind issuer client nonce and lifetime" {
  let header = base64url(@utf8.encode("{\"alg\":\"RS256\"}").view())
  let claims = base64url(
    @utf8.encode(
      "{\"iss\":\"https://106.39.18.146:5006/realms/lunanexa\",\"sub\":\"subject-1\",\"aud\":\"lunanexa-operator\",\"azp\":\"lunanexa-operator\",\"exp\":2000,\"nbf\":900,\"iat\":900,\"nonce\":\"nonce-1\"}",
    ).view(),
  )
  let token = "\{header}.\{claims}.abcdefghijklmnopqrstuvwxyz0123456789"
  let decoded = validate_id_token(
    token, "https://106.39.18.146:5006/realms/lunanexa", "lunanexa-operator", "nonce-1",
    1000000L,
  )
  assert_eq(decoded.sub, "subject-1")
  try
    validate_id_token(
      token, "https://106.39.18.146:5006/realms/lunanexa", "lunanexa-enterprise",
      "nonce-1", 1000000L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("cross-audience ID token must fail")
  }
}

///|
test "relay forwards only signed identity header allowlist" {
  let incoming : Map[String, String] = {
    "Content-Type": "application/json",
    "Authorization": "Bearer forged",
    "Cookie": "forged=true",
    "X-LunaNexa-Subject": "forged",
    "X-LunaNexa-Identity-Issuer": "https://issuer",
    "X-LunaNexa-Identity-Subject": "subject",
    "X-LunaNexa-Identity-Issued-At": "1000",
    "X-LunaNexa-Identity-Expires-At": "2000",
    "X-LunaNexa-Identity-Nonce": "nonce-1234567890",
    "X-LunaNexa-Identity-Signature": "sha256:signature",
  }
  guard relay_identity_headers(incoming) is Some(forwarded) else {
    fail("valid identity header set should forward")
  }
  assert_eq(forwarded.get("Authorization"), None)
  assert_eq(forwarded.get("Cookie"), None)
  assert_eq(forwarded.get("X-LunaNexa-Subject"), None)
  assert_eq(forwarded.get("X-LunaNexa-Identity-Subject"), Some("subject"))
}

///|
test "enterprise allowlist requires an exact route or slash child" {
  assert_true(enterprise_path_allowed("/v1/portal/self/organizations"))
  assert_true(enterprise_path_allowed("/v1/portal/self/machine-orders"))
  assert_true(enterprise_path_allowed("/v1/portal/payment-checkouts"))
  assert_true(enterprise_path_allowed("/v1/portal/signature-requests"))
  assert_true(
    enterprise_path_allowed("/v1/portal/signature-requests/request-1"),
  )
  assert_false(enterprise_path_allowed("/v1/portal/signature-requests-evil"))
  assert_false(enterprise_path_allowed("/v1/operator/accounts"))
}

///|
test "first sign-in registers on current and legacy unknown-account status" {
  assert_true(exchange_requires_registration(401))
  assert_true(exchange_requires_registration(404))
  assert_false(exchange_requires_registration(201))
  assert_false(exchange_requires_registration(409))
}

///|
test "API proxy forwards organization selector but strips identity authority" {
  let request : @http.Request = {
    meth: Post,
    path: "/v1/portal/self/machine-orders",
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "X-LunaNexa-Organization": "organization-a",
      "X-LunaNexa-Subject": "forged-subject",
      "X-LunaNexa-Identity-Subject": "forged-identity",
    },
  }
  let forwarded = forward_request_headers(
    request,
    authorization="Bearer lnxs_bound",
  )
  assert_eq(forwarded.get("X-LunaNexa-Organization"), Some("organization-a"))
  assert_eq(forwarded.get("X-LunaNexa-Subject"), None)
  assert_eq(forwarded.get("X-LunaNexa-Identity-Subject"), None)
  assert_eq(forwarded.get("Authorization"), Some("Bearer lnxs_bound"))
}
