///|
test "remote page outcomes reject old search person and session and retain off-page choices" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let base = deferred_read_test_model(Users)
  let (searching, _) = update_live(
    base,
    Console(ListQueryChanged(Accounts, "Alice")),
    emit,
  )
  let read : OperatorPageRead = {
    kind: Accounts,
    query: operator_page_query(searching.console, Accounts),
    generation: searching.console.remote_list_pages[Accounts].generation,
    value: {
      items: [],
      total: 0,
      page: 0,
      previous_cursor: "",
      next_cursor: "",
      summary: Map([]),
    },
  }
  let (next, _) = update_live(
    searching,
    Console(ListQueryChanged(Accounts, "Bob")),
    emit,
  )
  assert_true(merge_operator_page(next.console, read) == next.console)
  let (stale_session, _) = update_live(
    searching,
    Outcome(OperatorPageLoaded("different-session", read)),
    emit,
  )
  assert_true(stale_session == searching)
  let (failed, _) = update_live(
    searching,
    Outcome(
      OperatorPageFailed(searching.credential, Accounts, read.generation, false),
    ),
    emit,
  )
  assert_true(failed.console.remote_list_pages[Accounts].failed)
  assert_false(failed.console.remote_list_pages[Accounts].loading)
  let (retrying, _) = update_live(
    failed,
    Console(ListPageChanged(Accounts, 0)),
    emit,
  )
  assert_true(retrying.console.remote_list_pages[Accounts].loading)
  let (person_a, _) = update_live(
    base,
    Console(AccessRecordAccountChanged("person-a")),
    emit,
  )
  let person_read = {
    ..read,
    kind: AccessRecords,
    query: operator_page_query(person_a.console, AccessRecords),
    generation: person_a.console.remote_list_pages[AccessRecords].generation,
  }
  let (person_b, _) = update_live(
    person_a,
    Console(AccessRecordAccountChanged("person-b")),
    emit,
  )
  assert_true(
    merge_operator_page(person_b.console, person_read) == person_b.console,
  )
  let choice : @ui.AccountChoice = {
    account_id: "off-page",
    subject_ref: "subject-off",
    display_name: "Other person",
    email: "other@example.invalid",
    roles: [EnterpriseUser],
    state: Active,
  }
  let organizations = @ui.demo_state().access_organizations
  let state = {
    ..searching.console,
    account_choices: Some([choice]),
    accounts: [],
    registered_access_account: choice.account_id,
    access_package_draft: {
      ..searching.console.access_package_draft,
      organization_id: organizations[0].organization_id,
    },
    access_organizations: organizations,
  }
  assert_eq(
    @ui.account_choices(merge_operator_page(state, read))[0].account_id,
    "off-page",
  )
  assert_true(@ui.registered_access_ready(merge_operator_page(state, read)))
}

///|
test "ownership labels combine services of the same company and expose conflicting allocations" {
  let one : NodeOwnershipRead = {
    node_id: "node-a",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    display_name: "Company A",
  }
  assert_eq(node_ownership_labels([one, one])["node-a"], "Company A")
  assert_true(
    node_ownership_labels([one, { ..one, tenant_ref: "tenant-b", }, one])["node-a"].contains(
      "分配冲突",
    ),
  )
  assert_false(
    node_ownership_labels([{ ..one, tenant_ref: "", }]).contains("node-a"),
  )
}
