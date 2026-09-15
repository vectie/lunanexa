///|
test "simulator renews before expiry and after downtime" {
  let certificate : @node_agent.NodeCertificate = {
    node_id: "simulation-only",
    serial: 1L,
    issued_unix_ms: 1000L,
    expires_unix_ms: 3601000L,
    public_key_ref: "simulator-only:simulation-only",
  }
  assert_false(certificate_needs_renewal(certificate, 1000L))
  assert_false(certificate_needs_renewal(certificate, 3300999L))
  assert_true(certificate_needs_renewal(certificate, 3301000L))
  assert_true(certificate_needs_renewal(certificate, 3601000L))
  assert_true(certificate_needs_renewal(certificate, 7201000L))
}
