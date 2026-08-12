///|
test "installer renders guarded bilingual deployment workflow" {
  let english = @installer.default_state(locale=English)
  let english_html = @installer.render(english)
  assert_true(english_html.contains("Deploy your private DGX cluster"))
  assert_true(english_html.contains("Dry-run first"))
  assert_true(english_html.contains("StrictHostKeyChecking=yes"))
  assert_true(english_html.contains("type=\"password\""))
  assert_true(english_html.contains("disabled"))
  let chinese = @installer.update(english, LocaleChanged(ChineseSimplified))
  let chinese_html = @installer.render(chinese)
  assert_true(chinese_html.contains("部署您的私有 DGX 集群"))
  assert_true(chinese_html.contains("先预检"))
  assert_true(chinese_html.contains("检查四台 DGX GPU 工作节点"))
}

///|
test "terminal keeps a bounded tail and run state is explicit" {
  let mut state = @installer.default_state(locale=English)
  state = @installer.update(state, PreviewRequested)
  assert_true(@installer.is_running(state))
  for index in 0..<510 {
    state = @installer.update(state, TerminalLine("line-\{index}"))
  }
  assert_eq(state.terminal_lines.length(), 500)
  state = @installer.update(state, RunFinished(true, 0))
  assert_false(@installer.is_running(state))
  assert_true(state.preview_verified)
  state = @installer.update(state, ManagementHostChanged("10.0.0.11"))
  assert_false(state.preview_verified)
  assert_true(@installer.render(state).contains("Completed"))
}
