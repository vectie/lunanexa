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
test "application connection reports actual status without invented progress" {
  let ready = { ..@enterprise.demo_state(), route: DesktopIde, }
  let before = @enterprise.render(ready)
  assert_true(before.contains(">Ready</p>"))
  assert_true(before.contains("Refresh model and access"))
  assert_false(before.contains("Connection progress"))
  let issuing = ready.update(LaunchDesktopClient)
  assert_true(@enterprise.render(issuing).contains("Opening Desktop WebIDE…"))
  let issued = {
    ..issuing,
    loading: false,
    desktop_connect_phase: ClientOpened,
  }
  let issued_page = @enterprise.render(issued)
  assert_true(issued_page.contains("Continue in Desktop WebIDE."))
  assert_false(issued_page.contains("aria-valuenow=\"100\""))
  guard ready.desktop_client is Some(client) else {
    fail("missing demo client")
  }
  let blocked = {
    ..ready,
    desktop_client: Some({ ..client, models_ready: false, ready: false, }),
  }
  assert_false(@enterprise.render(blocked).contains("Connection progress"))
  let refreshing = blocked.update(RefreshDesktopStatus)
  assert_true(refreshing.loading)
  assert_true(
    @enterprise.render(refreshing).contains("Checking model and access"),
  )
  assert_true(
    @enterprise.render(blocked).contains("Waiting for a serving model"),
  )
}

///|
test "personal MoonDesk exposes a stop control without stopping the shared model" {
  let base = @enterprise.demo_state()
  guard base.desktop_client is Some(client) else {
    fail("missing demo desktop")
  }
  let desktop = {
    ..client,
    client_id: "desktop-workspace",
    launch_uri: "http://198.51.100.5:5002/connect",
  }
  let state = {
    ..base,
    route: DesktopIde,
    desktop_client: Some(desktop),
    desktop_clients: [desktop],
  }
  let rendered = @enterprise.render(state)
  assert_true(
    rendered.contains("管理／停止我的 WebIDE") ||
    rendered.contains("Manage / stop my WebIDE"),
  )
  assert_eq(
    @enterprise.personal_webide_control_uri(desktop),
    Some("http://198.51.100.5:5002/workspace-control"),
  )
  assert_false(rendered.contains("target=\"_blank\""))
  let opening = state.update(
    ManageWebIde("http://198.51.100.5:5002/workspace-control"),
  )
  assert_eq(opening.success_message, Some("Opening workspace controls…"))
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
  assert_true(rendered.contains("Applications"))
  assert_true(rendered.contains("ComfyUI"))
  assert_true(rendered.contains("aria-pressed=\"true\""))
  assert_false(rendered.contains("Open ComfyUI</button>"))
  assert_true(rendered.contains("Set up a GPU workspace below"))
  assert_false(rendered.contains("One-click connection"))
  assert_false(rendered.contains("href=\"https://creative.example/connect"))
  assert_true(selected.update(SelectWebIde("unregistered")) == selected)
  let loading = { ..selected, loading: true, }
  assert_true(loading.update(SelectWebIde(desktop.client_id)) == loading)
  let chinese = @enterprise.render(
    selected.update(LocaleChanged(ChineseSimplified)),
  )
  assert_true(chinese.contains("应用"))
  assert_true(chinese.contains("请先在下方配置 GPU 工作区"))
}

///|
test "MoonRobo is a selectable personal WebIDE with its own controls" {
  let demo = @enterprise.demo_state()
  guard demo.desktop_client is Some(desktop) else {
    fail("missing demo client")
  }
  let robo = {
    ..desktop,
    client_id: "moonrobo",
    display_name: "MoonRobo",
    launch_uri: "https://robot.example/connect",
    ready: true,
  }
  let selected = {
    ..demo,
    route: DesktopIde,
    desktop_clients: [desktop, robo],
  }.update(SelectWebIde("moonrobo"))
  assert_eq(selected.desktop_client, Some(robo))
  assert_true(@enterprise.webide_launch_selection(selected) is Some(_))
  let rendered = @enterprise.render(selected)
  assert_true(rendered.contains("Open MoonRobo"))
  assert_true(rendered.contains("Continue working in MoonRobo"))
  assert_true(rendered.contains("Manage / stop my WebIDE"))
  assert_eq(
    @enterprise.personal_webide_control_uri(robo),
    Some("https://robot.example/workspace-control"),
  )
  assert_false(rendered.contains("ComfyUI needs an active GPU delivery"))
}

///|
test "MoonTown is a selectable personal WebIDE with a named launch and stop path" {
  let demo = @enterprise.demo_state()
  guard demo.desktop_client is Some(desktop) else {
    fail("missing demo client")
  }
  let town = {
    ..desktop,
    client_id: "moontown",
    display_name: "MoonTown",
    launch_uri: "https://platform.example/moontown/connect",
    ready: true,
  }
  let selected = {
    ..demo,
    route: DesktopIde,
    desktop_clients: [desktop, town],
  }.update(SelectWebIde("moontown"))
  assert_eq(selected.desktop_client, Some(town))
  assert_true(@enterprise.webide_launch_selection(selected) is Some(_))
  let rendered = @enterprise.render(selected)
  assert_true(rendered.contains("Open MoonTown"))
  assert_true(rendered.contains("Continue working in MoonTown"))
  assert_true(rendered.contains("Manage / stop my WebIDE"))
  assert_eq(
    @enterprise.personal_webide_control_uri(town),
    Some("https://platform.example/moontown/workspace-control"),
  )
}

///|
test "legacy shared local MoonDesk cannot issue another user's one-click launch" {
  let demo = @enterprise.demo_state()
  guard demo.desktop_client is Some(client) else { fail("missing demo client") }
  let legacy = { ..client, launch_uri: "http://127.0.0.1:4188/?mode=mooncode", }
  let state = { ..demo, route: DesktopIde, desktop_client: Some(legacy), }
  assert_true(@enterprise.webide_launch_selection(state) is None)
  let page = @enterprise.render(state.update(LocaleChanged(ChineseSimplified)))
  assert_true(page.contains("MoonDesk 访问已暂停"))
  assert_true(page.contains("已保存的文件仍保留"))
  assert_true(page.contains("disabled>打开"))
}

///|
test "exclusive ComfyUI is launched only from a delivery and shared local desktop is blocked" {
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
  assert_true(rendered.contains("Set up a GPU workspace below"))
  assert_false(rendered.contains("Open ComfyUI</button>"))
  let chinese = @enterprise.render(
    selected.update(LocaleChanged(ChineseSimplified)),
  )
  assert_true(chinese.contains("请先在下方配置 GPU 工作区"))
  assert_true(chinese.contains("专属应用工作区"))
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
    @enterprise.render(local_state).contains("MoonDesk access is paused"),
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

///|
test "MoonDesk model picker separates trial Qwen from dedicated GLM and blocks offline launch" {
  let demo = @enterprise.demo_state()
  guard demo.desktop_client is Some(client) else {
    fail("missing demo desktop")
  }
  let desktop = {
    ..client,
    client_id: "desktop-workspace",
    display_name: "MoonDesk",
    launch_uri: "https://example.test/moondesk/connect",
    approved_model_aliases: ["text.qwen", "glm-5.3"],
  }
  let slot : @enterprise.SharedTrialSlotOption = {
    node_id: "spark-trial-b",
    node_label: "Spark trial 2",
    model_alias: "text.qwen",
    model_name: "Qwen3.8-27B",
    kind: "Text",
    node_online: true,
    service_responding: false,
    public_url: "",
    shared: true,
    request_limit: "none",
  }
  let state = {
    ..demo,
    route: DesktopIde,
    desktop_client: Some(desktop),
    desktop_clients: [desktop],
    deliveries: {
      ..demo.deliveries,
      options: { ..demo.deliveries.options, shared_trials: [slot], },
      external_model: Some({
        model_alias: "glm-5.3",
        state: "Stopped",
        can_stop: false,
        ready: false,
        context_window_tokens: None,
      }),
    },
  }
  let rendered = @enterprise.render(state)
  assert_true(rendered.contains("Trial · Qwen3.8-27B · unavailable"))
  assert_true(rendered.contains("Dedicated · glm-5.3 · unavailable"))
  assert_true(rendered.contains("MoonGate usage for my MoonDesk"))
  assert_true(rendered.contains("Open live MoonGate statistics"))
  assert_false(rendered.contains("<iframe"))
  assert_true(
    rendered.contains(
      "https://example.test/moondesk/api/desktop/moongate-stats/view",
    ),
  )
  let qwen = state.update(SelectWebIdeOrder("model:text.qwen"))
  assert_eq(qwen.webide_model_alias, Some("text.qwen"))
  assert_eq(@enterprise.webide_launch_selection(qwen), None)
  let glm = state.update(SelectWebIdeOrder("model:glm-5.3"))
  assert_eq(glm.webide_model_alias, Some("glm-5.3"))
  assert_eq(@enterprise.webide_launch_selection(glm), None)
  assert_eq(
    state.update(SelectWebIdeOrder("model:other")).webide_model_alias,
    None,
  )
  let ready = {
    ..state,
    deliveries: {
      ..state.deliveries,
      options: {
        ..state.deliveries.options,
        shared_trials: [{ ..slot, service_responding: true, }],
      },
    },
  }.update(SelectWebIdeOrder("model:text.qwen"))
  assert_eq(
    @enterprise.webide_launch_selection(ready),
    Some((None, demo.project_id, ["text.qwen"])),
  )
}
