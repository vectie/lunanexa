///|
async test "operator readiness requires the published model endpoint, not only a running unit" {
  let root = @fs.tmpdir(prefix="model-readiness-")
  defer @fs.rmdir(root, recursive=true)
  let template = machine_dedicated_template()
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://fixture.invalid/v1/responses",
    "",
    "v1",
    template.runtime.image_digest,
    template.artifact.digest,
  )
  let service = ApiService::new(
    @store.FileStore::open(root + "/state.json"),
    runtime,
    "operator",
    "inference",
    "node",
    "test",
  ).with_external_text_route(
    "test-model",
    "company",
    "node-a",
    "http://127.0.0.1:1",
    "served-model",
    "v1",
    template.runtime.image_digest,
    template.artifact.digest,
  )
  let instance : @deployment.ModelServiceInstance = {
    service_id: "service",
    model_alias: "test-model",
    artifact_digest: template.artifact.digest,
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
  let operator = service.model_service_operator_view(instance)
  assert_true(operator is { "observed": "Running", "ready": False, .. })
  let customer = service.model_service_portal_view(instance, true)
  assert_true(customer is { "state": "Running", "ready": False, .. })
  assert_true(
    service.model_service_operator_view({ ..instance, observed: Stopped, })
    is { "observed": "Stopped", "ready": False, .. },
  )
}
