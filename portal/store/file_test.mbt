///|
async test "signature and lease approval survive restart" {
  let directory = @fs.tmpdir(prefix="lunanexa-portal-store-")
  let path = "\{directory}/portal.json"
  let store = @store.FilePortalStore::open(path)
  ignore(
    store.put_membership({
      membership_id: "member-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [LegalSigner, LeaseRequester],
      active: true,
      created_unix_ms: 1000L,
    }),
  )
  ignore(
    store.publish_agreement({
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
      created_unix_ms: 1000L,
      updated_unix_ms: 1000L,
    }),
  )
  let requested = store.request_signature(
    "subject-a",
    {
      agreement_id: "agreement-a",
      expected_generation: 1L,
      idempotency_key: "sign-a",
    },
    1100L,
  )
  ignore(
    store.record_execution(
      {
        agreement_id: "agreement-a",
        expected_generation: requested.generation,
        signer_subject_ref: "subject-a",
        executed_artifact_hash: "sha256:executed",
        evidence_receipt: "provider:verified:a",
      },
      1200L,
    ),
  )
  let submitted = store.submit_lease_request(
    "subject-a",
    {
      request_id: "request-a",
      idempotency_key: "submit-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      unix_username: "alice",
      starts_unix_ms: 2000L,
      expires_unix_ms: 3000L,
      requested_model_ids: ["model-a"],
      justification: "Evaluation work",
    },
    1300L,
  )
  ignore(
    store.review_lease_request(
      {
        request_id: "request-a",
        expected_generation: submitted.generation,
        decision: Approve,
        node_id: Some("spark-01"),
        evidence_receipt: "operator:approved:a",
      },
      Some("exclusive-request-a"),
      1400L,
    ),
  )
  let reopened = @store.FilePortalStore::open(path)
  let view = reopened.self_view("subject-a")
  assert_eq(view.agreements[0].state, Executed)
  assert_eq(view.lease_requests[0].state, Approved)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "lease idempotency is tenant scoped and conflicting replay is isolated" {
  let directory = @fs.tmpdir(prefix="lunanexa-portal-scope-")
  let store = @store.FilePortalStore::open("\{directory}/portal.json")
  for
    membership in [
      @portal.EnterpriseMembership::{
        membership_id: "member-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "subject-a",
        roles: [LegalSigner, LeaseRequester],
        active: true,
        created_unix_ms: 1000L,
      },
      {
        membership_id: "member-b",
        tenant_ref: "tenant-b",
        organization_id: "org-b",
        subject_ref: "subject-b",
        roles: [LegalSigner, LeaseRequester],
        active: true,
        created_unix_ms: 1000L,
      },
    ] {
    ignore(store.put_membership(membership))
  }
  for
    agreement in [
      @portal.PortalAgreement::{
        agreement_id: "agreement-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        template_ref: "framework-v1",
        title: "Tenant A agreement",
        summary: "Required for tenant A.",
        rendered_document_hash: "sha256:document-a",
        state: ReviewRequired,
        generation: 1L,
        signer_subject_ref: None,
        signature_request_receipt: None,
        executed_artifact_hash: None,
        created_unix_ms: 1000L,
        updated_unix_ms: 1000L,
      },
      {
        agreement_id: "agreement-b",
        tenant_ref: "tenant-b",
        organization_id: "org-b",
        template_ref: "framework-v1",
        title: "Tenant B agreement",
        summary: "Required for tenant B.",
        rendered_document_hash: "sha256:document-b",
        state: ReviewRequired,
        generation: 1L,
        signer_subject_ref: None,
        signature_request_receipt: None,
        executed_artifact_hash: None,
        created_unix_ms: 1000L,
        updated_unix_ms: 1000L,
      },
    ] {
    ignore(store.publish_agreement(agreement))
  }
  let requested_a = store.request_signature(
    "subject-a",
    {
      agreement_id: "agreement-a",
      expected_generation: 1L,
      idempotency_key: "signature-a",
    },
    1100L,
  )
  let requested_b = store.request_signature(
    "subject-b",
    {
      agreement_id: "agreement-b",
      expected_generation: 1L,
      idempotency_key: "signature-b",
    },
    1100L,
  )
  ignore(
    store.record_execution(
      {
        agreement_id: "agreement-a",
        expected_generation: requested_a.generation,
        signer_subject_ref: "subject-a",
        executed_artifact_hash: "sha256:executed-a",
        evidence_receipt: "provider:verified:a",
      },
      1200L,
    ),
  )
  ignore(
    store.record_execution(
      {
        agreement_id: "agreement-b",
        expected_generation: requested_b.generation,
        signer_subject_ref: "subject-b",
        executed_artifact_hash: "sha256:executed-b",
        evidence_receipt: "provider:verified:b",
      },
      1200L,
    ),
  )
  let submission_a : @portal.LeaseRequestSubmission = {
    request_id: "request-a",
    idempotency_key: "shared-retry-key",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    unix_username: "alice",
    starts_unix_ms: 2000L,
    expires_unix_ms: 3000L,
    requested_model_ids: ["model-a"],
    justification: "Tenant A evaluation",
  }
  let first = store.submit_lease_request("subject-a", submission_a, 1300L)
  let replay = store.submit_lease_request("subject-a", submission_a, 1301L)
  assert_eq(replay, first)
  let second = store.submit_lease_request(
    "subject-b",
    {
      request_id: "request-b",
      idempotency_key: "shared-retry-key",
      tenant_ref: "tenant-b",
      organization_id: "org-b",
      project_id: "project-b",
      unix_username: "bob",
      starts_unix_ms: 2000L,
      expires_unix_ms: 3000L,
      requested_model_ids: ["model-b"],
      justification: "Tenant B evaluation",
    },
    1300L,
  )
  assert_eq(second.subject_ref, "subject-b")
  try
    store.submit_lease_request(
      "subject-a",
      { ..submission_a, request_id: "request-conflict" },
      1302L,
    )
  catch {
    @portal.PortalError::IdempotencyConflict(_) => ()
    error => fail("unexpected replay error: \{Repr(error)}")
  } noraise {
    _ => fail("same-scope idempotency mutation was accepted")
  }
  assert_eq(store.snapshot().lease_requests.length(), 2)
  let reopened = @store.FilePortalStore::open("\{directory}/portal.json")
  assert_eq(reopened.snapshot().lease_requests.length(), 2)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "corrupted portal snapshot cannot forge a second active identity" {
  let directory = @fs.tmpdir(prefix="lunanexa-portal-corrupt-")
  let path = "\{directory}/portal.json"
  let snapshot : @portal.PortalSnapshot = {
    schema_version: @portal.snapshot_schema_version,
    memberships: [
      {
        membership_id: "member-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "subject-collision",
        roles: [LeaseRequester],
        active: true,
        created_unix_ms: 1000L,
      },
      {
        membership_id: "member-b",
        tenant_ref: "tenant-b",
        organization_id: "org-b",
        subject_ref: "subject-collision",
        roles: [LeaseRequester],
        active: true,
        created_unix_ms: 1000L,
      },
    ],
    agreements: [],
    lease_requests: [],
  }
  @fs.write_file(
    path,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  try @store.FilePortalStore::open(path) catch {
    @portal.PortalError::InvalidInput(_) => ()
    error => fail("unexpected snapshot error: \{Repr(error)}")
  } noraise {
    _ => fail("duplicate active subject was restored")
  }
  @fs.rmdir(directory, recursive=true)
}
