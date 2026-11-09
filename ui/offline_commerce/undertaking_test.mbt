///|
#warnings("-alert_unstable")
test "ended rental documents retain history without offering allocation" {
  let manifest = @contractdoc.undertaking_ofl_manifest()
  let order = {
    ..offline_order(Cancelled),
    requested_undertaking_term: Some("month"),
  }
  let packet = @contractdoc.new_packet(
    manifest,
    "ended-packet",
    "ended-packet-key",
    order.tenant_ref,
    order.organization_id,
    order.purchaser_subject_ref,
    order.order_id,
    None,
    [MasterLease],
    1000L,
  )
  let state = {
    ..@offline_commerce.default_state(ChineseSimplified, OperatorCommerce),
    orders: [order],
    contract_packets: [{ ..packet, state: Effective, }],
  }
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @offline_commerce.rental_evidence_view(state, order.order_id, None),
    )
  })
  assert_true(html.contains("已取消"))
  assert_true(html.contains("本订单不再办理开通"))
  assert_false(html.contains("检查并下发机器"))
}

///|
test "full prepayment has an explicit audited bank verification confirmation" {
  let state = @offline_commerce.demo_state(ChineseSimplified, OperatorCommerce).update(
    BeginConfirmation(
      VerifyFullPrepayment("artifact-a", "sha256:" + "a".repeat(64)),
    ),
  )
  let html = @offline_commerce.render(state)
  assert_true(html.contains("确认本订单已全额到账"))
  assert_true(html.contains("真实银行到账记录"))
  assert_true(html.contains("仅上传文件不代表付款"))
}

///|
test "operator can read scan passed originals alongside review controls" {
  let state = {
    ..@offline_commerce.demo_state(ChineseSimplified, OperatorCommerce),
    orders: [offline_order(PendingEvidenceUpload)],
    selected_order_id: Some("order-2026-001"),
    artifacts: [evidence()],
  }
  let html = @offline_commerce.render(state)
  assert_true(html.contains("下载已验证文件"))
  assert_true(html.contains("接受此文件摘要"))
  let rejected = @offline_commerce.render({
    ..state,
    artifacts: [{ ..evidence(), scan_state: ScanRejected, }],
  })
  assert_false(rejected.contains("下载已验证文件"))
  assert_false(rejected.contains("接受此文件摘要"))
  assert_false(rejected.contains("要求补正"))
}

///|
test "terminal and fulfilled orders retain evidence downloads without review actions" {
  for
    status in [
      @offline.OfflineOrderState::Cancelled,
      Expired,
      Rejected,
      Revoked,
      Fulfilled,
      FulfillmentPending,
      ReversalPending,
      ReversalManualIntervention,
    ] {
    let state = {
      ..@offline_commerce.demo_state(ChineseSimplified, OperatorCommerce),
      orders: [offline_order(status)],
      selected_order_id: Some("order-2026-001"),
      artifacts: [evidence()],
    }
    let html = @offline_commerce.render(state)
    assert_true(html.contains("下载已验证文件"))
    assert_false(html.contains("接受此文件摘要"))
    assert_false(html.contains("要求补正"))
  }
}
