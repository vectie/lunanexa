///|
async test "completed portal machine lease is metered and rated exactly once" {
  let directory = @fs.tmpdir(prefix="lunanexa-machine-metering-")
  let now = @async.now()
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  ignore(
    portal.put_membership({
      membership_id: "membership-meter",
      tenant_ref: "tenant-meter",
      organization_id: "org-meter",
      subject_ref: "subject-meter",
      roles: [LeaseRequester, LegalSigner],
      active: true,
      created_unix_ms: now - 10000L,
    }),
  )
  ignore(
    portal.publish_agreement({
      agreement_id: "agreement-meter",
      tenant_ref: "tenant-meter",
      organization_id: "org-meter",
      template_ref: "master-lease-v1",
      title: "Machine lease",
      summary: "Metered test agreement",
      rendered_document_hash: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      state: ReviewRequired,
      generation: 1L,
      signer_subject_ref: None,
      signature_request_receipt: None,
      executed_artifact_hash: None,
      created_unix_ms: now - 10000L,
      updated_unix_ms: now - 10000L,
    }),
  )
  let signature_requested = portal.request_signature(
    "subject-meter",
    {
      agreement_id: "agreement-meter",
      expected_generation: 1L,
      idempotency_key: "signature-request-meter",
    },
    now - 9000L,
  )
  ignore(
    portal.record_execution(
      {
        agreement_id: "agreement-meter",
        expected_generation: signature_requested.generation,
        signer_subject_ref: "subject-meter",
        executed_artifact_hash: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        evidence_receipt: "execution-meter",
      },
      now - 8500L,
    ),
  )
  let submission : @portal.LeaseRequestSubmission = {
    request_id: "request-meter",
    idempotency_key: "request-meter-once",
    tenant_ref: "tenant-meter",
    organization_id: "org-meter",
    project_id: "project-meter",
    unix_username: "meter_user",
    starts_unix_ms: now - 5000L,
    expires_unix_ms: now + 60000L,
    requested_model_ids: ["model-meter"],
    justification: "Verify automatic machine billing",
  }
  ignore(portal.submit_lease_request("subject-meter", submission, now - 8000L))
  let leases = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/leases.json",
    "lease-signing-secret-more-than-thirty-two-bytes",
  )
  let lease_intent : @nodelease.ExclusiveNodeLeaseIntent = {
    version: @nodelease.contract_version,
    idempotency_key: "lease-meter-once",
    lease_id: "lease-meter",
    node_id: "node-meter",
    subject_ref: "subject-meter",
    unix_username: "meter_user",
    access_credential_ref: "ssh-cert:lease-meter",
    starts_unix_ms: submission.starts_unix_ms,
    expires_unix_ms: submission.expires_unix_ms,
  }
  let reserved = leases.issue(lease_intent, now - 7000L)
  ignore(
    portal.review_lease_request(
      {
        request_id: submission.request_id,
        expected_generation: 1L,
        decision: Approve,
        node_id: Some("node-meter"),
        evidence_receipt: "approval-meter",
      },
      Some(lease_intent.lease_id),
      now - 6000L,
    ),
  )
  let provisioning = leases.transition(
    lease_intent.lease_id,
    {
      expected_generation: reserved.generation,
      state: Provisioning,
      evidence_receipt: "provision-meter",
    },
    now - 4900L,
  )
  let active = leases.transition(
    lease_intent.lease_id,
    {
      expected_generation: provisioning.generation,
      state: Active,
      evidence_receipt: "active-meter",
    },
    now - 4800L,
  )
  let draining = leases.transition(
    lease_intent.lease_id,
    {
      expected_generation: active.generation,
      state: Draining,
      evidence_receipt: "drain-meter",
    },
    now - 100L,
  )
  let revoking = leases.transition(
    lease_intent.lease_id,
    {
      expected_generation: draining.generation,
      state: RevokingAccess,
      evidence_receipt: "revoke-meter",
    },
    now - 90L,
  )
  let sanitizing = leases.transition(
    lease_intent.lease_id,
    {
      expected_generation: revoking.generation,
      state: Sanitizing,
      evidence_receipt: "sanitize-meter",
    },
    now - 80L,
  )
  let completed = leases.transition(
    lease_intent.lease_id,
    {
      expected_generation: sanitizing.generation,
      state: Completed,
      evidence_receipt: "completed-meter",
    },
    now,
  )
  let durable = @store.FileStore::open("\{directory}/state.json")
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
    .with_exclusive_lease_store(leases)
    .with_exclusive_lease_unit_price(@commercial.money(3L, "CNY", 2))
  service.commercial_store.add_organization({
    organization_id: "org-meter",
    display_name: "Meter Org",
    state: Active,
    verification_ref: Some("verified-meter"),
    legal_profile: None,
    created_unix_ms: now - 12000L,
  })
  service.commercial_store.add_cost_center({
    cost_center_id: "cc-meter",
    organization_id: "org-meter",
    parent_cost_center_id: None,
    display_name: "Machine cost center",
    created_unix_ms: now - 12000L,
  })
  service.commercial_store.add_project({
    project_id: "project-meter",
    organization_id: "org-meter",
    cost_center_id: "cc-meter",
    display_name: "Machine project",
    created_unix_ms: now - 12000L,
  })
  assert_true(service.meter_completed_exclusive_lease(completed))
  assert_true(service.meter_completed_exclusive_lease(completed))
  let snapshot = service.commercial_store.snapshot("org-meter")
  assert_eq(snapshot.usage_observations.length(), 1)
  assert_eq(snapshot.ledger_entries.length(), 1)
  assert_eq(snapshot.usage_observations[0].quantity, 5L)
  assert_eq(snapshot.ledger_entries[0].amount.minor_units, 15L)
  @fs.rmdir(directory, recursive=true)
}
