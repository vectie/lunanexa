///|
test "deployment readiness requires matching generation and live heartbeat" {
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "deploy-1",
    deployment_id: "service-1",
    template: { template_id: "template-1", version: "v1" },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
  }
  let plan : @deployment.DeploymentPlan = {
    plan_id: "plan-1",
    intent,
    template: None,
    replicas: [
      { replica_id: "service-1-r1", node_id: "node-a", devices: ["gpu-0"] },
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
      [{ ..assignment, generation: 1L }],
      [heartbeat],
      1100L,
    ),
  )
  for
    hostile_heartbeat in [
      { ..heartbeat, state: Cordoned },
      { ..heartbeat, observed_generation: 1L },
      { ..heartbeat, controller_epoch: 2L },
      { ..heartbeat, inventory: { ..heartbeat.inventory, node_id: "node-b" } },
      { ..heartbeat, timestamp_unix_ms: -20000L },
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
      { ..assignment, signature: "" },
      { ..assignment, lease_expires_unix_ms: 1100L },
      { ..assignment, controller_epoch: 2L },
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
