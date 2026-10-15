///|
test "enterprise prioritizes services before purchasing and administration" {
  for locale in [@i18n.English, ChineseSimplified] {
    let html = render({ ..demo_state(), locale, })
    let mut previous = -1
    for
      route in [
        EnterpriseRoute::Overview,
        MachineAccess,
        Models,
        DesktopIde,
        SelfService,
        Agreements,
        OfflineCommerce,
        ContractDocuments,
        LeaseRequests,
        AccountAccess,
        Costs,
        Notifications,
      ] {
      let position = html
        .find(
          ">" +
          route_label(locale, route).replace(old="&", new="&amp;") +
          "</button>",
        )
        .unwrap()
      assert_true(position > previous)
      previous = position
    }
    assert_true(html.contains("IaaS · "))
    assert_true(html.contains("MaaS · "))
    assert_true(html.contains("PaaS · "))
    assert_true(html.contains("href=\"/docs/\""))
  }
}

///|
test "purchase progress advances only after confirmed results" {
  let base = demo_state()
  let pending_quote = base.update(SelfService(RequestQuote))
  assert_eq(pending_quote.self_service.step, Capacity)
  assert_true(pending_quote.self_service.action_loading)
  let quote = { ..base, self_service: { ..base.self_service, step: Quote, }, }
  let pending_order = quote.update(SelfService(CreateMachineOrder))
  assert_eq(pending_order.self_service.step, Quote)
  assert_true(pending_order.self_service.action_loading)
}

///|
test "purchase back follows the steps actually visited" {
  let base = demo_state()
  let selected = base.update(SelfService(SelectProduct(BareGpu)))
  assert_eq(selected.self_service.step, Capacity)
  assert_eq(
    selected.update(SelfService(PreviousSelfServiceStep)).self_service.step,
    ChooseService,
  )
  let onboarded = {
    ..base,
    self_service: { ..default_self_service_state(), step: Organization, },
  }
  assert_eq(
    onboarded.update(SelfService(ContinueWithOrganization)).self_service.step,
    ChooseService,
  )
}

///|
test "another purchase retains the catalog and existing orders can be resumed" {
  let base = demo_state()
  let restarted = base.update(SelfService(RestartSelfService))
  assert_eq(restarted.self_service.step, ChooseService)
  assert_eq(restarted.self_service.order, None)
  assert_eq(restarted.self_service.offerings, base.self_service.offerings)
  assert_eq(restarted.self_service.terms, base.self_service.terms)
  assert_eq(restarted.self_service.project_id, base.self_service.project_id)
  let order = { ..base.self_service.order.unwrap(), status: AwaitingPayment, }
  let orders = {
    ..restarted,
    self_service: { ..restarted.self_service, orders: [order], },
  }
  let resumed = orders.update(SelfService(ResumeMachineOrder(order.order_id)))
  assert_eq(resumed.self_service.step, ContractPayment)
  assert_eq(resumed.self_service.order, Some(order))
  let agreement_page = resumed.update(Navigate(Agreements))
  assert_true(render(agreement_page).contains("Continue order"))
  let returned = agreement_page.update(Navigate(SelfService))
  assert_eq(returned.self_service.step, ContractPayment)
  assert_eq(returned.self_service.order, Some(order))
}
