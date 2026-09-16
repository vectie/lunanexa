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
}
