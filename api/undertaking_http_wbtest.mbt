///|
fn undertaking_test_money(amount : Int64) -> @commercial.FixedMoney {
  { minor_units: amount, currency: "CNY", scale: 2, }
}

///|
fn undertaking_test_order() -> @offline.CommercialOrder {
  let money = undertaking_test_money(4900L)
  {
    order_id: "undertaking-order",
    idempotency_key: "undertaking-order-key",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    purchaser_subject_ref: "subject-a",
    selected_service_code: "machine",
    selected_sla_code: "standard",
    policy: {
      require_executed_agreement: true,
      require_payment: true,
      invoice_timing: InvoiceNotRequired,
      require_identity_verification: false,
      require_internal_approval: false,
    },
    quote: Some({
      quote_id: "quote-a",
      version: "v1",
      service_code: "machine",
      sla_code: "standard",
      currency: "CNY",
      lines: [
        {
          line_id: "machine-day",
          description: "device day",
          quantity: 1L,
          unit: "day",
          unit_price: money,
          line_total: money,
        },
      ],
      subtotal: money,
      tax: undertaking_test_money(0L),
      total: money,
      valid_until_unix_ms: 4000000000000L,
      terms_digest: "sha256:" + "a".repeat(64),
      created_unix_ms: 1000L,
    }),
    agreement_ref: None,
    artifact_ids: ["signed-a", "payment-a"],
    entitlement_ref: None,
    state: UnderReconciliation,
    generation: 1L,
    created_unix_ms: 1000L,
    updated_unix_ms: 3000L,
    expires_unix_ms: 4000000000000L,
  }
}

///|
fn undertaking_test_packet() -> @contractdoc.ContractPacket raise {
  let manifest = @contractdoc.undertaking_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "undertaking-packet",
    "undertaking-packet-key",
    "tenant-a",
    "org-a",
    "subject-a",
    "undertaking-order",
    None,
    [MasterLease],
    1000L,
  )
  let digest = "sha256:" + "a".repeat(64)
  {
    ..packet,
    state: Generated,
    revision: 6L,
    values_sha256: Some(digest),
    values: [
      { field_id: "lessee.name", value: "Test user", },
      { field_id: "undertaking.signed_date", value: "2026-09-16", },
      { field_id: "lease.start_date", value: "2026-09-16", },
      { field_id: "lease.end_date", value: "2026-09-16", },
      { field_id: "lease.total_rent", value: "49.00", },
    ],
    artifacts: [
      {
        artifact_id: "rendered-a",
        media_type: "application/pdf",
        sha256: digest,
        byte_count: 100L,
        page_count: 4,
        render_evidence_sha256: digest,
        generated_unix_ms: 2000L,
      },
    ],
  }
}

///|
fn undertaking_test_artifact(
  id : String,
  kind : @offline.DocumentArtifactKind,
) -> @offline.DocumentArtifact {
  {
    artifact_id: id,
    order_id: "undertaking-order",
    organization_id: "org-a",
    kind,
    revision: 1,
    template_id: None,
    template_version: None,
    locale: "zh-CN",
    media_type: "application/pdf",
    byte_count: 100L,
    sha256: "sha256:" + "b".repeat(64),
    object_ref: "object://undertaking/\{id}",
    generation_state: UserUploaded,
    scan_state: ScanPassed,
    review_state: ReviewAccepted,
    submitted_by: "subject-a",
    creator_receipt: "scanner-receipt",
    created_unix_ms: 3000L,
  }
}

///|
async fn undertaking_test_snapshot(
  path : String,
) -> @offline.OfflineCommerceSnapshot {
  let empty = @offline_store.OfflineCommerceStore::open(path).snapshot()
  {
    ..empty,
    orders: [undertaking_test_order()],
    artifacts: [
      undertaking_test_artifact("signed-a", ExecutedContractScan),
      undertaking_test_artifact("payment-a", PaymentReceipt),
    ],
    reviews: [
      {
        review_id: "finance-a",
        order_id: "undertaking-order",
        artifact_id: "payment-a",
        expected_artifact_sha256: "sha256:" + "b".repeat(64),
        reviewer_ref: "finance",
        accepted: true,
        reason_code: "FullPrepaymentVerified",
        audit_receipt: "finance-audit",
        reviewed_unix_ms: 4000L,
      },
    ],
  }
}

///|
test "undertaking fixed tariffs reject discounts extra taxes currencies and duration mismatch" {
  let base = undertaking_test_order()
  let quote = base.quote.unwrap()
  for
    (unit, days, amount) in [
      ("day", 1L, 4900L),
      ("week", 7L, 32200L),
      ("month", 30L, 129000L),
      ("quarter", 90L, 360000L),
      ("year", 365L, 1387000L),
    ] {
    let money = undertaking_test_money(amount)
    let q = {
      ..quote,
      lines: [{ ..quote.lines[0], unit, unit_price: money, line_total: money, }],
      subtotal: money,
      total: money,
    }
    assert_eq(
      @offline.undertaking_quote_term({ ..base, quote: Some(q), }),
      Some(days),
    )
  }
  for
    bad in [
      { ..quote, total: { ..quote.total, currency: "USD", }, },
      { ..quote, tax: undertaking_test_money(1L), },
      { ..quote, total: undertaking_test_money(4800L), },
      { ..quote, lines: [{ ..quote.lines[0], quantity: 0L, }], },
      { ..quote, lines: [{ ..quote.lines[0], quantity: 10001L, }], },
      { ..quote, lines: [{ ..quote.lines[0], unit: "negotiated", }], },
    ] {
    assert_eq(
      @offline.undertaking_quote_term({ ..base, quote: Some(bad), }),
      None,
    )
  }
  let packet = undertaking_test_packet()
  assert_true(undertaking_quote_matches(packet, base))
  assert_false(
    undertaking_quote_matches(
      {
        ..packet,
        values: packet.values.filter(v => v.field_id != "lease.start_date"),
      },
      base,
    ),
  )
  assert_false(
    undertaking_quote_matches(
      {
        ..packet,
        values: packet.values.map(v => {
          if v.field_id == "lease.end_date" {
            { ..v, value: "2026-09-17", }
          } else {
            v
          }
        }),
      },
      base,
    ),
  )
}

///|
async test "undertaking evidence requires current signed version and explicit full prepayment review" {
  let dir = @fs.tmpdir(prefix="undertaking-evidence-")
  let snapshot = undertaking_test_snapshot("\{dir}/offline.json")
  let packet = undertaking_test_packet()
  let digest = "sha256:" + "b".repeat(64)
  assert_true(undertaking_evidence_valid(snapshot, packet, digest, true, 5000L))
  assert_false(
    undertaking_evidence_valid(
      {
        ..snapshot,
        reviews: [{ ..snapshot.reviews[0], reason_code: "EvidenceAccepted", }],
      },
      packet,
      digest,
      true,
      5000L,
    ),
  )
  assert_false(
    undertaking_evidence_valid(
      {
        ..snapshot,
        reviews: [{ ..snapshot.reviews[0], reviewed_unix_ms: 500L, }],
      },
      packet,
      digest,
      true,
      5000L,
    ),
  )
  assert_false(
    undertaking_evidence_valid(
      {
        ..snapshot,
        reviews: [{ ..snapshot.reviews[0], reviewer_ref: "subject-a", }],
      },
      packet,
      digest,
      true,
      5000L,
    ),
  )
  assert_false(
    undertaking_evidence_valid(
      {
        ..snapshot,
        artifacts: [
          { ..snapshot.artifacts[0], created_unix_ms: 1500L, },
          snapshot.artifacts[1],
        ],
      },
      packet,
      digest,
      true,
      5000L,
    ),
  )
  for
    state in [
      @offline.OfflineOrderState::Cancelled,
      Revoked,
      ReversalPending,
      NeedsCorrection,
    ] {
    assert_false(
      undertaking_evidence_valid(
        { ..snapshot, orders: [{ ..snapshot.orders[0], state, }], },
        packet,
        digest,
        true,
        5000L,
      ),
    )
  }
  assert_false(
    undertaking_evidence_valid(
      snapshot,
      { ..packet, tenant_ref: "tenant-b", },
      digest,
      true,
      5000L,
    ),
  )
  assert_true(
    undertaking_order_live(
      { ..snapshot.orders[0], state: Fulfilled, expires_unix_ms: 4500L, },
      5000L,
    ),
  )
}

///|
async test "undertaking API submits approves persists and revokes with its prepaid order" {
  let dir = @fs.tmpdir(prefix="undertaking-api-")
  let snapshot = undertaking_test_snapshot("\{dir}/empty.json")
  @fs.write_file(
    "\{dir}/offline.json",
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
  let offline = @offline_store.OfflineCommerceStore::open("\{dir}/offline.json")
  let documents = @contractdoc_store.ContractDocumentStore::open(
    "\{dir}/documents.json",
  )
  let packet = undertaking_test_packet()
  ignore(documents.create_packet(packet, "subject-a"))
  let portal = @portal_store.FilePortalStore::open("\{dir}/portal.json")
  for
    (subject, tenant, organization) in [
      ("subject-a", "tenant-a", "org-a"),
      ("subject-b", "tenant-b", "org-b"),
    ] {
    ignore(
      portal.put_membership({
        membership_id: subject,
        tenant_ref: tenant,
        organization_id: organization,
        subject_ref: subject,
        roles: [LegalSigner, Developer],
        active: true,
        created_unix_ms: 1000L,
      }),
    )
  }
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      @store.FileStore::open("\{dir}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_contract_document_store(documents)
    .with_offline_commerce_store(offline)
    .with_operator_tokens([("manager-a", "operator-token")])
  let user = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  let other = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-b",
  }
  let manager = { "Authorization": "Bearer operator-token" }
  let body = "{\"expected_revision\":\"6\",\"evidence_artifact_id\":\"signed-a\",\"signed_on\":\"2026-09-16\"}"
  let path = "/v1/contract-documents/self/undertaking-packet:undertaking-submit"
  assert_eq(service.handle(Post, path, other, body).status, 404)
  let submitted = service.handle(Post, path, user, body)
  assert_eq(submitted.status, 202, msg=submitted.body)
  assert_eq(service.handle(Post, path, user, body).status, 202)
  let direct = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/undertaking-packet:execute",
    manager,
    "{\"expected_revision\":\"6\",\"evidence_sha256\":\"sha256:" +
    "b".repeat(64) +
    "\",\"signed_on\":\"2026-09-16\"}",
  )
  assert_eq(direct.status, 409)
  assert_false(
    service.undertaking_fulfillment_allowed("undertaking-order", 1789516800000L),
  )
  let approved = service.handle(
    Post,
    "/v1/contract-documents/operator/approvals/undertaking-undertaking-packet-6:approve",
    manager,
    "{}",
  )
  assert_eq(approved.status, 200, msg=approved.body)
  let current = documents.packet(packet.packet_id).unwrap()
  assert_eq(current.state, Effective)
  let reopened = @contractdoc_store.ContractDocumentStore::open(
    "\{dir}/documents.json",
  )
  assert_eq(reopened.packet(packet.packet_id), Some(current))
  let during = @contractdoc.calendar_date_days("2026-09-16").unwrap() *
    86400000L
  assert_true(
    service.has_effective_rental_authority(
      documents,
      "tenant-a",
      "subject-a",
      during,
      organization_id="org-a",
    ),
  )
  assert_false(
    service.has_effective_rental_authority(
      documents,
      "tenant-a",
      "subject-a",
      during,
      organization_id="org-b",
    ),
  )
  assert_false(
    service.has_effective_rental_authority(
      documents, "tenant-a", "subject-a", during,
    ),
  )
  assert_false(
    service.has_effective_rental_authority(
      documents,
      "tenant-a",
      "subject-a",
      during - 86400000L,
      organization_id="org-a",
    ),
  )
  assert_false(
    service.has_effective_rental_authority(
      documents,
      "tenant-a",
      "subject-a",
      during + 86400000L,
      organization_id="org-a",
    ),
  )
  let draft_documents = @contractdoc_store.ContractDocumentStore::open(
    "\{dir}/revision.json",
  )
  ignore(draft_documents.create_packet(packet, "subject-a"))
  let draft_service = service.with_contract_document_store(draft_documents)
  assert_eq(draft_service.handle(Post, path, user, body).status, 202)
  let approval_path = "/v1/contract-documents/self/approvals/undertaking-undertaking-packet-6:withdraw"
  assert_eq(
    draft_service.handle(
      Post,
      approval_path,
      other,
      "{\"reason\":\"correct details\"}",
    ).status,
    404,
  )
  assert_eq(
    draft_service.handle(
      Post,
      approval_path,
      user,
      "{\"reason\":\"correct details\"}",
    ).status,
    200,
  )
  assert_eq(
    draft_service.handle(
      Post,
      "/v1/contract-documents/operator/approvals/undertaking-undertaking-packet-6:approve",
      manager,
      "{}",
    ).status,
    409,
  )
  let revised = draft_service.handle(
    Post,
    "/v1/contract-documents/self/undertaking-packet:revise",
    user,
    "{\"expected_revision\":\"6\"}",
  )
  assert_eq(revised.status, 200, msg=revised.body)
  assert_eq(
    draft_documents.packet(packet.packet_id).unwrap().values_sha256,
    None,
  )
  assert_eq(draft_documents.packet(packet.packet_id).unwrap().artifacts, [])
  ignore(offline.cancel_order("undertaking-order", 1L, 5000L))
  assert_false(
    service.has_effective_rental_authority(
      documents,
      "tenant-a",
      "subject-a",
      during,
      organization_id="org-a",
    ),
  )
}
