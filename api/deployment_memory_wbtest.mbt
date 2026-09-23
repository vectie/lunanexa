///|
async test "GB10 planning uses fresh measured unified memory, not static GPU capacity" {
  let now = @async.now()
  let heartbeat : @contracts.NodeHeartbeat = {
    node_id: "node-a",
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: "node-a",
      agent_version: "test",
      os_release: "test",
      runtime_names: ["text-runtime"],
      accelerators: [
        {
          device_id: "gpu-0",
          architecture: "nvidia-sm121",
          memory_total_mib: 8192,
          memory_free_mib: 8192,
          healthy: true,
        },
      ],
      labels: {
        "lunanexa.gpu.model": "NVIDIA GB10",
        "lunanexa.data-classes": "Internal",
      },
      taints: [],
    },
    running_deployments: [],
    runtime_endpoints: None,
    timestamp_unix_ms: now,
    signature: "test",
  }
  let samples : Array[@contracts.TelemetrySample] = [
    {
      node_id: heartbeat.node_id,
      deployment_id: "",
      metric: "host_memory_available_mib",
      value: 1024.0,
      timestamp_unix_ms: now - 100L,
    },
  ]
  let observed = observed_available_memory_mib(
    samples,
    heartbeat.node_id,
    now,
    1000L,
  )
  assert_eq(observed, Some(1024))
  assert_eq(
    management_node(
      heartbeat,
      now,
      1000L,
      observed_available_memory_mib=observed,
    ).memory_free_mib,
    1024,
  )
  assert_true(
    observed_available_memory_mib(samples, heartbeat.node_id, now, 50L) is None,
  )
  assert_eq(management_node(heartbeat, now, 1000L).memory_free_mib, 0)
}
