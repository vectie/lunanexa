///|
test "changing company clears old scoped projections but same-company refresh keeps drafts" {
  let base = demo_state()
  let first = base.organizations[0]
  let second = {
    ..first,
    organization: {
      ..first.organization,
      organization_id: "other-company",
      display_name: "Other company",
    },
    membership: {
      ..first.membership,
      organization_id: "other-company",
      tenant_ref: "other-tenant",
    },
    default_project_id: Some("other-project"),
  }
  let state = { ..base, organizations: [first, second], }
  let refreshed = state.update(
    SelfService(SelectOrganization(first.organization.organization_id)),
  )
  assert_eq(refreshed.api_keys, state.api_keys)
  assert_eq(refreshed.self_service.order, state.self_service.order)
  let changed = state.update(SelfService(SelectOrganization("other-company")))
  assert_eq(changed.project_id, "other-project")
  assert_true(changed.api_keys.is_empty())
  assert_true(changed.agreements.is_empty())
  assert_true(changed.cost_centers.is_empty())
  assert_true(changed.model_catalog.is_empty())
  assert_true(changed.provider_requests.is_empty())
  assert_true(changed.lease_requests.is_empty())
  assert_true(changed.desktop_clients.is_empty())
  assert_true(changed.deliveries.operations.is_empty())
  assert_false(changed.api_key_issue_open)
  assert_eq(changed.account, state.account)
  assert_eq(
    changed.machine_access.now_unix_ms,
    state.machine_access.now_unix_ms,
  )
  let invalid = state.update(
    SelfService(SelectOrganization("not-a-membership")),
  )
  assert_true(invalid.api_keys.is_empty())
  assert_true(invalid.machine_access.machines.is_empty())
  assert_eq(invalid.membership, None)
}

///|
test "existing companies are chosen before creating another and rejected companies do not imply pending review" {
  let base = demo_state()
  let state = {
    ..base,
    route: SelfService,
    membership: None,
    selected_organization_id: None,
    self_service: { ..base.self_service, step: Organization, },
  }
  let html = render(state)
  assert_true(html.contains("onboarding-organization"))
  assert_true(html.contains("Choose a company"))
  let rejected = {
    ..base,
    route: SelfService,
    self_service: { ..base.self_service, step: Organization, },
    organizations: base.organizations.map(value => {
      ..value,
      organization: { ..value.organization, state: Rejected, },
    }),
  }
  let notice = render(rejected)
  assert_true(notice.contains("Company unavailable"))
  assert_false(notice.contains("Status updates automatically"))
}
