///|
fn assignment() -> @contracts.DesiredAssignment {
  {
    assignment_id: "assignment-1",
    deployment_id: "deployment-1",
    node_id: "node-1",
    artifact: {
      digest: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      uri: "s3://artifacts/model-1",
      size_bytes: 1024L,
      signature_ref: "signature:model-1",
    },
    runtime: {
      name: "fake-text",
      image_digest: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      version: "1.0.0",
      architectures: ["nvidia-gb10"],
      capabilities: [TextGenerate],
      supports_batching: true,
      supports_multi_node: false,
    },
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 1000,
      cpu_millis: 1000,
      memory_mib: 2048,
    },
    devices: ["gpu-0"],
    network: {
      allow_controller: true,
      allow_artifact_store: true,
      allowed_egress: [],
    },
    health: {
      readiness_path: "/health",
      interval_ms: 1000,
      failure_threshold: 3,
      termination_grace_ms: 5000,
    },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    generation: 1L,
    lease_expires_unix_ms: 20000L,
    controller_epoch: 1L,
    signature: "valid-test-signature",
  }
}

///|
fn workload() -> @contracts.WorkloadEnvelope {
  {
    version: @contracts.contract_version,
    idempotency_key: "idem-1",
    workload_id: "workload-1",
    tenant_ref: "opaque-tenant",
    credential_scope: "inference",
    capability: TextGenerate,
    model_selector: "text.default",
    payload: { "input": "hello" },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: 20000L,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: 100,
      max_output_units: 100,
      max_runtime_ms: 1000L,
      max_accelerator_memory_mib: 1000,
    },
    stream: true,
    output_format: "text",
    trace_token: "opaque-trace",
  }
}

///|
test "one-node enroll deploy invoke restart reconciliation" {
  let control = @controller.ControlPlane::new("0.1.0", 1L)
  let identity = @controller.authenticate_local_operator(
    "operator:local", "secret-ref-value", "secret-ref-value",
  )
  assert_true(identity.authenticated)
  let enrollment = control.enrollment()
  ignore(enrollment.issue_token("bootstrap-1", "one-use", 2000L))
  let certificate = enrollment.enroll(
    "node-1", "bootstrap-1", "one-use", "node-auth-secret", "key-ref:node-1", 1000L,
  )
  assert_eq(certificate.serial, 1L)
  let desired = assignment()
  control.publish_assignment(desired)
  let verifier = @node.TestAssignmentVerifier::new("valid-test-signature")
  let agent = @node.NodeAgent::new("node-1")
  agent.activate()
  assert_true(agent.reconcile(desired, verifier, 1000L))
  assert_eq(agent.running_deployments().length(), 0)
  let runtime = @runtimes.FakeRuntime::new("fake-text")
  assert_true(@runtimes.RuntimeAdapter::inspect(runtime, desired.runtime))
  runtime.start()
  agent.observe_runtime(desired.assignment_id, Ready)
  assert_eq(agent.running_deployments(), [desired.deployment_id])
  let restored_agent = @node.NodeAgent::from_snapshot(agent.snapshot())
  assert_eq(restored_agent.running_deployments(), [desired.deployment_id])
  let response = control.invoke(runtime, workload(), 1000L)
  assert_eq(response.state, Succeeded)
  assert_eq(response.audit_receipt, "receipt:workload-1")
  assert_eq(runtime.invocation_count(), 1)
  let restarted = @controller.ControlPlane::from_snapshot(
    "0.1.0",
    2L,
    control.snapshot(),
  )
  assert_eq(restarted.store().assignments().length(), 1)
  assert_eq(restarted.store().audit_events().length(), 1)
  let recovered = @node.NodeAgent::recover(
    "node-1",
    restarted.store().assignments(),
    verifier,
    1001L,
  )
  assert_eq(recovered.assignment_count(), 1)
  assert_eq(recovered.running_deployments().length(), 0)
}

///|
test "bootstrap tokens are one use and stale controller epochs are fenced" {
  let enrollment = @node.EnrollmentService::new()
  ignore(enrollment.issue_token("token", "secret", 100L))
  ignore(
    enrollment.enroll("node-1", "token", "secret", "node-auth", "key", 10L),
  )
  try
    enrollment.enroll("node-2", "token", "secret", "node-auth", "key", 11L)
  catch {
    @node.NodeError::InvalidBootstrapToken => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected token reuse rejection")
  }
  let verifier = @node.TestAssignmentVerifier::new("valid-test-signature")
  let agent = @node.NodeAgent::new("node-1")
  agent.activate()
  let current = assignment()
  assert_true(
    agent.reconcile({ ..current, controller_epoch: 2L }, verifier, 1L),
  )
  try agent.reconcile(current, verifier, 1L) catch {
    @node.NodeError::StaleControllerEpoch => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected stale controller rejection")
  }
}

///|
test "cordoned and draining agents do not launch new assignments" {
  let verifier = @node.TestAssignmentVerifier::new("valid-test-signature")
  let desired = assignment()
  let cordoned = @node.NodeAgent::new("node-1")
  cordoned.activate()
  cordoned.cordon()
  assert_false(cordoned.reconcile(desired, verifier, 1000L))
  assert_eq(cordoned.assignment_count(), 0)
  let draining = @node.NodeAgent::new("node-1")
  draining.activate()
  draining.drain()
  assert_false(draining.reconcile(desired, verifier, 1000L))
  assert_eq(draining.assignment_count(), 0)
  let active = @node.NodeAgent::new("node-1")
  active.activate()
  assert_true(active.reconcile(desired, verifier, 1000L))
  assert_eq(active.remove_absent([]), [desired.assignment_id])
  assert_eq(active.assignment_count(), 0)
}
