///|
test "search resets its page without touching other lists or the access approval draft" {
  let base = deferred_read_test_model(Users)
  let model = {
    ..base,
    console: {
      ..base.console,
      list_pages: Map([
        (@ui.OperatorList::Accounts, { query: "old", page: 4, }),
        (WorkspaceProfiles, { query: "workspace", page: 2, }),
      ]),
    },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (searched, _) = update(
    model,
    Console(ListQueryChanged(Accounts, "new")),
    emit,
  )
  assert_eq(searched.console.list_pages[Accounts].page, 0)
  assert_eq(searched.console.list_pages[WorkspaceProfiles].page, 2)
  assert_true(
    searched.console.access_package_draft == model.console.access_package_draft,
  )
  let (next, _) = update(searched, Console(ListPageChanged(Accounts, 1)), emit)
  assert_eq(next.console.list_pages[Accounts].query, "new")
  assert_eq(next.console.list_pages[Accounts].page, 1)
}
