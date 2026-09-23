///|
test "inactive workspace does not claim a prepared lease is waiting for activation" {
  let demo = @enterprise.demo_state()
  guard demo.desktop_client is Some(client) else { fail("missing demo client") }
  let inactive = {
    ..client,
    ready: false,
    workspace_ready: false,
    blocker_codes: ["ActiveWorkspaceLeaseRequired"],
  }
  let state = {
    ..demo,
    route: DesktopIde,
    desktop_client: Some(inactive),
    desktop_clients: [inactive],
  }
  let english = @enterprise.render(state)
  assert_true(english.contains("expired, or revoked"))
  assert_false(english.contains("Waiting for operator enablement"))
  let chinese = @enterprise.render(
    state.update(LocaleChanged(ChineseSimplified)),
  )
  assert_true(chinese.contains("已到期或已撤销"))
  assert_false(chinese.contains("等待运维人员启用"))
}

///|
test "ComfyUI is selectable beside code WebIDE without weakening readiness" {
  let demo = @enterprise.demo_state()
  guard demo.desktop_client is Some(desktop) else {
    fail("missing demo client")
  }
  let comfy = {
    ..desktop,
    client_id: "comfyui",
    display_name: "ComfyUI",
    launch_uri: "https://creative.example/connect",
    ready: false,
    models_ready: false,
    approved_model_aliases: [],
    blocker_codes: ["ApprovedModelRequired"],
  }
  let state = { ..demo, route: DesktopIde, desktop_clients: [desktop, comfy], }
  let selected = state.update(SelectWebIde("comfyui"))
  assert_eq(selected.desktop_client, Some(comfy))
  let rendered = @enterprise.render(selected)
  assert_true(rendered.contains("Choose your WebIDE"))
  assert_true(rendered.contains("ComfyUI"))
  assert_true(rendered.contains("aria-pressed=\"true\""))
  assert_true(rendered.contains("disabled>Open ComfyUI"))
  assert_true(rendered.contains("No model alias is ready yet"))
  assert_false(rendered.contains("href=\"https://creative.example/connect"))
  assert_true(selected.update(SelectWebIde("unregistered")) == selected)
  let loading = { ..selected, loading: true, }
  assert_true(loading.update(SelectWebIde(desktop.client_id)) == loading)
  let chinese = @enterprise.render(
    selected.update(LocaleChanged(ChineseSimplified)),
  )
  assert_true(chinese.contains("选择 WebIDE"))
  assert_true(chinese.contains("打开 ComfyUI"))
}

///|
test "exclusive ComfyUI is launched only from a delivery and loopback WebIDE explains local app" {
  let demo = @enterprise.demo_state()
  guard demo.desktop_client is Some(desktop) else {
    fail("missing demo client")
  }
  let comfy = {
    ..desktop,
    client_id: "comfyui",
    display_name: "ComfyUI",
    launch_uri: "https://creative.example/connect",
    ready: true,
  }
  let selected = {
    ..demo,
    route: DesktopIde,
    desktop_clients: [desktop, comfy],
  }.update(SelectWebIde("comfyui"))
  assert_eq(@enterprise.webide_launch_selection(selected), None)
  let rendered = @enterprise.render(selected)
  assert_true(
    rendered.contains("workspace lease alone does not reserve a machine"),
  )
  assert_true(rendered.contains("disabled>Open ComfyUI"))
  let chinese = @enterprise.render(
    selected.update(LocaleChanged(ChineseSimplified)),
  )
  assert_true(chinese.contains("仅有工作区租约不会预留机器"))
  assert_true(chinese.contains("通用 WebIDE 交接无法启动它"))
  let local_desktop = {
    ..desktop,
    launch_uri: "http://127.0.0.1:4188/connect",
    ready: true,
  }
  let local_state = {
    ..demo,
    route: DesktopIde,
    desktop_client: Some(local_desktop),
  }
  assert_true(
    @enterprise.render(local_state).contains(
      "loopback address is not a public website",
    ),
  )
}

///|
test "WebIDE labels remain escaped and selecting a client clears old notices" {
  let demo = @enterprise.demo_state()
  guard demo.desktop_client is Some(desktop) else {
    fail("missing demo client")
  }
  let other = {
    ..desktop,
    client_id: "other",
    display_name: "<script>bad</script>",
  }
  let state = {
    ..demo,
    route: DesktopIde,
    desktop_clients: [desktop, other],
    success_message: Some("old connection"),
  }
  let selected = state.update(SelectWebIde("other"))
  assert_eq(selected.success_message, None)
  assert_false(@enterprise.render(selected).contains("<script>bad</script>"))
}

///|
test "paid WebIDE selection pins project and model and never silently falls back" {
  let demo = @enterprise.demo_state()
  let order : @enterprise.SelfServiceOrderView = {
    order_id: "paid-endpoint-a",
    kind: DedicatedMaaS,
    status: ActiveOrder,
    project_id: "paid-project",
    gpu_sku: "DGX Spark",
    region: "test",
    duration_hours: 24,
    model_selector: Some("text.default"),
    display_amount: "prepaid",
    lease_ref: None,
    deployment_ref: Some("paid-deployment"),
    generation: 1L,
    updated_unix_ms: 100L,
  }
  let state = {
    ..demo,
    route: DesktopIde,
    self_service: { ..demo.self_service, orders: [order], order: Some(order), },
  }.update(SelectWebIdeOrder(order.order_id))
  assert_eq(
    @enterprise.webide_launch_selection(state),
    Some((Some(order.order_id), "paid-project", ["text.default"])),
  )
  let rendered = @enterprise.render(state)
  assert_eq(rendered.split("value=\"paid-endpoint-a\"").count(), 2)
  let terminated = {
    ..state,
    self_service: {
      ..state.self_service,
      orders: [{ ..order, status: TerminatedOrder, updated_unix_ms: 101L, }],
    },
  }
  assert_eq(@enterprise.webide_launch_selection(terminated), None)
  assert_true(@enterprise.render(terminated).contains("no shared fallback"))
  assert_true(
    @enterprise.render(terminated).contains("disabled>Open Desktop WebIDE"),
  )
  let missing = state.update(SelectWebIdeOrder("missing-order"))
  assert_eq(@enterprise.webide_launch_selection(missing), None)
  assert_true(
    @enterprise.webide_launch_selection(missing.update(SelectWebIdeOrder("")))
    is Some((None, _, _)),
  )
}
