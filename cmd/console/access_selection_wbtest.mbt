///|
test "selecting an existing person fills their approved organization and human profile" {
  let base = deferred_read_test_model(Users)
  let state = {
    ..base,
    console: { ..@ui.demo_state(), operator_authenticated: true, },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (selected, _) = update_live(
    state,
    Console(
      RegisteredAccessAccountChanged(state.console.accounts[0].account_id),
    ),
    emit,
  )
  assert_eq(
    selected.console.access_package_draft.display_name,
    state.console.accounts[0].display_name,
  )
  assert_eq(
    selected.console.access_package_draft.email,
    state.console.accounts[0].email,
  )
  assert_false(selected.console.access_package_draft.identity_verified)
  assert_eq(selected.console.access_package_draft.identity_subject, "")
  assert_eq(
    selected.console.access_package_draft.organization_id,
    "org-northstar",
  )
  assert_eq(
    selected.console.access_package_draft.tenant_ref,
    "tenant-northstar",
  )
  let refreshed = merge_loaded_console(selected.console, @ui.default_state())
  assert_eq(
    refreshed.registered_access_account,
    selected.console.registered_access_account,
  )
  assert_true(
    refreshed.access_organizations == selected.console.access_organizations,
  )
  let undecided = {
    ..selected.console,
    access_package_draft: {
      ..selected.console.access_package_draft,
      organization_id: "",
    },
  }
  let defaults = {
    ..@ui.default_state(),
    access_package_draft: {
      ..@ui.default_state().access_package_draft,
      organization_id: "global-default",
    },
  }
  assert_eq(
    merge_loaded_console(undecided, defaults).access_package_draft.organization_id,
    "",
  )
}
