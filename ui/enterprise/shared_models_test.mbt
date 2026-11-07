///|
test "shared model choice is generic and invalidates stale reads without a new launch" {
  let first : @enterprise.ExternalModelServiceView = {
    service_id: "first",
    model_alias: "glm-v1",
    state: "Stopped",
    can_stop: true,
    ready: false,
    context_window_tokens: None,
  }
  let second : @enterprise.ExternalModelServiceView = {
    ..first,
    service_id: "second",
    model_alias: "qwen-v2",
    state: "Running",
    ready: true,
  }
  let panel = {
    ..@enterprise.default_delivery_panel(),
    external_model: Some(first),
    shared_models: [first, second],
  }
  let selected = panel.update(SelectSharedModel("second"))
  assert_true(selected.external_model == Some(second))
  assert_eq(selected.poll_generation, panel.poll_generation + 1L)
  assert_false(selected.external_start_confirmation)
  assert_false(selected.loading)
  assert_true(selected.update(SelectSharedModel("unknown")) == selected)
  let state = @enterprise.default_state(1L)
  let rendered = @enterprise.render({
    ..state,
    route: Models,
    deliveries: { ..selected, loaded: true, },
  })
  assert_true(rendered.contains("glm-v1"))
  assert_true(rendered.contains("qwen-v2"))
  assert_true(rendered.contains("value=\"second\""))
}
