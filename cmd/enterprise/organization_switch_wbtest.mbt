///|
test "accepting another company's invitation selects that company and fences the previous scope" {
  let base = gateway_auth_test_model()
  let portal = @enterprise_ui.demo_state()
  let first = portal.organizations[0]
  let second = {
    ..first,
    organization: { ..first.organization, organization_id: "joined-company", },
    membership: {
      ..first.membership,
      organization_id: "joined-company",
      tenant_ref: "joined-tenant",
    },
    default_project_id: Some("joined-project"),
  }
  let model = { ..base, token: "lnxs_fixture", portal, }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (joined, _) = update(
    model,
    Outcome(OrganizationJoined("joined-company")),
    emit,
  )
  assert_eq(joined.portal.selected_organization_id, Some("joined-company"))
  assert_true(joined.session_generation > model.session_generation)
  assert_true(joined.portal.api_keys.is_empty())
  assert_eq(joined.portal.membership, None)
  let (late, _) = update(
    joined,
    scoped_outcome(model, Failed(English, "old request failed")),
    emit,
  )
  assert_true(late == joined)
  let (loaded, _) = update(
    joined,
    Outcome(
      OrganizationsLoaded(
        joined.session_generation,
        [first, second],
        Some("joined-company"),
        portal.account,
      ),
    ),
    emit,
  )
  assert_eq(loaded.portal.selected_organization_id, Some("joined-company"))
  assert_eq(loaded.portal.project_id, "joined-project")
  assert_eq(
    loaded.portal.membership.map(value => value.tenant_ref),
    Some("joined-tenant"),
  )
}

///|
test "new company and removed membership discard previous scoped data before loading" {
  let base = gateway_auth_test_model()
  let portal = @enterprise_ui.demo_state()
  let original = portal.organizations[0]
  let created = {
    ..original,
    organization: {
      ..original.organization,
      organization_id: "new-company",
      state: PendingVerification,
    },
    membership: {
      ..original.membership,
      organization_id: "new-company",
      tenant_ref: "new-tenant",
    },
  }
  let model = { ..base, token: "lnxs_fixture", portal, }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (pending, _) = update(model, Outcome(OrganizationCreated(created)), emit)
  assert_true(pending.portal.api_keys.is_empty())
  assert_true(pending.portal.agreements.is_empty())
  assert_eq(pending.portal.selected_organization_id, Some("new-company"))
  assert_true(pending.session_generation > model.session_generation)
  assert_true(waiting_for_application(pending) == false)
  let (removed, _) = update(
    model,
    Outcome(
      OrganizationsLoaded(model.session_generation, [], None, portal.account),
    ),
    emit,
  )
  assert_eq(removed.portal.membership, None)
  assert_true(removed.portal.api_keys.is_empty())
  assert_true(removed.portal.cost_centers.is_empty())
  assert_true(removed.portal.self_service.order is None)
  assert_true(removed.portal.self_service.quote is None)
}
