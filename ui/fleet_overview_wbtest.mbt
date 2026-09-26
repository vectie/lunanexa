///|
test "fleet posture requires fresh reservation evidence before showing a candidate" {
  let base = default_state()
  let node : NodeRow = {
    node_id: "node-a",
    state: Active,
    architecture: "nvidia-gb10",
    usage_pool: "enterprise-dedicated",
    accelerators: [
      {
        device_id: "gpu-0",
        architecture: "nvidia-gb10",
        memory_total_mib: 100,
        memory_free_mib: 100,
        healthy: true,
      },
    ],
    total_memory_mib: 100,
    free_memory_mib: 100,
    used_memory_mib: 0,
    memory_measured: true,
    utilization_per_mille: 0,
    cpu_per_mille: 0,
    cpu_measured: true,
    temperature_celsius: 35,
    power_watts: 20,
    workloads: 0,
    lease_holder: "",
    active_assignment: "",
    last_seen: "Just now",
  }
  let known = {
    ..base,
    resource_delivery: {
      ..base.resource_delivery,
      loaded: true,
      checked_unix_ms: 1000L,
    },
  }
  let (fresh_tone, _, _) = fleet_node_posture(known, node, 50000L)
  assert_eq(fresh_tone, "candidate")
  let pressured = { ..node, total_memory_mib: 122880, free_memory_mib: 9000, }
  let (pressured_tone, pressured_label, _) = fleet_node_posture(
    known, pressured, 50000L,
  )
  assert_eq(pressured_tone, "blocked")
  assert_eq(pressured_label, "Host memory pressured")
  let (stale_tone, _, _) = fleet_node_posture(known, node, 62000L)
  assert_eq(stale_tone, "unknown")
  let unavailable = {
    ..known,
    resource_delivery: {
      ..known.resource_delivery,
      error: Some("read failed"),
    },
  }
  let (error_tone, _, _) = fleet_node_posture(unavailable, node, 2000L)
  assert_eq(error_tone, "unknown")
  let (missing_tone, _, _) = fleet_node_posture(
    known,
    { ..node, accelerators: [], },
    2000L,
  )
  assert_eq(missing_tone, "unknown")
  let unhealthy = {
    ..node,
    accelerators: [{ ..node.accelerators[0], healthy: false, }],
  }
  let (unhealthy_tone, _, _) = fleet_node_posture(known, unhealthy, 2000L)
  assert_eq(unhealthy_tone, "blocked")
}
