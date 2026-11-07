///|
async test "pending platform assignments atomically exclude another deployment on the same node" {
  let root = @fs.tmpdir(prefix="platform-service-admission-")
  defer @fs.rmdir(root, recursive=true)
  let catalog = @deployment_store.FileDeploymentStore::open(
    root + "/deployments.json",
    "fixture-signing",
  )
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
  ).with_deployment_store(catalog)
  let assignment : @contracts.DesiredAssignment = {
    assignment_id: "first",
    deployment_id: "first",
    node_id: "node-a",
    artifact: template.artifact,
    runtime: template.runtime,
    resources: template.resources,
    devices: ["gpu"],
    network: template.network,
    health: template.health,
    data_policy: template.data_policy,
    generation: 1L,
    lease_expires_unix_ms: @async.now() + 60000L,
    controller_epoch: 1L,
    group: None,
    reservation: None,
    signature: "",
  }
  let owner : @deployment.ServiceOwner = {
    tenant_ref: "",
    organization_id: "",
    reservation_id: None,
  }
  service.register_assignment_service(assignment, owner)
  service.register_assignment_service(assignment, owner)
  assert_true(catalog.service("first").unwrap().exclusive)
  try
    service.register_assignment_service(
      { ..assignment, assignment_id: "second", deployment_id: "second", },
      owner,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("two pending platform deployments claimed the same GPU node")
  }
  assert_eq(catalog.services().length(), 1)
}

///|
async test "slow observations do not block admission or overwrite a newer lifecycle intent" {
  let root = @fs.tmpdir(prefix="service-observation-race-")
  defer @fs.rmdir(root, recursive=true)
  let catalog = @deployment_store.FileDeploymentStore::open(
    root + "/deployments.json",
    "fixture-signing",
  )
  let template = machine_dedicated_template()
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://fixture.invalid/v1/responses",
    "",
    "v1",
    template.runtime.image_digest,
    template.artifact.digest,
  )
  let entered = Ref(false)
  let release = Ref(false)
  let first = Ref(true)
  let service = ApiService::new(
      @store.FileStore::open(root + "/state.json"),
      runtime,
      "operator",
      "inference",
      "node",
      "test",
    )
    .with_deployment_store(catalog)
    .with_runtime_controls({
      "adapter": action => {
        if action == "status" && first.val {
          first.val = false
          entered.val = true
          while !release.val {
            @async.sleep(1)
          }
          "Stopped"
        } else if action == "start" {
          "Running"
        } else {
          "Stopped"
        }
      },
    })
  catalog.adopt_service({
    service_id: "model",
    model_alias: "model",
    artifact_digest: template.artifact.digest,
    owner: { tenant_ref: "", organization_id: "", reservation_id: None, },
    node_ids: ["node-a"],
    runtime_kind: ProcessGroup,
    binding_ref: "adapter",
    exclusive: true,
    generation: 1L,
    desired_running: false,
    observed: Stopped,
    updated_unix_ms: 1L,
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => service.reconcile_model_services())
    @async.with_timeout(1000, () => {
      while !entered.val {
        @async.sleep(1)
      }
      let started = service.apply_model_service_action("model", "start")
      assert_eq(started.observed, Running)
    })
    release.val = true
  })
  assert_eq(catalog.service("model").unwrap().observed, Running)
}
