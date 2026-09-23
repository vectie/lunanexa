///|
test "delivery projection reports stage without leaking physical placement" {
  let operation : @delivery.Operation = {
    operation_id: "delivery-1",
    intent: {
      tenant_id: "tenant-a",
      organization_id: "organization-a",
      project_id: "project-a",
      authorization_ref: "grant-a",
      lease_id: "lease-a",
      idempotency_key: "launch-a",
      kind: Workspace,
      template_id: "video-template",
      template_version: "v1",
      model_digest: Some(
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      node_count: 2,
      expires_at_ms: 10000L,
    },
    generation: 3L,
    stage: PreparingModel,
    resume_stage: PreparingModel,
    reservation_id: Some("reservation-a"),
    node_ids: ["private-node-a", "private-node-b"],
    cache_hit: false,
    transferred_bytes: 100L,
    total_bytes: Some(200L),
    model_service_id: None,
    workspace_id: None,
    failure_code: None,
    updated_at_ms: 500L,
    model_assignment_generation: None,
    model_replicas: None,
    stop_requested_at_ms: None,
  }
  let view = delivery_view(operation)
  assert_true(
    view
    is { "stage": String("PreparingModel"), "node_count": Number(2, ..), .. },
  )
  assert_true(
    view
    is {
      "transferred_bytes": String("100"),
      "total_bytes": Array([String("200")]),
      ..
    },
  )
  assert_false(view.stringify().contains("private-node"))
  assert_false(view.stringify().contains("grant-a"))
  assert_true(view is { "model_replica_progress": Null, .. })
  let replica : @delivery.ModelReplica = {
    assignment_id: "private-assignment",
    node_id: "private-node-a",
    generation: 1L,
    prepared: true,
    ready: true,
    stopped: false,
  }
  let replicated = delivery_view({
    ..operation,
    model_replicas: Some([
      replica,
      { ..replica, node_id: "private-node-b", stopped: true, },
    ]),
  })
  assert_true(
    replicated
    is {
      "model_replica_progress": {
        "topology": String("independent_replicas"),
        "observed": Number(2, ..),
        "prepared": Number(2, ..),
        "ready": Number(1, ..),
        "stopped": Number(1, ..),
        ..
      },
      ..
    },
  )
  assert_false(replicated.stringify().contains("private-node"))
  assert_false(replicated.stringify().contains("private-assignment"))
  let expired = delivery_view({ ..operation, stage: Expired, })
  assert_true(expired is { "stage": String("Expired"), .. })
}

///|
test "delivery routes do not match unrelated enterprise or operator paths" {
  assert_true(delivery_path("/v1/portal/self/delivery-options"))
  assert_true(delivery_path("/v1/portal/self/deliveries/delivery-1:retry"))
  assert_false(delivery_path("/v1/portal/self/client-handoffs"))
  assert_false(delivery_path("/v1/assignments"))
}

///|
test "ComfyUI delivery rejects text templates while model API keeps them" {
  let text = machine_dedicated_template()
  assert_false(template_supports_delivery_kind(text, Workspace))
  assert_true(template_supports_delivery_kind(text, ModelApi))
  let video = { ..text, capability: VideoGenerate, }
  assert_true(template_supports_delivery_kind(video, Workspace))
}

///|
test "customer one-click catalog selects only the newest template revision" {
  let first = {
    ..machine_dedicated_template(),
    template_id: "h3-comfyui",
    version: "20260923",
  }
  let revised = { ..first, version: "20260923-r2", }
  let templates = [first, revised]
  assert_false(latest_delivery_template(first, templates))
  assert_true(latest_delivery_template(revised, templates))
}
