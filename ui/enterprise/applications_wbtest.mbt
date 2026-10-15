///|
#warnings("-alert_unstable")
test "application launcher keeps all four branded cards when a profile is unavailable" {
  let base = demo_state()
  let desktop = base.desktop_client.unwrap()
  let state = { ..base, route: DesktopIde, desktop_clients: [desktop], }
  let cards = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(application_cards(state, None))
  })
  assert_eq(cards.split("<article ").to_array().length(), 5)
  for
    (name, logo) in [
      ("ComfyUI", "comfyui"),
      ("MoonDesk", "moondesk"),
      ("MoonRobo", "moonrobo"),
      ("MoonTown", "moontown"),
    ] {
    assert_true(cards.contains("<h3>\{name}</h3>"))
    assert_true(cards.contains("src=\"./apps/\{logo}.svg\""))
    assert_true(cards.contains("alt=\"\{name} logo\""))
  }
  assert_true(cards.contains("Open MoonDesk"))
  assert_false(cards.contains("Open MoonRobo"))
  assert_true(cards.contains("Not configured"))
  assert_true(cards.contains("disabled"))
  let robo = { ..desktop, client_id: "moonrobo", display_name: "MoonRobo", }
  let configured = render({ ..state, desktop_clients: [desktop, robo], })
  assert_true(configured.contains("Open MoonRobo"))
  let busy = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(application_cards({ ..state, loading: true, }, None))
  })
  assert_eq(busy.split(" disabled").to_array().length(), 5)
}

///|
#warnings("-alert_unstable")
test "switching to a trial video app clears an incompatible reserved model and order" {
  let base = demo_state()
  let comfy = {
    ..base.desktop_client.unwrap(),
    client_id: "comfyui",
    display_name: "ComfyUI",
    launch_uri: "https://platform.example/comfyui/connect",
    approved_model_aliases: ["video.shared"],
  }
  let state = {
    ..base,
    route: DesktopIde,
    desktop_clients: [base.desktop_client.unwrap(), comfy],
    webide_order_id: Some("reserved-text-order"),
    webide_model_alias: Some("text.private"),
  }
  let selected = state.update(OpenApplication("comfyui"))
  assert_eq(selected.webide_order_id, None)
  assert_eq(selected.webide_model_alias, None)
  assert_eq(
    webide_launch_selection(selected),
    Some((None, base.project_id, ["video.shared"])),
  )
  let cards = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(application_cards(state, None))
  })
  assert_true(cards.contains("Open ComfyUI"))
}

///|
test "hosted ComfyUI launches from its card while legacy direct GPU pages require delivery" {
  let base = demo_state()
  let client = {
    ..base.desktop_client.unwrap(),
    client_id: "comfyui",
    display_name: "ComfyUI",
    launch_uri: "https://platform.example/comfyui/connect",
  }
  let hosted = {
    ..base,
    route: DesktopIde,
    desktop_client: Some(client),
    desktop_clients: [client],
  }
  assert_true(webide_launch_selection(hosted) is Some(_))
  assert_eq(
    personal_webide_control_uri(client),
    Some("https://platform.example/comfyui/workspace-control"),
  )
  let page = render(hosted)
  assert_true(page.contains("Open ComfyUI"))
  assert_false(page.contains("Set up a GPU workspace below"))
  let legacy = {
    ..hosted,
    desktop_client: Some({ ..client, launch_uri: "http://198.51.100.1:5005/", }),
  }
  assert_true(webide_launch_selection(legacy) is None)
  let revoked = {
    ..hosted,
    desktop_client: Some({ ..client, ready: false, workspace_ready: false, }),
  }
  assert_true(webide_launch_selection(revoked) is None)
  assert_false(render(revoked).contains("Set up a GPU workspace below"))
}

///|
#warnings("-alert_unstable")
test "a shared ComfyUI outage never launches a reserved GPU delivery" {
  let base = demo_state()
  let client = {
    ..base.desktop_client.unwrap(),
    client_id: "comfyui",
    display_name: "ComfyUI",
    launch_uri: "https://platform.example/comfyui/connect",
    ready: false,
    models_ready: false,
    approved_model_aliases: [],
  }
  let state = {
    ..base,
    desktop_client: Some(client),
    desktop_clients: [client],
    deliveries: {
      ..base.deliveries,
      options: {
        ..base.deliveries.options,
        templates: [
          {
            template_id: "h3",
            template_version: "1",
            kind: "Workspace",
            label: "H3",
            model_selector: "video.h3",
            client_id: Some("comfyui"),
          },
        ],
      },
      operations: [
        {
          operation_id: "reserved-delivery",
          project_id: base.project_id,
          kind: "Workspace",
          template_id: "h3",
          template_version: "1",
          node_count: 2,
          stage: "Ready",
          generation: 1L,
          cache_hit: true,
          transferred_bytes: 0L,
          total_bytes: None,
          failure_code: None,
          expires_at_ms: 9223372036854775807L,
          can_manage: true,
        },
      ],
    },
  }
  let cards = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(application_cards(state, None))
  })
  assert_false(cards.contains("Open ComfyUI"))
  assert_true(cards.contains("Configure ComfyUI"))
}
