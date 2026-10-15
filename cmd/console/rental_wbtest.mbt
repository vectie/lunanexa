///|
test "management rental handoffs select the same order and clear stale node confirmation" {
  let base = deferred_read_test_model(OfflineCommerce)
  let commerce = @offline_commerce.demo_state(English, OperatorCommerce)
  let order = commerce.orders[0]
  let model = {
    ..base,
    console: { ..base.console, offline_commerce: commerce, },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (documents, _) = update(
    model,
    Console(OfflineCommerce(OpenContractDocuments(order.order_id))),
    emit,
  )
  assert_eq(documents.console.route, ContractDocuments)
  assert_eq(
    documents.console.contract_documents.order_context,
    Some(order.order_id),
  )
  assert_eq(
    documents.console.contract_documents.selected_tenant_ref,
    Some(order.tenant_ref),
  )
  assert_true(documents.console_read_groups.contains(ContractReads))
  assert_true(documents.console_read_groups.contains(CommerceReads))
  let (returned, _) = update(
    documents,
    Console(ContractDocuments(OpenOrder(order.order_id))),
    emit,
  )
  assert_eq(
    returned.console.offline_commerce.selected_order_id,
    Some(order.order_id),
  )
  let stale = {
    ..returned,
    console: {
      ..returned.console,
      resource_delivery: {
        ..returned.console.resource_delivery,
        undertaking_selected_nodes: ["old-node"],
        undertaking_confirmed_idle: true,
      },
    },
  }
  let (allocation, _) = update(
    stale,
    Console(OfflineCommerce(OpenAllocation(order.order_id))),
    emit,
  )
  assert_eq(allocation.console.route, Leases)
  assert_eq(
    allocation.console.resource_delivery.selected_undertaking_order,
    order.order_id,
  )
  assert_eq(allocation.console.resource_delivery.undertaking_selected_nodes, [])
  assert_false(allocation.console.resource_delivery.undertaking_confirmed_idle)
  let (loaded, _) = update(
    allocation,
    ResourcesLoaded(
      allocation.credential,
      Ok({
        ..@ui.default_resource_delivery_panel(),
        loaded: true,
        undertaking_orders: [
          {
            order_id: order.order_id,
            organization_id: order.organization_id,
            purchaser_subject_ref: order.purchaser_subject_ref,
            node_count: 1L,
            expires_unix_ms: Some(order.expires_unix_ms),
            status: "ReadyForAllocation",
            node_ids: [],
          },
        ],
      }),
    ),
    emit,
  )
  assert_eq(
    loaded.console.resource_delivery.selected_undertaking_order,
    order.order_id,
  )
}
