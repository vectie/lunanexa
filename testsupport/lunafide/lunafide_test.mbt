///|
fn verification_request(
  idempotency_key : String,
  tenant_ref? : String = "tenant-a",
) -> @lunafide.VerificationRequest {
  {
    protocol_version: @lunafide.protocol_version,
    idempotency_key,
    tenant_ref,
    subject_ref: "opaque-organization-a",
    subject_type: Organization,
    requested_unix_ms: 100L,
  }
}

///|
fn envelope_request(idempotency_key : String) -> @lunafide.EnvelopeRequest {
  {
    protocol_version: @lunafide.protocol_version,
    idempotency_key,
    tenant_ref: "tenant-a",
    template_ref: "framework-v1",
    document_sha256: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    signer_ref: "opaque-signer-a",
    countersigner_ref: Some("opaque-platform-signer"),
    expires_unix_ms: 1000L,
    requested_unix_ms: 100L,
  }
}

///|
fn invoice_request(
  idempotency_key : String,
  currency? : String = "CNY",
  amount_minor? : Int64 = 4200L,
) -> @lunafide.InvoiceRequest {
  {
    protocol_version: @lunafide.protocol_version,
    idempotency_key,
    tenant_ref: "tenant-a",
    bill_ref: "bill-a",
    billing_profile_ref: "opaque-billing-profile-a",
    amount_minor,
    currency,
    bill_content_sha256: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    requested_unix_ms: 200L,
  }
}

///|
test "service identity is explicit test-only and non-production" {
  let identity = @lunafide.service_identity()
  assert_eq(identity.service_name, "LunaFide")
  assert_eq(identity.protocol_version, "qualified-services.v1")
  assert_eq(identity.mode, TestOnly)
  assert_false(identity.production_ready)
  assert_false(identity.stores_real_pii)
  assert_false(identity.stores_payment_credentials)
  assert_true(identity.trust_claim.contains("none"))
  let service = @lunafide.LunaFide::new("test-secret")
  let health = service.health(123L)
  assert_eq(health.status, "ok")
  assert_eq(health.state_backend, "ephemeral-in-memory")
}

///|
test "verification requests and resolutions replay idempotently" {
  let service = @lunafide.LunaFide::new("test-secret")
  let request = verification_request("create-a")
  let first = service.request_verification(request)
  let replay = service.request_verification(request)
  assert_eq(first, replay)
  assert_eq(service.events().length(), 1)
  let resolution : @lunafide.VerificationResolution = {
    protocol_version: @lunafide.protocol_version,
    idempotency_key: "resolve-a",
    tenant_ref: "tenant-a",
    verification_ref: first.verification_ref,
    state: Verified,
    reason_code: "simulated_verified",
    resolved_unix_ms: 101L,
  }
  let verified = service.resolve_verification(resolution)
  assert_eq(verified.state, Verified)
  assert_eq(service.resolve_verification(resolution), verified)
  assert_eq(service.events().length(), 2)
}

///|
test "same idempotency key with different content is rejected" {
  let service = @lunafide.LunaFide::new("test-secret")
  ignore(service.request_verification(verification_request("same-key")))
  try
    service.request_verification({
      ..verification_request("same-key"),
      subject_ref: "opaque-different-subject",
    })
  catch {
    IdempotencyConflict(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("expected idempotency conflict")
  }
  assert_eq(service.events().length(), 1)
}

///|
test "cross-tenant verification resolution is hidden and rejected" {
  let service = @lunafide.LunaFide::new("test-secret")
  let created = service.request_verification(verification_request("create-a"))
  try
    service.resolve_verification({
      protocol_version: @lunafide.protocol_version,
      idempotency_key: "resolve-cross-tenant",
      tenant_ref: "tenant-b",
      verification_ref: created.verification_ref,
      state: Verified,
      reason_code: "attempted_cross_tenant",
      resolved_unix_ms: 101L,
    })
  catch {
    NotFound(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("expected tenant boundary rejection")
  }
}

///|
test "agreement execution requires signer then exact countersigner" {
  let service = @lunafide.LunaFide::new("test-secret")
  let envelope = service.create_envelope(envelope_request("envelope-a"))
  try
    service.record_signature({
      protocol_version: @lunafide.protocol_version,
      idempotency_key: "wrong-order",
      tenant_ref: "tenant-a",
      envelope_ref: envelope.envelope_ref,
      actor_ref: "opaque-platform-signer",
      party: Countersigner,
      decision: Signed,
      acted_unix_ms: 110L,
    })
  catch {
    IllegalTransition(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("countersignature must not precede signer")
  }
  let signer_action : @lunafide.SignatureAction = {
    protocol_version: @lunafide.protocol_version,
    idempotency_key: "signer-a",
    tenant_ref: "tenant-a",
    envelope_ref: envelope.envelope_ref,
    actor_ref: "opaque-signer-a",
    party: Signer,
    decision: Signed,
    acted_unix_ms: 111L,
  }
  let partial = service.record_signature(signer_action)
  assert_eq(partial.state, AwaitingCountersignature)
  assert_eq(service.record_signature(signer_action), partial)
  let executed = service.record_signature({
    protocol_version: @lunafide.protocol_version,
    idempotency_key: "counter-a",
    tenant_ref: "tenant-a",
    envelope_ref: envelope.envelope_ref,
    actor_ref: "opaque-platform-signer",
    party: Countersigner,
    decision: Signed,
    acted_unix_ms: 112L,
  })
  assert_eq(executed.state, Executed)
  assert_eq(executed.executed_unix_ms, Some(112L))
  assert_eq(service.events().length(), 3)
}

///|
test "expired envelopes and wrong actors cannot execute" {
  let service = @lunafide.LunaFide::new("test-secret")
  let envelope = service.create_envelope(envelope_request("envelope-expiry"))
  for
    row in [
      ("wrong-actor", "opaque-attacker", 110L),
      ("expired-action", "opaque-signer-a", 1001L),
    ] {
    let (idempotency_key, actor_ref, acted_unix_ms) = row
    try
      service.record_signature({
        protocol_version: @lunafide.protocol_version,
        idempotency_key,
        tenant_ref: "tenant-a",
        envelope_ref: envelope.envelope_ref,
        actor_ref,
        party: Signer,
        decision: Signed,
        acted_unix_ms,
      })
    catch {
      IllegalTransition(_) => ()
      ExpiredWebhook(_) => ()
      _ => fail("unexpected error kind")
    } noraise {
      _ => fail("expected signature action rejection")
    }
  }
}

///|
test "payment simulator exposes success decline and review without credentials" {
  let service = @lunafide.LunaFide::new("test-secret")
  let outcomes : Array[(@lunafide.PaymentOutcome, @lunafide.PaymentState)] = [
    (Succeed, Settled),
    (Decline, Declined),
    (RequireReview, UnderReview),
  ]
  for index, pair in outcomes {
    let (outcome, expected) = pair
    let record = service.request_payment({
      protocol_version: @lunafide.protocol_version,
      idempotency_key: "payment-\{index}",
      tenant_ref: "tenant-a",
      order_ref: "order-\{index}",
      amount_minor: 4200L,
      currency: "CNY",
      simulated_outcome: outcome,
      requested_unix_ms: 100L + index.to_int64(),
    })
    assert_eq(record.state, expected)
    assert_false(record.to_json().stringify().contains("card"))
  }
}

///|
test "invalid commercial amounts currencies and references fail closed" {
  let service = @lunafide.LunaFide::new("test-secret")
  for
    request in [
      invoice_request("zero", amount_minor=0L),
      invoice_request("negative", amount_minor=-1L),
      invoice_request("lowercase", currency="cny"),
      invoice_request("long-currency", currency="CNYX"),
      { ..invoice_request("bad-digest"), bill_content_sha256: "sha256:xyz" },
      { ..invoice_request("overlong"), billing_profile_ref: "x".repeat(257) },
    ] {
    try service.issue_invoice(request) catch {
      InvalidRequest(_) => ()
      _ => fail("unexpected error kind")
    } noraise {
      _ => fail("expected invalid invoice request")
    }
  }
  assert_eq(service.events().length(), 0)
}

///|
test "invoice void and reissue preserve lineage and forbid mutation" {
  let service = @lunafide.LunaFide::new("test-secret")
  let issued = service.issue_invoice(invoice_request("issue-a"))
  let void_action : @lunafide.InvoiceAction = {
    protocol_version: @lunafide.protocol_version,
    idempotency_key: "void-a",
    tenant_ref: "tenant-a",
    invoice_ref: issued.invoice_ref,
    reason_code: "simulated_correction",
    acted_unix_ms: 201L,
  }
  let voided = service.void_invoice(void_action)
  assert_eq(voided.state, Voided)
  assert_eq(service.void_invoice(void_action), voided)
  let replacement = service.reissue_invoice(issued.invoice_ref, {
    ..invoice_request("reissue-a"),
    bill_content_sha256: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    requested_unix_ms: 202L,
  })
  assert_eq(replacement.replaces_invoice_ref, Some(issued.invoice_ref))
  assert_eq(replacement.state, Issued)
  try
    service.reissue_invoice(issued.invoice_ref, {
      ..invoice_request("reissue-wrong-currency"),
      currency: "USD",
    })
  catch {
    InvalidRequest(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("expected currency preservation failure")
  }
  try
    service.reissue_invoice(issued.invoice_ref, {
      ..invoice_request("reissue-negative"),
      amount_minor: -1L,
    })
  catch {
    InvalidRequest(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("expected invalid reissue amount failure")
  }
  assert_eq(service.events().length(), 3)
}

///|
test "forged callback is rejected without poisoning valid event ID" {
  let service = @lunafide.LunaFide::new("test-secret")
  let record = service.request_verification(verification_request("callback-a"))
  let event = service.events()[0]
  let forged = { ..event, payload: Json::string("forged") }
  let receiver = @lunafide.WebhookReceiver::new()
  try
    receiver.accept(
      forged,
      "test-secret",
      "tenant-a",
      record.verification_ref,
      100L,
      10L,
    )
  catch {
    ForgedWebhook(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("forged callback was accepted")
  }
  receiver.accept(
    event,
    "test-secret",
    "tenant-a",
    record.verification_ref,
    100L,
    10L,
  )
}

///|
test "provider callback survives a JSON wire round trip" {
  let service = @lunafide.LunaFide::new("test-secret")
  ignore(service.request_verification(verification_request("json-roundtrip")))
  let event = service.events()[0]
  let wire = event.to_json().stringify()
  let decoded : @lunafide.WebhookEvent = @json.from_json(@json.parse(wire))
  assert_eq(decoded, event)
  assert_true(@lunafide.webhook_signature_valid(decoded, "test-secret"))
}

///|
test "valid MAC for another tenant or aggregate cannot cross binding" {
  let service = @lunafide.LunaFide::new("test-secret")
  let record = service.request_verification(verification_request("binding-a"))
  let original = service.events()[0]
  let unsigned = { ..original, tenant_ref: "tenant-b", signature: "" }
  let rebound = {
    ..unsigned,
    signature: @lunafide.sign_webhook(unsigned, "test-secret"),
  }
  assert_true(@lunafide.webhook_signature_valid(rebound, "test-secret"))
  let receiver = @lunafide.WebhookReceiver::new()
  try
    receiver.accept(
      rebound,
      "test-secret",
      "tenant-a",
      record.verification_ref,
      100L,
      10L,
    )
  catch {
    ForgedWebhook(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("cross-tenant signed callback was accepted")
  }
}

///|
test "callback replay stale ordering and expiry are rejected" {
  let service = @lunafide.LunaFide::new("test-secret")
  let record = service.request_verification(verification_request("ordering-a"))
  ignore(
    service.resolve_verification({
      protocol_version: @lunafide.protocol_version,
      idempotency_key: "ordering-resolution",
      tenant_ref: "tenant-a",
      verification_ref: record.verification_ref,
      state: Verified,
      reason_code: "simulated_verified",
      resolved_unix_ms: 101L,
    }),
  )
  let events = service.events()
  let receiver = @lunafide.WebhookReceiver::new()
  receiver.accept(
    events[1],
    "test-secret",
    "tenant-a",
    record.verification_ref,
    101L,
    10L,
  )
  try
    receiver.accept(
      events[1],
      "test-secret",
      "tenant-a",
      record.verification_ref,
      101L,
      10L,
    )
  catch {
    ReplayWebhook(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("callback replay was accepted")
  }
  try
    receiver.accept(
      events[0],
      "test-secret",
      "tenant-a",
      record.verification_ref,
      101L,
      10L,
    )
  catch {
    StaleWebhook(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("stale callback was accepted")
  }
  let fresh_receiver = @lunafide.WebhookReceiver::new()
  try
    fresh_receiver.accept(
      events[0],
      "test-secret",
      "tenant-a",
      record.verification_ref,
      1000L,
      10L,
    )
  catch {
    ExpiredWebhook(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("expired callback was accepted")
  }
}

///|
test "empty test secret is rejected and never degrades to unsigned callbacks" {
  try @lunafide.LunaFide::new("") catch {
    InvalidRequest(_) => ()
    _ => fail("unexpected error kind")
  } noraise {
    _ => fail("empty secret was accepted")
  }
}
