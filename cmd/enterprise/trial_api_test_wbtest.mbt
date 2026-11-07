///|
test "API smoke test reports actual content and metered usage only on success" {
  let result : TrialApiTestResult = {
    ok: true,
    status: 200,
    elapsed_ms: 1234,
    input_tokens: 18,
    output_tokens: 25,
    content: "帮助团队整理需求。",
  }
  guard trial_api_test_summary(result, ChineseSimplified) is Ok(text) else {
    fail("expected success")
  }
  assert_true(text.contains("1234"))
  assert_true(text.contains("18 / 输出 25"))
  assert_true(
    trial_api_test_summary({ ..result, content: "", }, ChineseSimplified)
    is Err(_),
  )
  assert_true(
    trial_api_test_summary(
      { ..result, ok: false, status: 401, },
      ChineseSimplified,
    )
    is Err(_),
  )
}
