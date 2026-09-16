///|
async test "undertaking renderer archives before Generated and recovers cross-store write failure" {
  let dir = @fs.tmpdir(prefix="contract-archive-api-")
  defer @fs.rmdir(dir, recursive=true)
  let offline = @offline_store.OfflineCommerceStore::open("\{dir}/offline.json")
  ignore(
    offline.create_order({
      ..undertaking_test_order(),
      artifact_ids: [],
      state: Draft,
      quote: None,
    }),
  )
  let document_path = "\{dir}/documents.json"
  let documents = @contractdoc_store.ContractDocumentStore::open(document_path)
  let packet = {
    ..undertaking_test_packet(),
    state: GenerationRequested,
    artifacts: [],
  }
  ignore(documents.create_packet(packet, "subject-a"))
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
    .with_contract_document_store(documents)
    .with_offline_commerce_store(offline)
    .with_contract_document_worker_token(
      "archive-worker-token-with-32-characters",
    )
  let objects = [
    @offline.DocumentArtifactKind::EditableContractDocx,
    PrintReadyContractPdf,
  ].map(kind => @offline_store.ContractArchiveObject::{
    artifact_id: @offline_store.contract_archive_artifact_id(
      packet.packet_id,
      packet.revision,
      kind,
    ),
    object_ref: @offline_store.contract_archive_object_ref(
      packet.organization_id,
      packet.order_ref,
      packet.packet_id,
      packet.revision,
      kind,
    ),
    media_type: if kind == EditableContractDocx {
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    } else {
      "application/pdf"
    },
    sha256: "sha256:" + "a".repeat(64),
    byte_count: 2000L,
    storage_receipt: "trusted-storage-fixture",
    stored_unix_ms: 3000L,
    verified: true,
    active_content_detected: false,
  })
  let artifacts = objects.map(object => @contractdoc.ContractGeneratedArtifact::{
    artifact_id: object.artifact_id,
    media_type: object.media_type,
    sha256: object.sha256,
    byte_count: object.byte_count,
    page_count: 4,
    render_evidence_sha256: "sha256:" + "b".repeat(64),
    generated_unix_ms: 2000L,
  })
  let request : Json = {
    "packet_id": packet.packet_id.to_json(),
    "expected_revision": packet.revision.to_json(),
    "docx": artifacts[0].to_json(),
    "pdf": artifacts[1].to_json(),
    "worker_receipt": "renderer-fixture",
    "docx_storage": objects[0].to_json(),
    "pdf_storage": objects[1].to_json(),
  }
  let headers = {
    "Authorization": "Bearer archive-worker-token-with-32-characters",
  }
  let path = "/v1/contract-documents/worker/results"
  assert_eq(
    service.handle(
      Post,
      path,
      { "Authorization": "Bearer inference-token" },
      request.stringify(),
    ).status,
    401,
  )
  let missing : Json = {
    "packet_id": packet.packet_id.to_json(),
    "expected_revision": packet.revision.to_json(),
    "docx": artifacts[0].to_json(),
    "pdf": artifacts[1].to_json(),
    "worker_receipt": "renderer-fixture",
  }
  assert_eq(
    service.handle(Post, path, headers, missing.stringify()).status,
    409,
  )
  assert_eq(offline.snapshot().artifacts.length(), 0)
  @fs.mkdir(document_path + ".next")
  let failed = service.handle(Post, path, headers, request.stringify())
  assert_true(failed.status >= 400)
  assert_eq(offline.snapshot().artifacts.length(), 2)
  assert_eq(
    documents.packet(packet.packet_id).unwrap().state,
    GenerationRequested,
  )
  @fs.rmdir(document_path + ".next")
  let recovered = service.handle(Post, path, headers, request.stringify())
  assert_eq(recovered.status, 200, msg=recovered.body)
  assert_eq(documents.packet(packet.packet_id).unwrap().state, Generated)
  assert_eq(offline.snapshot().artifacts.length(), 2)
  let replay = service.handle(Post, path, headers, request.stringify())
  assert_eq(replay.status, 200, msg=replay.body)
  assert_eq(offline.snapshot().artifacts.length(), 2)
}
