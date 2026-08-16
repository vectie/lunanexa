///|
async test "contract document API is subject scoped and rejects offline secret fields" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-document-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  for
    record in [
      ("membership-a", "subject-a", "tenant-a", "org-a"),
      ("membership-b", "subject-b", "tenant-b", "org-b"),
    ] {
    let (id, subject, tenant, organization) = record
    ignore(
      portal.put_membership({
        membership_id: id,
        tenant_ref: tenant,
        organization_id: organization,
        subject_ref: subject,
        roles: [Developer],
        active: true,
        created_unix_ms: @async.now(),
      }),
    )
  }
  let documents = @contractdoc_store.ContractDocumentStore::open(
    "\{directory}/contracts.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_portal_store(portal)
    .with_contract_document_store(documents)
    .with_contract_document_worker_token(
      "contract-renderer-test-token-more-than-32-bytes",
    )
  fn headers(subject : String) -> Map[String, String] {
    { "Authorization": "Bearer inference-token", "X-LunaNexa-Subject": subject }
  }
  let manifest = service.handle(
    Get,
    "/v1/contract-documents/manifest",
    headers("subject-a"),
    "",
  )
  assert_eq(manifest.status, 200)
  assert_true(
    manifest.body.contains("youthpolicy-dgx-spark-remote-lease-revised"),
  )
  let created = service.handle(
    Post,
    "/v1/contract-documents/self",
    headers("subject-a"),
    "{\"packet_id\":\"packet-api-1\",\"idempotency_key\":\"packet-api-key-1\",\"order_ref\":\"order-api-1\",\"active_forms\":[\"MasterLease\"]}",
  )
  assert_eq(created.status, 201)
  assert_false(created.body.contains("tenant-b"))
  let customer_cannot_edit_manager = service.handle(
    Put,
    "/v1/contract-documents/self/packet-api-1:information",
    headers("subject-a"),
    "{\"expected_revision\":\"1\",\"changes\":[{\"field_id\":\"lessor.name\",\"value\":\"forbidden\"}]}",
  )
  assert_eq(customer_cannot_edit_manager.status, 400)
  let operator = service.handle(
    Put,
    "/v1/contract-documents/operator/packets/packet-api-1:information",
    { "Authorization": "Bearer operator-token" },
    "{\"expected_revision\":\"1\",\"changes\":[{\"field_id\":\"lessor.name\",\"value\":\"青年政策运营方\"}]}",
  )
  assert_eq(operator.status, 200)
  assert_true(operator.body.contains("ManagerOperator"))
  assert_false(operator.body.contains("operator-token"))
  let preview = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-api-1:preview",
    { "Authorization": "Bearer operator-token" },
    "{\"expected_revision\":\"2\",\"form\":\"MasterLease\",\"changes\":[{\"field_id\":\"lessor.name\",\"value\":\"青年政策运营方\"}]}",
  )
  assert_eq(preview.status, 200)
  assert_true(preview.body.contains("\"engine\":\"moonleaf\""))
  assert_true(preview.body.contains("青年政策运营方"))
  assert_true(preview.body.contains("NVIDIA DGX Spark"))
  assert_false(preview.body.contains("operator-token"))
  let other = service.handle(
    Get,
    "/v1/contract-documents/self",
    headers("subject-b"),
    "",
  )
  assert_eq(other.status, 200)
  assert_eq(other.body, "[]")
  let secret = service.handle(
    Put,
    "/v1/contract-documents/self/packet-api-1:information",
    headers("subject-a"),
    "{\"expected_revision\":\"2\",\"changes\":[{\"field_id\":\"lessor.signatory\",\"value\":\"must-not-persist\"}]}",
  )
  assert_eq(secret.status, 400)
  assert_false(
    @fs.read_file("\{directory}/contracts.json")
    .text()
    .contains("must-not-persist"),
  )
  let denied_worker = service.handle(
    Get,
    "/v1/contract-documents/worker/pending",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(denied_worker.status, 401)
  let worker = service.handle(
    Get,
    "/v1/contract-documents/worker/pending",
    {
      "Authorization": "Bearer contract-renderer-test-token-more-than-32-bytes",
    },
    "",
  )
  assert_eq(worker.status, 200)
  assert_eq(worker.body, "[]")
}

///|
async test "contract document lifecycle endpoints gate creation and record execution" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-lifecycle-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  ignore(
    portal.put_membership({
      membership_id: "membership-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [Developer],
      active: true,
      created_unix_ms: @async.now(),
    }),
  )
  let documents = @contractdoc_store.ContractDocumentStore::open(
    "\{directory}/contracts.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_portal_store(portal)
    .with_contract_document_store(documents)
    .with_contract_document_worker_token(
      "contract-renderer-test-token-more-than-32-bytes",
    )
  let subject_headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  let operator_headers = { "Authorization": "Bearer operator-token" }
  let worker_headers = {
    "Authorization": "Bearer contract-renderer-test-token-more-than-32-bytes",
  }
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let digest = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  // An effective master packet unlocks the effective-stage follow-up forms.
  let master = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-master",
      "packet-master-key",
      "tenant-a",
      "org-a",
      "subject-a",
      "order-api-1",
      None,
      [MasterLease],
      1000L,
    ),
    state: Effective,
  }
  ignore(documents.create_packet(master, "operator"))
  // Follow-up forms are gated on an effective same-tenant predecessor.
  let missing_preceding = service.handle(
    Post,
    "/v1/contract-documents/self",
    subject_headers,
    "{\"packet_id\":\"packet-access\",\"idempotency_key\":\"packet-access-key\",\"order_ref\":\"order-api-1\",\"active_forms\":[\"AccessConfirmation\"]}",
  )
  assert_eq(missing_preceding.status, 409)
  assert_true(
    missing_preceding.body.contains("ContractPredecessorNotEffective"),
  )
  let drafting_master = {
    ..master,
    packet_id: "packet-master-draft",
    idempotency_key: "packet-master-draft-key",
    state: InformationDraft,
  }
  ignore(documents.create_packet(drafting_master, "subject-a"))
  let drafting_preceding = service.handle(
    Post,
    "/v1/contract-documents/self",
    subject_headers,
    "{\"packet_id\":\"packet-access-2\",\"idempotency_key\":\"packet-access-2-key\",\"order_ref\":\"order-api-1\",\"preceding_packet_ref\":\"packet-master-draft\",\"active_forms\":[\"AccessConfirmation\"]}",
  )
  assert_eq(drafting_preceding.status, 409)
  let accepted = service.handle(
    Post,
    "/v1/contract-documents/self",
    subject_headers,
    "{\"packet_id\":\"packet-access\",\"idempotency_key\":\"packet-access-key\",\"order_ref\":\"order-api-1\",\"preceding_packet_ref\":\"packet-master\",\"active_forms\":[\"AccessConfirmation\"]}",
  )
  assert_eq(accepted.status, 201)
  // Creation applies platform-derived linked values on the write path.
  assert_true(accepted.body.contains("access.order_number"))
  assert_true(accepted.body.contains("order-api-1"))
  // Reads are pure: listing packets must not advance any revision.
  let revision_before = documents.packet("packet-access").unwrap().revision
  let listed = service.handle(
    Get,
    "/v1/contract-documents/self",
    subject_headers,
    "",
  )
  assert_eq(listed.status, 200)
  let operator_listed = service.handle(
    Get,
    "/v1/contract-documents/operator/packets",
    operator_headers,
    "",
  )
  assert_eq(operator_listed.status, 200)
  assert_eq(
    documents.packet("packet-access").unwrap().revision,
    revision_before,
  )
  // The renderer reports failures and the customer retries with the same digest.
  let worker_packet = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-render",
      "packet-render-key",
      "tenant-a",
      "org-a",
      "subject-a",
      "order-api-1",
      None,
      [MasterLease],
      1000L,
    ),
    state: GenerationRequested,
    values_sha256: Some(digest),
    revision: 3L,
  }
  ignore(documents.create_packet(worker_packet, "subject-a"))
  let denied_failure = service.handle(
    Post,
    "/v1/contract-documents/worker/failures",
    operator_headers,
    "{\"packet_id\":\"packet-render\",\"expected_revision\":\"3\",\"reason\":\"renderer crashed\",\"worker_receipt\":\"receipt-1\"}",
  )
  assert_eq(denied_failure.status, 401)
  let failed = service.handle(
    Post,
    "/v1/contract-documents/worker/failures",
    worker_headers,
    "{\"packet_id\":\"packet-render\",\"expected_revision\":\"3\",\"reason\":\"renderer crashed\",\"worker_receipt\":\"receipt-1\"}",
  )
  assert_eq(failed.status, 200)
  assert_true(failed.body.contains("GenerationFailed"))
  assert_true(failed.body.contains("renderer crashed"))
  let retried = service.handle(
    Post,
    "/v1/contract-documents/self/packet-render:generate",
    subject_headers,
    "{\"expected_revision\":\"4\",\"expected_values_sha256\":\"\{digest}\"}",
  )
  assert_eq(retried.status, 202)
  assert_true(retried.body.contains("GenerationRequested"))
  // The operator registers offline execution evidence for a generated packet.
  let generated_packet = {
    ..worker_packet,
    packet_id: "packet-sign",
    idempotency_key: "packet-sign-key",
    state: Generated,
    revision: 5L,
  }
  ignore(documents.create_packet(generated_packet, "subject-a"))
  let bad_evidence = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-sign:execute",
    operator_headers,
    "{\"expected_revision\":\"5\",\"evidence_sha256\":\"not-a-digest\",\"signed_on\":\"2026-08-14\"}",
  )
  assert_eq(bad_evidence.status, 400)
  assert_true(bad_evidence.body.contains("ContractEvidenceRejected"))
  let effective = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-sign:execute",
    operator_headers,
    "{\"expected_revision\":\"5\",\"evidence_sha256\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"signed_on\":\"2026-08-14\"}",
  )
  assert_eq(effective.status, 200)
  assert_true(effective.body.contains("Effective"))
  // Early termination needs an effective settlement; expiry closes directly.
  let early = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-sign:close",
    operator_headers,
    "{\"expected_revision\":\"6\",\"kind\":\"EarlyTermination\",\"reason\":\"tenant vacated\"}",
  )
  assert_eq(early.status, 400)
  let closed = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-sign:close",
    operator_headers,
    "{\"expected_revision\":\"6\",\"kind\":\"Expired\",\"reason\":\"lease term ended\"}",
  )
  assert_eq(closed.status, 200)
  assert_true(closed.body.contains("Closed"))
  // Terminal packets cannot be superseded; drafts can, with a same-tenant successor.
  let terminal_supersede = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-sign:supersede",
    operator_headers,
    "{\"expected_revision\":\"7\",\"successor_ref\":\"packet-master-draft\",\"reason\":\"reissued\"}",
  )
  assert_eq(terminal_supersede.status, 409)
  let successor = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-successor",
      "packet-successor-key",
      "tenant-a",
      "org-a",
      "subject-a",
      "order-api-1",
      None,
      [MasterLease],
      2000L,
    ),
    revision: 1L,
  }
  ignore(documents.create_packet(successor, "subject-a"))
  let superseded = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-master-draft:supersede",
    operator_headers,
    "{\"expected_revision\":\"1\",\"successor_ref\":\"packet-successor\",\"reason\":\"reissued with corrected dates\"}",
  )
  assert_eq(superseded.status, 200)
  assert_true(superseded.body.contains("Superseded"))
  assert_true(superseded.body.contains("packet-successor"))
}

///|
async test "early termination close reconciles the settlement against the ledger" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-settlement-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  let documents = @contractdoc_store.ContractDocumentStore::open(
    "\{directory}/contracts.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  for tenant in ["tenant-a", "tenant-b"] {
    let organization = "org-\{tenant}"
    let master = {
      ..@contractdoc.new_packet(
        manifest,
        "packet-master-\{tenant}",
        "packet-master-key-\{tenant}",
        tenant,
        organization,
        "subject-a",
        "order-api-1",
        None,
        [MasterLease],
        1000L,
      ),
      state: Effective,
    }
    ignore(documents.create_packet(master, "operator"))
    let settlement = {
      ..@contractdoc.new_packet(
        manifest,
        "packet-settle-\{tenant}",
        "packet-settle-key-\{tenant}",
        tenant,
        organization,
        "subject-a",
        "order-api-1",
        Some("packet-master-\{tenant}"),
        [SettlementConfirmation],
        2000L,
      ),
      state: Effective,
      values: [
        {
          field_id: "settlement.amount_due",
          value: if tenant == "tenant-a" {
            "1234.56"
          } else {
            "¥1,234.56"
          },
        },
      ],
    }
    ignore(documents.create_packet(settlement, "operator"))
  }
  let commercial = @commercial.CommercialStore::new()
  // tenant-a's ledger total (CNY 1.00) disagrees with its settlement; tenant-b
  // has a single rated entry that exactly matches its settlement amount due.
  fn rate_entry(organization_id : String, minor_units : Int64) -> Unit raise {
    commercial.add_organization({
      organization_id,
      display_name: "Org \{organization_id}",
      state: Active,
      verification_ref: None,
      created_unix_ms: 1000L,
    })
    commercial.add_cost_center({
      cost_center_id: "cc-\{organization_id}",
      organization_id,
      parent_cost_center_id: None,
      display_name: "Cost center",
      created_unix_ms: 1000L,
    })
    commercial.add_project({
      project_id: "proj-\{organization_id}",
      organization_id,
      cost_center_id: "cc-\{organization_id}",
      display_name: "Project",
      created_unix_ms: 1000L,
    })
    ignore(
      commercial.ingest_usage({
        event_id: "usage-\{organization_id}",
        organization_id,
        project_id: "proj-\{organization_id}",
        actor_ref: "operator",
        workload_id: "workload-1",
        node_id: "node-1",
        lease_epoch: 0L,
        meter: "gpu-second",
        quantity: 1L,
        unit: "second",
        started_unix_ms: 1000L,
        ended_unix_ms: 2000L,
        observed_unix_ms: 2000L,
      }),
    )
    ignore(
      commercial.rate_usage(
        "usage-\{organization_id}",
        "entry-\{organization_id}",
        {
          rate_card_id: "rate-1",
          version: "v1",
          meter: "gpu-second",
          unit: "second",
          unit_price: { minor_units, currency: "CNY", scale: 2 },
          effective_from_unix_ms: 1000L,
          effective_until_unix_ms: 10000L,
        },
        2000L,
      ),
    )
  }
  rate_entry("org-tenant-a", 100L)
  rate_entry("org-tenant-b", 123456L)
  let service = {
    ..ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    ).with_contract_document_store(documents),
    commercial_store: commercial,
  }
  let operator_headers = { "Authorization": "Bearer operator-token" }
  let mismatch = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-master-tenant-a:close",
    operator_headers,
    "{\"expected_revision\":\"1\",\"kind\":\"EarlyTermination\",\"reason\":\"tenant vacated\"}",
  )
  assert_eq(mismatch.status, 409)
  assert_true(mismatch.body.contains("ContractSettlementMismatch"))
  assert_true(mismatch.body.contains("1234.56"))
  assert_true(mismatch.body.contains("1.00"))
  assert_eq(
    documents.packet("packet-master-tenant-a").unwrap().state,
    Effective,
  )
  let matched = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-master-tenant-b:close",
    operator_headers,
    "{\"expected_revision\":\"1\",\"kind\":\"EarlyTermination\",\"reason\":\"tenant vacated\"}",
  )
  assert_eq(matched.status, 200)
  assert_true(matched.body.contains("Closed"))
}

///|
async test "master lease close revokes only the subject's active API credentials" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-revoke-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  let access = @access.AccessStore::open(
    "\{directory}/access.json",
    "issuer-secret-with-more-than-32-bytes!",
  )
  let now = @async.now()
  for key_id in ["key-a1", "key-a2"] {
    ignore(
      access.issue(
        {
          key_id,
          tenant_ref: "tenant-a",
          subject_ref: "subject-a",
          display_name: "Key \{key_id}",
          scopes: [Inference],
          allowed_models: [],
          expires_unix_ms: now + 86400000L,
          maximum_requests: 1000L,
        },
        now,
      ),
    )
  }
  ignore(
    access.issue(
      {
        key_id: "key-b1",
        tenant_ref: "tenant-a",
        subject_ref: "subject-b",
        display_name: "Key key-b1",
        scopes: [Inference],
        allowed_models: [],
        expires_unix_ms: now + 86400000L,
        maximum_requests: 1000L,
      },
      now,
    ),
  )
  let documents = @contractdoc_store.ContractDocumentStore::open(
    "\{directory}/contracts.json",
  )
  let master = {
    ..@contractdoc.new_packet(
      @contractdoc.youthpolicy_remote_lease_manifest(),
      "packet-master",
      "packet-master-key",
      "tenant-a",
      "org-a",
      "subject-a",
      "order-api-1",
      None,
      [MasterLease],
      1000L,
    ),
    state: Effective,
  }
  ignore(documents.create_packet(master, "operator"))
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let service = ApiService::new(
      durable,
      @runtimes.OpenAiTextRuntime::new(
        "http://127.0.0.1:1/v1/responses",
        "runtime-secret",
        "runtime-v1",
        "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        allow_http_loopback=true,
      ),
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_access_store(access)
    .with_contract_document_store(documents)
    .with_notification_store(notifications)
  let closed = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-master:close",
    { "Authorization": "Bearer operator-token" },
    "{\"expected_revision\":\"1\",\"kind\":\"Expired\",\"reason\":\"lease term ended\"}",
  )
  assert_eq(closed.status, 200)
  let subject_keys = access.views_for_subject("tenant-a", "subject-a")
  assert_eq(subject_keys.length(), 2)
  assert_true(
    subject_keys.all(credential => credential.revoked_unix_ms is Some(_)),
  )
  let other_keys = access.views_for_subject("tenant-a", "subject-b")
  assert_eq(other_keys.length(), 1)
  assert_true(other_keys[0].revoked_unix_ms is None)
  let notices = notifications.records_for_subject(
    "tenant-a",
    "subject-a",
    now + 1L,
  )
  assert_eq(notices.length(), 1)
  assert_eq(notices[0].event.code, "AccessCredentialsRevoked")
  assert_eq(notices[0].event.topic, AccessCredential)
  assert_eq(notices[0].event.parameters.get("revoked_count"), Some("2"))
}

///|
async test "contract expiry reconciler notifies tiered windows with dedup" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-expiry-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  let documents = @contractdoc_store.ContractDocumentStore::open(
    "\{directory}/contracts.json",
  )
  let master = {
    ..@contractdoc.new_packet(
      @contractdoc.youthpolicy_remote_lease_manifest(),
      "packet-expiry",
      "packet-expiry-key",
      "tenant-a",
      "org-a",
      "subject-a",
      "order-api-1",
      None,
      [MasterLease],
      1000L,
    ),
    state: Effective,
    values: [{ field_id: "lease.end_date", value: "2026-08-25" }],
  }
  ignore(documents.create_packet(master, "operator"))
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let service = ApiService::new(
      durable,
      @runtimes.OpenAiTextRuntime::new(
        "http://127.0.0.1:1/v1/responses",
        "runtime-secret",
        "runtime-v1",
        "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        allow_http_loopback=true,
      ),
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_contract_document_store(documents)
    .with_notification_store(notifications)
  fn day_ms(year : Int, month : Int, day : Int) -> Int64 {
    @contractdoc.days_from_civil(year, month, day) * 86400000L
  }
  // 24 days remaining: only the 30-day window fires.
  service.reconcile_expiring_contracts(day_ms(2026, 8, 1))
  assert_eq(
    notifications
    .records_for_subject("tenant-a", "subject-a", day_ms(2026, 8, 1))
    .length(),
    1,
  )
  assert_eq(notifications.records_for_operators(day_ms(2026, 8, 1)).length(), 1)
  // A repeated pass at the same time must not duplicate the reminder.
  service.reconcile_expiring_contracts(day_ms(2026, 8, 1))
  assert_eq(
    notifications
    .records_for_subject("tenant-a", "subject-a", day_ms(2026, 8, 1))
    .length(),
    1,
  )
  assert_eq(notifications.records_for_operators(day_ms(2026, 8, 1)).length(), 1)
  // 5 days remaining: the 7-day window fires once.
  service.reconcile_expiring_contracts(day_ms(2026, 8, 20))
  service.reconcile_expiring_contracts(day_ms(2026, 8, 20))
  assert_eq(
    notifications
    .records_for_subject("tenant-a", "subject-a", day_ms(2026, 8, 20))
    .length(),
    2,
  )
  assert_eq(
    notifications.records_for_operators(day_ms(2026, 8, 20)).length(),
    2,
  )
  // 1 day remaining: the critical 1-day window fires once.
  service.reconcile_expiring_contracts(day_ms(2026, 8, 24))
  service.reconcile_expiring_contracts(day_ms(2026, 8, 24))
  let subject_notices = notifications.records_for_subject(
    "tenant-a",
    "subject-a",
    day_ms(2026, 8, 24),
  )
  assert_eq(subject_notices.length(), 3)
  assert_eq(
    notifications.records_for_operators(day_ms(2026, 8, 24)).length(),
    3,
  )
  let by_window : Map[String, @notifications.NotificationRecord] = Map([])
  for record in subject_notices {
    by_window[record.event.parameters.get("window").unwrap_or("")] = record
  }
  assert_eq(by_window.get("30d").unwrap().event.severity, Warning)
  assert_eq(by_window.get("7d").unwrap().event.severity, Warning)
  assert_eq(by_window.get("1d").unwrap().event.severity, Critical)
  assert_eq(
    by_window.get("1d").unwrap().event.parameters.get("end_date"),
    Some("2026-08-25"),
  )
}

///|
async test "contract renewal creates a linked draft for the owner and the operator" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-renewal-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  for
    record in [
      ("membership-a", "subject-a", "tenant-a", "org-a"),
      ("membership-b", "subject-b", "tenant-b", "org-b"),
    ] {
    let (id, subject, tenant, organization) = record
    ignore(
      portal.put_membership({
        membership_id: id,
        tenant_ref: tenant,
        organization_id: organization,
        subject_ref: subject,
        roles: [Developer],
        active: true,
        created_unix_ms: @async.now(),
      }),
    )
  }
  let documents = @contractdoc_store.ContractDocumentStore::open(
    "\{directory}/contracts.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_portal_store(portal)
    .with_contract_document_store(documents)
  fn headers(subject : String) -> Map[String, String] {
    { "Authorization": "Bearer inference-token", "X-LunaNexa-Subject": subject }
  }
  let operator_headers = { "Authorization": "Bearer operator-token" }
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let master = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-master",
      "packet-master-key",
      "tenant-a",
      "org-a",
      "subject-a",
      "order-api-1",
      None,
      [MasterLease],
      1000L,
    ),
    state: Effective,
    values: [{ field_id: "lessee.name", value: "星海科技" }],
  }
  ignore(documents.create_packet(master, "operator"))
  let drafting = {
    ..master,
    packet_id: "packet-drafting",
    idempotency_key: "packet-drafting-key",
    state: InformationDraft,
  }
  ignore(documents.create_packet(drafting, "subject-a"))
  // A non-effective source cannot renew.
  let not_renewable = service.handle(
    Post,
    "/v1/contract-documents/self/packet-drafting:renew",
    headers("subject-a"),
    "{\"packet_id\":\"packet-renewal-0\",\"idempotency_key\":\"packet-renewal-0-key\"}",
  )
  assert_eq(not_renewable.status, 409)
  assert_true(not_renewable.body.contains("ContractRenewalRejected"))
  // A different subject cannot renew someone else's packet.
  let wrong_owner = service.handle(
    Post,
    "/v1/contract-documents/self/packet-master:renew",
    headers("subject-b"),
    "{\"packet_id\":\"packet-renewal-x\",\"idempotency_key\":\"packet-renewal-x-key\"}",
  )
  assert_eq(wrong_owner.status, 404)
  // The owner renews; the draft links back to the effective source.
  let renewed = service.handle(
    Post,
    "/v1/contract-documents/self/packet-master:renew",
    headers("subject-a"),
    "{\"packet_id\":\"packet-renewal-1\",\"idempotency_key\":\"packet-renewal-1-key\"}",
  )
  assert_eq(renewed.status, 201)
  assert_true(renewed.body.contains("packet-renewal-1"))
  assert_true(renewed.body.contains("packet-master"))
  assert_true(renewed.body.contains("InformationDraft"))
  assert_true(renewed.body.contains("星海科技"))
  // Replaying the same idempotency key returns the stored renewal.
  let replayed = service.handle(
    Post,
    "/v1/contract-documents/self/packet-master:renew",
    headers("subject-a"),
    "{\"packet_id\":\"packet-renewal-1\",\"idempotency_key\":\"packet-renewal-1-key\"}",
  )
  assert_eq(replayed.status, 201)
  assert_true(replayed.body.contains("packet-renewal-1"))
  // The operator prepares a renewal from the console side.
  let operator_renewed = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-master:renew",
    operator_headers,
    "{\"packet_id\":\"packet-renewal-2\",\"idempotency_key\":\"packet-renewal-2-key\"}",
  )
  assert_eq(operator_renewed.status, 201)
  assert_true(operator_renewed.body.contains("packet-renewal-2"))
  let denied = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-master:renew",
    headers("subject-a"),
    "{\"packet_id\":\"packet-renewal-3\",\"idempotency_key\":\"packet-renewal-3-key\"}",
  )
  assert_eq(denied.status, 401)
}
