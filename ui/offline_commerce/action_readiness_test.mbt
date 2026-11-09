///|
test "quote controls follow their own blockers and ignore unrelated historical diagnostics" {
  let base = @offline_commerce.default_state(
    ChineseSimplified,
    OperatorCommerce,
  )
  let order = offline_order(Draft)
  let state = {
    ..base,
    orders: [order],
    selected_order_id: Some(order.order_id),
  }
  let blocked = @offline_commerce.render({
    ..state,
    readiness_blocker_codes: [
      "ApprovedLegalTemplatesPending", "ReadinessEvidenceExpired",
    ],
  })
  assert_true(blocked.contains("商务配置尚未就绪"))
  assert_true(blocked.contains("disabled>按承诺函价目报价"))
  assert_false(blocked.contains("请在下方确认申请档位报价"))
  let historical = @offline_commerce.render({
    ..state,
    readiness_blocker_codes: [
      "ReadinessArtifactDispatcherSuccessStale", "ReadinessOfflineWorkRetryExhausted",
      "ObjectStoragePending",
    ],
  })
  assert_false(historical.contains("商务配置尚未就绪"))
  assert_false(historical.contains("disabled>按承诺函价目报价"))
}

///|
test "draft cancellation describes only its own effect" {
  let order = offline_order(Draft)
  let state = {
    ..@offline_commerce.default_state(ChineseSimplified, CustomerCommerce),
    orders: [order],
    selected_order_id: Some(order.order_id),
  }.update(BeginConfirmation(CancelOrder(order.order_id, order.generation)))
  let html = @offline_commerce.render(state)
  assert_true(html.contains("确认取消此订单？"))
  assert_true(html.contains("历史记录保留"))
  assert_false(html.contains("结束其有效访问"))
  assert_false(html.contains("根据此证据确认"))
}
