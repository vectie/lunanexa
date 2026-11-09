///|
test "operator application handoffs retain user tenant and lease and clear stale node decisions" {
  let base = deferred_read_test_model(Users)
  let fixture = @ui.demo_state()
  let first = fixture.access_packages[0]
  let item = {
    ..first,
    organization_id: "requested-organization",
    tenant_ref: "requested-tenant",
    lease_id: Some("requested-lease"),
    models_ready: false,
    ready: false,
  }
  let model = {
    ..base,
    console: {
      ..base.console,
      access_packages: [first, item],
      access_record_account: first.account_id,
      resource_delivery: {
        ..base.console.resource_delivery,
        selected_nodes: ["previous-node"],
        confirmed_idle: true,
      },
    },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  assert_true(@ui.render(model.console).contains("Manage GPU resources"))
  assert_true(@ui.render(model.console).contains("View model deployments"))
  assert_false(@ui.render(model.console).contains("Deploy a serving model"))
  let (contracts, _) = update(
    model,
    Console(
      OpenAccessStep(item.account_id, item.organization_id, ContractDocuments),
    ),
    emit,
  )
  assert_eq(contracts.console.route, ContractDocuments)
  assert_eq(
    contracts.console.access_package_context,
    Some((item.account_id, item.organization_id)),
  )
  assert_eq(
    contracts.console.contract_documents.selected_tenant_ref,
    Some(item.tenant_ref),
  )
  assert_eq(contracts.console.contract_documents.order_context, None)
  let (deployments, _) = update(
    contracts,
    Console(OpenAccessStep(item.account_id, item.organization_id, Deployments)),
    emit,
  )
  assert_eq(deployments.console.route, Deployments)
  assert_eq(
    deployments.console.access_package_context,
    Some((item.account_id, item.organization_id)),
  )
  assert_true(@ui.render(deployments.console).contains("Back to user access"))
  assert_true(@ui.render(deployments.console).contains("Clear user context"))
  assert_true(deployments.console.model_pool == contracts.console.model_pool)
  assert_eq(deployments.console.deployments, contracts.console.deployments)
  let (resources, _) = update(
    deployments,
    Console(OpenAccessStep(item.account_id, item.organization_id, Leases)),
    emit,
  )
  assert_eq(
    resources.console.resource_delivery.selected_lease,
    item.lease_id.unwrap() + ":" + item.organization_id,
  )
  assert_eq(resources.console.resource_delivery.selected_nodes, [])
  assert_false(resources.console.resource_delivery.confirmed_idle)
  let page = @ui.render(resources.console)
  assert_false(page.contains("Undertaking allocation"))
  assert_true(page.contains(item.display_name))
  let (returned, _) = update(
    resources,
    Console(OpenAccessStep(item.account_id, item.organization_id, Users)),
    emit,
  )
  assert_eq(returned.console.route, Users)
  assert_eq(
    returned.console.access_package_context,
    Some((item.account_id, item.organization_id)),
  )
  assert_true(returned.console_read_groups.contains(AccessReads))
  let (unknown, _) = update(
    model,
    Console(OpenAccessStep("unknown-user", item.organization_id, Leases)),
    emit,
  )
  assert_true(unknown.console == model.console)
}
