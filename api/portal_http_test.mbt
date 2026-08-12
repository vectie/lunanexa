///|
async test "enterprise user signs, requests, and operator assigns exactly one node" {
  let directory = @fs.tmpdir(prefix="lunanexa-portal-api-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.put_heartbeat({
    ..schedulable_heartbeat(Active),
    running_deployments: [],
  })
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let portal_store = @portal_store.FilePortalStore::open(
    "\{directory}/portal.json",
  )
  let exclusive_store = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive.json",
    "lease-secret",
  )
  let service = @api.ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_portal_store(portal_store)
    .with_exclusive_lease_store(exclusive_store)
  let operator = { "Authorization": "Bearer operator-token" }
  let tenant = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  let now = @async.now()
  let membership : @portal.EnterpriseMembership = {
    membership_id: "member-a",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    subject_ref: "subject-a",
    roles: [LegalSigner, LeaseRequester, Developer],
    active: true,
    created_unix_ms: now,
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/operator/memberships",
      operator,
      membership.to_json().stringify(),
    ).status,
    201,
  )
  let agreement : @portal.PortalAgreement = {
    agreement_id: "agreement-a",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    template_ref: "framework-v1",
    title: "Framework agreement",
    summary: "Required for exclusive capacity.",
    rendered_document_hash: "sha256:document",
    state: ReviewRequired,
    generation: 1L,
    signer_subject_ref: None,
    signature_request_receipt: None,
    executed_artifact_hash: None,
    created_unix_ms: now,
    updated_unix_ms: now,
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/operator/agreements",
      operator,
      agreement.to_json().stringify(),
    ).status,
    201,
  )
  let premature : @portal.LeaseRequestSubmission = {
    request_id: "request-a",
    idempotency_key: "submit-a",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    unix_username: "alice",
    starts_unix_ms: now + 1000L,
    expires_unix_ms: now + 60000L,
    requested_model_ids: ["model-a"],
    justification: "Evaluation work",
  }
  let blocked = service.handle(
    Post,
    "/v1/portal/lease-requests",
    tenant,
    premature.to_json().stringify(),
  )
  assert_eq(blocked.status, 409)
  assert_true(blocked.body.contains("AgreementRequired"))
  let hostile_body = premature
    .to_json()
    .stringify()
    .replace_all(
      old="\"justification\":\"Evaluation work\"",
      new="\"justification\":\"Evaluation work\",\"password\":\"do-not-store\",\"node_id\":\"node-a\"",
    )
  let secret_rejected = service.handle(
    Post,
    "/v1/portal/lease-requests",
    tenant,
    hostile_body,
  )
  assert_eq(secret_rejected.status, 400)
  assert_false(
    @fs.read_file("\{directory}/portal.json").text().contains("do-not-store"),
  )
  let signature = service.handle(
    Post,
    "/v1/portal/signature-requests",
    tenant,
    @portal.SignatureRequest::{
      agreement_id: "agreement-a",
      expected_generation: 1L,
      idempotency_key: "sign-a",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(signature.status, 202)
  let requested_agreement : @portal.PortalAgreement = @json.from_json(
    @json.parse(signature.body),
  )
  ignore(
    portal_store.record_execution(
      {
        agreement_id: "agreement-a",
        expected_generation: requested_agreement.generation,
        signer_subject_ref: "subject-a",
        executed_artifact_hash: "sha256:executed",
        evidence_receipt: "test-fixture:verified:a",
      },
      @async.now(),
    ),
  )
  let submitted = service.handle(
    Post,
    "/v1/portal/lease-requests",
    tenant,
    premature.to_json().stringify(),
  )
  assert_eq(submitted.status, 201)
  let request : @portal.EnterpriseLeaseRequest = @json.from_json(
    @json.parse(submitted.body),
  )
  let approved = service.handle(
    Post,
    "/v1/portal/operator/lease-reviews",
    operator,
    @portal.LeaseReview::{
      request_id: "request-a",
      expected_generation: request.generation,
      decision: Approve,
      node_id: Some("node-a"),
      evidence_receipt: "operator:approved:a",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(approved.status, 200)
  let final_request : @portal.EnterpriseLeaseRequest = @json.from_json(
    @json.parse(approved.body),
  )
  assert_eq(final_request.state, Approved)
  assert_eq(final_request.assigned_node_id, Some("node-a"))
  assert_eq(exclusive_store.leases().length(), 1)
  assert_eq(exclusive_store.leases()[0].state, Reserved)
  assert_false(approved.body.contains("runtime-secret"))
  assert_false(approved.body.contains("password"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "enterprise portal denies cross-tenant and non-signer actions" {
  let directory = @fs.tmpdir(prefix="lunanexa-portal-deny-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let portal_store = @portal_store.FilePortalStore::open(
    "\{directory}/portal.json",
  )
  let service = @api.ApiService::new(
    @store.FileStore::open("\{directory}/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  ).with_portal_store(portal_store)
  let operator = { "Authorization": "Bearer operator-token" }
  let now = @async.now()
  ignore(
    service.handle(
      Post,
      "/v1/portal/operator/memberships",
      operator,
      @portal.EnterpriseMembership::{
        membership_id: "member-observer",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "subject-observer",
        roles: [BillingViewer],
        active: true,
        created_unix_ms: now,
      }
      .to_json()
      .stringify(),
    ),
  )
  ignore(
    service.handle(
      Post,
      "/v1/portal/operator/agreements",
      operator,
      @portal.PortalAgreement::{
        agreement_id: "agreement-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        template_ref: "framework-v1",
        title: "Framework agreement",
        summary: "Required for exclusive capacity.",
        rendered_document_hash: "sha256:document",
        state: ReviewRequired,
        generation: 1L,
        signer_subject_ref: None,
        signature_request_receipt: None,
        executed_artifact_hash: None,
        created_unix_ms: now,
        updated_unix_ms: now,
      }
      .to_json()
      .stringify(),
    ),
  )
  let observer = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-observer",
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/signature-requests",
      observer,
      @portal.SignatureRequest::{
        agreement_id: "agreement-a",
        expected_generation: 1L,
        idempotency_key: "sign-denied",
      }
      .to_json()
      .stringify(),
    ).status,
    403,
  )
  assert_eq(
    service.handle(
      Get,
      "/v1/portal/self",
      { "Authorization": "Bearer inference-token" },
      "",
    ).status,
    401,
  )
  @fs.rmdir(directory, recursive=true)
}
