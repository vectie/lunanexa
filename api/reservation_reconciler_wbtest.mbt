///|
async test "reservation host enforces full node set and releases only after claims stop" {
  let root = @fs.tmpdir(prefix="reservation-host-reconciler-")
  defer @fs.rmdir(root, recursive=true)
  let now = @async.now()
  let durable = @store.FileStore::open("\{root}/state.json")
  let scheduler = @scheduler.FileScheduler::open("\{root}/scheduler.json", 4)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "test",
    "v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let taints : Map[String, Json] = Map([])
  let visited : Array[String] = []
  let host = @reservation_host.ReservationHost::new(
    (verb, path, body) => {
      if path.has_prefix("/api/v1/pods?") {
        return (200, { "items": [] })
      }
      let name = path["/api/v1/nodes/".length():].to_owned()
      visited.push(name)
      if verb == "PATCH" {
        guard body is Some(Array(ops)) && ops[1] is { "value": value, .. } else {
          fail("invalid patch")
        }
        taints[name] = value
      }
      (
        200,
        {
          "metadata": { "name": name, "resourceVersion": "1" },
          "spec": { "taints": taints.get(name).unwrap_or([]) },
        },
      )
    },
    "workspaces",
    [],
  )
  let base = ApiService::new(durable, runtime, "op", "infer", "node", "test")
  let service = { ..base, scheduler: Some(scheduler), }.with_reservation_host(
    host,
    { "node-a": "spark-a", "node-b": "spark-b" },
  )
  let request : @scheduler.NodeReservationRequest = {
    reservation_id: "reservation-test",
    idempotency_key: "reservation-test",
    tenant_ref: "tenant",
    organization_id: "org",
    authority_ref: "grant",
    lease_id: "lease",
    node_ids: ["node-a", "node-b"],
    starts_unix_ms: now - 1000L,
    expires_unix_ms: now + 60000L,
    memory_mib_per_node: 10000,
    gpu_memory_mib_per_node: 8000,
    max_concurrency_per_node: 2,
  }
  ignore(scheduler.reserve_nodes(request, ["node-a", "node-b"], now))
  ignore(
    scheduler.claim_node_service(
      request.reservation_id,
      "tenant",
      {
        service_id: "model",
        node_id: "node-a",
        memory_mib: 1000,
        gpu_memory_mib: 1000,
        concurrency: 1,
      },
      now,
    ),
  )
  service.ensure_reservation_nodes(request.reservation_id)
  assert_true(visited.contains("spark-a") && visited.contains("spark-b"))
  let drained = scheduler.begin_node_release(request.reservation_id, now)
  service.reconcile_resource_reservations()
  assert_true(scheduler.node_is_reserved("node-a"))
  scheduler.confirm_node_service_stopped(
    request.reservation_id,
    "model",
    drained.updated_unix_ms,
  )
  for node_id in ["node-a", "node-b"] {
    let heartbeat = customer_machine_test_heartbeat(@async.now())
    durable.put_heartbeat({
      ..heartbeat,
      node_id,
      inventory: { ..heartbeat.inventory, node_id, },
    })
  }
  service.reconcile_resource_reservations()
  assert_false(scheduler.node_is_reserved("node-a"))
  assert_false(scheduler.node_is_reserved("node-b"))
  assert_eq(taints["spark-a"], [])
  assert_eq(taints["spark-b"], [])
}
