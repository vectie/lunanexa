///|
async test "created order-scoped packet supplies real dispatcher plan without agreement ref" {
  let dir = @fs.tmpdir(prefix="offline-packet-binding-")
  defer @fs.rmdir(dir, recursive=true)
  let documents = @contractdoc_store.ContractDocumentStore::open(
    dir + "/documents.json",
  )
  let commerce = @offline_store.OfflineCommerceStore::open(
    dir + "/offline.json",
  )
  let manifest = @contractdoc.undertaking_ofl_manifest()
  let now = @async.now()
  let initial = {
    ..undertaking_test_order(),
    state: @offline.Draft,
    quote: None,
    artifact_ids: [],
  }
  ignore(commerce.create_order(initial))
  let quoted = commerce.quote_order(
    initial.order_id,
    undertaking_test_order().quote.unwrap(),
    "operator",
    now,
  )
  let order = commerce.begin_offline_execution(
    initial.order_id,
    quoted.generation,
    now,
  )
  assert_true(order.agreement_ref is None)
  let template : @offline.DocumentTemplate = {
    template_id: manifest.template_id,
    version: manifest.template_version,
    kind: ContractTemplate,
    locale: "zh-CN",
    media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    object_ref: "s3://technical/templates/ofl.docx",
    sha256: manifest.fillable_sha256,
    byte_count: 16043L,
    active_content_allowed: false,
    created_unix_ms: now,
    superseded_unix_ms: None,
  }
  ignore(commerce.register_template(template))
  let packet = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-ofl",
      "packet-ofl-key",
      order.tenant_ref,
      order.organization_id,
      order.purchaser_subject_ref,
      order.order_id,
      None,
      [MasterLease],
      now,
    ),
    state: @contractdoc.GenerationRequested,
    values: [{ field_id: "lessee.name", value: "Technical acceptance only", }],
  }
  ignore(documents.create_packet(packet, order.purchaser_subject_ref))
  assert_true(offline_generation_packet([packet], order, template) is Some(_))
  assert_true(
    offline_generation_packet(
      [packet, { ..packet, packet_id: "other", }],
      order,
      template,
    )
    is None,
  )
  assert_true(
    offline_generation_packet(
      [packet],
      { ..order, agreement_ref: Some("missing"), },
      template,
    )
    is None,
  )
  for
    wrong in [
      { ..packet, tenant_ref: "other", },
      { ..packet, organization_id: "other", },
      { ..packet, subject_ref: "other", },
      { ..packet, order_ref: "other", },
      { ..packet, template_sha256: "sha256:" + "b".repeat(64), },
      { ..packet, state: @contractdoc.InformationDraft, },
    ] {
    assert_true(offline_generation_packet([wrong], order, template) is None)
  }
  let request = commerce.request_generation({
    request_id: "request-ofl",
    order_id: order.order_id,
    organization_id: order.organization_id,
    artifact_id: "artifact-ofl",
    kind: PrintReadyContractPdf,
    template_id: template.template_id,
    template_version: template.version,
    locale: template.locale,
    expected_object_ref: "s3://technical/output.pdf",
    input_snapshot_sha256: order.quote.unwrap().terms_digest,
    requested_by: "operator",
    requested_unix_ms: now,
  })
  ignore(commerce.claim_generation_requests(now))
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
    .with_offline_commerce_store(commerce)
    .with_contract_document_store(documents)
    .with_offline_artifact_callback_tokens(
      "artifact-worker-token-32-bytes-minimum", "artifact-scanner-token-32-bytes-minimum",
    )
  let response = service.handle(
    Post,
    "/v1/offline-commerce/operator/generation-plan",
    { "Authorization": "Bearer artifact-worker-token-32-bytes-minimum" },
    ({ "request": request.to_json(), "markers": ["{{lessee.name}}"] } : Json).stringify(),
  )
  assert_eq(response.status, 200)
  assert_true(response.body.contains("Technical acceptance only"))
  assert_true(commerce.generation_plan(request.request_id) is Some(_))
}
