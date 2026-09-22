///|
test "deployment readiness requires matching generation and live heartbeat" {
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "deploy-1",
    deployment_id: "service-1",
    template: { template_id: "template-1", version: "v1", },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
    topology_profile: None,
  }
  let plan : @deployment.DeploymentPlan = {
    plan_id: "plan-1",
    intent,
    template: None,
    replicas: [
      {
        replica_id: "service-1-r1",
        node_id: "node-a",
        devices: ["gpu-0"],
        group: None,
      },
    ],
    findings: [],
    executable: false,
    endpoint: None,
  }
  let operation : @deployment.DeploymentOperation = {
    operation_id: "operation:service-1:2",
    deployment_id: "service-1",
    generation: 2L,
    state: Reconciling,
    plan,
    assignment_ids: ["service-1-r1"],
    endpoint: None,
    message: "waiting",
    audit_receipt: "deployment:service-1:2",
    created_unix_ms: 1L,
    updated_unix_ms: 1L,
  }
  let assignment : @contracts.DesiredAssignment = {
    assignment_id: "service-1-r1",
    deployment_id: "service-1",
    node_id: "node-a",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model/v1",
      size_bytes: 1L,
      signature_ref: "cosign:model",
    },
    runtime: {
      name: "runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "v1",
      architectures: ["arch"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 1,
      cpu_millis: 1,
      memory_mib: 1,
    },
    devices: ["gpu-0"],
    network: {
      allow_controller: true,
      allow_artifact_store: true,
      allowed_egress: [],
    },
    health: {
      readiness_path: "/health",
      interval_ms: 1,
      failure_threshold: 1,
      termination_grace_ms: 1,
    },
    data_policy: {
      classification: Internal,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    generation: 2L,
    lease_expires_unix_ms: 100000L,
    controller_epoch: 1L,
    group: None,
    signature: "signed",
  }
  let heartbeat : @contracts.NodeHeartbeat = {
    node_id: "node-a",
    state: Active,
    observed_generation: 2L,
    controller_epoch: 1L,
    inventory: {
      node_id: "node-a",
      agent_version: "v1",
      os_release: "test",
      runtime_names: ["runtime"],
      accelerators: [],
      labels: {},
      taints: [],
    },
    running_deployments: ["service-1"],
    runtime_endpoints: None,
    timestamp_unix_ms: 1000L,
    signature: "signed",
  }
  assert_true(
    @controller.deployment_operation_ready(
      operation,
      [assignment],
      [heartbeat],
      1100L,
    ),
  )
  assert_false(
    @controller.deployment_operation_ready(
      operation,
      [{ ..assignment, generation: 1L, }],
      [heartbeat],
      1100L,
    ),
  )
  for
    hostile_heartbeat in [
      { ..heartbeat, state: Cordoned, },
      { ..heartbeat, observed_generation: 1L, },
      { ..heartbeat, controller_epoch: 2L, },
      { ..heartbeat, inventory: { ..heartbeat.inventory, node_id: "node-b", }, },
      { ..heartbeat, timestamp_unix_ms: -20000L, },
    ] {
    assert_false(
      @controller.deployment_operation_ready(
        operation,
        [assignment],
        [hostile_heartbeat],
        1100L,
      ),
    )
  }
  for
    hostile_assignment in [
      { ..assignment, signature: "", },
      { ..assignment, lease_expires_unix_ms: 1100L, },
      { ..assignment, controller_epoch: 2L, },
    ] {
    assert_false(
      @controller.deployment_operation_ready(
        operation,
        [hostile_assignment],
        [heartbeat],
        1100L,
      ),
    )
  }
}

///|
/// A paired placement is one logical instance in two ranked members. It is
/// Ready only while both ranks are live: a half-present pair must never be
/// promoted, and neither rank alone can carry the deployment.
test "a paired placement is ready only when both ranks are live" {
  let group : @contracts.AssignmentGroup = {
    group_id: "service-2-pair",
    rank: 0,
    world_size: 2,
    peer_endpoint: "10.0.22.2",
  }
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "deploy-2",
    deployment_id: "service-2",
    template: { template_id: "template-2", version: "v1", },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
    topology_profile: Some(@contracts.cx7_pair_topology_profile),
  }
  let plan : @deployment.DeploymentPlan = {
    plan_id: "plan-2",
    intent,
    template: None,
    replicas: [
      {
        replica_id: "service-2-r1",
        node_id: "node-a",
        devices: ["gpu-0"],
        group: Some(group),
      },
      {
        replica_id: "service-2-r2",
        node_id: "node-b",
        devices: ["gpu-0"],
        group: Some({ ..group, rank: 1, peer_endpoint: "10.0.22.1", }),
      },
    ],
    findings: [],
    executable: true,
    endpoint: None,
  }
  let operation : @deployment.DeploymentOperation = {
    operation_id: "operation:service-2:2",
    deployment_id: "service-2",
    generation: 2L,
    state: Reconciling,
    plan,
    assignment_ids: ["service-2-r1", "service-2-r2"],
    endpoint: None,
    message: "waiting",
    audit_receipt: "deployment:service-2:2",
    created_unix_ms: 1L,
    updated_unix_ms: 1L,
  }
  let head : @contracts.DesiredAssignment = {
    assignment_id: "service-2-r1",
    deployment_id: "service-2",
    node_id: "node-a",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model/v1",
      size_bytes: 1L,
      signature_ref: "cosign:model",
    },
    runtime: {
      name: "runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "v1",
      architectures: ["arch"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: true,
    },
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 1,
      cpu_millis: 1,
      memory_mib: 1,
    },
    devices: ["gpu-0"],
    network: {
      allow_controller: true,
      allow_artifact_store: true,
      allowed_egress: [],
    },
    health: {
      readiness_path: "/health",
      interval_ms: 1,
      failure_threshold: 1,
      termination_grace_ms: 1,
    },
    data_policy: {
      classification: Internal,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    generation: 2L,
    lease_expires_unix_ms: 100000L,
    controller_epoch: 1L,
    group: Some(group),
    signature: "signed",
  }
  let worker = {
    ..head,
    assignment_id: "service-2-r2",
    node_id: "node-b",
    group: Some({ ..group, rank: 1, peer_endpoint: "10.0.22.1", }),
  }
  let heartbeat : @contracts.NodeHeartbeat = {
    node_id: "node-a",
    state: Active,
    observed_generation: 2L,
    controller_epoch: 1L,
    inventory: {
      node_id: "node-a",
      agent_version: "v1",
      os_release: "test",
      runtime_names: ["runtime"],
      accelerators: [],
      labels: {
        "lunanexa.io/cx7-peer": "node-b",
        "lunanexa.io/cx7-address": "10.0.22.1",
      },
      taints: [],
    },
    running_deployments: ["service-2"],
    runtime_endpoints: None,
    timestamp_unix_ms: 1000L,
    signature: "signed",
  }
  let peer_heartbeat = {
    ..heartbeat,
    node_id: "node-b",
    inventory: { ..heartbeat.inventory, node_id: "node-b", },
  }
  assert_true(
    @controller.deployment_operation_ready(
      operation,
      [head, worker],
      [heartbeat, peer_heartbeat],
      1100L,
    ),
  )
  // One rank reporting is not the deployment: the whole pair is required.
  assert_false(
    @controller.deployment_operation_ready(
      operation,
      [head, worker],
      [heartbeat],
      1100L,
    ),
  )
  assert_false(
    @controller.deployment_operation_ready(
      operation,
      [head, worker],
      [peer_heartbeat],
      1100L,
    ),
  )
  // A pair whose members disagree about the rank they claim cannot be promoted.
  assert_false(
    @controller.deployment_operation_ready(
      operation,
      [head, { ..worker, group: Some(group), }],
      [heartbeat, peer_heartbeat],
      1100L,
    ),
  )
}
