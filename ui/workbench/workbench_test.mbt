///|
test "ready lease renders the dense Web IDE and client-side handoffs" {
  let html = @workbench.render(@workbench.demo_state())
  assert_true(html.contains("LunaNexa Workbench"))
  assert_true(html.contains("lease-demo-01"))
  assert_true(html.contains("src/main.mbt"))
  assert_true(html.contains("id=\"code-editor\""))
  assert_true(html.contains("workbench-shell workspace-ready"))
  assert_true(html.contains("class=\"editor-stack\""))
  assert_true(html.contains("Workspace ready"))
  assert_true(html.contains("Run with LunaNexa"))
  assert_true(html.contains("Session usage"))
  assert_true(html.contains("Send request"))
  assert_true(html.contains("Normalized output"))
  assert_true(html.contains("VS Code"))
  assert_true(html.contains("CodeBuddy"))
  assert_true(html.contains("WorkBuddy"))
  assert_true(html.contains("Trae"))
  assert_true(html.contains("Qoder"))
  assert_true(html.contains("No repository, credential, IDE agent, shell"))
}

///|
test "expired and absent leases fail closed with explicit boundaries" {
  let state = @workbench.demo_state()
  guard state.lease is Some(lease) else { fail("missing demo lease") }
  let expired = @workbench.render({
    ..state,
    lease: Some({ ..lease, state: Expired }),
  })
  let absent = @workbench.render(@workbench.default_state(state.now_unix_ms))
  assert_true(expired.contains("Your workspace is not ready"))
  assert_true(expired.contains("capacity lease has expired"))
  assert_true(expired.contains("Lease expired"))
  assert_true(expired.contains("status-pill is-danger"))
  assert_true(expired.contains("never grants a DGX login"))
  assert_false(expired.contains("id=\"code-editor\""))
  assert_true(absent.contains("scoped inference token"))
  assert_true(absent.contains("status-pill is-blocked"))
}

///|
test "draft editing is browser-local and send enters a loading state" {
  let state = @workbench.demo_state()
  let edited = state.update(DraftChanged("fn main { println(\"edited\") }"))
  assert_eq(edited.files[0].content, "fn main { println(\"edited\") }")
  let sending = edited.update(SendRequest)
  assert_true(sending.loading)
  assert_eq(sending.output_text, "")
  assert_eq(sending.receipt, "")
  assert_false(@workbench.can_send({ ..edited, files: [], active_path: "" }))
  assert_false(
    @workbench.can_send({
      ..edited,
      model_selector: "invalid alias with spaces",
    }),
  )
}

///|
test "empty, output, loading, narrow, and accessible states are rendered" {
  let base = @workbench.demo_state()
  let empty = @workbench.render({ ..base, files: [], active_path: "" })
  let output = @workbench.render({
    ..base,
    output_text: "{\"text\":\"ok\"}",
    receipt: "receipt-public-1",
    success_message: Some("Workload completed with a public receipt."),
  })
  let loading = @workbench.render({ ..base, loading: true })
  assert_true(empty.contains("No browser-local draft files"))
  assert_true(output.contains("receipt-public-1"))
  assert_true(output.contains("Workload completed with a public receipt"))
  assert_true(loading.contains("Sending canonical workload"))
  assert_true(output.contains("Skip to workspace"))
  assert_true(output.contains("aria-label=\"Project drafts\""))
  assert_true(output.contains("aria-label=\"Model request\""))
  assert_true(output.contains("Managed-node mounts: none"))
  assert_true(output.contains("class=\"sr-only\">Developer workspace"))
  assert_true(output.contains("grid-template-columns:14.5rem"))
  assert_true(output.contains("max-width:48rem"))
  assert_true(output.contains("prefers-reduced-motion:reduce"))
}

///|
test "client handoff copy preserves the managed-node boundary" {
  let selected = @workbench.demo_state().update(SelectIntegration(Trae))
  let html = @workbench.render(selected)
  assert_true(html.contains("Trae handoff requested"))
  assert_true(html.contains("Only opaque, expiring client metadata"))
  assert_true(html.contains("never install credentials, repositories, shells"))
}

///|
test "VS Code handoff uses the typed editor selection path" {
  let selected = @workbench.demo_state().update(SelectEditor(VSCode))
  assert_true(selected.selected_editor is Some(VSCode))
  assert_true(selected.selected_integration is None)
  let html = @workbench.render(selected)
  assert_true(html.contains("Prepare VS Code handoff"))
  assert_true(html.contains("VS Code handoff requested"))
  assert_true(html.contains("Only opaque, expiring client metadata"))
}

///|
test "Simplified Chinese localizes chrome without changing drafts or identifiers" {
  let locale = @i18n.parse_locale("zh-CN")
  let state = @workbench.demo_state().update(LocaleChanged(locale))
  let html = @workbench.render(state)
  assert_eq(state.locale, locale)
  assert_true(html.contains("id=\"workbench-locale\""))
  assert_true(html.contains("aria-label=\"界面语言\""))
  assert_true(html.contains("简体中文"))
  assert_true(html.contains("工作区就绪"))
  assert_true(html.contains("项目草稿"))
  assert_true(html.contains("代码编辑器"))
  assert_true(html.contains("模型别名"))
  assert_true(html.contains("客户端集成"))
  assert_true(html.contains("受管节点文件系统"))
  assert_true(html.contains("src/main.mbt"))
  assert_true(html.contains("text.default"))
  assert_true(html.contains("Hello from LunaNexa"))
  assert_true(html.contains("PingFang SC"))
  assert_true(html.contains("html[lang^=\"zh\"]"))
  let blocked = @workbench.default_state(state.now_unix_ms).update(
    LocaleChanged(locale),
  )
  let blocked_html = @workbench.render(blocked)
  assert_true(blocked_html.contains("工作区尚未就绪"))
  assert_true(blocked_html.contains("限定范围的推理令牌"))
  assert_true(blocked_html.contains("id=\"workbench-locale\""))
  let missing = state.update(SelectFile("missing.mbt"))
  assert_true(
    missing.error_message.unwrap().contains("浏览器草稿不可用"),
  )
}
