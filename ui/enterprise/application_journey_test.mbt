///|
test "unsupported model and inactive workspace offer an actionable next step" {
  let base = @enterprise.demo_state()
  let model_name = base.model_catalog[0].alias_name.unwrap()
  let unsupported = { ..base, desktop_client: None, desktop_clients: [], }.update(
    UseModelInApplication(model_name),
  )
  let page = @enterprise.render(unsupported)
  assert_true(page.contains("No application supports this model"))
  assert_true(page.contains("Choose another model"))
  assert_false(page.contains("finish desktop integration"))
  assert_false(page.contains("Workspace access is not active"))
  let inactive = {
    ..base,
    route: DesktopIde,
    desktop_client: Some({
      ..base.desktop_client.unwrap(),
      contract_ready: true,
      workspace_ready: false,
      ready: false,
    }),
  }
  assert_true(@enterprise.render(inactive).contains("View orders"))
}

///|
test "model selection carries into applications and keys without a shared fallback" {
  let base = @enterprise.demo_state()
  let model_name = base.desktop_client.unwrap().approved_model_aliases[0]
  let selected = base.update(UseModelInApplication(model_name))
  assert_eq(selected.route, DesktopIde)
  assert_eq(selected.webide_model_alias, Some(model_name))
  assert_eq(@enterprise.webide_launch_selection(selected).unwrap().2, [
    model_name,
  ])
  let page = @enterprise.render(selected)
  assert_true(page.contains("Back to models"))
  let unavailable = { ..selected, model_catalog: [], }
  assert_true(@enterprise.webide_launch_selection(unavailable) is None)
  assert_true(
    @enterprise.render(unavailable).contains(
      "This model is no longer available",
    ),
  )
  let other_client = {
    ..selected.desktop_client.unwrap(),
    approved_model_aliases: ["different.model"],
  }
  assert_true(
    @enterprise.webide_launch_selection({
      ..selected,
      desktop_client: Some(other_client),
    })
    is None,
  )
  let all_models = selected.update(SelectWebIdeOrder(""))
  assert_eq(all_models.webide_model_alias, None)
  let key = base.update(CreateModelApiKey(model_name))
  assert_eq(key.route, Models)
  assert_true(key.api_key_issue_open)
  assert_true(key.api_key_issue_draft.inference_scope)
  assert_true(key.api_key_issue_draft.model_list_scope)
  assert_eq(key.api_key_issue_draft.allowed_models, model_name)
  assert_true(@enterprise.render(key).contains("api-key-issue-title"))
  assert_true(base.update(UseModelInApplication("unknown.model")) == base)
}

///|
test "service choices survive IaaS MaaS and PaaS navigation and withdrawn options stay explicit" {
  let gpu : @enterprise.DeliveryTemplateOption = {
    template_id: "gpu",
    template_version: "1",
    kind: "GpuContainer",
    label: "GPU terminal",
    model_selector: "",
    client_id: Some("terminal"),
  }
  let maas = {
    ..gpu,
    template_id: "text",
    kind: "ModelApi",
    model_selector: "text.test",
  }
  let workspace = {
    ..gpu,
    template_id: "video",
    kind: "Workspace",
    model_selector: "video.test",
  }
  let alternative = { ..maas, template_id: "other", }
  let panel = {
    ..@enterprise.default_delivery_panel(),
    loaded: true,
    options: {
      reservations: [],
      templates: [gpu, maas, alternative, workspace],
    },
  }
  let iaas = panel.for_route(MachineAccess)
  assert_eq(iaas.template_choice, @enterprise.delivery_template_choice(gpu))
  let models = iaas.for_route(Models)
  assert_eq(models.template_choice, "")
  let models = models.update(
    SelectTemplate(@enterprise.delivery_template_choice(alternative)),
  )
  let paas = models.for_route(DesktopIde)
  assert_eq(
    paas.template_choice,
    @enterprise.delivery_template_choice(workspace),
  )
  assert_eq(
    paas.for_route(Models).template_choice,
    @enterprise.delivery_template_choice(alternative),
  )
  assert_eq(
    paas.for_route(MachineAccess).template_choice,
    @enterprise.delivery_template_choice(gpu),
  )
  let withdrawn = { ..paas, options: { reservations: [], templates: [maas], }, }.for_route(
    Models,
  )
  assert_eq(
    withdrawn.template_choice,
    @enterprise.delivery_template_choice(alternative),
  )
  assert_false(@enterprise.delivery_start_available(withdrawn))
}

///|
test "activation is the next action without a competing resource request" {
  let base = @enterprise.demo_state()
  let page = @enterprise.render({
    ..base,
    route: MachineAccess,
    deliveries: {
      ..base.deliveries,
      loaded: true,
      company_workspace: Some({
        status: "NeedsActivation",
        expires_unix_ms: None,
      }),
    },
  })
  assert_true(page.contains("Activate my access"))
  assert_false(page.contains("Rent machines"))
  assert_false(page.contains("Request resources"))
}

///|
test "ready applications expose named direct launch and no invented handoff percentage" {
  let base = @enterprise.demo_state()
  let client = base.desktop_client.unwrap()
  let app = { ..client, client_id: "moontown", display_name: "MoonTown", }
  let state = { ..base, route: DesktopIde, desktop_clients: [client, app], }
  let page = @enterprise.render(state)
  assert_true(page.contains("Applications"))
  assert_true(page.contains("Open MoonTown"))
  assert_false(page.contains("Connection progress"))
  assert_false(page.contains("One-time handoff"))
  assert_eq(
    state.update(OpenApplication(app.client_id)).desktop_client,
    Some(app),
  )
}
