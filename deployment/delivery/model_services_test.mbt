///|
async test "one physical model service survives its first delivery stopping" {
  let directory = @fs.tmpdir(prefix="delivery-model-service-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let path = "\{directory}/operations.json"
  let store = @delivery.DeliveryStore::open(path)
  let base : @delivery.Intent = {
    tenant_id: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    authorization_ref: "grant-a",
    lease_id: "lease-a",
    idempotency_key: "first",
    kind: ModelApi,
    template_id: "approved-h3",
    template_version: "v1",
    model_digest: Some("sha256:approved"),
    node_count: 1,
    expires_at_ms: 1000L,
  }
  let first = store.create(base, 1L)
  let mut owner = store.observe(
    first.operation_id,
    first.generation,
    Reserved(reservation_id="reservation-a", node_ids=["spark-a"]),
    2L,
  )
  let replica : @delivery.ModelReplica = {
    assignment_id: "delivery-1-model",
    node_id: "spark-a",
    generation: 1L,
    prepared: true,
    ready: true,
    stopped: false,
  }
  owner = store.observe(
    owner.operation_id,
    owner.generation,
    ModelReplicaObserved(replica),
    3L,
  )
  owner = store.observe(
    owner.operation_id,
    owner.generation,
    ModelPrepared(digest="sha256:approved", cache_hit=true),
    4L,
  )
  owner = store.observe(
    owner.operation_id,
    owner.generation,
    ModelResponded(service_id=owner.operation_id, digest="sha256:approved"),
    5L,
  )
  owner = store.bind_model_service(owner.operation_id, owner.generation, 6L)
  assert_eq(owner.model_service_id, Some(owner.operation_id))
  let second = store.create({ ..base, idempotency_key: "second", }, 7L)
  let reserved = store.observe(
    second.operation_id,
    second.generation,
    Reserved(reservation_id="reservation-a", node_ids=["spark-a"]),
    8L,
  )
  let attached = store.bind_model_service(
    reserved.operation_id,
    reserved.generation,
    9L,
    reuse_service_id=owner.operation_id,
  )
  assert_eq(attached.stage, Ready)
  assert_eq(attached.model_service_id, Some(owner.operation_id))
  let foreign = store.create(
    { ..base, idempotency_key: "foreign", authorization_ref: "other-grant", },
    9L,
  )
  let foreign = store.observe(
    foreign.operation_id,
    foreign.generation,
    Reserved(reservation_id="reservation-a", node_ids=["spark-a"]),
    9L,
  )
  try
    store.bind_model_service(
      foreign.operation_id,
      foreign.generation,
      9L,
      reuse_service_id=owner.operation_id,
    )
  catch {
    @delivery.DeliveryError::UnexpectedObservation => ()
    error => raise error
  } noraise {
    _ => fail("another grant reused the service")
  }
  let service = store.model_service(owner.operation_id).unwrap()
  let recovering = store.observe_model_service(
    owner.operation_id,
    service.runtime.generation,
    ModelReplicaObserved({
      ..replica,
      generation: 2L,
      prepared: false,
      ready: false,
    }),
    10L,
  )
  assert_eq(recovering.stage, LoadingModel)
  assert_eq(store.operation(attached.operation_id).unwrap().stage, LoadingModel)
  let recovering = store.observe_model_service(
    owner.operation_id,
    recovering.generation,
    ModelReplicaObserved({ ..replica, generation: 2L, }),
    10L,
  )
  ignore(
    store.observe_model_service(
      owner.operation_id,
      recovering.generation,
      ModelResponded(service_id=owner.operation_id, digest="sha256:approved"),
      10L,
    ),
  )
  assert_eq(store.operation(attached.operation_id).unwrap().stage, Ready)
  owner = store.operation(owner.operation_id).unwrap()
  owner = store.stop(owner.operation_id, owner.generation, 10L)
  owner = store.release_model_service(owner.operation_id, owner.generation, 11L)
  assert_eq(owner.stage, Stopped)
  let reopened = @delivery.DeliveryStore::open(path)
  let service = reopened.model_service(owner.operation_id).unwrap()
  assert_eq(service.runtime.stage, Ready)
  assert_eq(service.consumer_ids, [attached.operation_id])
  assert_eq(reopened.operation(attached.operation_id).unwrap().stage, Ready)
  let attached = reopened.operation(attached.operation_id).unwrap()
  let stopping = reopened.stop(attached.operation_id, attached.generation, 12L)
  ignore(
    reopened.release_model_service(
      stopping.operation_id,
      stopping.generation,
      13L,
    ),
  )
  let stopping_service = reopened.model_service(owner.operation_id).unwrap()
  assert_eq(stopping_service.runtime.stage, Stopping)
  let late = reopened.create({ ..base, idempotency_key: "late", }, 14L)
  let late = reopened.observe(
    late.operation_id,
    late.generation,
    Reserved(reservation_id="reservation-a", node_ids=["spark-a"]),
    14L,
  )
  try
    reopened.bind_model_service(
      late.operation_id,
      late.generation,
      14L,
      reuse_service_id=owner.operation_id,
    )
  catch {
    @delivery.DeliveryError::UnexpectedObservation => ()
    error => raise error
  } noraise {
    _ => fail("stopping service accepted another consumer")
  }
  let observed = reopened.observe_model_service(
    owner.operation_id,
    stopping_service.runtime.generation,
    ModelReplicaObserved({ ..replica, generation: 2L, stopped: true, }),
    14L,
  )
  ignore(
    reopened.observe_model_service(
      owner.operation_id,
      observed.generation,
      WorkloadsStopped,
      15L,
    ),
  )
  let terminal = reopened.operation(attached.operation_id).unwrap()
  let terminal = reopened.release_model_service(
    terminal.operation_id,
    terminal.generation,
    16L,
  )
  assert_eq(terminal.stage, Stopped)
  assert_true(
    reopened.model_service(owner.operation_id).unwrap().consumer_ids.is_empty(),
  )
}
