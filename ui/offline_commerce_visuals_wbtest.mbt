///|
#warnings("-alert_unstable")
fn render_offline_commerce_visual(html : @rabbita.Html) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(html))
}

///|
test "offline commerce lifecycle renders typed happy and branch paths" {
  let state = demo_state()
  let html = render_offline_commerce_visual(
    offline_commerce_lifecycle_graph(state),
  )
  for
    value in [
      "Draft", "Quoted", "PendingInternalApproval", "PendingOfflineExecution", "PendingEvidenceUpload",
      "UnderReconciliation", "FulfillmentPending", "Fulfilled", "NeedsCorrection",
      "Cancelled", "Expired", "ReversalPending", "ReversalManualIntervention", "Revoked",
      "Rejected",
    ] {
    assert_true(html.contains(value))
  }
  assert_true(html.contains("Selected order"))
  assert_true(html.contains("Manual intervention"))
  assert_true(html.contains("Current"))
  assert_true(html.contains("No published constructor"))
  assert_true(html.contains("Authoritative transition table"))
  assert_true(html.contains("<figure"))
  assert_true(html.contains("<figcaption"))
  assert_true(html.contains("<table"))
}

///|
test "offline commerce lifecycle renders empty reference state" {
  let state = default_state()
  let html = render_offline_commerce_visual(
    offline_commerce_lifecycle_graph(state),
  )
  assert_true(html.contains("No order selected"))
  assert_true(html.contains("Reference map only"))
  assert_true(html.contains("Draft"))
  assert_true(html.contains("Typed terminal record"))
}

///|
test "offline commerce lifecycle localizes state and transition limits" {
  let base = demo_state()
  let commerce = @offline_commerce.demo_state(
    ChineseSimplified,
    OperatorCommerce,
  )
  let state = { ..base, locale: ChineseSimplified, offline_commerce: commerce }
  let html = render_offline_commerce_visual(
    offline_commerce_lifecycle_graph(state),
  )
  for
    value in [
      "线下商务生命周期", "当前订单", "撤销需人工处理", "补正循环",
      "权益撤销", "权威转换表", "当前后端未发布进入此状态的转换构造器",
    ] {
    assert_true(html.contains(value))
  }
  assert_true(html.contains("ReversalManualIntervention"))
}

///|
test "offline commerce lifecycle escapes hostile current order evidence" {
  let hostile = "<img src=x onerror=alert(1)>"
  let base = demo_state()
  let commerce = base.offline_commerce
  let order = commerce.orders[0]
  let hostile_commerce = {
    ..commerce,
    orders: [{ ..order, order_id: hostile }],
    selected_order_id: Some(hostile),
  }
  let html = render_offline_commerce_visual(
    offline_commerce_lifecycle_graph({
      ..base,
      offline_commerce: hostile_commerce,
    }),
  )
  assert_false(html.contains(hostile))
  assert_false(html.contains("<img"))
  assert_true(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
  assert_true(html.contains("ReversalManualIntervention"))
}

///|
test "offline commerce lifecycle styles remain responsive and non-color-only" {
  let styles = offline_commerce_visual_styles()
  assert_true(styles.contains("@media(max-width:64rem)"))
  assert_true(styles.contains("@media(max-width:40rem)"))
  assert_true(styles.contains("@media(forced-colors:active)"))
  assert_true(styles.contains(".offline-life-current-marker"))
  assert_true(styles.contains("border-style:dashed"))
}
