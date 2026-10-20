///|
test "customer login distinguishes a temporary lock from wrong password" {
  let locked = gateway_auth_refusal(
    ChineseSimplified,
    { status: 429, body: "{\"error\":\"account-temporarily-locked\"}", },
    false,
  )
  assert_true(locked.contains("暂时锁定"))
  assert_false(locked.contains("密码不正确"))
  let rejected = gateway_auth_refusal(
    ChineseSimplified,
    { status: 401, body: "{\"error\":\"invalid-credentials\"}", },
    false,
  )
  assert_true(rejected.contains("注册邮箱"))
  assert_true(rejected.contains("不要填写显示名称"))
}
