///|
test "organization form derives its display name but preserves a custom choice" {
  let base = default_state(1000L)
  let first = base.update(SelfService(LegalNameChanged("Example company")))
  assert_eq(first.self_service.display_name, "Example company")
  let renamed = first.update(SelfService(LegalNameChanged("Renamed company")))
  assert_eq(renamed.self_service.display_name, "Renamed company")
  let custom = first
    .update(SelfService(CompanyDisplayNameChanged("Short name")))
    .update(SelfService(LegalNameChanged("Legal name")))
  assert_eq(custom.self_service.display_name, "Short name")
}

///|
test "organization refresh carries the approved project to the order form" {
  let base = demo_state()
  let selected = base.organizations[0]
  let state = {
    ..base,
    membership: Some(selected.membership),
    project_id: "",
    self_service: { ..base.self_service, project_id: "", },
  }.update(
    SelfService(SelectOrganization(selected.organization.organization_id)),
  )
  assert_eq(state.project_id, selected.default_project_id.unwrap())
  assert_eq(state.self_service.project_id, state.project_id)
}

///|
test "approved requests link to applications and pending requests explain their next step" {
  let base = demo_state()
  let request = base.lease_requests[0]
  let approved = {
    ..base,
    route: LeaseRequests,
    lease_requests: [{ ..request, state: Approved, }],
  }
  let html = render(approved)
  assert_true(html.contains("Open applications"))
  assert_true(html.contains("<select id=\"lease-models\""))
  assert_false(html.contains("<h3>" + request.submission.request_id + "</h3>"))
  let pending = render({
    ..approved,
    lease_requests: [{ ..request, state: Submitted, }],
  })
  assert_true(pending.contains("Status updates automatically"))
}

///|
test "expired trial gives an actionable company access path while preserving its expiry" {
  let base = demo_state()
  let membership = base.membership.unwrap()
  let trial : TrialEntitlementView = {
    trial_id: "expired",
    organization_id: membership.organization_id,
    tenant_ref: membership.tenant_ref,
    project_id: base.project_id,
    allowed_models: ["text.qwen"],
    maximum_requests: 0L,
    starts_unix_ms: 1L,
    expires_unix_ms: 100L,
    api_key_id: None,
    revoked_unix_ms: None,
    consumed_requests: None,
    max_output_tokens: None,
  }
  let state = { ..base, route: Overview, trial: Some(trial), }
  assert_true(render(state).contains("Request company access"))
  let requested = state.update(SelfService(SelectProduct(SharedMaaS)))
  assert_eq(requested.route, SelfService)
  assert_eq(requested.self_service.step, Organization)
  assert_eq(requested.self_service.organization_mode, JoinCompany)
  assert_false(render(requested).contains("aria-label=\"Order progress\""))
  assert_eq(requested.trial, Some(trial))
}

///|
test "approved organization can enter an already authorized application directly" {
  let base = demo_state()
  let state = {
    ..base,
    route: SelfService,
    self_service: {
      ..base.self_service,
      selected_product: Some(SharedMaaS),
      step: Organization,
    },
  }
  assert_true(render(state).contains("Open applications"))
  let pending = {
    ..state,
    organizations: state.organizations.map(value => {
      ..value,
      organization: { ..value.organization, state: PendingVerification, },
    }),
  }
  assert_false(render(pending).contains("Open applications"))
}
