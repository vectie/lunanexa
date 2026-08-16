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
