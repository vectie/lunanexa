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
  assert_true(rendered.contains("1 / 2 MiB"))
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
      },
    ],
  }
  let rendered = @enterprise.render({
    ..state,
    route: DesktopIde,
    locale: English,
    deliveries: panel,
  })
  assert_true(rendered.contains("Expired"))
  assert_false(rendered.contains(">Stop service<"))
  assert_false(rendered.contains(">Retry<"))
}
