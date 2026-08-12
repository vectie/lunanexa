///|
fn adversarial_template() -> @deployment.ModelServiceTemplate {
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
      size_bytes: 1024L,
      signature_ref: "s3://models/model.text/v1.sig",
    },
    runtime: {
      name: "registry.example/lunanexa/text-runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "runtime-v1",
      architectures: ["nvidia-gb10"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    capability: TextGenerate,
    architecture: "nvidia-gb10",
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 24000,
      cpu_millis: 4000,
      memory_mib: 32000,
    },
    network: {
      allow_controller: true,
      allow_artifact_store: true,
      allowed_egress: [],
    },
    health: {
      readiness_path: "/health/ready",
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
fn adversarial_intent() -> @deployment.ModelServiceIntent {
  {
    version: @contracts.contract_version,
    idempotency_key: "console:service-1",
    deployment_id: "service-1",
    template: { template_id: "text-small", version: "v1" },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
  }
}

///|
fn expect_invalid_template(
  candidate : @deployment.ModelServiceTemplate,
) -> Unit raise {
  try @deployment.validate_template(candidate) catch {
    InvalidTemplate(_) => ()
    error => fail("unexpected template error: \{Repr(error)}")
  } noraise {
    _ => fail("adversarial template was accepted")
  }
}

///|
fn intent_is_valid(candidate : @deployment.ModelServiceIntent) -> Bool {
  try @deployment.validate_intent(candidate) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
test "deterministic fuzz exhausts deployment intent boundaries" {
  let base = adversarial_intent()
  for length in 0..<=300 {
    let deployment_id = "a".repeat(length)
    assert_eq(
      intent_is_valid({ ..base, deployment_id, }),
      length > 0 && length <= 128,
    )
    let idempotency_key = "b".repeat(length)
    assert_eq(
      intent_is_valid({ ..base, idempotency_key, }),
      length > 0 && length <= 256,
    )
  }
  for replicas in -128..<=128 {
    assert_eq(intent_is_valid({ ..base, replicas, }), replicas == 1)
  }
  for
    hostile in [
      "../service", "service/name", "service name", "service\nname", "service<script>",
      "service%2fadmin", "服务",
    ] {
    assert_false(intent_is_valid({ ..base, deployment_id: hostile }))
    assert_false(intent_is_valid({ ..base, idempotency_key: hostile }))
  }
  for duration in [-1L, 0L, 2592000001L, 9223372036854775807L] {
    assert_false(intent_is_valid({ ..base, lease_duration_ms: duration }))
  }
  assert_true(intent_is_valid({ ..base, lease_duration_ms: 1L }))
  assert_true(intent_is_valid({ ..base, lease_duration_ms: 2592000000L }))
}

///|
test "mutation fuzz rejects forbidden identifier bytes at every position" {
  let base = adversarial_intent()
  let mutations = [
    "/", "\\", " ", "\n", "<", ">", "%", "?", "'", "\"", "服务",
  ]
  for position in 0..<=128 {
    for mutation in mutations {
      let candidate = "a".repeat(position) +
        mutation +
        "b".repeat(128 - position)
      assert_false(intent_is_valid({ ..base, deployment_id: candidate }))
    }
  }
  for position in 0..<=256 {
    for mutation in mutations {
      let candidate = "a".repeat(position) +
        mutation +
        "b".repeat(256 - position)
      assert_false(intent_is_valid({ ..base, idempotency_key: candidate }))
    }
  }
}

///|
test "adversarial catalog corpus fails before assignment planning" {
  let base = adversarial_template()
  let invalid : Array[@deployment.ModelServiceTemplate] = [
    { ..base, artifact: { ..base.artifact, size_bytes: 0L } },
    { ..base, artifact: { ..base.artifact, size_bytes: 1099511627777L } },
    { ..base, artifact: { ..base.artifact, uri: "s3://models/../secret" } },
    { ..base, artifact: { ..base.artifact, uri: "s3://models//model" } },
    {
      ..base,
      artifact: { ..base.artifact, uri: "s3://models/model?version=1" },
    },
    { ..base, artifact: { ..base.artifact, uri: "s3://models/%2e%2e/secret" } },
    { ..base, artifact: { ..base.artifact, signature_ref: "../../sig" } },
    { ..base, runtime: { ..base.runtime, name: "image@latest" } },
    { ..base, runtime: { ..base.runtime, name: "image\n--privileged" } },
    { ..base, runtime: { ..base.runtime, architectures: [] } },
    {
      ..base,
      runtime: { ..base.runtime, architectures: ["nvidia-gb10", "nvidia-gb10"] },
    },
    { ..base, runtime: { ..base.runtime, capabilities: [] } },
    { ..base, runtime: { ..base.runtime, supports_batching: true } },
    { ..base, runtime: { ..base.runtime, supports_multi_node: true } },
    { ..base, capability: ImageGenerate },
    { ..base, resources: { ..base.resources, accelerator_count: 65 } },
    { ..base, resources: { ..base.resources, memory_mib: 1048577 } },
    { ..base, network: { ..base.network, allow_controller: false } },
    { ..base, network: { ..base.network, allowed_egress: ["0.0.0.0/0"] } },
    {
      ..base,
      health: { ..base.health, readiness_path: "http://attacker/ready" },
    },
    { ..base, health: { ..base.health, readiness_path: "/../../ready" } },
    { ..base, health: { ..base.health, interval_ms: 3600001 } },
    { ..base, health: { ..base.health, failure_threshold: 101 } },
    { ..base, rollout: { ..base.rollout, readiness_timeout_ms: 86400001L } },
    { ..base, secret_refs: ["runtime-token", "runtime-token"] },
  ]
  for candidate in invalid {
    expect_invalid_template(candidate)
    let plan = @deployment.preflight([candidate], adversarial_intent(), {
      registry: [],
      nodes: [],
      available_secret_refs: [],
    })
    assert_false(plan.executable)
    assert_true(plan.findings.any(value => value.severity == Blocking))
  }
}

///|
fn eligible_node(node_id : String) -> @deployment.ManagementNode {
  {
    node_id,
    state: Active,
    architecture: "nvidia-gb10",
    memory_free_mib: 80000,
    runtime_names: ["registry.example/lunanexa/text-runtime"],
    device_ids: ["gpu-0"],
    allowed_data_classes: [Internal],
  }
}

///|
fn approved_evidence() -> @deployment.RegistryEvidence {
  let catalog = adversarial_template()
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
  }
}

///|
test "placement fuzz is deterministic and duplicate-node fail closed" {
  let catalog = adversarial_template()
  let intent = adversarial_intent()
  for
    nodes in [
      [
        eligible_node("node-c"),
        eligible_node("node-a"),
        eligible_node("node-b"),
      ],
      [
        eligible_node("node-b"),
        eligible_node("node-c"),
        eligible_node("node-a"),
      ],
      [
        eligible_node("node-a"),
        eligible_node("node-b"),
        eligible_node("node-c"),
      ],
    ] {
    let plan = @deployment.preflight([catalog], intent, {
      registry: [approved_evidence()],
      nodes,
      available_secret_refs: ["runtime-token"],
    })
    assert_true(plan.executable)
    assert_eq(plan.replicas[0].node_id, "node-a")
  }
  let multi_machine_plan = @deployment.preflight(
    [catalog],
    { ..intent, replicas: 2 },
    {
      registry: [approved_evidence()],
      nodes: [eligible_node("node-a"), eligible_node("node-a")],
      available_secret_refs: ["runtime-token"],
    },
  )
  assert_false(multi_machine_plan.executable)
  assert_true(
    multi_machine_plan.findings.any(value => value.code == InvalidIntent),
  )
  assert_eq(multi_machine_plan.replicas, [])
}
