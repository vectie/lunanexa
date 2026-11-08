///|
test "failure recovery distinguishes a retry from operator repair without losing the delivery identity" {
  let state = default_state(100L)
  let failed : DeliveryView = {
    operation_id: "existing-delivery",
    project_id: "project",
    kind: "ModelApi",
    template_id: "template",
    template_version: "1",
    node_count: 2,
    stage: "Failed",
    generation: 3L,
    cache_hit: false,
    transferred_bytes: 0L,
    total_bytes: None,
    failure_code: Some("ModelReadinessTimeout"),
    expires_at_ms: 999999L,
    can_manage: true,
  }
  assert_true(delivery_retry_primary(failed))
  assert_false(delivery_retry_primary({ ..failed, can_manage: false, }))
  assert_false(delivery_retry_primary({ ..failed, stage: "Expired", }))
  let blocked = { ..failed, failure_code: Some("ModelDeploymentBlocked"), }
  assert_false(delivery_retry_primary(blocked))
  assert_true(
    delivery_failure_guidance(blocked, English).contains("platform operator"),
  )
  let html = render({
    ..state,
    route: Models,
    deliveries: { ..state.deliveries, loaded: true, operations: [blocked], },
  })
  assert_true(html.contains("Copy failure reference"))
  assert_true(html.contains("<summary>Retry after repair</summary>"))
  assert_eq(blocked.operation_id, failed.operation_id)
  assert_false(html.contains("retry available"))
}
