///|
test "registered identity fills contact fields before any organization exists without inventing legal identity" {
  let base = @enterprise_ui.demo_state()
  let account = base.account.unwrap()
  let blank = @enterprise_ui.default_state(1000L)
  let filled = onboarding_account_defaults(blank, Some(account))
  assert_eq(filled.account, Some(account))
  assert_eq(filled.self_service.billing_contact_name, account.display_name)
  assert_eq(filled.self_service.billing_email, account.email)
  assert_eq(filled.self_service.legal_name, "")
  assert_true(@portal.valid_unix_username(filled.unix_username))
  let edited = {
    ..filled,
    unix_username: "chosen_name",
    self_service: {
      ..filled.self_service,
      billing_contact_name: "Different billing contact",
      billing_email: "billing@example.invalid",
    },
  }
  assert_true(onboarding_account_defaults(edited, Some(account)) == edited)
  assert_true(onboarding_account_defaults(blank, None) == blank)
}

///|
test "organization-less bootstrap retains the registered account and rejects stale identity results" {
  let base = gateway_auth_test_model()
  let account = @enterprise_ui.demo_state().account.unwrap()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (filled, _) = update(
    base,
    Outcome(
      OrganizationsLoaded(base.session_generation, [], None, Some(account)),
    ),
    emit,
  )
  assert_eq(filled.portal.account, Some(account))
  assert_eq(filled.portal.self_service.billing_email, account.email)
  assert_eq(filled.portal.route, SelfService)
  let (stale, _) = update(
    base,
    Outcome(
      OrganizationsLoaded(base.session_generation - 1L, [], None, Some(account)),
    ),
    emit,
  )
  assert_true(stale == base)
}

///|
test "application infrastructure failure keeps the session and explains recovery" {
  let base = gateway_auth_test_model()
  let model = {
    ..base,
    token: "lnxs_test_session",
    portal: @enterprise_ui.demo_state(),
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (failed, _) = update(
    model,
    Outcome(
      ApplicationLaunchCompleted(
        model.session_generation,
        model.portal.selected_organization_id,
        None,
        Err("HTTP 503 internal-host session-secret"),
      ),
    ),
    emit,
  )
  assert_eq(failed.token, model.token)
  assert_true(
    failed.portal.error_message
    .unwrap()
    .contains("do not need to sign in again"),
  )
  assert_false(failed.portal.error_message.unwrap().contains("session-secret"))
}

///|
test "late onboarding and order responses cannot replace a new account or organization" {
  let base = gateway_auth_test_model()
  let account = @enterprise_ui.demo_state().account.unwrap()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let outcome = OrganizationsLoaded(
    base.session_generation,
    [],
    None,
    Some(account),
  )
  let current = {
    ..base,
    portal: { ..base.portal, selected_organization_id: Some("new-company"), },
  }
  let (other, _) = update(current, scoped_outcome(base, outcome), emit)
  assert_true(other == current)
  let replaced = { ..base, session_generation: base.session_generation + 1L, }
  let (stale, _) = update(replaced, scoped_outcome(base, outcome), emit)
  assert_true(stale == replaced)
}

///|
test "initial authenticated loading does not offer a new order before authority is known" {
  let base = gateway_auth_test_model()
  let model = { ..base, token: "lnxs_test", connecting: true, }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("Loading your account and applications"))
  assert_false(html.contains("Pay online"))
  assert_false(html.contains("Request managed"))
}

///|
test "a new account picks up approved membership without signing in again or losing its draft" {
  let base = gateway_auth_test_model()
  let model = {
    ..base,
    token: "lnxs_new_account",
    portal: {
      ..base.portal,
      route: SelfService,
      account: @enterprise_ui.demo_state().account,
      self_service: {
        ..base.portal.self_service,
        step: Organization,
        legal_name: "Keep draft",
      },
    },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (waiting, _) = start_rental_wait(model, emit)
  assert_true(waiting_for_membership(waiting))
  assert_true(rental_wait_active(waiting, waiting.contract_poll_generation, ""))
  let (unchanged, _) = apply_rental_wait(
    waiting,
    waiting.contract_poll_generation,
    "",
    -1,
    Ok(Company([])),
    emit,
  )
  assert_true(unchanged == waiting)
  let (found, _) = apply_rental_wait(
    waiting,
    waiting.contract_poll_generation,
    "",
    -1,
    Ok(Company(@enterprise_ui.demo_state().organizations)),
    emit,
  )
  assert_eq(found.portal.self_service.legal_name, "Keep draft")
  assert_eq(found.token, model.token)
}

///|
test "an expired trial discovers approved company access without extending or reusing the trial project" {
  let base = gateway_auth_test_model()
  let portal = @enterprise_ui.demo_state()
  let customer = portal.organizations[0]
  let trial : @enterprise_ui.TrialEntitlementView = {
    trial_id: "expired",
    organization_id: "trial-org",
    tenant_ref: "trial-tenant",
    project_id: "trial-project",
    allowed_models: ["text.qwen"],
    maximum_requests: 0L,
    starts_unix_ms: 1L,
    expires_unix_ms: 100L,
    api_key_id: None,
    revoked_unix_ms: None,
    consumed_requests: None,
    max_output_tokens: None,
  }
  let private_organization = {
    ..customer,
    organization: {
      ..customer.organization,
      organization_id: trial.organization_id,
    },
    membership: {
      ..customer.membership,
      organization_id: trial.organization_id,
      tenant_ref: trial.tenant_ref,
    },
    default_project_id: Some(trial.project_id),
  }
  let model = {
    ..base,
    token: "lnxs_expired_trial",
    portal: {
      ..portal,
      route: SelfService,
      trial: Some(trial),
      membership: Some(private_organization.membership),
      selected_organization_id: Some(trial.organization_id),
      organizations: [private_organization],
      project_id: trial.project_id,
      self_service: {
        ..portal.self_service,
        step: Organization,
        project_id: trial.project_id,
      },
    },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (waiting, _) = start_rental_wait(model, emit)
  assert_true(waiting_for_membership(waiting))
  let (approved, _) = apply_rental_wait(
    waiting,
    waiting.contract_poll_generation,
    trial.organization_id,
    -1,
    Ok(Company([private_organization, customer])),
    emit,
  )
  assert_eq(
    approved.portal.selected_organization_id,
    Some(customer.organization.organization_id),
  )
  assert_eq(approved.portal.trial, Some(trial))
  assert_eq(approved.portal.project_id, customer.default_project_id.unwrap())
  assert_eq(approved.portal.self_service.project_id, approved.portal.project_id)
  assert_eq(approved.token, model.token)
}

///|
test "membership approval continues checking applications until workspace activation is visible" {
  let base = gateway_auth_test_model()
  let portal = @enterprise_ui.demo_state()
  let model = {
    ..base,
    token: "lnxs_pending_workspace",
    portal: {
      ..portal,
      route: SelfService,
      desktop_clients: [],
      self_service: {
        ..portal.self_service,
        selected_product: Some(SharedMaaS),
        step: Organization,
      },
    },
  }
  assert_true(waiting_for_application(model))
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (waiting, _) = start_rental_wait(model, emit)
  let organization = waiting.portal.selected_organization_id.unwrap()
  let (unchanged, _) = apply_rental_wait(
    waiting,
    waiting.contract_poll_generation,
    organization,
    -1,
    Ok(Applications([])),
    emit,
  )
  assert_true(unchanged == waiting)
  let clients : Array[DesktopClientResponse] = @json.from_json(
    @json.parse(
      "[{\"client_id\":\"business\",\"display_name\":\"Business\",\"launch_uri\":\"https://example.invalid/user/business/bp/\",\"handoff_lifetime_ms\":\"120000\",\"contract_ready\":true,\"workspace_ready\":true,\"models_ready\":true,\"ready\":true,\"blocker_codes\":[],\"approved_model_aliases\":[\"text.test\"],\"handoffs\":[]}]",
    ),
  )
  let (refreshing, _) = apply_rental_wait(
    waiting,
    waiting.contract_poll_generation,
    organization,
    -1,
    Ok(Applications(clients)),
    emit,
  )
  assert_eq(refreshing.token, model.token)
  assert_true(refreshing.portal == model.portal)
  let available = {
    ..model,
    portal: { ..model.portal, desktop_clients: portal.desktop_clients, },
  }
  assert_false(waiting_for_application(available))
}

///|
test "approval polling retains drafts fences organization and session and detects an approved request" {
  let base = polling_fixture()
  let organization = base.portal.membership.unwrap().organization_id
  let submitted = { ..base.portal.lease_requests[0], state: Submitted, }
  let model = {
    ..base,
    portal: {
      ..base.portal,
      route: LeaseRequests,
      selected_organization_id: Some(organization),
      lease_requests: [submitted],
      justification: "Keep this draft",
    },
  }
  assert_true(
    rental_wait_active(model, model.contract_poll_generation, organization),
  )
  let view : @portal.EnterpriseSelfView = {
    version: "lunanexa.portal.v1",
    membership: model.portal.membership.unwrap(),
    agreements: model.portal.agreements,
    lease_requests: [submitted],
    can_sign: false,
    can_request_lease: true,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (unchanged, _) = apply_rental_wait(
    model,
    model.contract_poll_generation,
    organization,
    -1,
    Ok(Access(view)),
    emit,
  )
  assert_true(unchanged == model)
  let approved = {
    ..view,
    lease_requests: [{ ..submitted, state: Approved, }],
  }
  let (refreshing, _) = apply_rental_wait(
    model,
    model.contract_poll_generation,
    organization,
    -1,
    Ok(Access(approved)),
    emit,
  )
  assert_eq(refreshing.portal.justification, "Keep this draft")
  let (stale, _) = apply_rental_wait(
    model,
    model.contract_poll_generation - 1L,
    organization,
    -1,
    Ok(Access(approved)),
    emit,
  )
  assert_true(stale == model)
  let (other, _) = apply_rental_wait(
    model,
    model.contract_poll_generation,
    "other",
    -1,
    Ok(Access(approved)),
    emit,
  )
  assert_true(other == model)
  let signed_out = signed_out_model(model)
  assert_false(
    rental_wait_active(signed_out, model.contract_poll_generation, organization),
  )
  let finished = {
    ..model,
    portal: { ..model.portal, lease_requests: approved.lease_requests, },
  }
  assert_false(waiting_for_lease_approval(finished))
}
