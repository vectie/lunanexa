///|
test "operator login separates permission denial from expired session and wrong password" {
  let denied = password_login_refusal(ChineseSimplified, {
    status: 403,
    body: "{\"error\":\"operator-access-denied\"}",
  })
  assert_true(denied.contains("身份验证已通过"))
  assert_true(denied.contains("没有平台运维权限"))
  assert_false(denied.contains("过期"))
  let locked = password_login_refusal(ChineseSimplified, {
    status: 429,
    body: "{\"error\":\"account-temporarily-locked\"}",
  })
  assert_true(locked.contains("暂时锁定"))
  assert_false(locked.contains("密码不正确"))
}

///|
#warnings("-alert_unstable")
test "operator denial has a customer portal exit and does not modify credential authority" {
  let base = deferred_read_test_model(Overview)
  let model = {
    ..base,
    console: { ..base.console, locale: ChineseSimplified, },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (denied, _) = update_live(
    model,
    OperatorLoginRefused(
      ChineseSimplified,
      operator_access_denied_notice(ChineseSimplified),
    ),
    emit,
  )
  assert_eq(denied.credential, model.credential)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(login_view(denied, emit))
  })
  assert_true(html.contains("href=\"/user/\""))
  assert_true(html.contains("没有平台运维权限"))
  assert_true(html.contains("注册邮箱／登录名"))
}
