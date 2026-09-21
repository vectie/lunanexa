///|
fn endpoint_fixture() -> @contracts.RuntimeEndpoint {
  let assignment = supervisor_assignment()
  {
    assignment_id: assignment.assignment_id,
    deployment_id: assignment.deployment_id,
    generation: assignment.generation,
    controller_epoch: assignment.controller_epoch,
    instance_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    address: "10.42.1.9",
    port: 5885,
    artifact_digest: assignment.artifact.digest,
    image_digest: assignment.runtime.image_digest,
    observed_unix_ms: 1000L,
  }
}

///|
test "runtime endpoint requires live matching assignment and fresh post-restart observation" {
  let assignment = supervisor_assignment()
  let endpoint = endpoint_fixture()
  let agent = NodeAgent::new(assignment.node_id)
  agent.activate()
  assert_false(agent.observe_runtime_endpoint(endpoint, 1000L))
  assert_true(
    agent.reconcile(assignment, TestAssignmentVerifier::new("signed"), 1000L),
  )
  assert_false(agent.observe_runtime_endpoint(endpoint, 1000L))
  agent.observe_runtime(assignment.assignment_id, Ready)
  assert_true(agent.observe_runtime_endpoint(endpoint, 1000L))
  assert_eq(agent.runtime_endpoints(1000L), [endpoint])
  assert_eq(agent.runtime_endpoints(16001L), [])
  for
    hostile in [
      { ..endpoint, generation: 2L, },
      { ..endpoint, controller_epoch: 2L, },
      { ..endpoint, deployment_id: "another-deployment", },
      { ..endpoint, image_digest: assignment.artifact.digest, },
      { ..endpoint, artifact_digest: assignment.runtime.image_digest, },
      { ..endpoint, address: "169.254.169.254", },
      { ..endpoint, address: "10.42.1.9:80", },
      { ..endpoint, instance_id: "pod-name-is-not-an-incarnation", },
    ] {
    assert_false(agent.observe_runtime_endpoint(hostile, 1000L))
  }
  let restored = NodeAgent::from_snapshot(agent.snapshot())
  assert_eq(restored.assignment_count(), 1)
  assert_eq(restored.running_deployments(), [])
  assert_eq(restored.runtime_endpoints(1000L), [])
  agent.observe_runtime(assignment.assignment_id, Failed)
  assert_eq(agent.runtime_endpoints(1000L), [])
  agent.observe_runtime(assignment.assignment_id, Ready)
  assert_true(agent.observe_runtime_endpoint(endpoint, 1000L))
  assert_eq(agent.runtime_endpoints(assignment.lease_expires_unix_ms), [])
  ignore(agent.remove_absent([]))
  assert_eq(agent.runtime_endpoints(1000L), [])
}

///|
test "runtime route boundaries accept exact private networks and reject URL tricks" {
  let policy : @contracts.RuntimeRoutePolicy = {
    network: "10.42.1.0",
    prefix_length: 24,
    port: 5885,
  }
  let endpoint = endpoint_fixture()
  assert_true(policy.valid())
  assert_true(policy.allows(endpoint))
  for
    address in [
      "10.42.2.9", "127.0.0.1", "169.254.169.254", "10.42.01.9", "10.42.1.256", "10.42.1.9/path",
      "10.42.1.9@evil", "::1",
    ] {
    assert_false(policy.allows({ ..endpoint, address, }))
  }
  assert_false(policy.allows({ ..endpoint, port: 80, }))
  for
    invalid in [
      { ..policy, network: "10.42.1.9", },
      { ..policy, network: "8.8.8.0", },
      { ..policy, prefix_length: 0, },
      { ..policy, prefix_length: 33, },
      { ..policy, port: 0, },
    ] {
    assert_false(invalid.valid())
  }
  assert_true(
    (
      { ..policy, network: "10.42.1.9", prefix_length: 32, } :
      @contracts.RuntimeRoutePolicy).allows(endpoint),
  )
  assert_false(
    (
      { ..policy, network: "10.42.1.128", prefix_length: 25, } :
      @contracts.RuntimeRoutePolicy).allows(endpoint),
  )
}

///|
test "endpoint heartbeats authenticate routes without changing the legacy MAC" {
  let heartbeat : @contracts.NodeHeartbeat = {
    node_id: "node-a",
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: "node-a",
      agent_version: "fixture",
      os_release: "test-only",
      runtime_names: [],
      accelerators: [],
      labels: Map([]),
      taints: [],
    },
    running_deployments: ["deployment-materialize-1"],
    runtime_endpoints: None,
    timestamp_unix_ms: 1000L,
    signature: "",
  }
  let legacy : Json = {
    "node_id": heartbeat.node_id,
    "state": heartbeat.state.to_json(),
    "observed_generation": heartbeat.observed_generation.to_json(),
    "controller_epoch": heartbeat.controller_epoch.to_json(),
    "inventory": heartbeat.inventory.to_json(),
    "running_deployments": heartbeat.running_deployments.to_json(),
    "timestamp_unix_ms": heartbeat.timestamp_unix_ms.to_json(),
    "signature": "",
  }
  let key = @utf8.encode("fixture-node-key")
  let material = @utf8.encode("lunanexa.heartbeat-mac.v1|" + legacy.stringify())
  let expected = @crypto.bytes_to_hex_string(
    @crypto.hmac(@crypto.SHA256::new(), key.view(), material.view()),
  )
  assert_eq(heartbeat_signature(heartbeat, "fixture-node-key"), expected)
  let endpoint = endpoint_fixture()
  let reported = { ..heartbeat, runtime_endpoints: Some([endpoint]), }
  let signature = heartbeat_signature(reported, "fixture-node-key")
  assert_true(signature != expected)
  assert_true(
    signature !=
    heartbeat_signature(
      {
        ..reported,
        runtime_endpoints: Some([{ ..endpoint, address: "10.42.1.10", }]),
      },
      "fixture-node-key",
    ),
  )
  let decoded : @contracts.NodeHeartbeat = @json.from_json(legacy)
  assert_eq(decoded.runtime_endpoints, None)
  assert_eq(decoded.to_json().stringify(), legacy.stringify())
  assert_eq(heartbeat_signature(decoded, "fixture-node-key"), expected)
}
