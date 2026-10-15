///|
#warnings("-alert_unstable")
test "icon commands preserve accessible names and guard pending actions" {
  let rendered = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @controls.icon_button(Refresh, "Refresh status", @rabbita.none, busy=true),
    )
  })
  assert_true(rendered.contains("aria-label=\"Refresh status\""))
  assert_true(rendered.contains("aria-busy=\"true\""))
  assert_true(rendered.contains("disabled"))
  assert_true(rendered.contains("aria-hidden=\"true\""))
  let copy = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @controls.icon_button(Copy, "Copy model alias: text.chat", @rabbita.none),
    )
  })
  assert_true(copy.contains("aria-label=\"Copy model alias: text.chat\""))
  assert_false(copy.contains("disabled"))
}

///|
#warnings("-alert_unstable")
test "advanced settings start closed and retain their field values" {
  let rendered = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @controls.advanced("Advanced", [
        @html.input(id="project", value="company-project"),
      ]),
    )
  })
  assert_true(rendered.contains("<details class=\"ln-advanced\">"))
  assert_true(rendered.contains("<summary>Advanced</summary>"))
  assert_true(rendered.contains("value=\"company-project\""))
  assert_false(rendered.contains(" open"))
}
