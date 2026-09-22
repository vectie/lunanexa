///|
test "cache locality only trusts fresh exact digest hints inside the reservation" {
  let digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let heartbeat : @contracts.NodeHeartbeat = {
    node_id: "node-a",
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: "node-a",
      agent_version: "test",
      os_release: "test",
      runtime_names: [],
      accelerators: [],
      labels: {
        "lunanexa.io/verified-artifact-digests": [digest].to_json().stringify(),
      },
      taints: [],
    },
    running_deployments: [],
    runtime_endpoints: None,
    timestamp_unix_ms: 1000L,
    signature: "authenticated-upstream",
  }
  let nodes = [
    heartbeat,
    { ..heartbeat, node_id: "foreign", },
    { ..heartbeat, node_id: "stale", timestamp_unix_ms: 1L, },
    { ..heartbeat, node_id: "future", timestamp_unix_ms: 10001L, },
    { ..heartbeat, node_id: "down", state: Unreachable, },
  ]
  assert_eq(
    @scheduler.cached_reserved_nodes(
      nodes,
      ["node-a", "stale", "future", "down"],
      digest,
      1100L,
      500L,
    ),
    ["node-a"],
  )
  assert_eq(
    @scheduler.cached_reserved_nodes(
      nodes,
      ["node-a"],
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      1100L,
      500L,
    ),
    [],
  )
  assert_eq(
    @scheduler.cached_reserved_nodes(
      [
        {
          ..heartbeat,
          inventory: {
            ..heartbeat.inventory,
            labels: { "lunanexa.io/verified-artifact-digests": "not-json" },
          },
        },
      ],
      ["node-a"],
      digest,
      1100L,
      500L,
    ),
    [],
  )
}
