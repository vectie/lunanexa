///|
test "mobile navigation closes after choosing a page" {
  let base = demo_state()
  assert_false(base.navigation_open)
  let expanded = base.update(ToggleNavigation)
  assert_true(expanded.navigation_open)
  assert_true(render(expanded).contains("aria-expanded=\"true\""))
  let selected = expanded.update(Navigate(AccountAccess))
  assert_eq(selected.route, AccountAccess)
  assert_false(selected.navigation_open)
}

///|
test "inactive key history stays collapsed and excludes retained secrets" {
  let base = demo_state()
  let active = {
    ..base.api_keys[0],
    key_id: "key-current",
    display_name: "Current integration",
    maximum_requests: 0L,
  }
  let old = {
    ..active,
    key_id: "key-revoked",
    display_name: "Old integration",
    revoked_unix_ms: Some(1L),
  }
  let html = render({
    ..base,
    route: AccountAccess,
    api_keys: [old, active],
    revealed_api_key: Some({
      key_id: old.key_id,
      secret: "retained-secret-must-not-render",
    }),
  })
  assert_true(html.contains("<summary>Inactive keys (1)</summary>"))
  assert_true(html.contains("Current integration"))
  assert_true(html.contains("Old integration"))
  assert_false(html.contains("retained-secret-must-not-render"))
  assert_true(
    html.find("Current integration").unwrap() <
    html.find("Inactive keys (1)").unwrap(),
  )
}
