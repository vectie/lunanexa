///|
test "delivery launch requires actual reservation and published template and preserves retry identity" {
  let empty = @enterprise.default_delivery_panel()
  assert_false(@enterprise.delivery_start_available(empty))
  let option : @enterprise.DeliveryTemplateOption = {
    template_id: "h3",
    template_version: "1",
    kind: "Workspace",
    label: "H3 + ComfyUI",
    model_selector: "video.h3",
    client_id: Some("comfyui"),
  }
  let panel = {
    ..empty,
    loaded: true,
    options: {
      reservations: [
        {
          reservation_id: "reserved-a",
          label: "Private allocation",
          node_count: 2,
          expires_at_ms: 99999L,
        },
      ],
      templates: [option],
    },
    reservation_id: "reserved-a",
    template_choice: @enterprise.delivery_template_choice(option),
    idempotency_key: "stable-key",
  }
  assert_true(@enterprise.delivery_start_available(panel))
  let pending = panel.update(Start)
  assert_true(pending.loading)
  assert_eq(pending.idempotency_key, "stable-key")
  assert_true(pending.update(Start) == pending)
  assert_false(
    @enterprise.delivery_start_available({ ..panel, reservation_id: "unknown", }),
  )
  assert_eq(panel.update(SelectTemplate("another")).idempotency_key, "")
}

///|
test "delivery progress renders truthful cache status and stop confirmation without topology" {
  let state = @enterprise.default_state(100L)
  let panel = {
    ..state.deliveries,
    loaded: true,
    operations: [
      {
        operation_id: "delivery-a",
        project_id: "project-a",
        kind: "Workspace",
        template_id: "h3",
        template_version: "1",
        node_count: 2,
        stage: "PreparingModel",
        generation: 3L,
        cache_hit: false,
        transferred_bytes: 1048576L,
        total_bytes: Some(2097152L),
        failure_code: None,
        expires_at_ms: 99999L,
        can_manage: true,
      },
    ],
  }
  let rendered = @enterprise.render({
    ..state,
    route: DesktopIde,
    locale: English,
    deliveries: panel,
  })
  assert_true(rendered.contains("Preparing model"))
  assert_true(rendered.contains("50% · 1 / 2 MiB"))
  assert_true(rendered.contains("<progress"))
  assert_true(rendered.contains("2 exclusive nodes"))
  assert_false(rendered.contains("Using verified local model cache"))
  assert_false(rendered.contains("Confirm stop"))
  let confirming = panel.update(RequestStop("delivery-a"))
  assert_true(
    @enterprise.render({
      ..state,
      route: DesktopIde,
      locale: English,
      deliveries: confirming,
    }).contains("Confirm stop"),
  )
  assert_true(confirming.update(CancelStop).stop_confirmation is None)
}

///|
test "expired delivery does not offer retry or stop" {
  let state = @enterprise.default_state(100L)
  let panel = {
    ..state.deliveries,
    loaded: true,
    operations: [
      {
        operation_id: "delivery-expired",
        project_id: "project-a",
        kind: "ModelApi",
        template_id: "h3",
        template_version: "1",
        node_count: 1,
        stage: "Expired",
        generation: 4L,
        cache_hit: true,
        transferred_bytes: 0L,
        total_bytes: None,
        failure_code: None,
        expires_at_ms: 99L,
        can_manage: true,
      },
    ],
  }
  let rendered = @enterprise.render({
    ..state,
    route: Models,
    locale: English,
    deliveries: panel,
  })
  assert_true(rendered.contains("Expired"))
  assert_false(rendered.contains(">Stop service<"))
  assert_false(rendered.contains(">Retry<"))
}

///|
test "GPU terminal uses catalog client without requiring a model" {
  let state = @enterprise.default_state(100L)
  let template : @enterprise.DeliveryTemplateOption = {
    template_id: "gpu-shell",
    template_version: "1",
    kind: "GpuContainer",
    label: "GPU terminal",
    model_selector: "",
    client_id: Some("approved-terminal"),
  }
  let operation : @enterprise.DeliveryView = {
    operation_id: "gpu-delivery",
    project_id: "project-a",
    kind: "GpuContainer",
    template_id: "gpu-shell",
    template_version: "1",
    node_count: 1,
    stage: "StartingWorkspace",
    generation: 2L,
    cache_hit: false,
    transferred_bytes: 0L,
    total_bytes: None,
    failure_code: None,
    expires_at_ms: 99999L,
    can_manage: true,
  }
  let panel = {
    ..state.deliveries,
    loaded: true,
    options: { reservations: [], templates: [template], },
    operations: [operation],
  }
  assert_true(
    @enterprise.delivery_launch_template(panel, "gpu-delivery") is Some(value) &&
    value.client_id == Some("approved-terminal"),
  )
  let rendered = @enterprise.render({
    ..state,
    route: MachineAccess,
    locale: English,
    deliveries: panel,
  })
  assert_true(rendered.contains("Open and start terminal"))
  assert_false(rendered.contains("Open and start workspace"))
  assert_true(rendered.contains("Starting GPU container"))
  let ready = { ..panel, operations: [{ ..operation, stage: "Ready", }], }
  assert_true(
    @enterprise.render({
      ..state,
      route: MachineAccess,
      locale: English,
      deliveries: ready,
    }).contains("Open terminal"),
  )
  let missing = {
    ..panel,
    options: {
      reservations: [],
      templates: [{ ..template, client_id: None, }],
    },
  }
  assert_true(
    @enterprise.delivery_launch_template(missing, "gpu-delivery") is None,
  )
  let expired = { ..panel, operations: [{ ..operation, stage: "Expired", }], }
  assert_true(
    @enterprise.delivery_launch_template(expired, "gpu-delivery") is None,
  )
}

///|
test "model workspace and model API retain distinct launch requirements" {
  let panel = @enterprise.default_delivery_panel()
  let template : @enterprise.DeliveryTemplateOption = {
    template_id: "h3",
    template_version: "1",
    kind: "Workspace",
    label: "H3",
    model_selector: "video.h3",
    client_id: Some("creative-client"),
  }
  let operation : @enterprise.DeliveryView = {
    operation_id: "workspace-delivery",
    project_id: "project-a",
    kind: "Workspace",
    template_id: "h3",
    template_version: "1",
    node_count: 1,
    stage: "StartingWorkspace",
    generation: 2L,
    cache_hit: false,
    transferred_bytes: 0L,
    total_bytes: None,
    failure_code: None,
    expires_at_ms: 99999L,
    can_manage: true,
  }
  let configured = {
    ..panel,
    operations: [operation],
    options: { reservations: [], templates: [template], },
  }
  assert_true(
    @enterprise.delivery_launch_template(configured, operation.operation_id)
    is Some(_),
  )
  let no_model = {
    ..configured,
    options: {
      reservations: [],
      templates: [{ ..template, model_selector: "", }],
    },
  }
  assert_true(
    @enterprise.delivery_launch_template(no_model, operation.operation_id)
    is None,
  )
  let api = {
    ..configured,
    operations: [{ ..operation, kind: "ModelApi", stage: "Ready", }],
    options: {
      reservations: [],
      templates: [
        { ..template, kind: "ModelApi", client_id: Some("desktop-workspace"), },
      ],
    },
  }
  assert_true(
    @enterprise.delivery_launch_template(api, operation.operation_id) is Some(_),
  )
}

///|
test "delivery operations appear only under their matching product" {
  let state = @enterprise.default_state(100L)
  let operation : @enterprise.DeliveryView = {
    operation_id: "gpu-delivery",
    project_id: "project-a",
    kind: "GpuContainer",
    template_id: "gpu-shell",
    template_version: "1",
    node_count: 1,
    stage: "Ready",
    generation: 1L,
    cache_hit: false,
    transferred_bytes: 0L,
    total_bytes: None,
    failure_code: None,
    expires_at_ms: 99999L,
    can_manage: true,
  }
  let panel = { ..state.deliveries, loaded: true, operations: [operation], }
  assert_true(
    @enterprise.render({ ..state, route: MachineAccess, deliveries: panel, }).contains(
      "gpu-shell",
    ),
  )
  assert_false(
    @enterprise.render({ ..state, route: DesktopIde, deliveries: panel, }).contains(
      "gpu-shell",
    ),
  )
}

///|
test "personal MoonDesk hides exclusive-delivery setup until it is relevant" {
  let state = @enterprise.demo_state()
  let personal = @enterprise.render({ ..state, route: DesktopIde, })
  assert_true(personal.contains("One-click connection"))
  assert_false(personal.contains("Dedicated application workspaces"))
  let models = @enterprise.render({ ..state, route: Models, })
  assert_false(models.contains("Dedicated model API"))
  let machine = @enterprise.render({
    ..state,
    route: MachineAccess,
    deliveries: { ..state.deliveries, loaded: true, },
  })
  assert_true(machine.contains("GPU container deliveries"))
  assert_true(machine.contains("Request resources"))
}

///|
test "shared external GLM stop belongs to company administrator in MaaS" {
  let state = @enterprise.default_state(100L)
  let shared : @enterprise.ExternalModelServiceView = {
    model_alias: "glm-5.3.flash",
    state: "Running",
    can_stop: true,
    ready: true,
  }
  let panel = {
    ..state.deliveries,
    loaded: true,
    external_model: Some(shared),
  }
  let owner = @enterprise.render({ ..state, route: Models, deliveries: panel, })
  assert_true(owner.contains("Stop GLM service"))
  assert_true(owner.contains("Running on the Spark pair"))
  let confirm = panel.update(RequestStopExternal)
  assert_true(
    @enterprise.render({ ..state, route: Models, deliveries: confirm, }).contains(
      "Confirm stop GLM",
    ),
  )
  assert_false(confirm.update(CancelStop).external_stop_confirmation)
  let colleague = @enterprise.render({
    ..state,
    route: Models,
    deliveries: {
      ..panel,
      external_model: Some({ ..shared, can_stop: false, }),
    },
  })
  assert_false(colleague.contains("Stop GLM service"))
  let stopped_colleague = @enterprise.render({
    ..state,
    route: Models,
    deliveries: {
      ..panel,
      external_model: Some({ ..shared, state: "Stopped", can_stop: false, }),
    },
  })
  assert_false(stopped_colleague.contains("Start GLM service"))
  let stopped = @enterprise.render({
    ..state,
    route: Models,
    deliveries: {
      ..panel,
      external_model: Some({ ..shared, state: "Stopped", }),
    },
  })
  assert_true(stopped.contains("Stopped; model files retained"))
  assert_false(stopped.contains("Stop GLM service"))
  assert_true(stopped.contains("Start GLM service"))
  let start_confirm = panel.update(RequestStartExternal)
  assert_true(
    @enterprise.render({ ..state, route: Models, deliveries: start_confirm, }).contains(
      "Confirm start GLM",
    ),
  )
  assert_false(start_confirm.update(CancelStop).external_start_confirmation)
}

///|
test "MaaS keeps status and refresh visible when model control fails to load" {
  let state = @enterprise.default_state(100L)
  let html = @enterprise.render({
    ..state,
    route: Models,
    deliveries: {
      ..state.deliveries,
      loaded: true,
      error: Some("model status unavailable"),
    },
  })
  assert_true(html.contains("Dedicated model APIs"))
  assert_true(html.contains("Refresh status"))
  assert_true(html.contains("model status unavailable"))
}

///|
test "ready MaaS exposes bound key creation and clears its one time secret" {
  let state = @enterprise.default_state(100L)
  let operation : @enterprise.DeliveryView = {
    operation_id: "model-delivery",
    project_id: "project-a",
    kind: "ModelApi",
    template_id: "text",
    template_version: "1",
    node_count: 1,
    stage: "Ready",
    generation: 4L,
    cache_hit: true,
    transferred_bytes: 0L,
    total_bytes: None,
    failure_code: None,
    expires_at_ms: 99999L,
    can_manage: true,
  }
  let panel = { ..state.deliveries, loaded: true, operations: [operation], }
  let ready = @enterprise.render({
    ..state,
    route: Models,
    locale: English,
    deliveries: panel,
  })
  assert_true(ready.contains("Create delivery API key"))
  assert_false(ready.contains("Open terminal"))
  let colleague_view = @enterprise.render({
    ..state,
    route: Models,
    locale: English,
    deliveries: { ..panel, operations: [{ ..operation, can_manage: false, }], },
  })
  assert_false(colleague_view.contains("Stop service"))
  assert_true(colleague_view.contains("Create delivery API key"))
  let access : @enterprise.DeliveryApiAccess = {
    delivery_id: operation.operation_id,
    key_id: "test-key",
    api_secret: "test-only-once-not-a-real-secret",
    model: "text.test",
    base_url: "https://api.example.invalid",
    expires_unix_ms: 99999L,
    maximum_requests: 100L,
    one_time: true,
  }
  let showing = { ..panel, api_access: Some(access), }
  let shown = @enterprise.render({
    ..state,
    route: Models,
    locale: English,
    deliveries: showing,
  })
  assert_true(shown.contains("test-only-once-not-a-real-secret"))
  assert_true(shown.contains("Copy API address"))
  let cleared = showing.update(DismissApiAccess)
  assert_true(cleared.api_access is None)
  assert_false(
    @enterprise.render({
      ..state,
      route: Models,
      locale: English,
      deliveries: cleared,
    }).contains("test-only-once-not-a-real-secret"),
  )
  assert_true(showing.update(SelectReservation("another")).api_access is None)
  let stopped = { ..panel, operations: [{ ..operation, stage: "Stopped", }], }
  assert_false(
    @enterprise.render({
      ..state,
      route: Models,
      locale: English,
      deliveries: stopped,
    }).contains("Create delivery API key"),
  )
}
