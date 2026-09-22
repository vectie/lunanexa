///|
/// The organization and tenant the operator types are free text, and the
/// customer's session resolves its tenant from its existing membership. A
/// package opened on a different tenant is invisible to that customer, so the
/// console has to show the tenants the subject already holds.
test "the guided setup names the tenants the subject already holds" {
  let issuer = "https://id.example"
  let subject = "abc"
  let subject_ref = @identity.subject_reference(issuer, subject)
  let html = render({
    ..default_state(),
    route: Users,
    accounts: [
      {
        account_id: @identity.account_identifier(issuer, subject),
        subject_ref,
        identity_issuer: issuer,
        display_name: "Ari Chen",
        email: "ari@example.test",
        identity_receipt: "oidc-registration",
        roles: [EnterpriseUser],
        state: Active,
        created_unix_ms: 0L,
        updated_unix_ms: 0L,
      },
    ],
    compute_leases: [
      {
        lease_id: "trial-lease-1",
        user_id: "trial-user-1",
        subject_ref,
        workspace: "trial-tenant-1",
        resource: "Text generation · 1 concurrent",
        started_at: "2026-09-22 10:00 UTC",
        expires_at: "2026-09-23 10:00 UTC",
        state: Active,
      },
      {
        lease_id: "trial-lease-2",
        user_id: "trial-user-1",
        subject_ref,
        workspace: "trial-tenant-1",
        resource: "Text generation · 1 concurrent",
        started_at: "2026-09-22 10:00 UTC",
        expires_at: "2026-09-23 10:00 UTC",
        state: Active,
      },
      {
        lease_id: "other-lease",
        user_id: "other-user",
        subject_ref: "subject-someone-else",
        workspace: "someone-elses-tenant",
        resource: "Text generation · 1 concurrent",
        started_at: "2026-09-22 10:00 UTC",
        expires_at: "2026-09-23 10:00 UTC",
        state: Active,
      },
    ],
    access_package_draft: {
      identity_issuer: issuer,
      identity_subject: subject,
      display_name: "",
      email: "",
      organization_id: "",
      tenant_ref: "",
      lifetime_days: 30,
      identity_verified: false,
    },
  })
  assert_true(html.contains("access-existing-authority"))
  assert_true(html.contains("Ari Chen"))
  assert_true(html.contains("ari@example.test"))
  assert_true(html.contains("trial-tenant-1"))
  assert_true(html.contains("will not be visible to them"))
  // The duplicate lease is folded away, and another subject's tenant is not
  // attributed to this one.
  assert_false(html.contains("trial-tenant-1, trial-tenant-1"))
  assert_false(html.contains("someone-elses-tenant"))
}

///|
test "an unknown subject says the package will create the organization and tenant" {
  let html = render({
    ..default_state(),
    route: Users,
    access_package_draft: {
      identity_issuer: "https://id.example",
      identity_subject: "nobody-here",
      display_name: "",
      email: "",
      organization_id: "",
      tenant_ref: "",
      lifetime_days: 30,
      identity_verified: false,
    },
  })
  assert_true(html.contains("holds no account or workspace lease"))
  assert_false(html.contains("already exists"))
}

///|
/// Before the subject is known there is nothing to look up, so the hint points
/// at the fields it depends on instead of claiming the subject is unknown.
test "the tenant hint stays neutral until the subject is filled in" {
  let html = render({ ..default_state(), route: Users, })
  assert_true(html.contains("Fill in Identity provider details first"))
  assert_false(html.contains("holds no account or workspace lease"))
  assert_false(html.contains("already exists"))
}
