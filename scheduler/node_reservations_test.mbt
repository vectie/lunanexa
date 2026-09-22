///|
fn reservation_request(
  id : String,
  tenant : String,
  nodes : Array[String],
) -> @scheduler.NodeReservationRequest {
  {
    reservation_id: id,
    idempotency_key: id,
    tenant_ref: tenant,
    organization_id: "org-\{tenant}",
    authority_ref: "approved-admin-grant",
    lease_id: "lease-\{tenant}",
    node_ids: nodes,
    starts_unix_ms: 1000L,
    expires_unix_ms: 5000L,
    memory_mib_per_node: 100000,
    gpu_memory_mib_per_node: 90000,
    max_concurrency_per_node: 4,
  }
}

///|
async test "multi node reservations persist atomically and exclude shared placements" {
  let dir = @fs.tmpdir(prefix="node-reservation-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/scheduler.json"
  let scheduler = @scheduler.FileScheduler::open(path, 8)
  let request = reservation_request("reservation-a", "tenant-a", ["a", "b"])
  let reserved = scheduler.reserve_nodes(request, ["a", "b", "c"], 1000L)
  assert_eq(scheduler.reserve_nodes(request, [], 1001L), reserved)
  try
    scheduler.reserve_nodes(
      reservation_request("reservation-b", "tenant-b", ["c", "b"]),
      ["a", "b", "c"],
      1001L,
    )
  catch {
    @scheduler.SchedulerStateError::InvalidSchedulerState(_) => ()
    error => raise error
  } noraise {
    _ => fail("overlapping nodes were reserved")
  }
  assert_false(scheduler.node_is_reserved("c"))
  let reopened = @scheduler.FileScheduler::open(path, 8)
  assert_eq(reopened.node_reservation("reservation-a"), Some(reserved))
  let nodes = [
    cx7_node("a", Active),
    cx7_node("b", Active),
    cx7_node("c", Active),
  ]
  assert_eq(
    reopened.place(nodes, requirements(), score_policy()).selected_node_id,
    Some("c"),
  )
  assert_eq(
    reopened.place_reserved(
      nodes,
      requirements(),
      score_policy(),
      "reservation-a",
      "tenant-a",
      1001L,
    ).selected_node_id,
    Some("a"),
  )
  try
    reopened.place_reserved(
      nodes,
      requirements(),
      score_policy(),
      "reservation-a",
      "tenant-b",
      1001L,
    )
  catch {
    @scheduler.SchedulerStateError::InvalidSchedulerState(_) => ()
    error => raise error
  } noraise {
    _ => fail("cross tenant placement accepted")
  }
  try
    reopened.place_reserved(
      nodes,
      requirements(),
      score_policy(),
      "reservation-a",
      "tenant-a",
      5000L,
    )
  catch {
    @scheduler.SchedulerStateError::InvalidSchedulerState(_) => ()
    error => raise error
  } noraise {
    _ => fail("expired placement accepted")
  }
  assert_true(reopened.node_is_reserved("a"))
}

///|
async test "service budgets and confirmed drain retain other service allocations" {
  let dir = @fs.tmpdir(prefix="node-reservation-drain-")
  defer @fs.rmdir(dir, recursive=true)
  let scheduler = @scheduler.FileScheduler::open("\{dir}/scheduler.json", 8)
  ignore(
    scheduler.reserve_nodes(
      reservation_request("r", "tenant", ["a", "b"]),
      ["a", "b"],
      1000L,
    ),
  )
  let claim : @scheduler.NodeServiceClaim = {
    service_id: "model",
    node_id: "a",
    memory_mib: 60000,
    gpu_memory_mib: 60000,
    concurrency: 2,
  }
  let first = scheduler.claim_node_service("r", "tenant", claim, 1001L)
  assert_eq(scheduler.claim_node_service("r", "tenant", claim, 1002L), first)
  try
    scheduler.claim_node_service(
      "r",
      "tenant",
      { ..claim, service_id: "too-big", },
      1002L,
    )
  catch {
    @scheduler.SchedulerStateError::InvalidSchedulerState(_) => ()
    error => raise error
  } noraise {
    _ => fail("memory budget exceeded")
  }
  ignore(
    scheduler.claim_node_service(
      "r",
      "tenant",
      {
        ..claim,
        service_id: "workspace",
        memory_mib: 4000,
        gpu_memory_mib: 0,
        concurrency: 1,
      },
      1002L,
    ),
  )
  scheduler.confirm_node_service_stopped("r", "workspace", 1003L)
  assert_eq(scheduler.node_reservation("r").unwrap().services, [claim])
  ignore(scheduler.begin_node_release("r", 5000L))
  try scheduler.complete_node_release("r", ["a", "b"], 5001L) catch {
    @scheduler.SchedulerStateError::InvalidSchedulerState(_) => ()
    error => raise error
  } noraise {
    _ => fail("live service released")
  }
  scheduler.confirm_node_service_stopped("r", "model", 5002L)
  try scheduler.complete_node_release("r", ["a"], 5003L) catch {
    @scheduler.SchedulerStateError::InvalidSchedulerState(_) => ()
    error => raise error
  } noraise {
    _ => fail("partial node release accepted")
  }
  assert_true(scheduler.node_is_reserved("b"))
  ignore(scheduler.complete_node_release("r", ["a", "b"], 5004L))
  assert_false(scheduler.node_is_reserved("b"))
}

///|
async test "concurrent tenant requests cannot partially reserve overlapping node sets" {
  let dir = @fs.tmpdir(prefix="node-reservation-race-")
  defer @fs.rmdir(dir, recursive=true)
  let scheduler = @scheduler.FileScheduler::open("\{dir}/scheduler.json", 8)
  let successes : Array[String] = []
  @async.with_task_group(group => {
    for tenant in ["first", "second"] {
      group.spawn_bg(() => {
        try
          scheduler.reserve_nodes(
            reservation_request(tenant, tenant, ["a", "b"]),
            ["a", "b"],
            1000L,
          )
        catch {
          @scheduler.SchedulerStateError::InvalidSchedulerState(_) => ()
          error => raise error
        } noraise {
          value => successes.push(value.request.tenant_ref)
        }
      })
    }
  })
  assert_eq(successes.length(), 1)
  assert_eq(scheduler.snapshot().node_reservations.unwrap().length(), 1)
}

///|
async test "failed reservation persistence does not leave an in memory node lock" {
  let dir = @fs.tmpdir(prefix="node-reservation-rollback-")
  let path = "\{dir}/scheduler.json"
  let scheduler = @scheduler.FileScheduler::open(path, 8)
  let before = scheduler.snapshot()
  @fs.remove(path)
  @fs.rmdir(dir)
  try
    scheduler.reserve_nodes(
      reservation_request("r", "tenant", ["a"]),
      ["a"],
      1000L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("write to missing directory unexpectedly succeeded")
  }
  assert_eq(scheduler.snapshot(), before)
  assert_false(scheduler.node_is_reserved("a"))
}
