///|
fn intent(kind : @delivery.DeliveryKind) -> @delivery.Intent {
  {
    tenant_id: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    authorization_ref: "approved-access",
    lease_id: "lease-a",
    idempotency_key: "one-click",
    kind,
    template_id: "video-workspace",
    template_version: "v1",
    model_digest: Some("sha256:approved-version"),
    node_count: 2,
    expires_at_ms: 1000L,
  }
}

///|
async test "one click survives restart and requires model response before workspace readiness" {
  let directory = @fs.tmpdir(prefix="delivery-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let path = "\{directory}/operations.json"
  let store = @delivery.DeliveryStore::open(path)
  let first = store.create(intent(Workspace), 1L)
  assert_eq(store.create(intent(Workspace), 2L), first)
  let reserved = store.observe(
    first.operation_id,
    first.generation,
    Reserved(reservation_id="reservation-a", node_ids=["spark-a", "spark-b"]),
    3L,
  )
  let prepared = store.observe(
    first.operation_id,
    reserved.generation,
    ModelPrepared(digest="sha256:approved-version", cache_hit=true),
    4L,
  )
  assert_eq(prepared.stage, LoadingModel)
  try
    store.observe(
      first.operation_id,
      prepared.generation,
      WorkspaceResponded(workspace_id="workspace-a"),
      5L,
    )
  catch {
    @delivery.DeliveryError::UnexpectedObservation => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("workspace claimed ready before model response")
  }
  let reopened = @delivery.DeliveryStore::open(path)
  assert_eq(reopened.operation(first.operation_id), Some(prepared))
  let loaded = reopened.observe(
    first.operation_id,
    prepared.generation,
    ModelResponded(service_id="service-a", digest="sha256:approved-version"),
    6L,
  )
  let ready = reopened.observe(
    first.operation_id,
    loaded.generation,
    WorkspaceResponded(workspace_id="workspace-a"),
    7L,
  )
  assert_eq(ready.stage, Ready)
  assert_true(ready.cache_hit)
}

///|
async test "failure resumes its stage and expiry waits for real stop" {
  let directory = @fs.tmpdir(prefix="delivery-retry-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let store = @delivery.DeliveryStore::open("\{directory}/operations.json")
  let created = store.create(intent(ModelApi), 1L)
  let reserved = store.observe(
    created.operation_id,
    created.generation,
    Reserved(reservation_id="reservation-a", node_ids=["spark-a", "spark-b"]),
    2L,
  )
  let failed = store.observe(
    created.operation_id,
    reserved.generation,
    Failure(code="transfer-interrupted"),
    3L,
  )
  let resumed = store.retry(created.operation_id, failed.generation, 4L)
  assert_eq(resumed.stage, PreparingModel)
  assert_eq(resumed.reservation_id, Some("reservation-a"))
  let stopping = store.expire_due(1001L)[0]
  assert_eq(stopping.stage, Stopping)
  assert_eq(stopping.node_ids.length(), 2)
  let expired = store.observe(
    created.operation_id,
    stopping.generation,
    WorkloadsStopped,
    1002L,
  )
  assert_eq(expired.stage, Expired)
  assert_eq(store.operations().length(), 1)
}

///|
async test "container delivery skips inference and MaaS skips workspace" {
  let directory = @fs.tmpdir(prefix="delivery-kinds-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let store = @delivery.DeliveryStore::open("\{directory}/operations.json")
  let container = store.create(
    { ..intent(GpuContainer), model_digest: None, },
    1L,
  )
  let reserved = store.observe(
    container.operation_id,
    container.generation,
    Reserved(reservation_id="reservation-a", node_ids=["spark-a", "spark-b"]),
    2L,
  )
  assert_eq(reserved.stage, StartingWorkspace)
  let ready = store.observe(
    container.operation_id,
    reserved.generation,
    ContainerResponded(instance_id="container-a"),
    3L,
  )
  assert_eq(ready.stage, Ready)
  let stopping = store.stop(container.operation_id, ready.generation, 4L)
  let workspace_stopped = store.observe(
    container.operation_id,
    stopping.generation,
    WorkspaceStopped,
    5L,
  )
  assert_eq(workspace_stopped.workspace_id, None)
  assert_eq(workspace_stopped.stage, Stopping)
  let api = store.create({ ..intent(ModelApi), idempotency_key: "api", }, 4L)
  let reserved = store.observe(
    api.operation_id,
    api.generation,
    Reserved(reservation_id="reservation-b", node_ids=["spark-c", "spark-d"]),
    5L,
  )
  let prepared = store.observe(
    api.operation_id,
    reserved.generation,
    ModelPrepared(digest="sha256:approved-version", cache_hit=false),
    6L,
  )
  let ready = store.observe(
    api.operation_id,
    prepared.generation,
    ModelResponded(service_id="api-model", digest="sha256:approved-version"),
    7L,
  )
  assert_eq(ready.stage, Ready)
  assert_eq(ready.workspace_id, None)
}

///|
async test "concurrent clicks and partial reservations do not create duplicate operations" {
  let directory = @fs.tmpdir(prefix="delivery-concurrent-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let store = @delivery.DeliveryStore::open("\{directory}/operations.json")
  @async.with_task_group(group => {
    for _ in 0..<8 {
      group.spawn_bg(() => ignore(store.create(intent(Workspace), 1L)))
    }
  })
  let operations = store.operations()
  assert_eq(operations.length(), 1)
  let first = operations[0]
  try
    store.observe(
      first.operation_id,
      first.generation,
      Reserved(reservation_id="r", node_ids=["spark-a"]),
      2L,
    )
  catch {
    @delivery.DeliveryError::UnexpectedObservation => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("partial allocation accepted")
  }
  assert_eq(store.operation(first.operation_id), Some(first))
  try store.create({ ..intent(Workspace), node_count: 1, }, 2L) catch {
    @delivery.DeliveryError::IdempotencyConflict => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("different request reused idempotency key")
  }
}

///|
async test "wrong model and stale observations cannot advance the operation" {
  let directory = @fs.tmpdir(prefix="delivery-observations-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let store = @delivery.DeliveryStore::open("\{directory}/operations.json")
  let created = store.create(intent(Workspace), 1L)
  let reserved = store.observe(
    created.operation_id,
    created.generation,
    Reserved(reservation_id="reservation-a", node_ids=["spark-a", "spark-b"]),
    2L,
  )
  try
    store.observe(
      created.operation_id,
      reserved.generation,
      ModelPrepared(digest="sha256:wrong-model", cache_hit=true),
      3L,
    )
  catch {
    @delivery.DeliveryError::UnexpectedObservation => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("wrong model advanced operation")
  }
  try
    store.observe(
      created.operation_id,
      created.generation,
      ModelPrepared(digest="sha256:approved-version", cache_hit=true),
      3L,
    )
  catch {
    @delivery.DeliveryError::StaleGeneration => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("stale observation advanced operation")
  }
  reserved.node_ids.clear()
  assert_eq(store.operations()[0].node_ids.length(), 2)
  let stopped = store.stop(created.operation_id, reserved.generation, 4L)
  assert_eq(store.stop(created.operation_id, stopped.generation, 5L), stopped)
  let complete = store.observe(
    created.operation_id,
    stopped.generation,
    WorkloadsStopped,
    6L,
  )
  assert_eq(complete.stage, Stopped)
}
