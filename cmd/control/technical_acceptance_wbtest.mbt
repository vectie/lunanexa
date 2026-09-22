///|
test "technical acceptance configuration is disabled by default and bounded" {
  assert_true(technical_acceptance_authorization(None) is None)
  let source = (
    {
      "order_id": "technical-acceptance-test-order",
      "purchaser_subject_ref": "technical-subject",
      "user_authorization_ref": "test-explicit-authorization",
      "expires_unix_ms": "1234",
    } : Json).stringify()
  guard technical_acceptance_authorization(Some(source)) is Some(scope) else {
    fail("expected exact explicit scope")
  }
  assert_eq(scope.order_id, "technical-acceptance-test-order")
  assert_eq(scope.purchaser_subject_ref, "technical-subject")
  assert_eq(scope.expires_unix_ms, 1234L)
  for malformed in ["", "{invalid-private-config", "x".repeat(4097), "{}"] {
    try technical_acceptance_authorization(Some(malformed)) catch {
      _ => ()
    } noraise {
      _ => fail("malformed technical scope was accepted")
    }
  }
}
