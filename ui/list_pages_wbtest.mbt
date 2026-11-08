///|
test "pagination filters before slicing and clamps after refresh shrinks the list" {
  let base = default_state()
  let values = [ for i in 0..<61 => "person-\{i}" ]
  let first = paged_rows(base, Accounts, values, value => value)
  assert_eq(first.rows.length(), 25)
  assert_eq(first.total, 61)
  let setting : Map[OperatorList, ListPage] = Map([
    (Accounts, { query: "", page: 2, }),
  ])
  let last = paged_rows({ ..base, list_pages: setting, }, Accounts, values, fn(
    value,
  ) {
    return value
  })
  assert_eq(last.rows, values[50:].to_owned())
  let shrunk = paged_rows(
    { ..base, list_pages: setting, },
    Accounts,
    values[:10].to_owned(),
    value => value,
  )
  assert_eq(shrunk.page, 0)
  assert_eq(shrunk.rows.length(), 10)
  let searched = paged_rows(
    {
      ..base,
      list_pages: Map([(Accounts, { query: "  PERSON-60  ", page: 99, })]),
    },
    Accounts,
    values,
    value => value,
  )
  assert_eq(searched.rows, ["person-60"])
  assert_eq(searched.page, 0)
  let empty = paged_rows({ ..base, list_pages: setting, }, Accounts, [], (
    value : String,
  ) => value)
  assert_eq(empty.page, 0)
  assert_eq(empty.pages, 1)
  assert_eq(empty.total, 0)
  assert_eq(values.length(), 61)
}

///|
test "lists retain independent pagination and render at most one page of accounts" {
  let base = demo_state()
  let account = base.accounts[0]
  let accounts = [
    for i in 0..<61 => {
      {
        ..account,
        account_id: "paged-account-\{i}",
        display_name: "Person \{i}",
      }
    }
  ]
  let state = {
    ..base,
    route: Users,
    accounts,
    list_pages: Map([(Accounts, { query: "", page: 1, })]),
  }
  let html = render(state)
  assert_true(html.contains("Person 25"))
  assert_false(html.contains("<strong>Person 0</strong>"))
  assert_false(html.contains("<strong>Person 50</strong>"))
  let grants = paged_rows(state, AccessGrants, ["one", "two"], value => value)
  assert_eq(grants.page, 0)
}
