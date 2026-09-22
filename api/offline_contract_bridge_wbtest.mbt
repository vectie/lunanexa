///|
async fn contract_bridge_fixture(
  dir : String,
) -> (
  ApiService,
  @offline_store.OfflineCommerceStore,
  @contractdoc_store.ContractDocumentStore,
  @contractdoc.ContractPacket,
) {
  let commerce = @offline_store.OfflineCommerceStore::open(
    dir + "/commerce.json",
  )
  let documents = @contractdoc_store.ContractDocumentStore::open(
    dir + "/documents.json",
  )
  let portal = @portal_store.FilePortalStore::open(dir + "/portal.json")
  let now = @async.now()
  let manifest = @contractdoc.undertaking_ofl_manifest()
  ignore(
    portal.put_membership({
      membership_id: "bridge-member",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [LeaseRequester],
      active: true,
      created_unix_ms: now,
    }),
  )
  let initial = {
    ..undertaking_test_order(),
    quote: None,
    artifact_ids: [],
    state: @offline.Draft,
  }
  ignore(commerce.create_order(initial))
  let quoted = commerce.quote_order(
    initial.order_id,
    {
      ..undertaking_test_order().quote.unwrap(),
      terms_digest: manifest.sha256,
    },
    "operator",
    now,
  )
  ignore(
    commerce.begin_offline_execution(initial.order_id, quoted.generation, now),
  )
  ignore(
    commerce.register_template({
      template_id: manifest.template_id,
      version: manifest.template_version,
      kind: ContractTemplate,
      locale: "zh-CN",
      media_type: manifest.media_type,
      object_ref: "s3://technical/ofl.docx",
      sha256: manifest.fillable_sha256,
      byte_count: 16043L,
      active_content_allowed: false,
      created_unix_ms: now,
      superseded_unix_ms: None,
    }),
  )
  let packet = {
    ..@contractdoc.new_packet(
      manifest,
      "bridge-packet",
      "bridge-packet-key",
      "tenant-a",
      "org-a",
      "subject-a",
      initial.order_id,
      None,
      [MasterLease],
      now,
    ),
    state: @contractdoc.InformationConfirmed,
    values_sha256: Some("sha256:" + "a".repeat(64)),
    values: [{ field_id: "lessee.name", value: "Original confirmed company", }],
  }
  ignore(documents.create_packet(packet, "subject-a"))
  commerce.record_worker_acceptance(ArtifactDispatcher, now)
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
  let caps = kinds.mapi((index, capability) => @offline.OfflineCommerceCapabilityEvidence::{
    capability,
    configured: true,
    verified: true,
    evidence_ref: Some("unit-test-only-not-production-" + index.to_string()),
  })
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      @store.FileStore::open(dir + "/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_contract_document_store(documents)
    .with_offline_commerce_store(commerce)
    .with_offline_artifact_callback_tokens(
      "bridge-worker-token-with-more-than-32-characters", "bridge-scanner-token-with-more-than-32-characters",
    )
    .with_offline_commerce_capabilities(caps, now + 3600000L)
    .with_offline_template_approvals([
      {
        template_id: manifest.template_id,
        version: manifest.template_version,
        locale: manifest.locale,
        sha256: manifest.fillable_sha256,
        approval_ref: "unit-test-only",
      },
    ])
  (service, commerce, documents, packet)
}

///|
fn bridge_result(
  request : @offline.ArtifactGenerationRequest,
  count : Int?,
) -> @offline.ArtifactGenerationResult {
  {
    request_id: request.request_id,
    artifact_id: request.artifact_id,
    expected_object_ref: request.expected_object_ref,
    media_type: if request.kind == EditableContractDocx {
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    } else {
      "application/pdf"
    },
    byte_count: 1234L,
    sha256: "sha256:" + "b".repeat(64),
    worker_receipt: "unit-test-renderer",
    verified: true,
    active_content_detected: false,
    moonleaf_verified: true,
    render_verified: true,
    formula_error_count: 0,
    visual_evidence_sha256: "sha256:" + "c".repeat(64),
    completed_unix_ms: @async.now(),
    page_count: count,
  }
}

///|
async test "MoonEdit generate queues frozen pair and recovers packet commit after callback and restart" {
  let dir = @fs.tmpdir(prefix="offline-contract-bridge-")
  defer @fs.rmdir(dir, recursive=true)
  let (service, commerce, documents, packet) = contract_bridge_fixture(dir)
  let body : Json = {
    "expected_revision": packet.revision.to_json(),
    "expected_values_sha256": packet.values_sha256.unwrap(),
  }
  let headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  let clicked = service.handle(
    Post,
    "/v1/contract-documents/self/bridge-packet:generate",
    headers,
    body.stringify(),
  )
  assert_eq(clicked.status, 202, msg=clicked.body)
  assert_eq(commerce.snapshot().generation_requests.length(), 2)
  let frozen = documents.packet(packet.packet_id).unwrap()
  assert_eq(frozen.state, @contractdoc.GenerationRequested)
  // Exact click retry is not a second revision/request pair.
  assert_eq(
    service.handle(
      Post,
      "/v1/contract-documents/self/bridge-packet:generate",
      headers,
      body.stringify(),
    ).status,
    202,
  )
  assert_eq(documents.packet(packet.packet_id).unwrap(), frozen)
  assert_eq(commerce.snapshot().generation_requests.length(), 2)
  let requests = commerce.claim_generation_requests(@async.now())
  assert_eq(requests.length(), 2)
  let worker = {
    "Authorization": "Bearer bridge-worker-token-with-more-than-32-characters",
  }
  for request in requests {
    let plan = service.handle(
      Post,
      "/v1/offline-commerce/operator/generation-plan",
      worker,
      ({ "request": request.to_json(), "markers": ["{{lessee.name}}"] } : Json).stringify(),
    )
    assert_eq(plan.status, 200)
    assert_true(plan.body.contains("Original confirmed company"))
    assert_true(plan.body.contains("contract_binding"))
  }
  let first = bridge_result(requests[0], Some(4))
  let second = bridge_result(requests[1], Some(4))
  let result_path = "/v1/offline-commerce/operator/generation-results"
  assert_eq(
    service.handle(
      Post,
      result_path,
      worker,
      ({ "result": first.to_json() } : Json).stringify(),
    ).status,
    201,
  )
  assert_eq(
    documents.packet(packet.packet_id).unwrap().state,
    @contractdoc.GenerationRequested,
  )
  // Both objects stay durable if the final packet commit fails.
  @fs.mkdir(dir + "/documents.json.next")
  assert_eq(
    service.handle(
      Post,
      result_path,
      worker,
      ({ "result": second.to_json() } : Json).stringify(),
    ).status,
    201,
  )
  assert_eq(commerce.snapshot().artifacts.length(), 2)
  assert_eq(
    documents.packet(packet.packet_id).unwrap().state,
    @contractdoc.GenerationRequested,
  )
  @fs.rmdir(dir + "/documents.json.next")
  let reopened_commerce = @offline_store.OfflineCommerceStore::open(
    dir + "/commerce.json",
  )
  let reopened_documents = @contractdoc_store.ContractDocumentStore::open(
    dir + "/documents.json",
  )
  let restarted = service
    .with_offline_commerce_store(reopened_commerce)
    .with_contract_document_store(reopened_documents)
  restarted.reconcile_offline_contract_packets()
  let completed = reopened_documents.packet(packet.packet_id).unwrap()
  assert_eq(completed.state, @contractdoc.Generated)
  assert_eq(completed.artifacts.length(), 2)
  assert_true(
    completed.artifacts.all(a => {
      a.page_count == 4 &&
      a.render_evidence_sha256 == first.visual_evidence_sha256
    }),
  )
  assert_eq(completed.revision, frozen.revision + 1L)
  restarted.reconcile_offline_contract_packets()
  assert_eq(reopened_documents.packet(packet.packet_id).unwrap(), completed)
  // Changed proof cannot replace an exact completed callback.
  assert_eq(
    restarted.handle(
      Post,
      result_path,
      worker,
      ({ "result": { ..second, page_count: Some(3), }.to_json() } : Json).stringify(),
    ).status,
    409,
  )
}

///|
async test "contract bridge rejects stale revision missing page proof and mismatched pair" {
  let dir = @fs.tmpdir(prefix="offline-contract-bridge-denial-")
  defer @fs.rmdir(dir, recursive=true)
  let (service, commerce, documents, packet) = contract_bridge_fixture(dir)
  let requested = documents.request_generation(
    packet.packet_id,
    packet.revision,
    packet.values_sha256.unwrap(),
    packet.subject_ref,
    @async.now(),
  )
  service.enqueue_offline_contract_packet(requested)
  let requests = commerce.claim_generation_requests(@async.now())
  try commerce.complete_generation(bridge_result(requests[0], None)) catch {
    @offline.OfflineCommerceError::ArtifactUnavailable(_) => ()
    error => fail("unexpected missing-proof error: \{Repr(error)}")
  } noraise {
    _ => fail("missing actual page count accepted")
  }
  ignore(commerce.complete_generation(bridge_result(requests[0], Some(4))))
  ignore(commerce.complete_generation(bridge_result(requests[1], Some(3))))
  try service.complete_offline_contract_packet(requested) catch {
    _ => ()
  } noraise {
    _ => fail("different page counts completed packet")
  }
  assert_eq(
    documents.packet(packet.packet_id).unwrap().state,
    @contractdoc.GenerationRequested,
  )
  ignore(
    documents.fail_generation(
      packet.packet_id,
      requested.revision,
      "unit-test cancellation of rendering",
      "operator",
      @async.now(),
    ),
  )
  let response = service.handle(
    Post,
    "/v1/offline-commerce/operator/generation-plan",
    {
      "Authorization": "Bearer bridge-worker-token-with-more-than-32-characters",
    },
    ({ "request": requests[0].to_json(), "markers": ["{{lessee.name}}"] } : Json).stringify(),
  )
  assert_eq(response.status, 409)
  assert_eq(
    documents.packet(packet.packet_id).unwrap().state,
    @contractdoc.GenerationFailed,
  )
}

///|
async test "contract bridge resumes enqueue failure and preserves legacy packet reads" {
  let dir = @fs.tmpdir(prefix="offline-contract-bridge-retry-")
  defer @fs.rmdir(dir, recursive=true)
  let (service, commerce, documents, packet) = contract_bridge_fixture(dir)
  let body : Json = {
    "expected_revision": packet.revision.to_json(),
    "expected_values_sha256": packet.values_sha256.unwrap(),
  }
  let headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  @fs.mkdir(dir + "/commerce.json.next")
  let failed = service.handle(
    Post,
    "/v1/contract-documents/self/bridge-packet:generate",
    headers,
    body.stringify(),
  )
  assert_eq(failed.status, 503)
  assert_true(failed.body.contains("ContractGenerationEnqueuePending"))
  assert_eq(
    documents.packet(packet.packet_id).unwrap().state,
    @contractdoc.GenerationRequested,
  )
  assert_eq(commerce.snapshot().generation_requests.length(), 0)
  @fs.rmdir(dir + "/commerce.json.next")
  service.reconcile_offline_contract_packets()
  assert_eq(commerce.snapshot().generation_requests.length(), 2)
  assert_eq(
    service.handle(
      Post,
      "/v1/contract-documents/self/bridge-packet:generate",
      headers,
      body.stringify(),
    ).status,
    202,
  )
  let legacy = {
    ..undertaking_test_packet(),
    order_ref: "legacy-read-only-order",
  }
  ignore(documents.create_packet(legacy, "operator"))
  let original = documents.packet(legacy.packet_id).unwrap()
  let denied = service
    .offline_contract_generation_gate(legacy, @async.now())
    .unwrap()
  assert_true(denied.body.contains("TemplateApprovalScopeMissing"))
  assert_eq(documents.packet(legacy.packet_id).unwrap(), original)
  assert_eq(
    service.handle(Get, "/v1/contract-documents/self", headers, "").status,
    200,
  )
}
