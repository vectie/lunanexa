///|
async test "PostgreSQL portal registration and agreement survive restart" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) &&
    url.trim() != "" else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let store = @store.FilePortalStore::open_postgres(database)
  ignore(
    store.put_membership({
      membership_id: "member-postgres",
      tenant_ref: "tenant-postgres",
      organization_id: "org-postgres",
      subject_ref: "subject-postgres",
      roles: [LegalSigner, LeaseRequester],
      active: true,
      created_unix_ms: 1000L,
    }),
  )
  ignore(
    store.publish_agreement({
      agreement_id: "agreement-postgres",
      tenant_ref: "tenant-postgres",
      organization_id: "org-postgres",
      template_ref: "framework-v1",
      title: "Agreement'; DROP TABLE portal_agreements; --",
      summary: "Required for database acceptance.",
      rendered_document_hash: "document-postgres",
      state: ReviewRequired,
      generation: 1L,
      signer_subject_ref: None,
      signature_request_receipt: None,
      executed_artifact_hash: None,
      created_unix_ms: 1000L,
      updated_unix_ms: 1000L,
    }),
  )
  assert_eq(database.projection_count("enterprise_memberships"), 1L)
  assert_eq(database.projection_count("portal_agreements"), 1L)
  let reopened_database = @database.PostgresDatabase::open(url)
  let reopened = @store.FilePortalStore::open_postgres(reopened_database)
  let view = reopened.self_view("subject-postgres")
  assert_eq(view.membership.organization_id, "org-postgres")
  assert_eq(view.agreements[0].state, ReviewRequired)
  assert_eq(
    view.agreements[0].title,
    "Agreement'; DROP TABLE portal_agreements; --",
  )
  assert_eq(database.projection_count("portal_agreements"), 1L)
  try
    database.projection_count("portal_agreements; DROP SCHEMA lunanexa")
  catch {
    QueryFailed(_) => ()
    error => fail("unexpected allowlist error: \{Repr(error)}")
  } noraise {
    _ => fail("projection table SQL injection was accepted")
  }
  try
    database.save_opaque_snapshot(
      "enterprise_portal; DROP SCHEMA lunanexa", @portal.snapshot_schema_version,
      "{}",
    )
  catch {
    @database.DatabaseError::UnsupportedSnapshot(_) => ()
    error => fail("unexpected snapshot-domain error: \{Repr(error)}")
  } noraise {
    _ => fail("snapshot domain injection was accepted")
  }
  ignore(
    store.put_membership({
      membership_id: "member-postgres-b",
      tenant_ref: "tenant-postgres-b",
      organization_id: "org-postgres-b",
      subject_ref: "subject-postgres-b",
      roles: [LegalSigner, LeaseRequester],
      active: true,
      created_unix_ms: 1000L,
    }),
  )
  ignore(
    store.publish_agreement({
      agreement_id: "agreement-postgres-b",
      tenant_ref: "tenant-postgres-b",
      organization_id: "org-postgres-b",
      template_ref: "framework-v1",
      title: "Tenant B agreement",
      summary: "Required for tenant B.",
      rendered_document_hash: "document-postgres-b",
      state: ReviewRequired,
      generation: 1L,
      signer_subject_ref: None,
      signature_request_receipt: None,
      executed_artifact_hash: None,
      created_unix_ms: 1000L,
      updated_unix_ms: 1000L,
    }),
  )
  let requested_a = store.request_signature(
    "subject-postgres",
    {
      agreement_id: "agreement-postgres",
      expected_generation: 1L,
      idempotency_key: "sign-postgres-a",
    },
    1100L,
  )
  let requested_b = store.request_signature(
    "subject-postgres-b",
    {
      agreement_id: "agreement-postgres-b",
      expected_generation: 1L,
      idempotency_key: "sign-postgres-b",
    },
    1100L,
  )
  ignore(
    store.record_execution(
      {
        agreement_id: "agreement-postgres",
        expected_generation: requested_a.generation,
        signer_subject_ref: "subject-postgres",
        executed_artifact_hash: "executed-postgres-a",
        evidence_receipt: "provider:verified:postgres-a",
      },
      1200L,
    ),
  )
  ignore(
    store.record_execution(
      {
        agreement_id: "agreement-postgres-b",
        expected_generation: requested_b.generation,
        signer_subject_ref: "subject-postgres-b",
        executed_artifact_hash: "executed-postgres-b",
        evidence_receipt: "provider:verified:postgres-b",
      },
      1200L,
    ),
  )
  let submission_a : @portal.LeaseRequestSubmission = {
    request_id: "request-postgres-a",
    idempotency_key: "shared-postgres-key",
    tenant_ref: "tenant-postgres",
    organization_id: "org-postgres",
    project_id: "project-postgres-a",
    unix_username: "alice",
    starts_unix_ms: 2000L,
    expires_unix_ms: 3000L,
    requested_model_ids: ["model-a"],
    justification: "Tenant A database test",
  }
  ignore(store.submit_lease_request("subject-postgres", submission_a, 1300L))
  ignore(
    store.submit_lease_request(
      "subject-postgres-b",
      {
        request_id: "request-postgres-b",
        idempotency_key: "shared-postgres-key",
        tenant_ref: "tenant-postgres-b",
        organization_id: "org-postgres-b",
        project_id: "project-postgres-b",
        unix_username: "bob",
        starts_unix_ms: 2000L,
        expires_unix_ms: 3000L,
        requested_model_ids: ["model-b"],
        justification: "Tenant B database test",
      },
      1300L,
    ),
  )
  assert_eq(database.projection_count("portal_lease_requests"), 2L)
  ignore(
    store.put_membership({
      membership_id: "member-postgres-second-org",
      tenant_ref: "tenant-postgres-second-org",
      organization_id: "org-postgres-second-org",
      subject_ref: "subject-postgres",
      roles: [Developer],
      active: true,
      created_unix_ms: 1400L,
    }),
  )
  assert_eq(database.projection_count("enterprise_memberships"), 3L)
  assert_eq(
    store.self_view_for_organization(
      "subject-postgres", "org-postgres-second-org",
    ).membership.tenant_ref,
    "tenant-postgres-second-org",
  )
  let before_invalid = store.snapshot()
  let duplicate_memberships = before_invalid.memberships.copy()
  duplicate_memberships.push({
    membership_id: "member-postgres-forged",
    tenant_ref: "tenant-postgres",
    organization_id: "org-postgres",
    subject_ref: "subject-postgres",
    roles: [LeaseRequester],
    active: true,
    created_unix_ms: 1000L,
  })
  try
    database.save_portal_snapshot({
      ..before_invalid,
      memberships: duplicate_memberships,
    })
  catch {
    @database.DatabaseError::QueryFailed(_) => ()
    error => fail("unexpected rollback error: \{Repr(error)}")
  } noraise {
    _ => fail("duplicate active subject snapshot was committed")
  }
  assert_eq(database.projection_count("enterprise_memberships"), 3L)
  assert_eq(database.projection_count("portal_lease_requests"), 2L)
  reopened_database.close()
  database.close()
}
