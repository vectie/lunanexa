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
  let state = {
    ..demo,
    route: @enterprise.DesktopIde,
    desktop_clients: [desktop, comfy],
  }
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
    route: @enterprise.DesktopIde,
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
