///|
fn base_intent() -> @credential.CredentialHandoffIssueIntent {
  {
    request_id: "credential-url-test",
    lease_id: "lease-url-test",
    expected_generation: 1L,
    host_alias: "dgx.example",
    ssh_port: 22,
    host_key_fingerprint: "SHA256:abcdefghijklmnopqrstuvwxyzABCDEFG1234567890_-",
    issuer_redirect_url: "https://ssh-ca.example/redeem/url-test",
  }
}

///|
test "credential issuer URL rejects credentials queries fragments and ambiguity" {
  @credential.validate_issue_intent(base_intent())
  for
    value in [
      "https://ssh-ca.example", "https:///redeem/path", "https://ssh-ca.example/",
      "https://user@ssh-ca.example/redeem/path", "https://ssh-ca.example/redeem/path?token=secret",
      "https://ssh-ca.example/redeem/path#fragment", "https://ssh-ca.example/redeem\\path",
      "https://ssh-ca.example/redeem/%2e%2e/secret", "https://ssh-ca.example//evil.example/path",
      "http://ssh-ca.example/redeem/path", " https://ssh-ca.example/redeem/path",
      "https://ssh-ca.example/redeem/path\nforged",
    ] {
    try {
      @credential.validate_issue_intent({
        ..base_intent(),
        issuer_redirect_url: value,
      })
      fail("unsafe issuer URL accepted: \{value}")
    } catch {
      @credential.CredentialHandoffError::InvalidInput(_) => ()
      _ => fail("unexpected issuer URL error")
    }
  }
}

///|
test "credential issuer readiness expires and rejects simulated health" {
  let evidence : @credential.CredentialIssuerReadinessEvidence = {
    version: @credential.issuer_readiness_contract_version,
    adapter_id: "ssh-ca-primary",
    health_endpoint: "https://ssh-ca.example/healthz",
    evidence_ref: "retained-issuer-health-20260813",
    checked_unix_ms: 1000L,
    expires_unix_ms: 61000L,
    healthy: true,
    signature: "a".repeat(64),
  }
  assert_true(@credential.credential_issuer_evidence_ready(evidence, 1000L))
  assert_false(@credential.credential_issuer_evidence_ready(evidence, 61000L))
  assert_false(
    @credential.credential_issuer_evidence_ready(
      { ..evidence, healthy: false },
      1000L,
    ),
  )
  assert_false(
    @credential.credential_issuer_evidence_ready(
      { ..evidence, health_endpoint: "http://attacker.example/health" },
      1000L,
    ),
  )
  assert_true(
    @credential.credential_issuer_origin_matches(
      evidence, "https://ssh-ca.example/redeem/request-a",
    ),
  )
  for
    redirect in [
      "https://other.example/redeem/request-a", "https://ssh-ca.example.evil/redeem/request-a",
      "https://ssh-ca.example:444/redeem/request-a",
    ] {
    assert_false(
      @credential.credential_issuer_origin_matches(evidence, redirect),
    )
  }
}
