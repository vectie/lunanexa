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

///|
test "access inspection renders only the selected person" {
  let base = demo_state()
  let first = base.access_packages[0]
  let other = {
    ..first,
    account_id: "another-person",
    package_id: "other-package-evidence",
  }
  let state = { ..base, route: Users, access_packages: [first, other], }
  let initial = render(state)
  assert_false(initial.contains(first.package_id))
  assert_false(initial.contains(other.package_id))
  let selected = render({ ..state, access_record_account: first.account_id, })
  assert_true(selected.contains(first.package_id))
  assert_false(selected.contains(other.package_id))
}
