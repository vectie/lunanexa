///|
test "runtime process does not become ready before the inference probe" {
  let service : @deployment.ModelServiceInstance = {
    service_id: "model-service",
    model_alias: "model-v1",
    artifact_digest: "sha256:" + "a".repeat(64),
    owner: {
      tenant_ref: "company",
      organization_id: "org",
      reservation_id: None,
    },
    node_ids: ["node-a"],
    runtime_kind: ProcessGroup,
    binding_ref: "runtime",
    exclusive: true,
    generation: 1L,
    desired_running: true,
    observed: Running,
    updated_unix_ms: 1L,
  }
  let value = Json(service)
  assert_true(model_service_deployment_row(value).observed == Starting)
  guard value is Object(fields) else { fail("expected service object") }
  fields["ready"] = false
  assert_true(model_service_deployment_row(Json(fields)).observed == Starting)
  fields["ready"] = true
  assert_true(model_service_deployment_row(Json(fields)).observed == Ready)
  fields["observed"] = "Stopped"
  assert_true(model_service_deployment_row(Json(fields)).observed == Stopped)
}

///|
test "startup refresh prevents overlapping reads and stops when the service is ready" {
  let base = deferred_read_test_model(Deployments)
  let row : @ui.DeploymentRow = {
    assignment_id: "service:company-model",
    deployment_id: "company-model",
    desired: Ready,
    observed: Starting,
    placement_reason: "#1",
    model_digest: "digest",
    node_id: "node-a",
    resource_owner: "company",
  }
  let model = {
    ..base,
    console: { ..base.console, deployments: [row], },
    console_read_groups: Map([(DeploymentReads, true)]),
  }
  let (loading, _) = refresh_starting_model_services(model, _ => ())
  assert_eq(loading.console_read_groups.get(DeploymentReads), Some(false))
  let (overlap, _) = refresh_starting_model_services(loading, _ => ())
  assert_eq(overlap, loading)
  for state in [Ready, Stopped] {
    let settled = {
      ..model,
      console: { ..model.console, deployments: [{ ..row, observed: state, }], },
    }
    let (unchanged, _) = refresh_starting_model_services(settled, _ => ())
    assert_eq(unchanged, settled)
  }
}
