///|
test "refreshing the same company repairs a missing or foreign trial billing project" {
  let base = demo_state()
  let organization = base.organizations[0]
  let expected = organization.default_project_id.unwrap()
  let trial : TrialEntitlementView = {
    trial_id: "old-trial",
    organization_id: "old-trial-org",
    tenant_ref: "old-trial-tenant",
    project_id: "old-trial-project",
    allowed_models: ["text.old"],
    maximum_requests: 100L,
    starts_unix_ms: 1L,
    expires_unix_ms: 2L,
    api_key_id: None,
    revoked_unix_ms: None,
  }
  for project in ["", "old-trial-project", "company-custom-project"] {
    let state = {
      ..base,
      membership: Some(organization.membership),
      project_id: project,
      trial: Some(trial),
    }
    let refreshed = state.update(
      SelfService(SelectOrganization(organization.organization.organization_id)),
    )
    assert_eq(
      refreshed.project_id,
      if project == "company-custom-project" {
        project
      } else {
        expected
      },
    )
    assert_eq(
      refreshed.membership.unwrap().organization_id,
      organization.organization.organization_id,
    )
  }
}
