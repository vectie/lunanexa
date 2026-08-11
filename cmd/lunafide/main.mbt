///|
/// Runs a deterministic happy-path scenario and prints JSON lines. This is a
/// test fixture, not a network service and not a production provider emulator.
fn main raise {
  let service = @provider.LunaFide::new("public-test-fixture-secret")
  println(service.health(1700000000000L).to_json().stringify())
  let verification = service.request_verification({
    protocol_version: @provider.protocol_version,
    idempotency_key: "verify-create-1",
    tenant_ref: "tenant-demo",
    subject_ref: "opaque-organization-demo",
    subject_type: Organization,
    requested_unix_ms: 1700000000001L,
  })
  ignore(
    service.resolve_verification({
      protocol_version: @provider.protocol_version,
      idempotency_key: "verify-resolve-1",
      tenant_ref: "tenant-demo",
      verification_ref: verification.verification_ref,
      state: Verified,
      reason_code: "simulated_verified",
      resolved_unix_ms: 1700000000002L,
    }),
  )
  let envelope = service.create_envelope({
    protocol_version: @provider.protocol_version,
    idempotency_key: "envelope-create-1",
    tenant_ref: "tenant-demo",
    template_ref: "framework-v1",
    document_sha256: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    signer_ref: "opaque-signer-demo",
    countersigner_ref: Some("opaque-platform-signer"),
    expires_unix_ms: 1700001000000L,
    requested_unix_ms: 1700000000003L,
  })
  ignore(
    service.record_signature({
      protocol_version: @provider.protocol_version,
      idempotency_key: "envelope-sign-1",
      tenant_ref: "tenant-demo",
      envelope_ref: envelope.envelope_ref,
      actor_ref: "opaque-signer-demo",
      party: Signer,
      decision: Signed,
      acted_unix_ms: 1700000000004L,
    }),
  )
  ignore(
    service.record_signature({
      protocol_version: @provider.protocol_version,
      idempotency_key: "envelope-countersign-1",
      tenant_ref: "tenant-demo",
      envelope_ref: envelope.envelope_ref,
      actor_ref: "opaque-platform-signer",
      party: Countersigner,
      decision: Signed,
      acted_unix_ms: 1700000000005L,
    }),
  )
  ignore(
    service.request_payment({
      protocol_version: @provider.protocol_version,
      idempotency_key: "payment-1",
      tenant_ref: "tenant-demo",
      order_ref: "order-demo",
      amount_minor: 4200L,
      currency: "CNY",
      simulated_outcome: Succeed,
      requested_unix_ms: 1700000000006L,
    }),
  )
  let invoice = service.issue_invoice({
    protocol_version: @provider.protocol_version,
    idempotency_key: "invoice-1",
    tenant_ref: "tenant-demo",
    bill_ref: "bill-demo",
    billing_profile_ref: "opaque-billing-profile",
    amount_minor: 4200L,
    currency: "CNY",
    bill_content_sha256: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    requested_unix_ms: 1700000000007L,
  })
  ignore(
    service.void_invoice({
      protocol_version: @provider.protocol_version,
      idempotency_key: "invoice-void-1",
      tenant_ref: "tenant-demo",
      invoice_ref: invoice.invoice_ref,
      reason_code: "simulated_correction",
      acted_unix_ms: 1700000000008L,
    }),
  )
  ignore(
    service.reissue_invoice(invoice.invoice_ref, {
      protocol_version: @provider.protocol_version,
      idempotency_key: "invoice-reissue-1",
      tenant_ref: "tenant-demo",
      bill_ref: "bill-demo",
      billing_profile_ref: "opaque-billing-profile",
      amount_minor: 4200L,
      currency: "CNY",
      bill_content_sha256: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      requested_unix_ms: 1700000000009L,
    }),
  )
  for event in service.events() {
    println(event.to_json().stringify())
  }
}
