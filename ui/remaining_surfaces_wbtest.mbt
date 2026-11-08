///|
test "large model search finds an off-page variant and opens its family and version" {
  let base = demo_state()
  let models = [
    for n in 0..<80 => {
      {
        ..base.models[0],
        model_id: "qwen3.8-variant-\{n}",
        alias_name: "alias-\{n}",
      }
    }
  ]
  let state = {
    ..base,
    route: Models,
    models,
    list_pages: Map([(ModelRegistry, { query: "variant-79", page: 0, })]),
  }
  let html = render(state)
  assert_true(html.contains("qwen3.8-variant-79"))
  assert_false(html.contains("qwen3.8-variant-78"))
  assert_true(html.contains("class=\"model-family\" open"))
  assert_true(html.contains("class=\"model-registry-group\" open"))
}

///|
test "unselected paged access records do not expand the authorization form" {
  let base = demo_state()
  let html = render({
    ..base,
    route: Users,
    access_packages: [],
    registered_access_account: "",
  })
  assert_true(
    html.contains(
      "<details class=\"access-package-panel ln-advanced\"><summary>Review and open access</summary>",
    ),
  )
  let selected = render({
    ..base,
    route: Users,
    access_packages: [],
    registered_access_account: base.accounts[0].account_id,
  })
  assert_true(
    selected.contains(
      "<details class=\"access-package-panel ln-advanced\" open>",
    ),
  )
}

///|
test "empty catalog exposes publishing and fixed company ownership outranks registered pool labels" {
  let base = demo_state()
  let empty = render({ ..base, route: Catalog, catalog_templates: [], })
  assert_true(
    empty.contains(
      "<details class=\"ln-advanced\" open><summary>Publish service template</summary>",
    ),
  )
  let node = { ..base.nodes[0], usage_pool: "trial", workloads: 0, }
  let state = {
    ..base,
    route: Nodes,
    nodes: [node],
    exclusive_node_leases: [],
    node_ownership: Map([(node.node_id, "Company allocation")]),
  }
  let html = render(state)
  assert_true(html.contains("Resource ownership"))
  assert_true(html.contains("Company allocation"))
  let (_, label, owner) = fleet_node_posture(state, node, 1000L)
  assert_eq(label, "Company allocation")
  assert_eq(owner, "Company allocation")
  let unavailable = { ..node, state: Unreachable, }
  assert_eq(fleet_node_posture(state, unavailable, 1000L).1, "Unreachable")
}
