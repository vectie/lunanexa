///|
async test "deployment write failures roll back catalog operations and transitions" {
  let dir = @fs.tmpdir(prefix="deployment-rollback-")
  let held = "\{dir}-held"
  let path = "\{dir}/state.json"
  let store = @store.FileDeploymentStore::open(path, "catalog-secret")
  @fs.rename(dir, held)
  for _ in 0..<2 {
    try store.register_template(unsigned_template()) catch {
      _ => assert_eq(store.templates(), [])
    } noraise {
      _ => fail("catalog write must fail")
    }
  }
  @fs.rename(held, dir)
  let template = store.register_template(unsigned_template())
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "rollback-key",
    deployment_id: "rollback-service",
    template: { template_id: "text-small", version: "v1", },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
  }
  let plan = @deployment.preflight([template], intent, {
    registry: [],
    nodes: [],
    available_secret_refs: [],
  })
  @fs.rename(dir, held)
  for _ in 0..<2 {
    try store.create_operation(plan, 1000L) catch {
      _ => assert_eq(store.deployment("rollback-service"), None)
    } noraise {
      _ => fail("operation write must fail")
    }
  }
  @fs.rename(held, dir)
  let operation = store.create_operation(plan, 1000L)
  @fs.rename(dir, held)
  for _ in 0..<2 {
    try
      store.transition(
        operation.operation_id,
        operation.state,
        "changed",
        2000L,
      )
    catch {
      _ => assert_eq(store.operation(operation.operation_id), Some(operation))
    } noraise {
      _ => fail("transition write must fail")
    }
  }
  @fs.rename(held, dir)
  let reopened = @store.FileDeploymentStore::open(path, "catalog-secret")
  assert_eq(reopened.operation(operation.operation_id), Some(operation))
  assert_false(@fs.exists("\{path}.next"))
  @fs.remove(path)
  @fs.remove(dir)
}
