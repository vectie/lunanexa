///|
fn service_fixture(
  id : String,
  tenant : String,
  state : @deployment.ServiceRuntimeState,
) -> @deployment.ModelServiceInstance {
  {
    service_id: id,
    model_alias: "model-v1",
    artifact_digest: "sha256:" + "a".repeat(64),
    owner: {
      tenant_ref: tenant,
      organization_id: tenant,
      reservation_id: None,
    },
    node_ids: ["node-a", "node-b"],
    runtime_kind: ProcessGroup,
    binding_ref: id,
    exclusive: true,
    generation: 1L,
    desired_running: state != Stopped,
    observed: state,
    updated_unix_ms: 1L,
  }
}

///|
test "stopped delivery service does not retain an expired reservation's node ownership" {
  let delivered = {
    ..service_fixture("delivered", "company-a", Stopped),
    runtime_kind: NodeAssignment,
    owner: {
      tenant_ref: "company-a",
      organization_id: "company-a",
      reservation_id: Some("reservation-a"),
    },
  }
  let platform = service_fixture("platform", "", Stopped)
  assert_false(delivered.reserves_company_node())
  assert_false(@deployment.service_conflicts(platform, delivered))
  assert_true(
    @deployment.service_conflicts(platform, { ..delivered, observed: Unknown, }),
  )
}

///|
async test "service adoption preserves the signed deployment catalog and restart identity" {
  let root = @fs.tmpdir(prefix="service-adoption-")
  defer @fs.rmdir(root, recursive=true)
  let path = root + "/deployments.json"
  let store = @store.FileDeploymentStore::open(path, "fixture-secret")
  let original = @fs.read_file(path).text()
  let model = service_fixture("existing-model", "company-a", Running)
  store.adopt_service(model)
  store.adopt_service(model)
  assert_eq(@fs.read_file(path).text(), original)
  let restarted = @store.FileDeploymentStore::open(path, "fixture-secret")
  assert_eq(restarted.services(), [model])
  try restarted.adopt_service({ ..model, node_ids: ["other"], }) catch {
    _ => ()
  } noraise {
    _ => fail("adoption replaced the live binding")
  }
  assert_eq(restarted.service(model.service_id), Some(model))
}

///|
async test "unknown stop keeps claims and stopped company ownership blocks platform starts" {
  let root = @fs.tmpdir(prefix="service-conflicts-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.FileDeploymentStore::open(
    root + "/deployments.json",
    "fixture-secret",
  )
  let company = service_fixture("company-model", "company-a", Running)
  let platform = service_fixture("platform-model", "", Stopped)
  store.adopt_service(company)
  store.adopt_service(platform)
  let stopping = store.set_service_desired(company.service_id, 1L, false, 2L)
  assert_true(stopping.holds_resources())
  store.observe_service(company.service_id, stopping.generation, Unknown, 3L)
  try store.set_service_desired(platform.service_id, 1L, true, 4L) catch {
    _ => ()
  } noraise {
    _ => fail("platform overrode company allocation")
  }
  store.observe_service(company.service_id, stopping.generation, Stopped, 5L)
  assert_false(store.service(company.service_id).unwrap().holds_resources())
  try store.set_service_desired(platform.service_id, 1L, true, 6L) catch {
    _ => ()
  } noraise {
    _ => fail("stop released company ownership")
  }
  try store.observe_service(company.service_id, 1L, Running, 7L) catch {
    _ => ()
  } noraise {
    _ => fail("stale observation won")
  }
}

///|
async test "different models share the same platform runtime conflict rule" {
  let root = @fs.tmpdir(prefix="model-neutral-conflict-")
  defer @fs.rmdir(root, recursive=true)
  let path = root + "/deployments.json"
  let store = @store.FileDeploymentStore::open(path, "fixture-secret")
  let first = { ..service_fixture("first", "", Running), model_alias: "qwen", }
  let second = { ..service_fixture("second", "", Stopped), model_alias: "glm", }
  store.adopt_service(first)
  store.adopt_service(second)
  try store.set_service_desired(second.service_id, 1L, true, 2L) catch {
    _ => ()
  } noraise {
    _ => fail("overlapping runtime started")
  }
  let stopped = store.set_service_desired(first.service_id, 1L, false, 3L)
  store.observe_service(first.service_id, stopped.generation, Stopped, 4L)
  let started = store.set_service_desired(second.service_id, 1L, true, 5L)
  assert_true(started.holds_resources())
  let recovered = @store.FileDeploymentStore::open(path, "fixture-secret")
  assert_eq(recovered.service(second.service_id), Some(started))
}
