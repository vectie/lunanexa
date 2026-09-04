///|
async fn configure_provider_test_period(service : @api.ApiService) -> Unit {
  let operator = { "Authorization": "Bearer operator-token" }
  ignore(
    service.handle(
      Post,
      "/v1/commercial/organizations",
      operator,
      @commercial.Organization::{
        organization_id: "org-a",
        display_name: "Organization A",
        state: Active,
        verification_ref: Some("verified:org-a"),
        created_unix_ms: 1000L,
      }
      .to_json()
      .stringify(),
    ),
  )
  ignore(
    service.handle(
      Post,
      "/v1/commercial/cost-centers",
      operator,
      @commercial.CostCenter::{
        cost_center_id: "center-a",
        organization_id: "org-a",
        parent_cost_center_id: None,
        display_name: "AI",
        created_unix_ms: 1001L,
      }
      .to_json()
      .stringify(),
    ),
  )
  ignore(
    service.handle(
      Post,
      "/v1/commercial/projects",
      operator,
      @commercial.Project::{
        project_id: "project-a",
        organization_id: "org-a",
        cost_center_id: "center-a",
        display_name: "Inference",
        created_unix_ms: 1002L,
      }
      .to_json()
      .stringify(),
    ),
  )
  ignore(
    service.handle(
      Post,
      "/v1/commercial/usage",
      operator,
      @commercial.UsageObservation::{
        event_id: "usage-a",
        organization_id: "org-a",
        project_id: "project-a",
        actor_ref: "subject-a",
        workload_id: "workload-a",
        node_id: "node-a",
        lease_epoch: 1L,
        meter: "accelerator-second",
        quantity: 64L,
        unit: "second",
        started_unix_ms: 2000L,
        ended_unix_ms: 66000L,
        observed_unix_ms: 66001L,
      }
      .to_json()
      .stringify(),
    ),
  )
  let rate : @commercial.RateCard = {
    rate_card_id: "rate-a",
    version: "v1",
    meter: "accelerator-second",
    unit: "second",
    unit_price: @commercial.money(200L, "CNY", 2),
    effective_from_unix_ms: 1L,
    effective_until_unix_ms: 100000L,
  }
  ignore(
    service.handle(
      Post,
      "/v1/commercial/usage:rate",
      operator,
      (
        {
          "event_id": "usage-a",
          "entry_id": "entry-a",
          "rate": rate.to_json(),
          "recorded_unix_ms": 66002L.to_json(),
        } : Json).stringify(),
    ),
  )
  ignore(
    service.handle(
      Post,
      "/v1/commercial/periods:finalize",
      operator,
      (
        {
          "period_id": "period-a",
          "organization_id": "org-a",
          "started_unix_ms": 1L.to_json(),
          "ended_unix_ms": 70000L.to_json(),
          "billing_timezone": "UTC",
          "currency": "CNY",
          "scale": 2,
          "finalized_by": "operator",
          "finalized_unix_ms": 70001L.to_json(),
        } : Json).stringify(),
    ),
  )
}

///|
async test "commercial provider outbox closes checkout initiation without controller SSRF" {
  let directory = @fs.tmpdir(prefix="lunanexa-provider-outbox-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let callback_secret = "provider-callback-secret-more-than-32-bytes"
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_provider_callback_secrets({ "provider-a|sandbox": callback_secret })
    .with_commercial_provider_adapter(
      "provider-adapter-machine-token-more-than-32-bytes", "provider-a", "sandbox",
      "https://payments.example",
    )
  let operator = { "Authorization": "Bearer operator-token" }
  configure_provider_test_period(service)
  let now = @async.now()
  for
    membership in [
      @portal.EnterpriseMembership::{
        membership_id: "billing-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "subject-a",
        roles: [BillingViewer],
        active: true,
        created_unix_ms: now,
      },
      {
        membership_id: "billing-b",
        tenant_ref: "tenant-b",
        organization_id: "org-b",
        subject_ref: "subject-b",
        roles: [BillingViewer],
        active: true,
        created_unix_ms: now,
      },
      {
        membership_id: "developer-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "developer-a",
        roles: [Developer],
        active: true,
        created_unix_ms: now,
      },
    ] {
    assert_eq(
      service.handle(
        Post,
        "/v1/portal/operator/memberships",
        operator,
        membership.to_json().stringify(),
      ).status,
      201,
    )
  }
  let customer = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/payment-checkouts",
      {
        "Authorization": "Bearer inference-token",
        "X-LunaNexa-Subject": "developer-a",
      },
      (
        #|{"idempotency_key":"developer-denied","period_id":"period-a"}
      ),
    ).status,
    403,
  )
  let queued = service.handle(
    Post,
    "/v1/portal/payment-checkouts",
    customer,
    (
      #|{"idempotency_key":"checkout-a","period_id":"period-a"}
    ),
  )
  assert_eq(queued.status, 202)
  assert_true(queued.body.contains("Pending"))
  assert_false(queued.body.contains("action_url"))
  let replayed = service.handle(
    Post,
    "/v1/portal/payment-checkouts",
    customer,
    (
      #|{"idempotency_key":"another-browser-retry","period_id":"period-a"}
    ),
  )
  assert_eq(replayed.status, 202)
  assert_eq(replayed.body, queued.body)
  assert_eq(
    service.handle(
      Get,
      "/internal/v1/commercial-provider/requests",
      { "Authorization": "Bearer wrong" },
      "",
    ).status,
    401,
  )
  let adapter = {
    "Authorization": "Bearer provider-adapter-machine-token-more-than-32-bytes",
  }
  let claimed = service.handle(
    Get,
    "/internal/v1/commercial-provider/requests",
    adapter,
    "",
  )
  assert_eq(claimed.status, 200)
  assert_false(claimed.body.contains("org-a"))
  assert_false(claimed.body.contains("subject-a"))
  let intents : Array[@commercial_integrations.ExternalProviderIntent] = @json.from_json(
    @json.parse(claimed.body),
  )
  assert_eq(intents.length(), 1)
  let accepted = @async.now()
  let receipt : @commercial_integrations.ExternalDispatchReceipt = {
    record_id: intents[0].record_id,
    provider: intents[0].provider,
    environment: intents[0].environment,
    external_ref: intents[0].external_ref,
    action_url: "https://payments.example/checkout/opaque?token=one-time",
    action_expires_unix_ms: accepted + 5L,
    accepted_unix_ms: accepted,
  }
  assert_eq(
    service.handle(
      Post,
      "/internal/v1/commercial-provider/dispatch-receipts",
      adapter,
      receipt.to_json().stringify(),
    ).status,
    200,
  )
  let customer_view = service.handle(
    Get,
    "/v1/portal/self/provider-requests",
    customer,
    "",
  )
  assert_eq(customer_view.status, 200)
  assert_true(customer_view.body.contains("Submitted"))
  assert_true(customer_view.body.contains(receipt.action_url))
  let developer_view = service.handle(
    Get,
    "/v1/portal/self/provider-requests",
    {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "developer-a",
    },
    "",
  )
  assert_eq(developer_view.status, 200)
  assert_false(developer_view.body.contains(receipt.action_url))
  assert_false(developer_view.body.contains(intents[0].record_id))
  let other_customer = service.handle(
    Get,
    "/v1/portal/self/provider-requests",
    {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "subject-b",
    },
    "",
  )
  assert_eq(other_customer.status, 200)
  assert_false(other_customer.body.contains(receipt.action_url))
  assert_eq(
    service.handle(
      Get,
      "/internal/v1/commercial-provider/requests",
      adapter,
      "",
    ).body,
    "[]",
  )
  @async.sleep(10)
  let renewed_checkout = service.handle(
    Post,
    "/v1/portal/payment-checkouts",
    customer,
    (
      #|{"idempotency_key":"renew-checkout","period_id":"period-a"}
    ),
  )
  assert_eq(renewed_checkout.status, 202)
  let renewed_intents : Array[@commercial_integrations.ExternalProviderIntent] = @json.from_json(
    @json.parse(
      service.handle(
        Get,
        "/internal/v1/commercial-provider/requests",
        adapter,
        "",
      ).body,
    ),
  )
  assert_eq(renewed_intents.length(), 1)
  assert_eq(renewed_intents[0].record_id, intents[0].record_id)
  assert_eq(
    service.handle(
      Post,
      "/internal/v1/commercial-provider/dispatch-receipts",
      adapter,
      receipt.to_json().stringify(),
    ).status,
    409,
  )
  let renewed_at = @async.now()
  let renewed_receipt = {
    ..receipt,
    action_url: "https://payments.example/checkout/opaque?token=renewed",
    accepted_unix_ms: renewed_at,
    action_expires_unix_ms: renewed_at + 600000L,
  }
  assert_eq(
    service.handle(
      Post,
      "/internal/v1/commercial-provider/dispatch-receipts",
      adapter,
      renewed_receipt.to_json().stringify(),
    ).status,
    200,
  )
  let event_now = @async.now()
  let callback : @commercial_integrations.ExternalCallback = {
    callback_id: "payment-settled-a",
    record_id: intents[0].record_id,
    organization_id: "org-a",
    provider: intents[0].provider,
    environment: intents[0].environment,
    external_ref: intents[0].external_ref,
    expected_previous_state: Submitted,
    next_state: Settled,
    amount_minor: intents[0].expected_amount_minor,
    currency: intents[0].currency,
    document_hash: None,
    provider_event_unix_ms: event_now,
    received_unix_ms: event_now,
    signature_verified: false,
  }
  let callback_body = callback.to_json().stringify()
  let callback_signature = @api.provider_callback_signature(
    "provider-a",
    "sandbox",
    callback.callback_id,
    event_now,
    callback_body,
    callback_secret,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/provider-callbacks/commercial",
      {
        "X-LunaNexa-Provider": "provider-a",
        "X-LunaNexa-Environment": "sandbox",
        "X-LunaNexa-Event-Id": callback.callback_id,
        "X-LunaNexa-Event-Timestamp": event_now.to_string(),
        "X-LunaNexa-Signature": callback_signature,
      },
      callback_body,
    ).status,
    200,
  )
  let after_settlement = service.handle(
    Post,
    "/v1/portal/payment-checkouts",
    customer,
    (
      #|{"idempotency_key":"post-settlement-retry","period_id":"period-a"}
    ),
  )
  assert_eq(after_settlement.status, 200)
  assert_true(after_settlement.body.contains("Settled"))
  assert_eq(
    service.handle(
      Get,
      "/internal/v1/commercial-provider/requests",
      adapter,
      "",
    ).body,
    "[]",
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "commercial provider outbox fails closed and rejects unsafe actions" {
  let directory = @fs.tmpdir(prefix="lunanexa-provider-outbox-deny-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  let base = @api.ApiService::new(
    @store.FileStore::open("\{directory}/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  ).with_portal_store(portal)
  assert_eq(
    base.handle(
      Post,
      "/v1/portal/operator/memberships",
      { "Authorization": "Bearer operator-token" },
      @portal.EnterpriseMembership::{
        membership_id: "billing-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "subject-a",
        roles: [BillingViewer],
        active: true,
        created_unix_ms: @async.now(),
      }
      .to_json()
      .stringify(),
    ).status,
    201,
  )
  let body =
    #|{"idempotency_key":"checkout-a","period_id":"period-a"}
  let customer = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  assert_eq(
    base.handle(Post, "/v1/portal/payment-checkouts", customer, body).status,
    503,
  )
  let service = base
    .with_provider_callback_secrets({
      "provider-a|sandbox": "provider-callback-secret-more-than-32-bytes",
    })
    .with_commercial_provider_adapter(
      "provider-adapter-machine-token-more-than-32-bytes", "provider-a", "sandbox",
      "https://payments.example",
    )
  configure_provider_test_period(service)
  assert_eq(
    service.handle(Post, "/v1/portal/payment-checkouts", customer, body).status,
    202,
  )
  let adapter = {
    "Authorization": "Bearer provider-adapter-machine-token-more-than-32-bytes",
  }
  let intents : Array[@commercial_integrations.ExternalProviderIntent] = @json.from_json(
    @json.parse(
      service.handle(
        Get,
        "/internal/v1/commercial-provider/requests",
        adapter,
        "",
      ).body,
    ),
  )
  let intent = intents[0]
  let accepted = @async.now()
  let unsafe_receipt : @commercial_integrations.ExternalDispatchReceipt = {
    record_id: intent.record_id,
    provider: intent.provider,
    environment: intent.environment,
    external_ref: intent.external_ref,
    action_url: "http://169.254.169.254/latest/meta-data",
    action_expires_unix_ms: accepted + 600000L,
    accepted_unix_ms: accepted,
  }
  let rejected = service.handle(
    Post,
    "/internal/v1/commercial-provider/dispatch-receipts",
    adapter,
    unsafe_receipt.to_json().stringify(),
  )
  assert_eq(rejected.status, 400)
  assert_false(rejected.body.contains("169.254.169.254"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "signature outbox repairs crash renews expiry and isolates signer action" {
  let directory = @fs.tmpdir(prefix="lunanexa-signature-outbox-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_provider_callback_secrets({
      "provider-a|sandbox": "provider-callback-secret-more-than-32-bytes",
    })
    .with_commercial_provider_adapter(
      "provider-adapter-machine-token-more-than-32-bytes", "provider-a", "sandbox",
      "https://signatures.example",
    )
  let operator = { "Authorization": "Bearer operator-token" }
  let now = @async.now()
  for
    membership in [
      @portal.EnterpriseMembership::{
        membership_id: "signer-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "signer-a",
        roles: [LegalSigner],
        active: true,
        created_unix_ms: now,
      },
      {
        membership_id: "signer-b",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "signer-b",
        roles: [LegalSigner],
        active: true,
        created_unix_ms: now,
      },
      {
        membership_id: "developer-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "developer-a",
        roles: [Developer],
        active: true,
        created_unix_ms: now,
      },
    ] {
    assert_eq(
      service.handle(
        Post,
        "/v1/portal/operator/memberships",
        operator,
        membership.to_json().stringify(),
      ).status,
      201,
    )
  }
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
        summary: "Qualified signature test",
        rendered_document_hash: "sha256:document-a",
        state: ReviewRequired,
        generation: 1L,
        signer_subject_ref: None,
        signature_request_receipt: None,
        executed_artifact_hash: None,
        created_unix_ms: now,
        updated_unix_ms: now,
      }
      .to_json()
      .stringify(),
    ).status,
    201,
  )
  // Simulate a crash window: the legal state was persisted, but the provider
  // outbox record was never written.
  let requested = portal.request_signature(
    "signer-a",
    {
      agreement_id: "agreement-a",
      expected_generation: 1L,
      idempotency_key: "lost-before-outbox",
    },
    now + 1L,
  )
  assert_eq(requested.state, SignatureRequested)
  let signer = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "signer-a",
  }
  let repaired = service.handle(
    Post,
    "/v1/portal/signature-requests",
    signer,
    @portal.SignatureRequest::{
      agreement_id: "agreement-a",
      expected_generation: 1L,
      idempotency_key: "new-browser-retry",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(repaired.status, 202)
  let adapter = {
    "Authorization": "Bearer provider-adapter-machine-token-more-than-32-bytes",
  }
  let intents : Array[@commercial_integrations.ExternalProviderIntent] = @json.from_json(
    @json.parse(
      service.handle(
        Get,
        "/internal/v1/commercial-provider/requests",
        adapter,
        "",
      ).body,
    ),
  )
  assert_eq(intents.length(), 1)
  let accepted = @async.now()
  let old_receipt : @commercial_integrations.ExternalDispatchReceipt = {
    record_id: intents[0].record_id,
    provider: intents[0].provider,
    environment: intents[0].environment,
    external_ref: intents[0].external_ref,
    action_url: "https://signatures.example/sign/old",
    action_expires_unix_ms: accepted + 5L,
    accepted_unix_ms: accepted,
  }
  assert_eq(
    service.handle(
      Post,
      "/internal/v1/commercial-provider/dispatch-receipts",
      adapter,
      old_receipt.to_json().stringify(),
    ).status,
    200,
  )
  let signer_view = service.handle(
    Get,
    "/v1/portal/self/provider-requests",
    signer,
    "",
  )
  assert_true(signer_view.body.contains(old_receipt.action_url))
  for subject in ["signer-b", "developer-a"] {
    let denied_view = service.handle(
      Get,
      "/v1/portal/self/provider-requests",
      {
        "Authorization": "Bearer inference-token",
        "X-LunaNexa-Subject": subject,
      },
      "",
    )
    assert_eq(denied_view.status, 200)
    assert_false(denied_view.body.contains(old_receipt.action_url))
    assert_false(denied_view.body.contains(intents[0].record_id))
  }
  @async.sleep(10)
  let renewed = service.handle(
    Post,
    "/v1/portal/signature-requests",
    signer,
    @portal.SignatureRequest::{
      agreement_id: "agreement-a",
      expected_generation: 1L,
      idempotency_key: "renew-expired-action",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(renewed.status, 202)
  let renewed_intents : Array[@commercial_integrations.ExternalProviderIntent] = @json.from_json(
    @json.parse(
      service.handle(
        Get,
        "/internal/v1/commercial-provider/requests",
        adapter,
        "",
      ).body,
    ),
  )
  assert_eq(renewed_intents.length(), 1)
  assert_eq(renewed_intents[0].record_id, intents[0].record_id)
  assert_eq(
    service.handle(
      Post,
      "/internal/v1/commercial-provider/dispatch-receipts",
      adapter,
      old_receipt.to_json().stringify(),
    ).status,
    409,
  )
  let renewed_at = @async.now()
  let new_receipt = {
    ..old_receipt,
    action_url: "https://signatures.example/sign/new",
    accepted_unix_ms: renewed_at,
    action_expires_unix_ms: renewed_at + 600000L,
  }
  assert_eq(
    service.handle(
      Post,
      "/internal/v1/commercial-provider/dispatch-receipts",
      adapter,
      new_receipt.to_json().stringify(),
    ).status,
    200,
  )
  let final_view = service.handle(
    Get,
    "/v1/portal/self/provider-requests",
    signer,
    "",
  )
  assert_false(final_view.body.contains(old_receipt.action_url))
  assert_true(final_view.body.contains(new_receipt.action_url))
  @fs.rmdir(directory, recursive=true)
}
