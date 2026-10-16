///|
test "saved API keys are masked by default and reveal controls clear across navigation" {
  let base = demo_state()
  let key = base.api_keys[0]
  let state = {
    ..base,
    route: AccountAccess,
    machine_access: {
      ..base.machine_access,
      now_unix_ms: key.issued_unix_ms + 1L,
    },
    api_keys: [{ ..key, revoked_unix_ms: None, }],
  }
  let masked = render(state)
  assert_true(masked.contains("********"))
  assert_true(masked.contains("aria-label=\"Reveal API key\""))
  assert_true(masked.contains("aria-label=\"Copy API key\""))
  let history = render({
    ..state,
    api_keys: [
      {
        ..key,
        display_name: "Archived key",
        revoked_unix_ms: Some(key.issued_unix_ms),
      },
      {
        ..key,
        key_id: "active-key",
        display_name: "Active key",
        revoked_unix_ms: None,
      },
    ],
  })
  assert_true(
    history.find("Active key").unwrap() < history.find("Archived key").unwrap(),
  )
  let pending = state.update(ToggleApiKeySecret(key.key_id))
  assert_eq(pending.api_key_secret_request, Some(key.key_id))
  let shown = {
    ..pending,
    api_key_secret_request: None,
    revealed_api_key: Some({
      key_id: key.key_id,
      secret: "synthetic-key-not-a-credential",
    }),
  }
  assert_true(render(shown).contains("synthetic-key-not-a-credential"))
  let hidden = shown.update(ToggleApiKeySecret(key.key_id))
  assert_true(hidden.revealed_api_key is None)
  assert_false(render(hidden).contains("synthetic-key-not-a-credential"))
  for
    next in [
      shown.update(Navigate(Overview)),
      shown.update(SelfService(SelectOrganization("other"))),
      shown.update(BeginRevokeApiKey(key.key_id)),
    ] {
    assert_true(next.revealed_api_key is None)
    assert_true(next.api_key_secret_request is None)
    assert_true(
      next.api_key_secret_generation > shown.api_key_secret_generation,
    )
  }
  let expired = {
    ..shown,
    machine_access: {
      ..shown.machine_access,
      now_unix_ms: key.expires_unix_ms,
    },
  }
  assert_false(render(expired).contains("synthetic-key-not-a-credential"))
  assert_true(
    expired.update(ToggleApiKeySecret(key.key_id)).api_key_secret_request
    is None,
  )
}
