///|
test "resource chooser hides memory-pressured and unmeasured Sparks" {
  let ready = {
    ..demo_state().nodes[0],
    memory_measured: true,
    total_memory_mib: 122880,
    free_memory_mib: 100000,
    workloads: 0,
  }
  assert_true(resource_node_selectable(ready, [], true))
  assert_true(resource_node_selectable(ready, [], false))
  assert_false(
    resource_node_selectable({ ..ready, usage_pool: "trial", }, [], true),
  )
  assert_true(
    resource_node_selectable({ ..ready, usage_pool: "trial", }, [], false),
  )
  assert_false(
    resource_node_selectable({ ..ready, free_memory_mib: 20000, }, [], true),
  )
  assert_false(
    resource_node_selectable({ ..ready, memory_measured: false, }, [], false),
  )
  assert_false(
    resource_node_selectable({ ..ready, free_memory_mib: 60000, }, [], true),
  )
  assert_true(
    resource_node_selectable({ ..ready, free_memory_mib: 60000, }, [], false),
  )
  assert_eq(
    undertaking_node_unavailable_reason(@i18n.Locale::ChineseSimplified, {
      ..ready,
      usage_pool: "trial",
    }),
    "非企业专属池",
  )
  assert_eq(
    undertaking_allocation_status(
      @i18n.Locale::ChineseSimplified,
      "OrderClosed",
    ),
    "订单已关闭，需重新下单",
  )
  assert_eq(
    undertaking_allocation_status(
      @i18n.Locale::ChineseSimplified,
      "OrderTermMismatch",
    ),
    "订单授权截止早于已签租期结束；需重新下单",
  )
}

///|
test "unsigned undertaking shows a pending signed term rather than a missing order deadline" {
  let base = demo_state()
  let order : UndertakingAllocationRow = {
    order_id: "order-unsigned",
    organization_id: "organization-test",
    purchaser_subject_ref: "subject-test",
    node_count: 1L,
    expires_unix_ms: None,
    status: "AwaitingApprovalOrEvidence",
    node_ids: [],
  }
  let html = render({
    ..base,
    locale: ChineseSimplified,
    route: Leases,
    resource_delivery: {
      ..base.resource_delivery,
      loaded: true,
      undertaking_orders: [order],
      selected_undertaking_order: order.order_id,
    },
  })
  assert_true(html.contains("已签租期结束：尚未签署"))
  assert_false(html.contains("订单授权截止：—"))
}
