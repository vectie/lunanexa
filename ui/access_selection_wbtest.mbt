///|
test "registered access review requires a live operator, active account and approved organization" {
  let base = demo_state()
  let state = {
    ..base,
    operator_authenticated: true,
    registered_access_account: base.accounts[0].account_id,
    accounts: [{ ..base.accounts[0], roles: [EnterpriseUser], state: Active, }],
  }
  assert_true(registered_access_ready(state))
  assert_false(
    registered_access_ready({ ..state, operator_authenticated: false, }),
  )
  assert_false(registered_access_ready({ ..state, access_organizations: [], }))
  assert_false(
    registered_access_ready({
      ..state,
      registered_access_account: "unknown-person",
    }),
  )
  assert_false(
    registered_access_ready({
      ..state,
      accounts: [{ ..state.accounts[0], state: Suspended, }],
    }),
  )
}
