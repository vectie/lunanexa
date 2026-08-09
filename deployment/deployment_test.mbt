///|
fn template() -> @deployment.ModelServiceTemplate {
  {
    template_id: "text-small",
    version: "v1",
    display_name: "Text small",
    description: "Approved text service",
    model_selector: "text.default",
    model_id: "model.text",
    model_version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model.text/v1",
      size_bytes: 1L,
      signature_ref: "cosign:model",
    },
    runtime: {
      name: "text-runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "runtime-v1",
      architectures: ["nvidia-gb10"],
      capabilities: [TextGenerate],
      supports_batching: true,
      supports_multi_node: false,
    },
    capability: TextGenerate,
    architecture: "nvidia-gb10",
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 1000,
      cpu_millis: 1000,
      memory_mib: 2000,
    },
    network: {
      allow_controller: true,
      allow_artifact_store: true,
      allowed_egress: [],
    },
    health: {
      readiness_path: "/health",
      interval_ms: 1000,
      failure_threshold: 3,
      termination_grace_ms: 30000,
    },
    data_policy: {
      classification: Internal,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    secret_refs: ["runtime-token"],
    rollout: {
      canary_replicas: 1,
      automatic_promotion: false,
      automatic_rollback: true,
      readiness_timeout_ms: 60000L,
    },
    approval_receipt: "catalog:text-small:v1",
    signature: "signed",
  }
}

///|
fn intent() -> @deployment.ModelServiceIntent {
  {
    version: @contracts.contract_version,
    idempotency_key: "deploy-text-small",
    deployment_id: "text-small-service",
    template: { template_id: "text-small", version: "v1" },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
  }
}

///|
test "approved template produces deterministic executable plan" {
  let catalog = template()
  let plan = @deployment.preflight([catalog], intent(), {
    registry: [
      {
        model_id: catalog.model_id,
        model_version: catalog.model_version,
        model_state: Approved,
        artifact_digest: catalog.artifact.digest,
        runtime_name: catalog.runtime.name,
        runtime_version: catalog.runtime.version,
        runtime_image_digest: catalog.runtime.image_digest,
        model_selector: catalog.model_selector,
        license_accepted: true,
        artifact_verified: true,
        runtime_verified: true,
        evaluation_passed: true,
        alias_points_to_model: true,
      },
    ],
    nodes: [
      {
        node_id: "node-a",
        state: Active,
        architecture: "nvidia-gb10",
        memory_free_mib: 8000,
        runtime_names: ["text-runtime"],
        device_ids: ["gpu-0"],
        allowed_data_classes: [Internal],
      },
    ],
    available_secret_refs: ["runtime-token"],
  })
  assert_true(plan.executable)
  assert_eq(plan.plan_id, "plan:text-small-service:text-small:v1")
  assert_eq(plan.replicas[0].node_id, "node-a")
  let assignments = @deployment.desired_assignments(plan, 2L, 1L, 1000L)
  assert_eq(assignments[0].assignment_id, "text-small-service-r1")
  assert_eq(assignments[0].controller_epoch, 2L)
}

///|
test "preflight blocks missing evidence secrets and capacity" {
  let plan = @deployment.preflight([template()], intent(), {
    registry: [],
    nodes: [],
    available_secret_refs: [],
  })
  assert_false(plan.executable)
  assert_true(plan.findings.any(value => value.code == RuntimeNotRegistered))
  assert_true(plan.findings.any(value => value.code == MissingSecretReference))
  assert_true(
    plan.findings.any(value => value.message.contains("runtime-token")),
  )
  assert_true(plan.findings.any(value => value.code == NoCompatibleNode))
}
