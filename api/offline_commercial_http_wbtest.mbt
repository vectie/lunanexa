///|
test "offline upload projection and operator actor are server-owned" {
  let grant : @offline.EvidenceUploadGrant = {
    grant_id: "grant-safe-view",
    idempotency_key: "secret-idempotency-key",
    order_id: "order-safe-view",
    organization_id: "org-safe-view",
    subject_ref: "spoofed-customer",
    artifact_id: "artifact-safe-view",
    kind: PaymentReceipt,
    revision: 1,
    expected_object_ref: "object://private-bucket/org/order/artifact",
    allowed_media_types: ["application/pdf"],
    maximum_byte_count: 1000L,
    expires_unix_ms: 2000003600000L,
    state: UploadGranted,
    created_unix_ms: 2000000000000L,
  }
  let encoded = grant.public_view().to_json().stringify()
  assert_true(encoded.contains("grant-safe-view"))
  assert_false(encoded.contains("object://"))
  assert_false(encoded.contains("spoofed-customer"))
  assert_false(encoded.contains("secret-idempotency-key"))
  assert_eq(offline_operator_actor(Map([])), "platform-operator")
  let mtls = offline_operator_actor({
    "ssl-client-verify": "SUCCESS",
    "ssl-client-subject-dn": "CN=operator-7,O=LunaNexa",
    "X-LunaNexa-Subject": "spoofed-operator",
  })
  assert_true(mtls.has_prefix("mtls:sha256:"))
  assert_false(mtls.contains("spoofed-operator"))
}
