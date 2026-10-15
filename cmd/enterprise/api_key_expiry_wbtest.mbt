///|
test "company API key lifetime is independent of an expired personal trial" {
  let portal = @enterprise_ui.demo_state()
  let membership = portal.membership.unwrap()
  let now = portal.machine_access.now_unix_ms
  let trial : @enterprise_ui.TrialEntitlementView = {
    trial_id: "expired-personal-trial",
    organization_id: "personal-trial-organization",
    tenant_ref: "personal-trial-tenant",
    project_id: "personal-trial-project",
    allowed_models: ["text.qwen"],
    maximum_requests: 100L,
    starts_unix_ms: now - 86400000L,
    expires_unix_ms: now - 1000L,
    api_key_id: None,
    revoked_unix_ms: None,
  }
  let state = { ..portal, trial: Some(trial), }
  let requested_expiry = now +
    portal.api_key_issue_draft.lifetime_days.to_int64() * 86400000L
  assert_eq(api_key_issue_expiry(state, now), requested_expiry)
  let same_scope = {
    ..trial,
    organization_id: membership.organization_id,
    tenant_ref: membership.tenant_ref,
    project_id: portal.project_id,
    expires_unix_ms: now + 3600000L,
  }
  assert_eq(
    api_key_issue_expiry({ ..portal, trial: Some(same_scope), }, now),
    same_scope.expires_unix_ms,
  )
  assert_eq(
    api_key_issue_expiry(
      {
        ..portal,
        trial: Some({ ..same_scope, project_id: "another-project", }),
      },
      now,
    ),
    requested_expiry,
  )
  assert_eq(
    api_key_issue_expiry(
      {
        ..portal,
        trial: Some({ ..same_scope, tenant_ref: "another-tenant", }),
      },
      now,
    ),
    requested_expiry,
  )
  assert_eq(
    api_key_issue_expiry(
      { ..portal, trial: Some({ ..same_scope, revoked_unix_ms: Some(now), }), },
      now,
    ),
    requested_expiry,
  )
}

///|
test "successful key issuance closes the creation form and reveals only the one-time result" {
  let base = gateway_auth_test_model()
  let portal = @enterprise_ui.demo_state()
  let model = {
    ..base,
    portal: {
      ..portal,
      route: Models,
      api_key_issue_open: true,
      loading: true,
    },
  }
  let issued : @enterprise_ui.IssuedApiKeyView = {
    credential: { ..portal.api_keys[0], maximum_requests: 0L, },
    secret: "fixture-only-secret",
    api_base_url: Some("https://api.example.invalid"),
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (updated, _) = update(
    model,
    Outcome(ApiKeyIssued(model.session_generation, issued)),
    emit,
  )
  assert_false(updated.portal.api_key_issue_open)
  assert_false(updated.portal.loading)
  assert_eq(updated.portal.route, Models)
  assert_eq(updated.portal.api_keys[0].maximum_requests, 0L)
  assert_true(updated.portal.one_time_api_key_secret is Some(_))
}
