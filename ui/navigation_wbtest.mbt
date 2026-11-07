///|
#warnings("-alert_unstable")
test "operator secondary destinations remain reachable and expand on direct navigation" {
  let routes : Array[OperatorRoute] = [
    Overview,
    Alerts,
    Nodes,
    Models,
    Deployments,
    Users,
    Catalog,
    QualifiedServices,
    Policies,
    OfflineCommerce,
    Agreements,
    ContractDocuments,
    Leases,
    CostCenters,
    Benchmarks,
    Requests,
    Audit,
  ]
  for route in routes {
    let html = @rabbita.render_to_string(() => {
      @rabbita.Val::constant(navigation(@i18n.English, route, None))
    })
    for destination in routes {
      assert_true(
        html.contains(
          route_label(@i18n.English, destination).replace(old="&", new="&amp;"),
        ),
      )
    }
    assert_eq(html.split("aria-current=\"page\"").to_array().length(), 2)
    assert_eq(
      html.contains(" open"),
      ![Overview, Alerts, Nodes, Models, Deployments, Users].contains(route),
    )
  }
}
