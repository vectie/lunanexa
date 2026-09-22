///|
test "technical waiver UI is scoped to the exact order and never offered to the customer" {
  let demo = @offline_commerce.demo_state(ChineseSimplified, OperatorCommerce)
  let order = {
    ..demo.orders[0],
    state: PendingInternalApproval,
    agreement_ref: None,
    artifact_ids: [],
    entitlement_ref: None,
  }
  let scope : @offline.TechnicalAcceptanceAuthorization = {
    order_id: order.order_id,
    purchaser_subject_ref: order.purchaser_subject_ref,
    user_authorization_ref: "explicit-test-approval",
    expires_unix_ms: 1786401000000L,
    order_binding: Some({
      organization_id: order.organization_id,
      tenant_ref: order.tenant_ref,
      quote: order.quote.unwrap(),
      entitlement_kind: WorkspaceLease,
    }),
  }
  let state = { ..demo, orders: [order], technical_authorization: Some(scope), }
  assert_true(
    @offline_commerce.render(state).contains("审阅本订单测试豁免"),
  )
  assert_false(
    @offline_commerce.render({ ..state, audience: CustomerCommerce, }).contains(
      "审阅本订单测试豁免",
    ),
  )
  assert_false(
    @offline_commerce.render({ ..state, technical_authorization: None, }).contains(
      "审阅本订单测试豁免",
    ),
  )
  assert_false(
    @offline_commerce.render({
      ..state,
      technical_authorization: Some({ ..scope, order_id: "another", }),
    }).contains("审阅本订单测试豁免"),
  )
  let confirmed = state.update(
    BeginConfirmation(
      AuthorizeTechnicalOrder(
        order.order_id,
        order.generation,
        "approved-target",
        "approved-grant",
        scope.user_authorization_ref,
        scope.expires_unix_ms,
      ),
    ),
  )
  let html = @offline_commerce.render(confirmed)
  assert_true(html.contains("未签署、未付款、非商业测试"))
  assert_true(html.contains("本操作不直接开通资源"))
  assert_true(html.contains("approved-target"))
}
