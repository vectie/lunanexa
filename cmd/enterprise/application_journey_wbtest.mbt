///|
test "navigation retains launch choices and refresh cannot switch a removed reservation" {
  let base = gateway_auth_test_model()
  let gpu : @enterprise_ui.DeliveryTemplateOption = {
    template_id: "gpu",
    template_version: "1",
    kind: "GpuContainer",
    label: "Terminal",
    model_selector: "",
    client_id: Some("terminal"),
  }
  let model = {
    ..base,
    token: "test-session",
    demo_mode: false,
    portal: {
      ..@enterprise_ui.demo_state(),
      route: MachineAccess,
      deliveries: {
        ..@enterprise_ui.default_delivery_panel(),
        reservation_id: "selected-reservation",
        template_choice: @enterprise_ui.delivery_template_choice(gpu),
        options: { reservations: [], templates: [gpu], shared_trials: [], },
      },
    },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (moved, _) = update(model, Portal(Navigate(Models)), emit)
  let (returned, _) = update(moved, Portal(Navigate(MachineAccess)), emit)
  assert_eq(
    returned.portal.deliveries.template_choice,
    @enterprise_ui.delivery_template_choice(gpu),
  )
  let options : @enterprise_ui.DeliveryOptions = {
    templates: [gpu],
    shared_trials: [],
    reservations: [
      {
        reservation_id: "other-reservation",
        label: "Other machines",
        node_count: 1,
        expires_at_ms: 999999L,
      },
    ],
  }
  let (refreshed, _) = update(
    returned,
    DeliveriesLoaded(
      returned.session_generation,
      returned.portal.selected_organization_id,
      returned.portal.deliveries.poll_generation,
      Ok((options, [], None, None, None)),
    ),
    emit,
  )
  assert_eq(refreshed.portal.deliveries.reservation_id, "selected-reservation")
  assert_false(
    @enterprise_ui.delivery_start_available(refreshed.portal.deliveries),
  )
  let (late, _) = update(
    refreshed,
    DeliveriesLoaded(
      refreshed.session_generation,
      Some("another-company"),
      refreshed.portal.deliveries.poll_generation,
      Ok((options, [], None, None, None)),
    ),
    emit,
  )
  assert_true(late.portal == refreshed.portal)
}

///|
test "direct application launch uses selected application and rejects repeat clicks" {
  let base = gateway_auth_test_model()
  let portal = @enterprise_ui.demo_state()
  let client = {
    ..portal.desktop_client.unwrap(),
    client_id: "moonrobo",
    display_name: "MoonRobo",
  }
  let model = {
    ..base,
    token: "test-session",
    demo_mode: false,
    portal: { ..portal, desktop_clients: [client], },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (opening, _) = update(model, Portal(OpenApplication("moonrobo")), emit)
  assert_eq(opening.portal.desktop_client, Some(client))
  assert_true(opening.portal.loading)
  let (duplicate, _) = update(
    opening,
    Portal(OpenApplication("moonrobo")),
    emit,
  )
  assert_true(duplicate.portal == opening.portal)
  let (unknown, _) = update(model, Portal(OpenApplication("unknown")), emit)
  assert_true(unknown.portal == model.portal)
}

///|
test "application completion from another company cannot overwrite current launch status" {
  let base = gateway_auth_test_model()
  let model = {
    ..base,
    portal: { ..@enterprise_ui.demo_state(), loading: true, },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (late, _) = update(
    model,
    Outcome(
      ApplicationLaunchCompleted(
        model.session_generation,
        Some("old-company"),
        None,
        Ok("Old app"),
      ),
    ),
    emit,
  )
  assert_true(late.portal == model.portal)
  let (done, _) = update(
    model,
    Outcome(
      ApplicationLaunchCompleted(
        model.session_generation,
        model.portal.selected_organization_id,
        None,
        Ok("Selected app"),
      ),
    ),
    emit,
  )
  assert_false(done.portal.loading)
  assert_eq(done.portal.success_message, Some("Continue in Selected app."))
}

///|
test "background delivery refresh preserves a stop decision until the service actually stops" {
  let base = gateway_auth_test_model()
  let operation : @enterprise_ui.DeliveryView = {
    operation_id: "delivery",
    project_id: "project",
    kind: "ModelApi",
    template_id: "model",
    template_version: "1",
    node_count: 1,
    stage: "Ready",
    generation: 1L,
    cache_hit: false,
    transferred_bytes: 0L,
    total_bytes: None,
    failure_code: None,
    expires_at_ms: 999999L,
    can_manage: true,
  }
  let portal = @enterprise_ui.demo_state()
  let panel = {
    ..portal.deliveries,
    operations: [operation],
    stop_confirmation: Some(operation.operation_id),
  }
  let model = {
    ..base,
    demo_mode: false,
    portal: { ..portal, route: Models, deliveries: panel, },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let result = Ok((panel.options, [operation], None, None, None))
  let (refreshed, _) = update(
    model,
    DeliveriesLoaded(
      model.session_generation,
      model.portal.selected_organization_id,
      panel.poll_generation,
      result,
    ),
    emit,
  )
  assert_eq(
    refreshed.portal.deliveries.stop_confirmation,
    Some(operation.operation_id),
  )
  let stopped = Ok(
    (panel.options, [{ ..operation, stage: "Stopped", }], None, None, None),
  )
  let (ended, _) = update(
    refreshed,
    DeliveriesLoaded(
      model.session_generation,
      model.portal.selected_organization_id,
      panel.poll_generation,
      stopped,
    ),
    emit,
  )
  assert_eq(ended.portal.deliveries.stop_confirmation, None)
}
