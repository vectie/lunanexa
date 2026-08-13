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
