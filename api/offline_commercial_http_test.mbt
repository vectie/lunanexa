///|
fn offline_ready_capabilities() -> Array[
  @offline.OfflineCommerceCapabilityEvidence,
] {
  let kinds : Array[@offline.OfflineCommerceCapability] = [
    ApprovedLegalTemplates,
    ObjectStorage,
    MalwareScanner,
    OoxmlWorker,
    PdfRenderer,
    SpreadsheetFormulaEngine,
    CjkFonts,
    MachineCallbackIdentity,
    EntitlementAuthority,
    FinanceLegalPolicy,
  ]
  kinds.mapi((index, capability) => {
    capability,
    configured: true,
    verified: true,
    evidence_ref: Some("evidence/readiness-\{index}"),
  })
}

///|
priv struct OfflineTestReversalRecoveryAction {
  recovery_id : String
  idempotency_key : String
  order_id : String
  failed_reversal_id : String
  expected_generation : Int64
  decision : @offline.ReversalRecoveryDecision
  replacement_reversal_id : String?
  authority_receipt : String
  reason_code : String
} derive(ToJson)

///|
extend OfflineTestReversalRecoveryAction with ToJson::{to_json}

///|
async fn offline_api_fixture(
  directory : String,
) -> (@api.ApiService, @offline_store.OfflineCommerceStore) {
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  let now = @async.now()
  ignore(
    portal.put_membership({
      membership_id: "member-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [LeaseRequester],
      active: true,
      created_unix_ms: now,
    }),
  )
  ignore(
    portal.put_membership({
      membership_id: "member-b",
      tenant_ref: "tenant-b",
      organization_id: "org-b",
      subject_ref: "subject-b",
      roles: [LeaseRequester],
      active: true,
      created_unix_ms: now,
    }),
  )
  let offline = @offline_store.OfflineCommerceStore::open(
    "\{directory}/offline-commerce.json",
  )
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  offline.record_worker_acceptance(ArtifactDispatcher, now)
  offline.record_worker_acceptance(EntitlementDispatcher, now)
  offline.record_reconciler_attempt(now)
  offline.record_reconciler_success(now)
  let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_offline_commerce_store(offline)
    .with_notification_store(notifications)
    .with_offline_artifact_callback_tokens(
      "artifact-worker-token-32-bytes-minimum-a", "artifact-scanner-token-32-bytes-minimum-b",
    )
    .with_entitlement_authority_callback_token(
      "entitlement-authority-token-32-bytes-minimum-c",
    )
    .with_offline_transfer_adapter(
      "http://127.0.0.1:1/v1/offline-transfers", "offline-transfer-adapter-token-32-bytes-minimum-d",
      "offline-transfer-session-secret-32-bytes-minimum-e",
    )
    .with_offline_commerce_capabilities(
      offline_ready_capabilities(),
      @async.now() + 3600000L,
    )
  (service, offline)
}

///|
fn offline_test_quote(id : String, now : Int64) -> @offline.ImmutableQuote {
  {
    quote_id: "quote-\{id}",
    version: "v1",
    service_code: "exclusive-dgx",
    sla_code: "standard",
    currency: "CNY",
    lines: [
      {
        line_id: "line-1",
        description: "Exclusive machine lease",
        quantity: 1L,
        unit: "lease",
        unit_price: { currency: "CNY", minor_units: 10000L, scale: 2 },
        line_total: { currency: "CNY", minor_units: 10000L, scale: 2 },
      },
    ],
    subtotal: { currency: "CNY", minor_units: 10000L, scale: 2 },
    tax: { currency: "CNY", minor_units: 0L, scale: 2 },
    total: { currency: "CNY", minor_units: 10000L, scale: 2 },
    valid_until_unix_ms: now + 3600000L,
    terms_digest: "sha256:" + "a".repeat(64),
    created_unix_ms: now,
  }
}

///|
async test "offline commerce self route derives tenant and isolates purchasers" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-api-")
  let (service, _) = offline_api_fixture(directory)
  let now = @async.now()
  let subject_a = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  let create_body = (
    {
      "order_id": "order-http-a",
      "idempotency_key": "idem-http-a",
      "project_id": "project-a",
      "selected_service_code": "exclusive-dgx",
      "selected_sla_code": "standard",
      "policy": {
        "require_executed_agreement": true,
        "require_payment": true,
        "invoice_timing": "InvoiceBeforeFulfillment",
        "require_identity_verification": true,
        "require_internal_approval": true,
      },
      "expires_unix_ms": (now + 3600000L).to_json(),
      "tenant_ref": "tenant-attacker",
      "organization_id": "org-attacker",
      "purchaser_subject_ref": "subject-attacker",
    } : Json).stringify()
  let created = service.handle(
    Post,
    "/v1/offline-commerce/self/orders",
    subject_a,
    create_body,
  )
  if created.status != 201 {
    fail("unexpected create response: \{created.status} \{created.body}")
  }
  assert_true(created.body.contains("tenant-a"))
  assert_true(created.body.contains("org-a"))
  assert_true(created.body.contains("subject-a"))
  assert_false(created.body.contains("attacker"))
  let secure_order : @offline.CommercialOrder = @json.from_json(
    @json.parse(created.body),
  )
  assert_true(secure_order.policy.require_executed_agreement)
  assert_true(secure_order.policy.require_payment)
  assert_eq(secure_order.policy.invoice_timing, InvoiceBeforeFulfillment)
  assert_true(secure_order.policy.require_identity_verification)
  assert_true(secure_order.policy.require_internal_approval)
  let replay = service.handle(
    Post,
    "/v1/offline-commerce/self/orders",
    subject_a,
    create_body,
  )
  assert_eq(replay.status, 201)
  let listed = service.handle(
    Get,
    "/v1/offline-commerce/self/orders",
    subject_a,
    "",
  )
  assert_eq(listed.status, 200)
  assert_true(listed.body.contains("order-http-a"))
  let subject_b = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-b",
  }
  let isolated = service.handle(
    Get,
    "/v1/offline-commerce/self/orders",
    subject_b,
    "",
  )
  assert_eq(isolated.status, 200)
  assert_false(isolated.body.contains("order-http-a"))
  assert_eq(
    service.handle(Get, "/v1/offline-commerce/self/orders", Map([]), "").status,
    401,
  )
}

///|
async test "offline self policy is server-owned and expiry is bounded" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-policy-api-")
  let (service, _) = offline_api_fixture(directory)
  let now = @async.now()
  let headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  fn body(order_id : String, expiry : Int64) -> String {
    (
      {
        "order_id": order_id,
        "idempotency_key": "idem-\{order_id}",
        "project_id": "project-a",
        "selected_service_code": "exclusive-dgx",
        "selected_sla_code": "standard",
        "policy": {
          "require_executed_agreement": false,
          "require_payment": false,
          "invoice_timing": "InvoiceNotRequired",
          "require_identity_verification": false,
          "require_internal_approval": false,
        },
        "expires_unix_ms": expiry.to_json(),
      } : Json).stringify()
  }
  let accepted = service.handle(
    Post,
    "/v1/offline-commerce/self/orders",
    headers,
    body("order-policy-secure", now + 86400000L),
  )
  assert_eq(accepted.status, 201)
  let persisted : @offline.CommercialOrder = @json.from_json(
    @json.parse(accepted.body),
  )
  assert_true(persisted.policy.require_executed_agreement)
  assert_true(persisted.policy.require_payment)
  assert_eq(persisted.policy.invoice_timing, InvoiceBeforeFulfillment)
  assert_true(persisted.policy.require_identity_verification)
  assert_true(persisted.policy.require_internal_approval)
  let invalid_expiries = [
    now - 1L,
    now,
    now + 299999L,
    now + 31623000000L,
    0x7fffffffffffffffL,
  ]
  for index, expiry in invalid_expiries {
    let response = service.handle(
      Post,
      "/v1/offline-commerce/self/orders",
      headers,
      body("order-expiry-\{index}", expiry),
    )
    if response.status != 400 {
      fail("invalid expiry index \{index} was accepted: \{expiry}")
    }
    assert_false(response.body.contains("tenant-a"))
  }
}

///|
async test "offline operator route rejects customers and exposes no artifact bytes" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-operator-api-")
  let (service, store) = offline_api_fixture(directory)
  let now = @async.now()
  ignore(
    store.create_order({
      order_id: "order-operator-a",
      idempotency_key: "idem-operator-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
      selected_service_code: "exclusive-dgx",
      selected_sla_code: "standard",
      policy: {
        require_executed_agreement: false,
        require_payment: false,
        invoice_timing: InvoiceNotRequired,
        require_identity_verification: false,
        require_internal_approval: false,
      },
      quote: None,
      agreement_ref: None,
      artifact_ids: [],
      entitlement_ref: None,
      state: Draft,
      generation: 1L,
      created_unix_ms: now,
      updated_unix_ms: now,
      expires_unix_ms: now + 3600000L,
    }),
  )
  let customer = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  assert_eq(
    service.handle(Get, "/v1/offline-commerce/operator/snapshot", customer, "").status,
    401,
  )
  let operator = { "Authorization": "Bearer operator-token" }
  let snapshot = service.handle(
    Get,
    "/v1/offline-commerce/operator/snapshot",
    operator,
    "",
  )
  assert_eq(snapshot.status, 200)
  assert_true(snapshot.body.contains("order-operator-a"))
  assert_false(snapshot.body.contains("document_bytes"))
  assert_false(snapshot.body.contains("private_key"))
  let invalid_callback = service.handle(
    Post,
    "/v1/offline-commerce/operator/upload-callbacks",
    operator,
    "{\"callback_id\":\"forged\",\"grant_id\":\"missing\"}",
  )
  assert_eq(invalid_callback.status, 401)
  let customer_callback = service.handle(
    Post,
    "/v1/offline-commerce/operator/upload-callbacks",
    customer,
    "{\"callback_id\":\"forged\",\"grant_id\":\"missing\"}",
  )
  assert_eq(customer_callback.status, 401)
  let scanner = {
    "Authorization": "Bearer artifact-scanner-token-32-bytes-minimum-b",
  }
  let machine_callback = service.handle(
    Post,
    "/v1/offline-commerce/operator/upload-callbacks",
    scanner,
    (
      {
        "callback_id": "callback-missing-grant",
        "grant_id": "missing-grant",
        "expected_object_ref": "object://offline-uploads/missing",
        "media_type": "application/pdf",
        "byte_count": 100L.to_json(),
        "sha256": "sha256:" + "a".repeat(64),
        "scan_passed": true,
        "active_content_detected": false,
        "scanner_receipt": "scanner-receipt",
        "verified": true,
        "completed_unix_ms": now.to_json(),
      } : Json).stringify(),
  )
  assert_eq(machine_callback.status, 404)
  let operator_alerts = service.handle(
    Get,
    "/v1/notifications/operator",
    operator,
    "",
  )
  assert_eq(operator_alerts.status, 200)
  assert_true(operator_alerts.body.contains("OfflineScannerCallbackRejected"))
  assert_false(operator_alerts.body.contains("object://"))
  assert_false(operator_alerts.body.contains("sha256:"))
  assert_eq(
    service.handle(Get, "/v1/offline-commerce/operator/snapshot", scanner, "").status,
    401,
  )
  let worker = {
    "Authorization": "Bearer artifact-worker-token-32-bytes-minimum-a",
  }
  assert_eq(
    service.handle(Get, "/v1/offline-commerce/operator/snapshot", worker, "").status,
    401,
  )
}

///|
async test "offline callbacks fail closed when machine identities are absent" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-callback-unconfigured-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let offline = @offline_store.OfflineCommerceStore::open(
    "\{directory}/offline.json",
  )
  let service = @api.ApiService::new(
    @store.FileStore::open("\{directory}/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  ).with_offline_commerce_store(offline)
  let operator = { "Authorization": "Bearer operator-token" }
  assert_eq(
    service.handle(
      Post,
      "/v1/offline-commerce/operator/generation-results",
      operator,
      "{}",
    ).status,
    503,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/offline-commerce/operator/upload-callbacks",
      operator,
      "{}",
    ).status,
    503,
  )
}

///|
async test "offline callback identity builder rejects weak reused human secrets" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-weak-callback-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let offline = @offline_store.OfflineCommerceStore::open(
    "\{directory}/offline.json",
  )
  let base = @api.ApiService::new(
    @store.FileStore::open("\{directory}/state.json"),
    runtime,
    "operator-token-with-at-least-32-bytes-a",
    "inference-token-with-at-least-32-bytes-b",
    "node-token",
    "0.1.0",
  ).with_offline_commerce_store(offline)
  let attempts = [
    ("", "scanner-token-with-at-least-32-bytes-c"),
    ("short", "scanner-token-with-at-least-32-bytes-c"),
    (
      "same-callback-token-with-at-least-32-bytes", "same-callback-token-with-at-least-32-bytes",
    ),
    (
      "operator-token-with-at-least-32-bytes-a", "scanner-token-with-at-least-32-bytes-c",
    ),
    (
      "worker-token-with-at-least-32-bytes-d", "inference-token-with-at-least-32-bytes-b",
    ),
  ]
  for attempt in attempts {
    let service = base.with_offline_artifact_callback_tokens(
      attempt.0,
      attempt.1,
    )
    assert_eq(
      service.handle(
        Post,
        "/v1/offline-commerce/operator/generation-results",
        { "Authorization": "Bearer \{attempt.0}" },
        "{}",
      ).status,
      503,
    )
  }
}

///|
async test "entitlement callback authority is distinct terminal and idempotent" {
  let directory = @fs.tmpdir(prefix="lunanexa-entitlement-callback-")
  let (base, store) = offline_api_fixture(directory)
  let service = base.with_entitlement_authority_callback_token(
    "entitlement-authority-token-32-bytes-minimum-c",
  )
  let now = @async.now()
  let draft = store.create_order({
    order_id: "order-entitlement-callback",
    idempotency_key: "idem-entitlement-callback",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    purchaser_subject_ref: "subject-a",
    selected_service_code: "exclusive-dgx",
    selected_sla_code: "standard",
    policy: {
      require_executed_agreement: true,
      require_payment: false,
      invoice_timing: InvoiceNotRequired,
      require_identity_verification: false,
      require_internal_approval: false,
    },
    quote: None,
    agreement_ref: None,
    artifact_ids: [],
    entitlement_ref: None,
    state: Draft,
    generation: 1L,
    created_unix_ms: now,
    updated_unix_ms: now,
    expires_unix_ms: now + 3600000L,
  })
  let quoted = store.quote_order(
    draft.order_id,
    offline_test_quote("entitlement-callback", now),
    "operator-a",
    now,
  )
  let begun = store.begin_offline_execution(
    quoted.order_id,
    quoted.generation,
    now + 1L,
  )
  ignore(
    store.register_template({
      template_id: "contract-http-a",
      version: "v1",
      kind: ContractTemplate,
      locale: "zh-CN",
      media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      object_ref: "s3://templates/contract-http-a.docx",
      sha256: "sha256:" + "a".repeat(64),
      byte_count: 1000L,
      active_content_allowed: false,
      created_unix_ms: now,
      superseded_unix_ms: None,
    }),
  )
  let generation : @offline.ArtifactGenerationRequest = {
    request_id: "generation-http-a",
    order_id: begun.order_id,
    organization_id: begun.organization_id,
    artifact_id: "contract-pdf-http-a",
    kind: PrintReadyContractPdf,
    template_id: "contract-http-a",
    template_version: "v1",
    locale: "zh-CN",
    expected_object_ref: "s3://orders/order-entitlement-callback/contract.pdf",
    input_snapshot_sha256: "sha256:" + "a".repeat(64),
    requested_by: "operator-a",
    requested_unix_ms: now + 1L,
  }
  ignore(store.request_generation(generation))
  ignore(store.claim_generation_requests(now + 2L))
  ignore(
    store.complete_generation({
      request_id: generation.request_id,
      artifact_id: generation.artifact_id,
      expected_object_ref: generation.expected_object_ref,
      media_type: "application/pdf",
      byte_count: 2000L,
      sha256: "sha256:" + "d".repeat(64),
      worker_receipt: "worker-http-a",
      verified: true,
      active_content_detected: false,
      moonleaf_verified: false,
      render_verified: true,
      formula_error_count: 0,
      visual_evidence_sha256: "sha256:" + "e".repeat(64),
      completed_unix_ms: now + 2L,
    }),
  )
  let awaiting = store.release_offline_packet(
    begun.order_id,
    store.order("org-a", begun.order_id).generation,
    now + 3L,
  )
  let grant : @offline.EvidenceUploadGrant = {
    grant_id: "grant-entitlement-http-a",
    idempotency_key: "upload-entitlement-http-a",
    order_id: awaiting.order_id,
    organization_id: awaiting.organization_id,
    subject_ref: awaiting.purchaser_subject_ref,
    artifact_id: "executed-entitlement-http-a",
    kind: ExecutedContractScan,
    revision: 1,
    expected_object_ref: "object://offline-uploads/org-a/order-entitlement-callback/executed-entitlement-http-a",
    allowed_media_types: ["application/pdf"],
    maximum_byte_count: 1000000L,
    expires_unix_ms: now + 600000L,
    state: UploadGranted,
    created_unix_ms: now + 4L,
  }
  ignore(store.grant_upload(grant))
  let upload_callback : @offline.EvidenceUploadCallback = {
    callback_id: "callback-entitlement-http-a",
    grant_id: grant.grant_id,
    expected_object_ref: grant.expected_object_ref,
    media_type: "application/pdf",
    byte_count: 1000L,
    sha256: "sha256:" + "c".repeat(64),
    scan_passed: true,
    active_content_detected: false,
    scanner_receipt: "scanner-entitlement-http-a",
    verified: true,
    completed_unix_ms: now + 5L,
  }
  assert_true(grant.allowed_media_types.contains(upload_callback.media_type))
  assert_true(@offline.valid_sha256(upload_callback.sha256))
  assert_true(upload_callback.completed_unix_ms <= grant.expires_unix_ms)
  assert_eq(upload_callback.expected_object_ref, grant.expected_object_ref)
  assert_true(upload_callback.byte_count > 0L)
  assert_true(upload_callback.byte_count <= grant.maximum_byte_count)
  assert_true(@contracts.valid_identifier(upload_callback.callback_id))
  assert_true(@contracts.valid_identifier(upload_callback.scanner_receipt))
  assert_true(upload_callback.verified)
  let artifact = store.complete_upload(upload_callback) catch {
    @offline.OfflineCommerceError::ArtifactUnavailable(reason) => fail(reason)
    error => raise error
  }
  ignore(
    store.review_evidence({
      review_id: "review-entitlement-http-a",
      order_id: awaiting.order_id,
      artifact_id: artifact.artifact_id,
      expected_artifact_sha256: artifact.sha256,
      reviewer_ref: "legal-a",
      accepted: true,
      reason_code: "EvidenceVerified",
      audit_receipt: "audit-entitlement-http-a",
      reviewed_unix_ms: now + 6L,
    }),
  )
  let order = store.order("org-a", awaiting.order_id)
  let activation : @offline.EntitlementActivation = {
    activation_id: "activation-http-a",
    idempotency_key: "activation-http-idem-a",
    order_id: order.order_id,
    organization_id: order.organization_id,
    purchaser_subject_ref: order.purchaser_subject_ref,
    kind: ExclusiveMachineLease,
    authority_target_ref: "lease-target-a",
    expected_order_generation: order.generation,
    state: EntitlementActivationRequested,
    entitlement_ref: None,
    authority_receipt: None,
    reason_code: None,
    requested_by: "operator-a",
    requested_unix_ms: now,
    completed_unix_ms: None,
  }
  ignore(store.fulfill(order.order_id, order.generation, activation, now))
  let path = "/v1/offline-commerce/operator/entitlement-activation-results"
  let authority = {
    "Authorization": "Bearer entitlement-authority-token-32-bytes-minimum-c",
  }
  assert_eq(
    service.handle(
      Get,
      "/v1/offline-commerce/operator/entitlement-work/pending",
      { "Authorization": "Bearer operator-token" },
      "",
    ).status,
    401,
  )
  let claimed = service.handle(
    Get,
    "/v1/offline-commerce/operator/entitlement-work/pending",
    authority,
    "",
  )
  assert_eq(claimed.status, 200)
  assert_true(claimed.body.contains(activation.activation_id))
  assert_eq(
    service.handle(
      Post,
      path,
      { "Authorization": "Bearer operator-token" },
      "{}",
    ).status,
    401,
  )
  assert_eq(
    service.handle(Post, path, authority, activation.to_json().stringify()).status,
    400,
  )
  let missing_receipt = {
    ..activation,
    state: EntitlementActivationConfirmed,
    entitlement_ref: Some("lease-a"),
  }
  assert_eq(
    service.handle(Post, path, authority, missing_receipt.to_json().stringify()).status,
    400,
  )
  let confirmed : @offline.EntitlementActivation = {
    ..missing_receipt,
    authority_receipt: Some("authority-receipt-a"),
  }
  let expired_service = service.with_offline_commerce_capabilities(
    offline_ready_capabilities(),
    @async.now() - 1L,
  )
  let first = expired_service.handle(
    Post,
    path,
    authority,
    confirmed.to_json().stringify(),
  )
  assert_eq(first.status, 200)
  assert_true(first.body.contains("Fulfilled"))
  let replay = expired_service.handle(
    Post,
    path,
    authority,
    confirmed.to_json().stringify(),
  )
  assert_eq(replay.status, 200)
  let mutated = { ..confirmed, authority_target_ref: "lease-target-attacker" }
  assert_eq(
    expired_service.handle(Post, path, authority, mutated.to_json().stringify()).status,
    409,
  )
  let active = store.order_for_operator(order.order_id)
  let failed_reversal : @offline.CommercialReversal = {
    reversal_id: "reversal-http-failed-a",
    idempotency_key: "reversal-http-failed-a",
    order_id: active.order_id,
    organization_id: active.organization_id,
    entitlement_ref: active.entitlement_ref.unwrap(),
    reason: CustomerCancellation,
    expected_order_generation: active.generation,
    state: ReversalRequested,
    authority_receipt: None,
    reason_code: None,
    requested_by: "operator-a",
    requested_unix_ms: now + 7L,
    completed_unix_ms: None,
  }
  ignore(store.request_reversal(failed_reversal))
  ignore(store.claim_authority_work(now + 8L))
  let intervention = store.complete_reversal({
    ..failed_reversal,
    state: ReversalFailed,
    authority_receipt: Some("authority-failure-http-a"),
    reason_code: Some("authority-unavailable"),
    completed_unix_ms: Some(now + 9L),
  })
  let recovery_body : OfflineTestReversalRecoveryAction = {
    recovery_id: "recovery-http-a",
    idempotency_key: "recovery-http-a",
    order_id: intervention.order_id,
    failed_reversal_id: failed_reversal.reversal_id,
    expected_generation: intervention.generation,
    decision: ConfirmRevoked,
    replacement_reversal_id: None,
    authority_receipt: "operator-confirmed-revocation-http-a",
    reason_code: "authority-state-reconciled",
  }
  let recovered = service.handle(
    Post,
    "/v1/offline-commerce/operator/reversal-recoveries",
    { "Authorization": "Bearer operator-token" },
    recovery_body.to_json().stringify(),
  )
  assert_eq(recovered.status, 200)
  assert_true(recovered.body.contains("Revoked"))
}

///|
async test "configured readiness is evaluated rather than inferred" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-ready-api-")
  let (base, _) = offline_api_fixture(directory)
  let service = base.with_offline_commerce_capabilities(
    offline_ready_capabilities(),
    @async.now() + 3600000L,
  )
  let response = service.handle(
    Get,
    "/v1/offline-commerce/operator/readiness",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(response.status, 200)
  assert_true(response.body.contains("OfflineCommerceReady"))
  assert_false(response.body.contains("PdfRendererPending"))
  let expired_service = base.with_offline_commerce_capabilities(
    offline_ready_capabilities(),
    @async.now() - 1L,
  )
  let expired = expired_service.handle(
    Get,
    "/v1/offline-commerce/operator/readiness",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_true(expired.body.contains("ReadinessEvidenceExpired"))
  assert_true(expired.body.contains("OfflineCommerceAdaptersPending"))
  let blocked = expired_service.handle(
    Post,
    "/v1/offline-commerce/operator/quotes",
    { "Authorization": "Bearer operator-token" },
    "{}",
  )
  assert_eq(blocked.status, 503)
  assert_true(blocked.body.contains("ReadinessEvidenceExpired"))
  let callback_reconciled = expired_service.handle(
    Post,
    "/v1/offline-commerce/operator/entitlement-activation-results",
    { "Authorization": "Bearer entitlement-authority-token-32-bytes-minimum-c" },
    "{}",
  )
  // Terminal callbacks remain reachable for work issued before evidence
  // expiry; this malformed body reaches validation instead of readiness.
  assert_eq(callback_reconciled.status, 400)
  assert_false(callback_reconciled.body.contains("ReadinessEvidenceExpired"))
}

///|
async test "offline lifecycle reconciliation emits safe deduplicated customer notices" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-notices-")
  let (service, store) = offline_api_fixture(directory)
  let now = @async.now()
  ignore(
    store.create_order({
      order_id: "order-notice",
      idempotency_key: "idem-notice",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
      selected_service_code: "exclusive-dgx",
      selected_sla_code: "standard",
      policy: {
        require_executed_agreement: true,
        require_payment: true,
        invoice_timing: InvoiceBeforeFulfillment,
        require_identity_verification: true,
        require_internal_approval: true,
      },
      quote: None,
      agreement_ref: None,
      artifact_ids: [],
      entitlement_ref: None,
      state: Draft,
      generation: 1L,
      created_unix_ms: now,
      updated_unix_ms: now,
      expires_unix_ms: now + 3600000L,
    }),
  )
  ignore(
    store.quote_order(
      "order-notice",
      offline_test_quote("notice", now),
      "platform-operator",
      now + 1L,
    ),
  )
  let subject = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  assert_eq(
    service.handle(Get, "/v1/offline-commerce/self/orders", subject, "").status,
    200,
  )
  // A second reconciliation is an idempotent replay.
  ignore(service.handle(Get, "/v1/offline-commerce/self/orders", subject, ""))
  let inbox = service.handle(Get, "/v1/notifications/self", subject, "")
  assert_eq(inbox.status, 200)
  assert_true(inbox.body.contains("QuoteReady"))
  assert_false(inbox.body.contains("object://"))
  assert_false(inbox.body.contains("sha256:"))
  let records : Array[@notifications.NotificationRecord] = @json.from_json(
    @json.parse(inbox.body),
  )
  assert_eq(records.length(), 1)
}

///|
async test "offline readiness stays pending and purchaser cancellation is fenced" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-readiness-cancel-")
  let (ready_service, _) = offline_api_fixture(directory)
  let service = ready_service.with_offline_commerce_capabilities([], 0L)
  let operator = { "Authorization": "Bearer operator-token" }
  let readiness = service.handle(
    Get,
    "/v1/offline-commerce/operator/readiness",
    operator,
    "",
  )
  assert_eq(readiness.status, 200)
  assert_true(readiness.body.contains("OfflineCommerceAdaptersPending"))
  assert_true(readiness.body.contains("PdfRendererPending"))
  let now = @async.now()
  let subject = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  let created = service.handle(
    Post,
    "/v1/offline-commerce/self/orders",
    subject,
    (
      {
        "order_id": "order-self-cancel",
        "idempotency_key": "idem-self-cancel",
        "project_id": "project-a",
        "selected_service_code": "exclusive-dgx",
        "selected_sla_code": "standard",
        "expires_unix_ms": (now + 3600000L).to_json(),
      } : Json).stringify(),
  )
  assert_eq(created.status, 201)
  let stale = service.handle(
    Post,
    "/v1/offline-commerce/self/orders/order-self-cancel:cancel",
    subject,
    (
      {
        "order_id": "order-self-cancel",
        "expected_generation": 2L.to_json(),
        "now_unix_ms": now.to_json(),
      } : Json).stringify(),
  )
  assert_eq(stale.status, 409)
  let cancelled = service.handle(
    Post,
    "/v1/offline-commerce/self/orders/order-self-cancel:cancel",
    subject,
    (
      {
        "order_id": "order-self-cancel",
        "expected_generation": 1L.to_json(),
        "now_unix_ms": now.to_json(),
      } : Json).stringify(),
  )
  assert_eq(cancelled.status, 200)
  assert_true(cancelled.body.contains("Cancelled"))
}
