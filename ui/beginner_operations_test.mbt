///|
test "trial aggregate has explicit unavailable and no revenue claim" {
  let base = { ..@ui.default_state(), route: Users, }
  let unavailable = @ui.render(base)
  assert_true(unavailable.contains("Trial statistics unavailable"))
  let rendered = @ui.render({
    ..base,
    trial_summary: Some({
      registered_trials: 12,
      active_trials: 3,
      expired_trials: 5,
      converted_trials: 4,
    }),
  })
  assert_true(rendered.contains("Registered trials"))
  assert_true(rendered.contains("Converted trials"))
  assert_true(rendered.contains("not payment or revenue"))
  assert_false(rendered.contains("Trial statistics unavailable"))
  let chinese = @ui.render({ ..base, locale: ChineseSimplified, })
  assert_true(chinese.contains("试用统计暂不可用"))
}

///|
test "announcement draft validation and escaped tenant-scoped form" {
  let empty = @ui.empty_announcement_draft()
  assert_false(@ui.announcement_ready(empty))
  let draft : @ui.AnnouncementDraft = {
    announcement_id: "notice-1",
    tenant_ref: "tenant-1",
    title: "Maintenance",
    body: "Model catalog refresh tomorrow.",
    expires_unix_ms: "1800000000000",
  }
  assert_true(@ui.announcement_ready(draft))
  assert_false(
    @ui.announcement_ready({ ..draft, expires_unix_ms: "tomorrow", }),
  )
  assert_false(@ui.announcement_ready({ ..draft, body: "x".repeat(257), }))
  let rendered = @ui.render({
    ..@ui.default_state(),
    route: Alerts,
    announcement_draft: { ..draft, title: "<script>bad</script>", },
  })
  assert_true(rendered.contains("Publish platform announcement"))
  assert_true(rendered.contains("one tenant only"))
  assert_false(rendered.contains("<script>bad</script>"))
  assert_true(rendered.contains("&lt;script&gt;"))
}
