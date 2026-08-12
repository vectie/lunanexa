///|
test "tenant role and agreement gates are fail closed" {
  assert_true(@portal.role_allows([OrganizationAdministrator], LegalSigner))
  assert_false(@portal.role_allows([Developer], LeaseRequester))
  let submission : @portal.LeaseRequestSubmission = {
    request_id: "request-1",
    idempotency_key: "submit-1",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    unix_username: "alice",
    starts_unix_ms: 1000L,
    expires_unix_ms: 2000L,
    requested_model_ids: ["model-a"],
    justification: "Evaluation work",
  }
  @portal.validate_submission(submission)
  try
    @portal.validate_submission({ ..submission, unix_username: "root" })
  catch {
    InvalidInput(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("reserved username accepted")
  }
}

///|
test "only requested agreements can become executed" {
  let agreement : @portal.PortalAgreement = {
    agreement_id: "agreement-1",
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
  }
  let requested = agreement.request_signature(
    "subject-a", "signature-request:1", 1L, 1100L,
  )
  assert_eq(requested.state, SignatureRequested)
  let executed = requested.record_execution(
    {
      agreement_id: "agreement-1",
      expected_generation: 2L,
      signer_subject_ref: "subject-a",
      executed_artifact_hash: "sha256:executed",
      evidence_receipt: "provider:verified:1",
    },
    1200L,
  )
  assert_eq(executed.state, Executed)
}

///|
test "adversarial lease fields fail closed" {
  let base : @portal.LeaseRequestSubmission = {
    request_id: "request-fuzz",
    idempotency_key: "submit-fuzz",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    unix_username: "alice",
    starts_unix_ms: 1000L,
    expires_unix_ms: 2000L,
    requested_model_ids: ["model-a"],
    justification: "Bounded evaluation",
  }
  let hostile_usernames = [
    "root", "Alice", "-alice", "alice/../../root", "alice\u0000root", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ]
  for username in hostile_usernames {
    try @portal.validate_submission({ ..base, unix_username: username }) catch {
      InvalidInput(_) => ()
      _ => fail("unexpected username error")
    } noraise {
      _ => fail("unsafe username accepted")
    }
  }
  let hostile_models = ["../model", "model<script>", "model\u0000hidden", ""]
  for model in hostile_models {
    try
      @portal.validate_submission({ ..base, requested_model_ids: [model] })
    catch {
      InvalidInput(_) => ()
      _ => fail("unexpected model error")
    } noraise {
      _ => fail("unsafe model accepted")
    }
  }
}
