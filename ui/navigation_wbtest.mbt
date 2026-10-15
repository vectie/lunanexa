///|
test "operator journeys put prerequisites before delivery and consumption" {
  for locale in [@i18n.English, ChineseSimplified] {
    let html = render({ ..demo_state(), locale, })
    assert_true(html.contains("href=\"/docs/\""))
    assert_false(
      html.contains("<span>" + route_label(locale, Blank) + "</span>"),
    )
    for
      journey in [
        [
          OperatorRoute::Nodes,
          Models,
          Benchmarks,
          QualifiedServices,
          Catalog,
          Deployments,
          Requests,
        ],
        [
          Users,
          Policies,
          Agreements,
          OfflineCommerce,
          ContractDocuments,
          Leases,
          CostCenters,
        ],
      ] {
      let mut previous = -1
      for route in journey {
        let position = html
          .find(
            "<span>" +
            route_label(locale, route).replace(old="&", new="&amp;") +
            "</span>",
          )
          .unwrap()
        assert_true(position > previous)
        previous = position
      }
    }
  }
}
