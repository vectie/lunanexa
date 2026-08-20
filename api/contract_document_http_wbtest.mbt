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
  let access_store = @access.AccessStore::open(
    "\{directory}/access.json",
    "contract-document-access-issuer-secret-more-than-32-bytes",
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
    .with_access_store(access_store)
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
    {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "subject-a",
    },
    "",
  )
  assert_eq(manifest.status, 200)
  assert_true(
    manifest.body.contains("youthpolicy-dgx-spark-remote-lease-revised"),
  )
  let created = service.handle(
    Post,
    "/v1/contract-documents/self",
    {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "subject-a",
    },
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
async test "governance routes enforce effective access and expose the operating view" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-governance-api-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  let documents = @contractdoc_store.ContractDocumentStore::open(
    "\{directory}/contracts.json",
  )
  let access = @access.AccessStore::open(
    "\{directory}/access.json",
    "governance-issuer-secret-more-than-32-bytes",
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
    .with_access_store(access)
    .with_contract_document_store(documents)
    .with_operator_tokens([
      ("operator-a", "operator-token"),
      ("operator-b", "operator-b-token"),
    ])
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet : @contractdoc.ContractPacket = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-governance-api",
      "packet-governance-api-key",
      "tenant-governance-api",
      "org-governance-api",
      "subject-governance-api",
      "order-governance-api",
      None,
      [MasterLease],
      1000L,
    ),
    state: Effective,
  }
  ignore(documents.create_packet(packet, "operator-a"))
  let operator_headers = { "Authorization": "Bearer operator-token" }
  let key_expiry = @async.now() + 86400000L
  let no_lease_intent : @access.ApiKeyIssueIntent = {
    key_id: "key-no-lease",
    tenant_ref: "tenant-other",
    subject_ref: "subject-other",
    display_name: "No lease",
    scopes: [Inference],
    allowed_models: [],
    expires_unix_ms: key_expiry,
    maximum_requests: 10L,
  }
  let with_lease_intent : @access.ApiKeyIssueIntent = {
    key_id: "key-with-lease",
    tenant_ref: "tenant-governance-api",
    subject_ref: "subject-governance-api",
    display_name: "With lease",
    scopes: [Inference],
    allowed_models: [],
    expires_unix_ms: key_expiry,
    maximum_requests: 10L,
  }
  let denied = service.handle(
    Post,
    "/v1/access/api-keys",
    operator_headers,
    no_lease_intent.to_json().stringify(),
  )
  assert_eq(denied.status, 409)
  let issued = service.handle(
    Post,
    "/v1/access/api-keys",
    operator_headers,
    with_lease_intent.to_json().stringify(),
  )
  assert_eq(issued.status, 201)
  let amendment = service.handle(
    Post,
    "/v1/contract-governance/operator/amendments",
    operator_headers,
    "{\"preceding_packet_ref\":\"packet-governance-api\",\"base_revision\":\"1\",\"reason\":\"price amendment\",\"changes\":[{\"field_id\":\"lease.total_rent\",\"value\":\"100\"}]}",
  )
  assert_eq(amendment.status, 201)
  let amendment_value : @contractdoc.ContractAmendment = @json.from_json(
    @json.parse(amendment.body),
  )
  let amendment_again = service.handle(
    Post,
    "/v1/contract-governance/operator/amendments",
    operator_headers,
    "{\"preceding_packet_ref\":\"packet-governance-api\",\"base_revision\":\"1\",\"reason\":\"second price amendment\",\"changes\":[{\"field_id\":\"lease.total_rent\",\"value\":\"110\"}]}",
  )
  assert_eq(amendment_again.status, 201)
  let amendment_again_value : @contractdoc.ContractAmendment = @json.from_json(
    @json.parse(amendment_again.body),
  )
  assert_true(
    amendment_again_value.amendment_id != amendment_value.amendment_id,
  )
  let amendment_replay = service.handle(
    Post,
    "/v1/contract-governance/operator/amendments",
    operator_headers,
    "{\"preceding_packet_ref\":\"packet-governance-api\",\"base_revision\":\"1\",\"reason\":\"price amendment\",\"changes\":[{\"field_id\":\"lease.total_rent\",\"value\":\"100\"}]}",
  )
  assert_eq(amendment_replay.status, 200)
  assert_true(amendment_replay.body.contains(amendment_value.amendment_id))
  let customer_owned_amendment = service.handle(
    Post,
    "/v1/contract-governance/operator/amendments",
    operator_headers,
    "{\"preceding_packet_ref\":\"packet-governance-api\",\"base_revision\":\"1\",\"reason\":\"cross-owner\",\"changes\":[{\"field_id\":\"lessee.name\",\"value\":\"不应由运营方填写\"}]}",
  )
  assert_eq(customer_owned_amendment.status, 409)
  let self_approval = service.handle(
    Post,
    "/v1/contract-governance/operator/amendments/\{amendment_value.amendment_id}:approve",
    operator_headers,
    "",
  )
  assert_eq(self_approval.status, 409)
  let approved = service.handle(
    Post,
    "/v1/contract-governance/operator/amendments/\{amendment_value.amendment_id}:approve",
    { "Authorization": "Bearer operator-b-token" },
    "",
  )
  assert_eq(approved.status, 200)
  let materialized = service.handle(
    Post,
    "/v1/contract-governance/operator/amendments/\{amendment_value.amendment_id}:materialize",
    { "Authorization": "Bearer operator-b-token" },
    "{\"packet_id\":\"packet-governance-successor\",\"idempotency_key\":\"packet-governance-successor-key\"}",
  )
  assert_eq(materialized.status, 201)
  let successor = documents.packet("packet-governance-successor").unwrap()
  assert_eq(successor.preceding_packet_ref, Some("packet-governance-api"))
  assert_eq(successor.value("lease.total_rent"), Some("100"))
  let materialized_replay = service.handle(
    Post,
    "/v1/contract-governance/operator/amendments/\{amendment_value.amendment_id}:materialize",
    { "Authorization": "Bearer operator-b-token" },
    "{\"packet_id\":\"packet-governance-successor\",\"idempotency_key\":\"packet-governance-successor-key\"}",
  )
  assert_eq(materialized_replay.status, 201)
  let duplicate_materialization = service.handle(
    Post,
    "/v1/contract-governance/operator/amendments/\{amendment_value.amendment_id}:materialize",
    { "Authorization": "Bearer operator-b-token" },
    "{\"packet_id\":\"packet-governance-successor-2\",\"idempotency_key\":\"packet-governance-successor-key-2\"}",
  )
  assert_eq(duplicate_materialization.status, 409)
  let dashboard = service.handle(
    Post,
    "/v1/contract-governance/operator/dashboard",
    operator_headers,
    "{\"tenant_ref\":\"tenant-governance-api\"}",
  )
  assert_eq(dashboard.status, 200)
  assert_true(dashboard.body.contains("effective_packets"))
  assert_true(dashboard.body.contains("pending_approvals"))
  let dashboard_post = service.handle(
    Get,
    "/v1/contract-governance/operator/dashboard",
    operator_headers,
    "{\"tenant_ref\":\"tenant-governance-api\"}",
  )
  assert_eq(dashboard_post.status, 404)
  let admission = service.handle(
    Post,
    "/v1/contract-governance/operator/admission",
    operator_headers,
    "{\"tenant_ref\":\"tenant-governance-api\",\"subject_ref\":\"subject-governance-api\"}",
  )
  assert_eq(admission.status, 200)
  assert_true(admission.body.contains("effective_master_lease"))
  let admission_get = service.handle(
    Get,
    "/v1/contract-governance/operator/admission",
    operator_headers,
    "{\"tenant_ref\":\"tenant-governance-api\",\"subject_ref\":\"subject-governance-api\"}",
  )
  assert_eq(admission_get.status, 404)
  @fs.remove(directory + "/state.json")
  @fs.remove(directory + "/state.json.lock")
  @fs.remove(directory + "/contracts.json")
  @fs.remove(directory + "/access.json")
  @fs.remove(directory)
}

///|
async test "four-eyes HTTP approval is 202, second-person, and replay-safe" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-approval-http-")
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
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_contract_document_store(documents)
    .with_operator_tokens([
      ("operator-a", "operator-token"),
      ("operator-b", "operator-b-token"),
    ])
    .with_contract_approval_threshold(0L)
  let packet : @contractdoc.ContractPacket = {
    ..@contractdoc.new_packet(
      @contractdoc.youthpolicy_remote_lease_manifest(),
      "packet-approval-http",
      "packet-approval-http-key",
      "tenant-approval-http",
      "org-approval-http",
      "subject-approval-http",
      "order-approval-http",
      None,
      [MasterLease],
      1000L,
    ),
    state: Effective,
    values: [{ field_id: "lease.total_rent", value: "1" }],
  }
  ignore(documents.create_packet(packet, "operator-a"))
  let pending = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-approval-http:close",
    { "Authorization": "Bearer operator-token" },
    "{\"expected_revision\":\"1\",\"kind\":\"Expired\",\"reason\":\"term ended\"}",
  )
  assert_eq(pending.status, 202)
  let approval : @contractdoc.ContractApproval = @json.from_json(
    @json.parse(pending.body),
  )
  let self_decision = service.handle(
    Post,
    "/v1/contract-documents/operator/approvals/\{approval.approval_id}:approve",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(self_decision.status, 409)
  let decided = service.handle(
    Post,
    "/v1/contract-documents/operator/approvals/\{approval.approval_id}:approve",
    { "Authorization": "Bearer operator-b-token" },
    "",
  )
  assert_eq(decided.status, 200)
  assert_eq(documents.packet(packet.packet_id).unwrap().state, Closed)
  let replay = service.handle(
    Post,
    "/v1/contract-documents/operator/approvals/\{approval.approval_id}:approve",
    { "Authorization": "Bearer operator-b-token" },
    "",
  )
  assert_eq(replay.status, 409)
  @fs.rmdir(directory, recursive=true)
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
  let access_store = @access.AccessStore::open(
    "\{directory}/access.json",
    "contract-lifecycle-access-issuer-secret-more-than-32-bytes",
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
    .with_access_store(access_store)
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
  let portal_body = (
    {
      "key_id": "portal-key-effective",
      "display_name": "Portal key",
      "scopes": ["Inference"],
      "allowed_models": [],
      "expires_unix_ms": (@async.now() + 86400000L).to_json(),
      "maximum_requests": 10L.to_json(),
    } : Json).stringify()
  assert_true(decode_portal_api_key(portal_body) is Some(_))
  let portal_key = service.handle(
    Post,
    "/v1/portal/self/api-keys",
    {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "subject-a",
    },
    portal_body,
  )
  assert_eq(portal_key.status, 201)
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
  service.reconcile_expiring_contracts(day_ms(2026, 8, 1), 7L)
  assert_eq(
    notifications
    .records_for_subject("tenant-a", "subject-a", day_ms(2026, 8, 1))
    .length(),
    1,
  )
  assert_eq(notifications.records_for_operators(day_ms(2026, 8, 1)).length(), 1)
  // A repeated pass at the same time must not duplicate the reminder.
  service.reconcile_expiring_contracts(day_ms(2026, 8, 1), 7L)
  assert_eq(
    notifications
    .records_for_subject("tenant-a", "subject-a", day_ms(2026, 8, 1))
    .length(),
    1,
  )
  assert_eq(notifications.records_for_operators(day_ms(2026, 8, 1)).length(), 1)
  // 5 days remaining: the 7-day window fires once.
  service.reconcile_expiring_contracts(day_ms(2026, 8, 20), 7L)
  service.reconcile_expiring_contracts(day_ms(2026, 8, 20), 7L)
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
  service.reconcile_expiring_contracts(day_ms(2026, 8, 24), 7L)
  service.reconcile_expiring_contracts(day_ms(2026, 8, 24), 7L)
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

///|
async test "operator tokens attribute contract actions to the authenticated operator" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-operators-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  let access = @access.AccessStore::open(
    "\{directory}/access.json",
    "issuer-secret-with-more-than-32-bytes!",
  )
  let now = @async.now()
  ignore(
    access.issue(
      {
        key_id: "key-a1",
        tenant_ref: "tenant-a",
        subject_ref: "subject-a",
        display_name: "Key key-a1",
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
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
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
      durable, runtime, "legacy-operator-token-0000000000000000", "inference-token",
      "node-token", "0.1.0",
    )
    .with_operator_tokens([
      ("alice", "alice-operator-token-0000000000000000"),
      ("bob", "bob-operator-token-000000000000000000"),
    ])
    .with_access_store(access)
    .with_contract_document_store(documents)
    .with_notification_store(notifications)
  let alice_headers = {
    "Authorization": "Bearer alice-operator-token-0000000000000000",
  }
  let bob_headers = {
    "Authorization": "Bearer bob-operator-token-000000000000000000",
  }
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  fn draft_packet(packet_id : String) -> @contractdoc.ContractPacket raise {
    @contractdoc.new_packet(
      manifest,
      packet_id,
      "\{packet_id}-key",
      "tenant-a",
      "org-a",
      "subject-a",
      "order-api-1",
      None,
      [MasterLease],
      1000L,
    )
  }
  ignore(documents.create_packet(draft_packet("packet-info"), "subject-a"))
  let generated = {
    ..draft_packet("packet-sign"),
    state: Generated,
    revision: 5L,
  }
  ignore(documents.create_packet(generated, "subject-a"))
  let effective = { ..draft_packet("packet-close"), state: Effective }
  ignore(documents.create_packet(effective, "subject-a"))
  let renewable = { ..draft_packet("packet-renew-src"), state: Effective }
  ignore(documents.create_packet(renewable, "subject-a"))
  let superseding = {
    ..draft_packet("packet-supersede"),
    state: InformationDraft,
  }
  ignore(documents.create_packet(superseding, "subject-a"))
  let successor = { ..draft_packet("packet-successor"), revision: 1L }
  ignore(documents.create_packet(successor, "subject-a"))
  // An unknown token is rejected, and the legacy single token no longer
  // authenticates once the multi-operator map is installed.
  let unknown = service.handle(
    Get,
    "/v1/contract-documents/operator/packets",
    { "Authorization": "Bearer nope" },
    "",
  )
  assert_eq(unknown.status, 401)
  let legacy = service.handle(
    Get,
    "/v1/contract-documents/operator/packets",
    { "Authorization": "Bearer legacy-operator-token-0000000000000000" },
    "",
  )
  assert_eq(legacy.status, 401)
  // Alice edits operator-owned information.
  let informed = service.handle(
    Put,
    "/v1/contract-documents/operator/packets/packet-info:information",
    alice_headers,
    "{\"expected_revision\":\"1\",\"changes\":[{\"field_id\":\"lessor.name\",\"value\":\"青年政策运营方\"}]}",
  )
  assert_eq(informed.status, 200)
  // Alice registers execution evidence.
  let executed = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-sign:execute",
    alice_headers,
    "{\"expected_revision\":\"5\",\"evidence_sha256\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"signed_on\":\"2026-08-14\"}",
  )
  assert_eq(executed.status, 200)
  assert_eq(
    documents.packet("packet-sign").unwrap().execution.unwrap().registered_by,
    "alice",
  )
  // Bob closes the effective master lease; the closure and the revocation
  // audit both carry his identity.
  let closed = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-close:close",
    bob_headers,
    "{\"expected_revision\":\"1\",\"kind\":\"Expired\",\"reason\":\"lease term ended\"}",
  )
  assert_eq(closed.status, 200)
  let closure = documents.packet("packet-close").unwrap().closure.unwrap()
  assert_eq(closure.closed_by, "bob")
  assert_eq(closure.kind, Expired)
  let audits = durable.audit_events()
  assert_eq(audits.length(), 1)
  assert_eq(audits[0].actor, "bob")
  assert_eq(audits[0].action, "access.api-key.revoke")
  // Bob supersedes a draft.
  let superseded = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-supersede:supersede",
    bob_headers,
    "{\"expected_revision\":\"1\",\"successor_ref\":\"packet-successor\",\"reason\":\"reissued\"}",
  )
  assert_eq(superseded.status, 200)
  assert_eq(
    documents.packet("packet-supersede").unwrap().supersession.unwrap().superseded_by,
    "bob",
  )
  // Alice opens a renewal draft; the creation event names her.
  let renewed = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-renew-src:renew",
    alice_headers,
    "{\"packet_id\":\"packet-renewal\",\"idempotency_key\":\"packet-renewal-key\"}",
  )
  assert_eq(renewed.status, 201)
  let renewal_events = documents.snapshot().events
    .iter()
    .filter(event => event.packet_id == "packet-renewal")
    .collect()
  assert_eq(renewal_events.length(), 1)
  assert_eq(renewal_events[0].actor_ref, "alice")
  // The information event is attributed to alice as well.
  let information_events = documents.snapshot().events
    .iter()
    .filter(event => event.packet_id == "packet-info")
    .collect()
  assert_eq(information_events.length(), 2)
  assert_eq(information_events[1].actor_ref, "alice")
}

///|
async test "legacy single operator token still authenticates as operator" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-operator-legacy-")
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
  let service = ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_contract_document_store(documents)
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
  let closed = service.handle(
    Post,
    "/v1/contract-documents/operator/packets/packet-master:close",
    { "Authorization": "Bearer operator-token" },
    "{\"expected_revision\":\"1\",\"kind\":\"Expired\",\"reason\":\"lease term ended\"}",
  )
  assert_eq(closed.status, 200)
  assert_eq(
    documents.packet("packet-master").unwrap().closure.unwrap().closed_by,
    "operator",
  )
}

///|
async test "contract expiry reconciler auto-closes past the grace period once" {
  let directory = @fs.tmpdir(prefix="lunanexa-contract-autoclose-")
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
        tenant_ref: "tenant-b",
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
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  // Eleven days past its end date at scan time: beyond the 7-day grace.
  let expired = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-expired",
      "packet-expired-key",
      "tenant-a",
      "org-a",
      "subject-a",
      "order-api-1",
      None,
      [MasterLease],
      1000L,
    ),
    state: Effective,
    values: [{ field_id: "lease.end_date", value: "2026-08-01" }],
  }
  ignore(documents.create_packet(expired, "operator"))
  // Two days past its end date: still inside the grace period.
  let within_grace = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-grace",
      "packet-grace-key",
      "tenant-b",
      "org-b",
      "subject-b",
      "order-api-2",
      None,
      [MasterLease],
      1000L,
    ),
    state: Effective,
    values: [{ field_id: "lease.end_date", value: "2026-08-10" }],
  }
  ignore(documents.create_packet(within_grace, "operator"))
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
  fn day_ms(year : Int, month : Int, day : Int) -> Int64 {
    @contractdoc.days_from_civil(year, month, day) * 86400000L
  }
  let scan_now = day_ms(2026, 8, 12)
  service.reconcile_expiring_contracts(scan_now, 7L)
  // The expired packet closed automatically under the scheduler identity.
  let closed = documents.packet("packet-expired").unwrap()
  assert_eq(closed.state, Closed)
  let closure = closed.closure.unwrap()
  assert_eq(closure.kind, Expired)
  assert_eq(closure.closed_by, "scheduler")
  assert_true(closure.reason.contains("2026-08-01"))
  let closed_revision = closed.revision
  // Its subject's credentials were revoked through the shared closure effects.
  assert_true(
    access
    .views_for_subject("tenant-a", "subject-a")
    .all(credential => credential.revoked_unix_ms is Some(_)),
  )
  // Both the subject and the operators were notified of the automatic close.
  let subject_notices = notifications.records_for_subject(
    "tenant-a", "subject-a", scan_now,
  )
  assert_true(
    subject_notices
    .iter()
    .any(record => record.event.code == "ContractExpiredClosed"),
  )
  assert_true(
    subject_notices
    .iter()
    .any(record => record.event.code == "AccessCredentialsRevoked"),
  )
  let operator_notices = notifications.records_for_operators(scan_now)
  assert_eq(operator_notices.length(), 1)
  assert_eq(operator_notices[0].event.code, "ContractExpiredClosed")
  assert_eq(operator_notices[0].event.severity, Critical)
  assert_eq(
    operator_notices[0].event.parameters.get("end_date"),
    Some("2026-08-01"),
  )
  // The packet still inside its grace period is untouched.
  let grace = documents.packet("packet-grace").unwrap()
  assert_eq(grace.state, Effective)
  assert_true(grace.closure is None)
  assert_true(
    access
    .views_for_subject("tenant-b", "subject-b")
    .all(credential => credential.revoked_unix_ms is None),
  )
  assert_eq(
    notifications
    .records_for_subject("tenant-b", "subject-b", scan_now)
    .length(),
    0,
  )
  // A second pass neither re-closes nor re-notifies.
  service.reconcile_expiring_contracts(scan_now, 7L)
  assert_eq(
    documents.packet("packet-expired").unwrap().revision,
    closed_revision,
  )
  assert_eq(
    notifications
    .records_for_subject("tenant-a", "subject-a", scan_now)
    .length(),
    subject_notices.length(),
  )
  assert_eq(notifications.records_for_operators(scan_now).length(), 1)
  assert_eq(documents.packet("packet-grace").unwrap().state, Effective)
}
