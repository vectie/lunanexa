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
