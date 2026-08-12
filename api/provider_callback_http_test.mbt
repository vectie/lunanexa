///|
async test "provider callback requires signed bound replay-safe transport" {
  let directory = @fs.tmpdir(prefix="lunanexa-provider-callback-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let secret = "provider-callback-test-secret-32-bytes-minimum"
  let portal_store = @portal_store.FilePortalStore::open(
    "\{directory}/portal.json",
  )
  let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_provider_callback_secrets({ "provider-a|sandbox": secret })
    .with_portal_store(portal_store)
  let now = @async.now()
  let operator = { "Authorization": "Bearer operator-token" }
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/operator/memberships",
      operator,
      @portal.EnterpriseMembership::{
        membership_id: "membership-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "subject-a",
        roles: [LegalSigner],
        active: true,
        created_unix_ms: now - 2000L,
      }
      .to_json()
      .stringify(),
    ).status,
    201,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/operator/agreements",
      operator,
      @portal.PortalAgreement::{
        agreement_id: "agreement-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        template_ref: "framework-v1",
        title: "Framework",
        summary: "Exclusive machine lease agreement",
        rendered_document_hash: "sha256:document-a",
        state: ReviewRequired,
        generation: 1L,
        signer_subject_ref: None,
        signature_request_receipt: None,
        executed_artifact_hash: None,
        created_unix_ms: now - 2000L,
        updated_unix_ms: now - 2000L,
      }
      .to_json()
      .stringify(),
    ).status,
    201,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/signature-requests",
      {
        "Authorization": "Bearer inference-token",
        "X-LunaNexa-Subject": "subject-a",
      },
      @portal.SignatureRequest::{
        agreement_id: "agreement-a",
        expected_generation: 1L,
        idempotency_key: "signature-request-a",
      }
      .to_json()
      .stringify(),
    ).status,
    202,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/operator/agreement-executions",
      operator,
      @portal.AgreementExecution::{
        agreement_id: "agreement-a",
        expected_generation: 2L,
        signer_subject_ref: "subject-a",
        executed_artifact_hash: "sha256:document-a",
        evidence_receipt: "operator:self-asserted",
      }
      .to_json()
      .stringify(),
    ).status,
    409,
  )
  let record : @commercial_integrations.ExternalRecord = {
    record_id: "signature-a",
    organization_id: "org-a",
    kind: QualifiedSignature,
    provider: "provider-a",
    environment: "sandbox",
    external_ref: "envelope-a",
    state: Pending,
    expected_amount_minor: None,
    currency: None,
    money_scale: None,
    expected_document_hash: Some("sha256:document-a"),
    entitlement_transaction_ref: Some("portal-agreement:agreement-a"),
    created_unix_ms: now - 1000L,
    updated_unix_ms: now - 1000L,
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/commercial/external-records",
      operator,
      record.to_json().stringify(),
    ).status,
    201,
  )
  let event_now = @async.now()
  let callback : @commercial_integrations.ExternalCallback = {
    callback_id: "event-a",
    record_id: "signature-a",
    organization_id: "org-a",
    provider: "provider-a",
    environment: "sandbox",
    external_ref: "envelope-a",
    expected_previous_state: Pending,
    next_state: Verified,
    amount_minor: None,
    currency: None,
    document_hash: Some("sha256:document-a"),
    provider_event_unix_ms: event_now,
    received_unix_ms: event_now,
    signature_verified: false,
  }
  let body = callback.to_json().stringify()
  let signature = @api.provider_callback_signature(
    "provider-a", "sandbox", "event-a", event_now, body, secret,
  )
  let headers = {
    "X-LunaNexa-Provider": "provider-a",
    "X-LunaNexa-Environment": "sandbox",
    "X-LunaNexa-Event-Id": "event-a",
    "X-LunaNexa-Event-Timestamp": event_now.to_string(),
    "X-LunaNexa-Signature": signature,
  }
  let accepted = service.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    headers,
    body,
  )
  assert_eq(accepted.status, 200)
  assert_true(accepted.body.contains("Verified"))
  let portal_view = service.handle(
    Get,
    "/v1/portal/self",
    {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "subject-a",
    },
    "",
  )
  assert_eq(portal_view.status, 200)
  assert_true(portal_view.body.contains("Executed"))
  let replay = service.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    headers,
    body,
  )
  assert_eq(replay.status, 200)
  assert_true(replay.body.contains("Replayed"))
  let tampered = service.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    headers,
    body.replace_all(old="sha256:document-a", new="sha256:document-b"),
  )
  assert_eq(tampered.status, 401)
  let direct = service.handle(
    Post,
    "/v1/commercial/external-callbacks",
    { "Authorization": "Bearer operator-token" },
    { ..callback, signature_verified: true }.to_json().stringify(),
  )
  assert_eq(direct.status, 409)
  assert_true(direct.body.contains("VerifiedTransportRequired"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "provider callback rejects stale and cross-provider headers" {
  let directory = @fs.tmpdir(prefix="lunanexa-provider-callback-deny-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let secret = "provider-callback-test-secret-32-bytes-minimum"
  let service = @api.ApiService::new(
    @store.FileStore::open("\{directory}/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  ).with_provider_callback_secrets({ "provider-a|sandbox": secret })
  let stale = @async.now() - 300001L
  let body = "{}"
  let signature = @api.provider_callback_signature(
    "provider-a", "sandbox", "event-stale", stale, body, secret,
  )
  let headers = {
    "X-LunaNexa-Provider": "provider-a",
    "X-LunaNexa-Environment": "sandbox",
    "X-LunaNexa-Event-Id": "event-stale",
    "X-LunaNexa-Event-Timestamp": stale.to_string(),
    "X-LunaNexa-Signature": signature,
  }
  let expired = service.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    headers,
    body,
  )
  assert_eq(expired.status, 401)
  assert_true(expired.body.contains("CallbackExpired"))
  let crossed_headers = headers.copy()
  crossed_headers["X-LunaNexa-Provider"] = "provider-b"
  let crossed = service.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    crossed_headers,
    body,
  )
  assert_eq(crossed.status, 401)
  @fs.rmdir(directory, recursive=true)
}
