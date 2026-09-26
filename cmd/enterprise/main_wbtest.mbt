///|
test "undertaking order authority covers the selected rental term" {
  let now = 1800000000000L
  assert_eq(offline_order_expiry(now, "year"), now + 396L * 86400000L)
  assert_eq(offline_order_expiry(now, "month"), now + 61L * 86400000L)
  assert_eq(offline_order_expiry(now, ""), now + 30L * 86400000L)
}

///|
test "personal MoonDesk catalog decodes the live string-encoded handoff lifetime" {
  let payload =
    $|[{"client_id":"desktop-workspace","display_name":"MoonDesk / MoonCode","launch_uri":"http://106.39.18.146:5003/connect","handoff_lifetime_ms":"120000","contract_ready":true,"workspace_ready":true,"models_ready":true,"ready":true,"blocker_codes":[],"approved_model_aliases":["glm-5.3.flash"],"handoffs":[]}]
  let clients : Array[DesktopClientResponse] = @json.from_json(
    @json.parse(payload),
  )
  assert_eq(clients.length(), 1)
  assert_eq(clients[0].client_id, "desktop-workspace")
  assert_eq(clients[0].handoff_lifetime_ms, 120000L)
  assert_eq(clients[0].approved_model_aliases, ["glm-5.3.flash"])
}

///|
test "PaaS entry prefers personal MoonDesk over GPU-only ComfyUI" {
  let base = @enterprise_ui.demo_state().desktop_client.unwrap()
  let comfy = { ..base, client_id: "comfyui", display_name: "ComfyUI", }
  let personal = {
    ..base,
    client_id: "desktop-workspace",
    display_name: "MoonDesk / MoonCode",
  }
  assert_eq(
    preferred_personal_webide([comfy, personal]).unwrap().client_id,
    "desktop-workspace",
  )
  assert_eq(preferred_personal_webide([comfy]).unwrap().client_id, "comfyui")
  assert_true(preferred_personal_webide([]) is None)
}

///|
test "enterprise lease model input is trimmed and empty entries are ignored" {
  assert_eq(
    requested_models(" text.default,embedding.default ,, image.default "),
    ["text.default", "embedding.default", "image.default"],
  )
  assert_eq(requested_models(" , , "), [])
}

///|
test "demo one-time key walkthrough creates no authority and dismissal clears fixture" {
  let portal = @enterprise_ui.demo_state()
  let model : AppModel = {
    endpoint: "https://unused.invalid",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: true,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: { ..portal, route: AccountAccess, api_key_issue_open: true, },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (preview, _) = update(model, Portal(SubmitApiKeyIssue), emit)
  assert_eq(preview.portal.api_keys, portal.api_keys)
  assert_false(preview.portal.api_key_issue_open)
  guard preview.portal.one_time_api_key_secret is Some(value) else {
    fail("missing demo walkthrough")
  }
  assert_eq(value.secret, "DEMO-NOT-A-CREDENTIAL")
  assert_true(
    preview.portal.success_message
    .unwrap_or("")
    .contains("no API key was issued"),
  )
  let rendered = @enterprise_ui.render(preview.portal)
  assert_true(rendered.contains("DEMO preview"))
  assert_true(rendered.contains("cannot authorize any request"))
  assert_true(rendered.contains("api-key-secret-dismiss"))
  let (dismissed, _) = update(preview, Portal(DismissOneTimeApiKeySecret), emit)
  assert_eq(dismissed.portal.one_time_api_key_secret, None)
  assert_eq(dismissed.portal.api_keys, portal.api_keys)
}

///|
test "enterprise demo lease submission never claims an operator mutation" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: true,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: LeaseRequests, },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let before = model.portal.lease_requests.length()
  let (submitted, _) = update(model, Portal(SubmitLease), emit)
  assert_eq(submitted.portal.lease_requests.length(), before)
  let message = submitted.portal.success_message.unwrap_or("")
  assert_true(message.contains("Demo preview only"))
  assert_true(message.contains("no lease request was submitted"))
}

///|
test "enterprise contract preview is reactive and generation fenced" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: true,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: ContractDocuments, },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (selected, _) = update(
    model,
    Portal(ContractDocuments(SelectForm(ReservationApplication))),
    emit,
  )
  assert_eq(selected.contract_preview_generation, 1L)
  assert_eq(
    selected.portal.contract_documents.selected_form,
    Some(ReservationApplication),
  )
  let (changed, _) = update(
    selected,
    Portal(
      ContractDocuments(
        FieldChanged("reservation.organization_name", "星海研究院"),
      ),
    ),
    emit,
  )
  assert_eq(changed.contract_preview_generation, 2L)
  guard changed.portal.contract_documents.preview_request() is Some(request) else {
    fail("expected current customer preview request")
  }
  let (after_stale, _) = update(changed, ContractPreviewDue(1L, request), emit)
  assert_eq(after_stale.contract_preview_generation, 2L)
  assert_eq(
    after_stale.portal.contract_documents.draft_values,
    changed.portal.contract_documents.draft_values,
  )
}

///|
test "demo machine termination mirrors the controller cleanup transition" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: true,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: MachineAccess, },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (begun, _) = update(
    model,
    Portal(MachineAccess(BeginTermination("exclusive-lease-demo"))),
    emit,
  )
  let confirmation = "TERMINATE exclusive-lease-demo"
  let (typed, _) = update(
    begun,
    Portal(MachineAccess(ConfirmationChanged(confirmation))),
    emit,
  )
  let (terminated, _) = update(
    typed,
    Portal(
      MachineAccess(
        ConfirmTermination("exclusive-lease-demo", 5L, confirmation),
      ),
    ),
    emit,
  )
  let machine = terminated.portal.machine_access.machines[0]
  assert_eq(machine.state, Expiring)
  assert_eq(machine.generation, 6L)
  assert_eq(machine.credential_handoff.state, Closed)
  assert_false(machine.can_terminate)
  assert_eq(terminated.portal.machine_access.confirmation_lease_ref, None)
  assert_true(
    terminated.portal.success_message.unwrap_or("").contains("verified cleanup"),
  )
}

///|
test "demo credential redemption is explicit and never contains a secret" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: true,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: MachineAccess, },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (redeemed, _) = update(
    model,
    Portal(MachineAccess(RedeemCredential("exclusive-lease-demo", 5L))),
    emit,
  )
  assert_eq(redeemed.portal.machine_access.redeemed_credentials.length(), 1)
  let credential = redeemed.portal.machine_access.redeemed_credentials[0]
  assert_eq(credential.lease_ref, "exclusive-lease-demo")
  assert_eq(credential.generation, 5L)
  assert_true(credential.one_time)
  assert_false(credential.raw_secret_included)
  assert_true(credential.issuer_redirect_url.contains(".invalid"))
  assert_false(redeemed.portal.machine_access.loading)
  assert_true(
    redeemed.portal.success_message
    .unwrap_or("")
    .contains("no credential was issued"),
  )
}

///|
test "enterprise demo machine countdown uses the snapshot clock" {
  let portal = @enterprise_ui.demo_state()
  let machine = portal.machine_access.machines[0]
  assert_true(portal.machine_access.now_unix_ms > 0L)
  assert_true(machine.expires_unix_ms > portal.machine_access.now_unix_ms)
  assert_true(
    machine.expires_unix_ms - portal.machine_access.now_unix_ms <= 86400000L,
  )
}

///|
test "enterprise demo renews the selected effective contract packet" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: true,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: ContractDocuments, },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (selected, _) = update(
    model,
    Portal(ContractDocuments(SelectPacket("packet-demo-effective"))),
    emit,
  )
  let (begun, _) = update(
    selected,
    Portal(ContractDocuments(BeginRequestRenewal("packet-demo-effective"))),
    emit,
  )
  let (renewed, _) = update(
    begun,
    Portal(
      ContractDocuments(ConfirmAction(RequestRenewal("packet-demo-effective"))),
    ),
    emit,
  )
  let prior_count = model.portal.contract_documents.packets.length()
  assert_eq(renewed.portal.contract_documents.packets.length(), prior_count + 1)
  let packet = renewed.portal.contract_documents.packets[prior_count]
  assert_eq(
    renewed.portal.contract_documents.selected_packet_id,
    Some(packet.packet_id),
  )
  assert_eq(packet.state, InformationDraft)
  assert_eq(packet.preceding_packet_ref, Some("packet-demo-effective"))
  assert_true(packet.packet_id.has_prefix("contract-renewal-"))
}

///|
#warnings("-alert_unstable")
test "signed-out enterprise gate hides application navigation and actions" {
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: false,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: @enterprise_ui.default_state(1000L),
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  // The gate is now the customer's own form; organization sign-in stays as a
  // second option, and the development fallback stays hidden on public HTTP.
  assert_true(html.contains("portal-login-email"))
  assert_true(html.contains("portal-login-password"))
  assert_true(html.contains("Register a new account"))
  assert_true(html.contains("href=\"/auth/oidc/start?audience=enterprise\""))
  assert_false(html.contains("Development credential fallback"))
  assert_false(html.contains("session_token="))
  assert_false(html.contains("Enterprise navigation"))
  assert_false(html.contains("Request capacity"))
  assert_false(html.contains("Create API key"))
}

///|
test "logout erases account key and one-time secret state and fences stale issue" {
  let portal = @enterprise_ui.demo_state()
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    token: "lnxs_test_session",
    csrf_token: "csrf-test",
    subject_ref: "subject-alice",
    connecting: false,
    bootstrap_started: true,
    demo_mode: false,
    session_generation: 7L,
    session_expires_unix_ms: Some(999999L),
    machine_clock_generation: 2L,
    contract_preview_generation: 3L,
    contract_poll_generation: 0L,
    portal: {
      ..portal,
      one_time_api_key_secret: Some({
        key_id: "key-new",
        display_name: "New integration",
        secret: "lnx_one_time",
        allowed_models: ["text.default"],
        api_base_url: None,
        tenant_ref: "tenant-demo",
        memory_ceiling_mib: Some(4096),
      }),
    },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (signed_out, _) = update(model, Logout, emit)
  assert_eq(signed_out.token, "")
  assert_eq(signed_out.csrf_token, "")
  assert_eq(signed_out.subject_ref, "")
  assert_eq(signed_out.portal.membership, None)
  assert_eq(signed_out.portal.account, None)
  assert_eq(signed_out.portal.api_keys, [])
  assert_eq(signed_out.portal.one_time_api_key_secret, None)
  assert_eq(signed_out.session_generation, 8L)
  let issued : @enterprise_ui.IssuedApiKeyView = {
    credential: portal.api_keys[0],
    secret: "lnx_stale_secret",
    api_base_url: None,
  }
  let (after_stale, _) = update(
    signed_out,
    Outcome(ApiKeyIssued(7L, issued)),
    emit,
  )
  assert_eq(after_stale.portal.membership, None)
  assert_eq(after_stale.portal.one_time_api_key_secret, None)
  assert_eq(after_stale.portal.api_keys, [])
}

///|
test "gateway bootstrap remains memory-only and generation fenced" {
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: false,
    demo_mode: false,
    session_generation: 3L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: @enterprise_ui.default_state(1000L),
    login_email: "",
    login_password: "MustBeClearedAfterSignIn",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (started, _) = update(model, Bootstrap, emit)
  assert_true(started.bootstrap_started)
  assert_true(started.connecting)
  let browser_session : GatewayBrowserBootstrap = {
    session_token: "lnxs_memory_only",
    csrf_token: "csrf-memory-only",
    expires_unix_ms: 9999999999999L,
  }
  let (ready, _) = update(started, BootstrapReady(3L, browser_session), emit)
  assert_eq(ready.token, "lnxs_memory_only")
  assert_eq(ready.csrf_token, "csrf-memory-only")
  assert_eq(ready.login_password, "")
  assert_eq(ready.session_expires_unix_ms, Some(9999999999999L))
  assert_eq(ready.session_generation, 4L)
  let stale_session : GatewayBrowserBootstrap = {
    ..browser_session,
    session_token: "lnxs_stale",
  }
  let (after_stale, _) = update(ready, BootstrapReady(3L, stale_session), emit)
  assert_eq(after_stale.token, "lnxs_memory_only")
  assert_eq(after_stale.csrf_token, "csrf-memory-only")
}

///|
test "matching browser-session expiry clears the local session" {
  let portal = @enterprise_ui.demo_state()
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    token: "lnxs_test_session",
    csrf_token: "csrf-test",
    subject_ref: "subject-alice",
    connecting: false,
    bootstrap_started: true,
    demo_mode: false,
    session_generation: 4L,
    session_expires_unix_ms: Some(1000L),
    machine_clock_generation: 9L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: {
      ..portal,
      machine_access: { ..portal.machine_access, now_unix_ms: 500L, },
    },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (expired, _) = update(
    model,
    Outcome(MachineClockAdvanced(1000L, 9L)),
    emit,
  )
  assert_eq(expired.token, "")
  assert_eq(expired.portal.membership, None)
  assert_eq(expired.portal.api_keys, [])
}

///|
test "HTTP 401 signs out a stale browser session with a clear message" {
  let model : AppModel = {
    ..gateway_auth_test_model(),
    token: "lnxs_expired",
    csrf_token: "csrf-expired",
    subject_ref: "subject-test",
    login_password: "MustNotRemainInMemory",
    session_generation: 7L,
    session_expires_unix_ms: Some(9999999999999L),
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (signed_out, _) = update(
    model,
    Outcome(
      Failed(
        model.portal.locale,
        "Unable to load your organizations: HTTP 401 Unauthenticated",
      ),
    ),
    emit,
  )
  assert_eq(signed_out.token, "")
  assert_eq(signed_out.csrf_token, "")
  assert_eq(signed_out.subject_ref, "")
  assert_eq(signed_out.login_password, "")
  assert_eq(signed_out.session_generation, 8L)
  assert_eq(
    signed_out.portal.error_message,
    Some("Your session has expired. Sign in again."),
  )
  let (forbidden, _) = update(
    model,
    Outcome(Failed(model.portal.locale, "HTTP 403 Forbidden")),
    emit,
  )
  assert_eq(forbidden.token, "lnxs_expired")
}

///|
test "enterprise checkout quote is stable and selects the latest finalized period" {
  let entry : @commercial.LedgerEntry = {
    entry_id: "entry-one",
    organization_id: "org-one",
    cost_center_id: "cost-one",
    project_id: "project-one",
    organization_name_snapshot: "One",
    cost_center_name_snapshot: "Research",
    project_name_snapshot: "Inference",
    source_event_id: "usage-one",
    linked_entry_id: None,
    kind: Charge,
    meter: "tokens",
    quantity: 10L,
    unit: "token",
    amount: { minor_units: 12345L, currency: "CNY", scale: 2, },
    rate_card_id: "rate-one",
    rate_card_version: "v1",
    service_started_unix_ms: 1000L,
    service_ended_unix_ms: 2000L,
    recorded_unix_ms: 3000L,
    reason: "metered usage",
  }
  let snapshot : @commercial.CommercialSnapshot = {
    schema_version: @commercial.snapshot_schema_version,
    organizations: [],
    cost_centers: [],
    projects: [],
    usage_observations: [],
    ledger_entries: [
      entry,
      {
        ..entry,
        entry_id: "entry-two",
        amount: { ..entry.amount, minor_units: 55L, },
        recorded_unix_ms: 4000L,
      },
    ],
    finalized_periods: [
      {
        period_id: "period-one",
        organization_id: "org-one",
        started_unix_ms: 1000L,
        ended_unix_ms: 2000L,
        billing_timezone: "UTC",
        entry_ids: ["entry-one", "entry-two"],
        total: { minor_units: 12400L, currency: "CNY", scale: 2, },
        finalized_unix_ms: 4000L,
        finalized_by: "billing-operator",
      },
    ],
    budgets: [],
    quotas: [],
    commitments: [],
    consumptions: [],
    agreement_templates: [],
    clickwrap_acceptances: [],
    agreements: [],
    role_grants: [],
  }
  guard derive_payment_checkout_quote(Some(snapshot)) is Some(quote) else {
    fail("expected checkout quote")
  }
  assert_eq(quote.expected_amount_minor, 12400L)
  assert_eq(quote.period_id, "period-one")
  assert_eq(quote.display_amount, "CNY 124.00")
  assert_eq(quote.money_scale, 2)
  assert_eq(quote.ledger_entry_count, 2)
  assert_eq(quote.ledger_revision_unix_ms, 4000L)
  assert_true(quote.entitlement_transaction_ref_sha256.has_prefix("sha256:"))
  assert_true(quote.idempotency_key.has_prefix("checkout-"))
  assert_eq(quote.idempotency_key.length(), "checkout-".length() + 64)
  assert_eq(derive_payment_checkout_quote(Some(snapshot)), Some(quote))
  let newer = {
    ..snapshot,
    finalized_periods: [
      ..snapshot.finalized_periods,
      {
        ..snapshot.finalized_periods[0],
        period_id: "period-two",
        total: { minor_units: 2500L, currency: "USD", scale: 2, },
        finalized_unix_ms: 5000L,
      },
    ],
  }
  guard derive_payment_checkout_quote(Some(newer)) is Some(latest) else {
    fail("expected latest checkout quote")
  }
  assert_eq(latest.period_id, "period-two")
  assert_eq(latest.expected_amount_minor, 2500L)
}

///|
test "enterprise demo checkout requires an explicit provider-link click" {
  let portal = @enterprise_ui.demo_state()
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: true,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: { ..portal, route: Costs, },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (submitted, _) = update(model, Portal(SubmitPaymentCheckout), emit)
  assert_false(submitted.portal.payment_checkout_loading)
  let checkout = submitted.portal.provider_requests
    .iter()
    .find_first(record => record.record_id == "payment-demo-checkout")
  guard checkout is Some(record) else { fail("expected demo checkout") }
  assert_eq(record.state, Submitted)
  assert_true(record.action_url.unwrap_or("").has_prefix("https://"))
  let html = @enterprise_ui.render(submitted.portal)
  assert_true(html.contains("Continue with payment provider"))
  assert_false(html.contains("location.assign"))
}

///|
test "organization bootstrap honors an active saved choice and fails closed on ambiguity" {
  let state = @enterprise_ui.demo_state()
  let first = state.organizations[0]
  let second : @enterprise_ui.SelfServiceOrganizationView = {
    organization: {
      ..first.organization,
      organization_id: "org-second",
      display_name: "Second organization",
    },
    membership: {
      ..first.membership,
      membership_id: "membership-second",
      organization_id: "org-second",
      tenant_ref: "tenant-second",
    },
    default_project_id: Some("project-second"),
    verification: first.verification,
  }
  let organizations = [first, second]
  assert_eq(
    preferred_organization(organizations, "org-second").map(value => {
      value.organization.organization_id
    }),
    Some("org-second"),
  )
  assert_eq(preferred_organization(organizations, ""), None)
  assert_eq(
    preferred_organization([first], "").map(value => {
      value.organization.organization_id
    }),
    Some("org-northstar"),
  )
  let inactive = {
    ..first,
    membership: { ..first.membership, active: false, },
  }
  assert_eq(preferred_organization([inactive], "org-northstar"), None)
}

///|
#warnings("-alert_unstable")
test "authenticated users without a company reach organization self-service" {
  let portal = {
    ..@enterprise_ui.default_state(1000L),
    route: SelfService,
    membership: None,
    self_service: {
      ..@enterprise_ui.default_state(1000L).self_service,
      step: Organization,
    },
  }
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    token: "lnxs_authenticated",
    csrf_token: "csrf",
    subject_ref: "user@example.test",
    connecting: false,
    bootstrap_started: true,
    demo_mode: false,
    session_generation: 1L,
    session_expires_unix_ms: Some(100000L),
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal,
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("Create company"))
  assert_true(html.contains("Join company"))
  assert_true(html.contains("能源谷“创未来”生态街区"))
  assert_false(html.contains("LunaNexa enterprise access"))
}

///|
fn mock_machine_offering(
  kind : @machinecommerce.MachineOfferingKind,
) -> @machinecommerce.MachineOfferingView {
  {
    offering: {
      offering_id: "offering-test",
      sku: "gpu-test",
      display_name: "Test GPU",
      kind,
      region: "cn-north-1",
      accelerator_class: "NVIDIA Test GPU",
      accelerator_count: 1L,
      memory_mib: 16384L,
      cpu_count: 16L,
      meter: "machine-second",
      unit_price: { minor_units: 2L, currency: "CNY", scale: 2, },
      billing_quantum_seconds: 3600L,
      price_unit_seconds: None,
      minimum_duration_seconds: 86400L,
      maximum_duration_seconds: 2592000L,
      capacity_total: 2L,
      allowed_model_template_refs: ["qwen"],
      state: OfferingActive,
      generation: 1L,
      created_unix_ms: 1000L,
      updated_unix_ms: 2000L,
    },
    availability: {
      offering_id: "offering-test",
      capacity_total: 2L,
      capacity_reserved: 1L,
      capacity_available: 1L,
      observed_unix_ms: 3000L,
    },
  }
}

///|
fn mock_machine_order(
  state : @machinecommerce.MachineOrderState,
) -> @machinecommerce.MachineOrder {
  {
    order_id: "machine-order-test",
    idempotency_key: "order-create-test",
    quote_id: "machine-quote-test",
    tenant_ref: "tenant-test",
    organization_id: "org-test",
    project_id: "project-test",
    purchaser_subject_ref: "subject-test",
    offering_id: "offering-test",
    offering_kind: DedicatedEndpoint,
    quantity: 1L,
    duration_seconds: 86400L,
    unix_username: None,
    requested_model_selector: Some("qwen3"),
    model_template_ref: None,
    quoted_total: { minor_units: 4800L, currency: "CNY", scale: 2, },
    state,
    generation: 3L,
    payment_ref: Some("payment-test"),
    payment_event_id: Some("payment-event-test"),
    target_lease_ref: Some("lease-test"),
    target_deployment_ref: Some("deployment-test"),
    failure_code: if state == CompensationPending {
      Some("CapacityUnavailableAfterPayment")
    } else {
      None
    },
    compensation_ref: None,
    capacity_reserved: state == Provisioning || state == Active,
    active_started_unix_ms: None,
    last_metered_unix_ms: None,
    ended_unix_ms: None,
    created_unix_ms: 1000L,
    updated_unix_ms: 3000L,
  }
}

///|
test "machine quote request derives bare username and dedicated model without tenant claims" {
  let state = @enterprise_ui.demo_state().self_service
  let bare_offering = state.offerings
    .iter()
    .find_first(value => value.kind == BareGpu)
    .unwrap()
  let bare = machine_quote_intent(
    {
      ..state,
      selected_product: Some(BareGpu),
      selected_offering_id: bare_offering.offering_id,
      project_id: " project-bare ",
      unix_username: " alice ",
      model_selector: "",
      duration_hours: 24,
    },
    "quote-bare",
    "request-bare",
  )
  assert_eq(bare.quantity, 1L)
  assert_eq(bare.duration_seconds, 86400L)
  assert_eq(bare.unix_username, Some("alice"))
  assert_eq(bare.requested_model_selector, None)
  let json = bare.to_json().stringify()
  assert_false(json.contains("tenant_ref"))
  assert_false(json.contains("organization_id"))
  assert_false(json.contains("purchaser_subject_ref"))
  let dedicated = machine_quote_intent(
    { ..state, model_selector: " qwen3 ", },
    "quote-dedicated",
    "request-dedicated",
  )
  assert_eq(dedicated.unix_username, None)
  assert_eq(dedicated.requested_model_selector, Some("qwen3"))
  assert_eq(dedicated.model_template_ref, Some("qwen-template-v1"))
}

///|
test "mock machine responses map inventory compensation and checkout without node identity" {
  let raw_offering = mock_machine_offering(DedicatedEndpoint)
  let offering = machine_offering_view(raw_offering)
  assert_eq(offering.kind, DedicatedMaaS)
  assert_eq(offering.regions, ["cn-north-1"])
  assert_eq(offering.accelerator_count, 1)
  assert_true(offering.available)
  let order = machine_order_view(mock_machine_order(CompensationPending), [
    offering,
  ])
  assert_eq(order.status, CompensationPending)
  assert_eq(order.gpu_sku, "NVIDIA Test GPU")
  assert_eq(order.region, "cn-north-1")
  let checkout : @commercial_integrations.ExternalRecordView = {
    record_id: "checkout-test",
    organization_id: "org-test",
    kind: Payment,
    provider: "provider-test",
    environment: "test",
    external_ref_sha256: "sha256:" + "a".repeat(64),
    state: Submitted,
    expected_amount_minor: Some(4800L),
    currency: Some("CNY"),
    money_scale: Some(2),
    expected_document_hash: None,
    entitlement_transaction_ref_sha256: Some("sha256:" + "b".repeat(64)),
    action_url: Some("https://pay.example.test/checkout"),
    action_expires_unix_ms: Some(900000L),
    updated_unix_ms: 3000L,
  }
  let mapped = machine_checkout_view(checkout)
  assert_eq(mapped.state, "Submitted")
  assert_eq(mapped.provider, "provider-test")
  assert_eq(mapped.action_url, Some("https://pay.example.test/checkout"))
}

///|
test "daily machine offer displays the CNY 49 day price" {
  let raw = mock_machine_offering(BareMachine)
  let daily = {
    ..raw,
    offering: {
      ..raw.offering,
      unit_price: { minor_units: 4900L, currency: "CNY", scale: 2, },
      price_unit_seconds: Some(86400L),
      billing_quantum_seconds: 86400L,
    },
  }
  let view = machine_offering_view(daily)
  assert_eq(view.price_summary, "¥49.00 / 天")
}

///|
test "machine terms acceptance request binds the immutable document and hashed contexts" {
  let terms : @enterprise_ui.SelfServiceTermsView = {
    template_id: "machine-terms",
    version: "v3",
    locale: "zh-CN",
    rendered_document_hash: "sha256:" + "c".repeat(64),
    document_uri: "/docs/legal/machine-terms-v3.html",
  }
  let intent = machine_terms_acceptance_intent(
    terms, "https://controller.example.test", "org-test", "terms-request-test",
  )
  assert_eq(intent.document_uri, "/docs/legal/machine-terms-v3.html")
  assert_eq(intent.template_version, "v3")
  assert_true(intent.presentation_context_hash.has_prefix("sha256:"))
  assert_eq(intent.presentation_context_hash.length(), 71)
  assert_true(intent.network_context_hash.has_prefix("sha256:"))
  assert_eq(intent.network_context_hash.length(), 71)
}

///|
test "machine order refresh recovers the newest submitted provider checkout URL" {
  let order = machine_order_view(mock_machine_order(AwaitingPayment), [
    machine_offering_view(mock_machine_offering(DedicatedEndpoint)),
  ])
  let digest = sha256_label("machine-order:" + order.order_id)
  let pending : @commercial_integrations.ExternalRecordView = {
    record_id: "checkout-pending",
    organization_id: "org-test",
    kind: Payment,
    provider: "provider-test",
    environment: "test",
    external_ref_sha256: "sha256:" + "d".repeat(64),
    state: Pending,
    expected_amount_minor: Some(4800L),
    currency: Some("CNY"),
    money_scale: Some(2),
    expected_document_hash: None,
    entitlement_transaction_ref_sha256: Some(digest),
    action_url: None,
    action_expires_unix_ms: None,
    updated_unix_ms: 1000L,
  }
  let submitted = {
    ..pending,
    record_id: "checkout-submitted",
    state: Submitted,
    action_url: Some("https://pay.example.test/resumed"),
    action_expires_unix_ms: Some(900000L),
    updated_unix_ms: 2000L,
  }
  guard checkout_for_order(Some(order), [pending, submitted]) is Some(checkout) else {
    fail("expected correlated checkout")
  }
  assert_eq(checkout.state, "Submitted")
  assert_eq(checkout.action_url, Some("https://pay.example.test/resumed"))
  assert_eq(checkout_for_order(None, [submitted]), None)
}

///|
test "organization mock response keeps verification provider action and redacted summary" {
  let body = "{\"version\":\"lunanexa.enterprise-portal.v1\",\"organizations\":[{\"organization\":{\"organization_id\":\"org-test\",\"display_name\":\"Test Org\",\"state\":\"PendingVerification\"},\"membership\":{\"membership_id\":\"membership-test\",\"tenant_ref\":\"tenant-test\",\"organization_id\":\"org-test\",\"subject_ref\":\"subject-test\",\"roles\":[\"OrganizationAdministrator\",\"LegalSigner\",\"LeaseRequester\",\"Developer\"],\"active\":true,\"created_unix_ms\":\"1000\"},\"default_project_id\":\"project-test\",\"verification\":{\"required\":true,\"record\":{\"provider\":\"provider-test\",\"state\":\"Submitted\",\"action_url\":\"https://verify.example.test/start\",\"action_expires_unix_ms\":\"900000\",\"updated_unix_ms\":\"2000\"}}}]}"
  let response : SelfServiceOrganizationsResponse = @json.from_json(
    @json.parse(body),
  )
  assert_eq(response.organizations.length(), 1)
  let organization = response.organizations[0]
  assert_eq(organization.organization.state, PendingVerification)
  guard organization.verification is Some(verification) &&
    verification.record is Some(record) else {
    fail("expected provider verification action")
  }
  assert_true(verification.required)
  assert_eq(record.action_url, Some("https://verify.example.test/start"))
}

///|
test "portal failures reach the refusal-specific friendly copy" {
  let conflict = portal_failure_message(
    @i18n.English,
    "Unable to approve the model version: " +
    "HTTP 409: {\"error\":{\"code\":\"RegistryRejected\",\"message\":\"model approval prerequisites were not met\"}}",
  )
  assert_true(conflict.contains("The resource changed"))
  assert_true(conflict.contains("Operation"))
  let denied = portal_failure_message(
    @i18n.English,
    "Unable to load your organizations: " +
    "HTTP 403: {\"error\":{\"code\":\"PortalAccessDenied\",\"message\":\"denied\"}}",
  )
  assert_true(denied.contains("lacks permission"))
  let unauthenticated = portal_failure_message(
    @i18n.English,
    "HTTP 401: {\"error\":{\"code\":\"Unauthenticated\"}}",
  )
  assert_true(
    unauthenticated.contains("Session") ||
    unauthenticated.contains("credential"),
  )
}

///|
test "an opaque debug representation cannot select friendly copy" {
  // The regression this guards: interpolating the debug `Repr` of the error
  // never carries the status line, so every refusal silently fell through to
  // the generic copy instead of its own recovery guidance.
  let debug_repr = portal_failure_message(
    @i18n.English,
    "Unable to approve the model version: Error(\"RegistryRejected\")",
  )
  assert_true(debug_repr.contains("The action failed"))
  assert_false(debug_repr.contains("The resource changed"))
}

///|
fn gateway_auth_test_model() -> AppModel {
  {
    endpoint: "https://controller.example.test",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: false,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 0L,
    portal: @enterprise_ui.default_state(1000L),
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
}

///|
#warnings("-alert_unstable")
test "signed-in shell shows a human status instead of internal tenant ids" {
  let base = gateway_auth_test_model()
  let model = {
    ..base,
    token: "session-test",
    portal: @enterprise_ui.demo_state(),
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("Signed in"))
  assert_false(html.contains("<strong>subject-"))
}

///|
test "the gateway's refusal codes choose the customer-facing copy" {
  let refusal = fn(code : String, registering : Bool) -> String {
    gateway_auth_refusal(
      English,
      { status: 401, body: "{\"error\":\"\{code}\"}", },
      registering,
    )
  }
  assert_true(refusal("invalid-credentials", false).contains("not accepted"))
  assert_true(refusal("email-taken", true).contains("already has an account"))
  // The realm's password policy is the provider's, so the form repeats it
  // rather than inventing its own rule.
  assert_true(refusal("password-rejected", true).contains("12 characters"))
  assert_true(
    refusal("registration-unavailable", true).contains("platform administrator"),
  )
  assert_true(refusal("too-many-attempts", false).contains("five minutes"))
  assert_true(
    refusal("identity-provider-unavailable", false).contains("unavailable"),
  )
  // An unrecognised code still names which action was refused.
  assert_true(refusal("something-else", true).contains("registration"))
  assert_true(refusal("something-else", false).contains("sign-in"))
  assert_true(refusal("not json", false).contains("sign-in"))
}

///|
test "the customer gate needs both fields and drops the password once it is used" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = gateway_auth_test_model()
  // An incomplete draft cannot be submitted and does not start a connection.
  let (unsubmitted, _) = update(
    { ..model, login_email: "buyer@example.test", },
    EnterpriseSignInSubmitted,
    emit,
  )
  assert_false(unsubmitted.connecting)
  // Registration additionally needs a display name.
  let (incomplete_registration, _) = update(
    {
      ..model,
      registering: true,
      login_email: "buyer@example.test",
      login_password: "Correct-Horse-9!",
    },
    EnterpriseRegistrationSubmitted,
    emit,
  )
  assert_false(incomplete_registration.connecting)
  let (submitted, _) = update(
    {
      ..model,
      login_email: "buyer@example.test",
      login_password: "Correct-Horse-9!",
    },
    EnterpriseSignInSubmitted,
    emit,
  )
  assert_true(submitted.connecting)
  let (refused, _) = update(
    submitted,
    EnterpriseAuthRefused(
      English,
      gateway_auth_refusal(
        English,
        { status: 401, body: "{\"error\":\"invalid-credentials\"}", },
        false,
      ),
    ),
    emit,
  )
  assert_false(refused.connecting)
  // The address is kept so the customer can correct only what is wrong; the
  // password is not.
  assert_eq(refused.login_email, "buyer@example.test")
  assert_eq(refused.login_password, "")
  assert_true(refused.portal.error_message.unwrap().contains("not accepted"))
}

///|
test "switching between sign-in and registration clears the other form's secret" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = {
    ..gateway_auth_test_model(),
    login_email: "buyer@example.test",
    login_password: "Correct-Horse-9!",
    portal: {
      ..@enterprise_ui.default_state(1000L),
      error_message: Some("stale refusal"),
    },
  }
  let (registering, _) = update(model, ToggleRegistration, emit)
  assert_true(registering.registering)
  assert_eq(registering.login_password, "")
  assert_eq(registering.login_email, "buyer@example.test")
  assert_eq(registering.portal.error_message, None)
  let (back, _) = update(registering, ToggleRegistration, emit)
  assert_false(back.registering)
}

///|
#warnings("-alert_unstable")
test "the registration form asks for a display name the sign-in form does not" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(gateway_auth_test_model(), emit))
  })
  assert_true(html.contains("portal-login-email"))
  assert_false(html.contains("portal-register-name"))
  // Without a deployment opt-in the page still renders the form, but says why
  // it cannot be used yet instead of leaving a dead button unexplained.
  let blocked = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      app_view(
        { ..gateway_auth_test_model(), endpoint: "http://106.39.18.146:5002", },
        emit,
      ),
    )
  })
  assert_true(blocked.contains("blocked on public plain HTTP"))
  let registering = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      app_view({ ..gateway_auth_test_model(), registering: true, }, emit),
    )
  })
  assert_true(registering.contains("portal-register-name"))
  assert_true(registering.contains("Create account"))
  // The realm's password policy is stated before the customer picks one.
  assert_true(registering.contains("12 characters"))
}
