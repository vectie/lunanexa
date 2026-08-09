///|
test "asserted workspace subject is refused without transport proof" {
  let headers = { "X-LunaNexa-Subject": "subject-workspace" }
  assert_eq(trusted_workspace_subject(headers, false), None)
  assert_eq(trusted_workspace_subject(headers, true), Some("subject-workspace"))
}

///|
test "verified ingress identity remains available to non-loopback dispatch" {
  let raw_dn = "CN=developer,O=LunaNexa"
  let expected = "mtls:sha256:\{digest_hex(raw_dn)}"
  assert_eq(
    trusted_workspace_subject(
      {
        "ssl-client-verify": "SUCCESS",
        "ssl-client-subject-dn": raw_dn,
        "X-LunaNexa-Subject": "forged-fallback",
      },
      false,
    ),
    Some(expected),
  )
  assert_false(loopback_client(@socket.Addr::parse("192.0.2.10:443")))
  assert_true(loopback_client(@socket.Addr::parse("127.0.0.1:443")))
}
