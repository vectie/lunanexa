///|
test "partial and unavailable model services retain their reference and expose a bounded handoff" {
  let base = default_state(1000L)
  for status in ["Partial", "Unavailable"] {
    let service : ExternalModelServiceView = {
      service_id: "existing-service",
      model_alias: "model.chat",
      state: status,
      can_stop: true,
      ready: false,
      context_window_tokens: Some(524288),
    }
    let state = {
      ..base,
      route: Models,
      deliveries: {
        ..base.deliveries,
        loaded: true,
        external_model: Some(service),
      },
    }
    let html = render(state)
    assert_true(html.contains("Copy service reference"))
    assert_true(html.contains("platform operator"))
    assert_true(html.contains("Model: model.chat"))
    assert_eq(
      state.deliveries.external_model.unwrap().service_id,
      "existing-service",
    )
  }
}
