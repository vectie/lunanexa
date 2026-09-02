///|
test "enterprise portal separates customer requests from operator assignment" {
  let state = @enterprise.demo_state()
  let agreements = @enterprise.render({ ..state, route: Agreements })
  let requests = @enterprise.render({ ..state, route: LeaseRequests })
  let models = @enterprise.render({ ..state, route: Models })
  let desktop = @enterprise.render({ ..state, route: DesktopIde })
  assert_true(agreements.contains("Enterprise capacity framework"))
  assert_true(agreements.contains("Review &amp; sign"))
  assert_true(requests.contains("Submit lease request"))
  assert_true(requests.contains("Request requirements, not a specific machine"))
  assert_true(
    requests.contains("operators select and prepare the assigned DGX node"),
  )
  assert_true(requests.contains("Password is not accepted"))
  assert_true(requests.contains(">WebIDE</button>"))
  assert_true(desktop.contains("SECURE DESKTOP HANDOFF"))
  assert_true(desktop.contains("short-lived, single-use connection"))
  assert_false(desktop.contains("href=\"/workbench/\""))
  assert_true(models.contains("Shared model catalog"))
  assert_true(models.contains("Managed centrally"))
  assert_false(models.contains("/data/models"))
  assert_true(models.contains("Usage &amp; costs"))
  assert_true(models.contains("aria-current=\"page\""))
  assert_true(models.contains("prefers-reduced-motion:reduce"))
}

///|
test "enterprise locale control renders Chinese and preserves opaque data" {
  let state = @enterprise.demo_state()
  let chinese = state.update(LocaleChanged(ChineseSimplified))
  let html = @enterprise.render({ ..chinese, route: Models })
  assert_true(html.contains("界面语言"))
  assert_true(html.contains("共享模型目录"))
  assert_true(html.contains("中央托管"))
  assert_true(html.contains("qwen3-32b"))
  assert_true(html.contains("text.default"))
  assert_false(html.contains("/data/models"))
}

///|
test "customer notification inbox is bilingual and keeps opaque receipts" {
  let state = @enterprise.demo_state()
  let english = @enterprise.render({ ..state, route: Notifications })
  assert_true(english.contains("Notification inbox"))
  assert_true(english.contains("Machine access is ready"))
  assert_true(english.contains("Mark as read"))
  assert_true(english.contains("Delivery preferences"))
  assert_true(english.contains("Disable email"))
  assert_true(english.contains("In-app delivery always remains enabled"))
  assert_true(english.contains("exclusive-lease:demo:5"))
  assert_true(english.contains("2026-08-09 23:30:00 UTC"))
  assert_false(english.contains(">1786318200000<"))
  let chinese = @enterprise.render({
    ..state,
    route: Notifications,
    locale: ChineseSimplified,
  })
  assert_true(chinese.contains("通知收件箱"))
  assert_true(chinese.contains("机器访问已就绪"))
  assert_true(chinese.contains("标记为已读"))
  assert_true(chinese.contains("投递偏好"))
  assert_true(chinese.contains("关闭邮件"))
  assert_true(chinese.contains("exclusive-lease:demo:5"))
}

///|
test "enterprise machine route shows safe live access without topology" {
  let state = @enterprise.demo_state()
  let english = @enterprise.render({ ..state, route: MachineAccess })
  assert_true(english.contains("My machine access"))
  assert_true(english.contains("assigned-machine:exclusive-lease-demo"))
  assert_true(english.contains("End access early"))
  assert_false(english.contains("node_id"))
  assert_false(english.contains("access_credential_ref"))
  let chinese = @enterprise.render({
    ..state,
    route: MachineAccess,
    locale: ChineseSimplified,
  })
  assert_eq(state.machine_access.locale, English)
  assert_true(chinese.contains("我的机器访问"))
  assert_true(chinese.contains("已就绪"))
  assert_true(chinese.contains("提前结束访问"))
  assert_false(chinese.contains("My machine access"))
  assert_false(chinese.contains(">Ready<"))
}

///|
test "lease form requires every bounded field" {
  let state = @enterprise.demo_state()
  assert_true(@enterprise.lease_form_valid(state))
  assert_false(@enterprise.lease_form_valid({ ..state, unix_username: "" }))
  assert_false(@enterprise.lease_form_valid({ ..state, unix_username: "root" }))
  assert_false(
    @enterprise.lease_form_valid({ ..state, unix_username: "Alice" }),
  )
  assert_false(@enterprise.lease_form_valid({ ..state, model_ids: "" }))
  assert_false(@enterprise.lease_form_valid({ ..state, loading: true }))
  let invalid = @enterprise.render({
    ..state,
    route: LeaseRequests,
    unix_username: "root",
  })
  assert_true(invalid.contains("aria-invalid=\"true\""))
  assert_true(invalid.contains("non-reserved lowercase Unix username"))
}

///|
test "customer offline order route explains evidence upload in both languages" {
  let state = @enterprise.demo_state()
  let english = @enterprise.render({ ..state, route: OfflineCommerce })
  assert_true(english.contains("Orders and offline documents"))
  assert_true(english.contains("Upload Executed contract scan"))
  let chinese = @enterprise.render({
    ..state,
    route: OfflineCommerce,
    locale: ChineseSimplified,
  })
  assert_eq(state.offline_commerce.locale, English)
  assert_true(chinese.contains("订单与线下材料"))
  assert_true(chinese.contains("上传已盖章合同扫描件"))
}

///|
test "tenant-provided content is escaped" {
  let state = @enterprise.demo_state()
  let html = @enterprise.render({
    ..state,
    route: LeaseRequests,
    justification: "<script>alert(1)</script>",
    lease_requests: [
      {
        ..state.lease_requests[0],
        submission: {
          ..state.lease_requests[0].submission,
          justification: "<img src=x onerror=alert(1)>",
        },
      },
    ],
  })
  assert_false(html.contains("<script>alert(1)</script>"))
  assert_false(html.contains("<img src=x onerror=alert(1)>"))
  assert_true(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
}
