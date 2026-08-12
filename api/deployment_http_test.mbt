///|
fn management_template() -> @deployment.ModelServiceTemplate {
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
      name: "text-runtime",
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
      accelerator_memory_mib: 1024,
      cpu_millis: 1000,
      memory_mib: 2048,
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
    approval_receipt: "",
    signature: "",
  }
}

///|
async fn management_registry(
  path : String,
  template : @deployment.ModelServiceTemplate,
) -> @registry.FileRegistry {
  let registry = @registry.FileRegistry::open(path)
  registry.register_runtime(template.runtime)
  registry.register_model({
    model_id: template.model_id,
    version: template.model_version,
    artifact: template.artifact,
    license_id: "license.text",
    provenance: "upstream",
    compatible_architectures: [template.architecture],
    minimum_memory_mib: 1024,
    state: Candidate,
  })
  registry.record_license({
    license_id: "license.text",
    model_id: template.model_id,
    status: Accepted,
    accepted_by: "operator",
    evidence_ref: "license-review",
    expires_unix_ms: None,
  })
  registry.record_verification({
    digest: template.artifact.digest,
    signature_verified: true,
    provenance_verified: true,
    verified_unix_ms: 1L,
    verifier: "test",
  })
  registry.record_verification({
    digest: template.runtime.image_digest,
    signature_verified: true,
    provenance_verified: true,
    verified_unix_ms: 1L,
    verifier: "test",
  })
  registry.record_evaluation({
    evaluation_id: "eval.text.v1",
    model_id: template.model_id,
    model_version: template.model_version,
    suite_version: "suite-v1",
    passed: true,
    score: 1.0,
    benchmark: {
      profile_id: "profile-v1",
      model_id: template.model_id,
      model_version: template.model_version,
      runtime_version: template.runtime.version,
      hardware_profile: template.architecture,
      workload_profile: "smoke",
      p50_ms: 1.0,
      p95_ms: 2.0,
      p99_ms: 3.0,
      throughput_per_second: 1.0,
      peak_memory_mib: 1024,
    },
    evidence_ref: "evaluation-report",
  })
  ignore(registry.approve(template.model_id, template.model_version, 2L))
  ignore(
    registry.promote(
      template.model_selector,
      template.model_id,
      template.model_version,
      Canary,
      "operator",
      3L,
    ),
  )
  registry
}

///|
fn management_heartbeat(
  running : Array[String],
  observed_generation? : Int64 = 1L,
) -> @contracts.NodeHeartbeat {
  {
    node_id: "node-a",
    state: Active,
    observed_generation,
    controller_epoch: 1L,
    inventory: {
      node_id: "node-a",
      agent_version: "0.1.0",
      os_release: "test",
      runtime_names: ["text-runtime"],
      accelerators: [
        {
          device_id: "gpu-0",
          architecture: "nvidia-gb10",
          memory_total_mib: 8192,
          memory_free_mib: 8192,
          healthy: true,
        },
      ],
      labels: { "lunanexa.data-classes": "Internal" },
      taints: [],
    },
    running_deployments: running,
    timestamp_unix_ms: @async.now(),
    signature: "test",
  }
}

///|
async test "one request creates durable assignments and converges to ready" {
  let directory = @fs.tmpdir(prefix="lunanexa-management-api-")
  let template = management_template()
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.fence_controller(1L)
  durable.put_heartbeat(management_heartbeat([]))
  let registry = management_registry("\{directory}/registry.json", template)
  let deployments = @deployment_store.FileDeploymentStore::open(
    "\{directory}/deployments.json",
    "assignment-secret",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    template.runtime.version,
    template.runtime.image_digest,
    template.artifact.digest,
    allow_http_loopback=true,
  )
  let service = @api.ApiService::with_registry(
      durable, registry, runtime, "operator-token", "inference-token", "node-token",
      "0.1.0",
    )
    .with_assignment_signing_secret("assignment-secret")
    .with_deployment_store(deployments, available_secret_refs=["runtime-token"])
  let headers = { "Authorization": "Bearer operator-token" }
  let registered = service.handle(
    Post,
    "/v1/catalog/templates",
    headers,
    template.to_json().stringify(),
  )
  assert_eq(registered.status, 201)
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "deploy-text-small",
    deployment_id: "text-small-service",
    template: { template_id: "text-small", version: "v1" },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
  }
  let created = service.handle(
    Post,
    "/v1/service-deployments",
    headers,
    intent.to_json().stringify(),
  )
  assert_eq(created.status, 202)
  let operation : @deployment.DeploymentOperation = @json.from_json(
    @json.parse(created.body),
  )
  assert_eq(operation.state, Reconciling)
  let assignments = durable.assignments()
  assert_eq(assignments.length(), 1)
  assert_true(assignments[0].signature != "")
  durable.put_heartbeat(management_heartbeat([intent.deployment_id]))
  let observed = durable.heartbeats()[0]
  assert_eq(observed.state, Active)
  assert_eq(observed.inventory.node_id, assignments[0].node_id)
  assert_eq(observed.controller_epoch, assignments[0].controller_epoch)
  assert_true(observed.observed_generation >= assignments[0].generation)
  assert_true(assignments[0].lease_expires_unix_ms > @async.now())
  assert_true(
    @controller.deployment_operation_ready(
      operation,
      assignments,
      [observed],
      @async.now(),
    ),
  )
  let ready = service.handle(
    Get,
    "/v1/operations/\{operation.operation_id}",
    headers,
    "",
  )
  assert_eq(ready.status, 200)
  let ready_operation : @deployment.DeploymentOperation = @json.from_json(
    @json.parse(ready.body),
  )
  assert_eq(ready_operation.state, Ready)
  let repeated = service.handle(
    Post,
    "/v1/service-deployments",
    headers,
    intent.to_json().stringify(),
  )
  assert_eq(repeated.status, 202)
  assert_eq(durable.assignments().length(), 1)
  let scale_absent = service.handle(
    Post,
    "/v1/service-deployments/\{intent.deployment_id}/scale",
    headers,
    "{}",
  )
  assert_eq(scale_absent.status, 404)
  let rolled_back = service.handle(
    Post,
    "/v1/service-deployments/\{intent.deployment_id}/rollback",
    headers,
    "",
  )
  assert_eq(rolled_back.status, 200)
  assert_eq(durable.assignments(), [])
  let deleted = service.handle(
    Post,
    "/v1/service-deployments/\{intent.deployment_id}/delete",
    headers,
    "",
  )
  assert_eq(deleted.status, 200)
  let deleted_operation : @deployment.DeploymentOperation = @json.from_json(
    @json.parse(deleted.body),
  )
  assert_eq(deleted_operation.state, Deleted)
}

///|
async test "deployment HTTP adversarial corpus fails closed without side effects" {
  let directory = @fs.tmpdir(prefix="lunanexa-management-adversarial-")
  let template = management_template()
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.fence_controller(1L)
  durable.put_heartbeat(management_heartbeat([]))
  let registry = management_registry("\{directory}/registry.json", template)
  let deployments = @deployment_store.FileDeploymentStore::open(
    "\{directory}/deployments.json",
    "catalog-secret",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    template.runtime.version,
    template.runtime.image_digest,
    template.artifact.digest,
    allow_http_loopback=true,
  )
  let service = @api.ApiService::with_registry(
      durable, registry, runtime, "operator-token", "inference-token", "node-token",
      "0.1.0",
    )
    .with_assignment_signing_secret("assignment-secret")
    .with_deployment_store(deployments, available_secret_refs=["runtime-token"])
  let headers = { "Authorization": "Bearer operator-token" }
  for
    path in [
      "/v1/catalog/templates", "/v1/deployment-plans", "/v1/service-deployments",
      "/v1/service-deployments/service-1/delete",
    ] {
    for
      hostile_headers in [
        ({} : Map[String, String]),
        { "Authorization": "Bearer inference-token" },
        { "Authorization": "Bearer operator-token-suffix" },
        { "Authorization": "Basic operator-token" },
      ] {
      let denied = service.handle(Post, path, hostile_headers, "{}")
      assert_eq(denied.status, 401)
      assert_false(denied.body.contains("operator-token"))
    }
  }
  assert_eq(deployments.templates().length(), 0)
  assert_eq(deployments.operations().length(), 0)
  assert_eq(durable.assignments().length(), 0)
  for
    malformed in [
      "", "{", "[]", "null", "true", "{\"version\":\"lunanexa.v1\"}", "{\"replicas\":1e999999}",
    ] {
    assert_eq(
      service.handle(Post, "/v1/catalog/templates", headers, malformed).status,
      400,
    )
    assert_eq(
      service.handle(Post, "/v1/deployment-plans", headers, malformed).status,
      400,
    )
    assert_eq(
      service.handle(Post, "/v1/service-deployments", headers, malformed).status,
      400,
    )
  }
  let hostile_template = {
    ..template,
    artifact: { ..template.artifact, uri: "s3://models/../../private-key" },
  }
  let rejected_template = service.handle(
    Post,
    "/v1/catalog/templates",
    headers,
    hostile_template.to_json().stringify(),
  )
  assert_eq(rejected_template.status, 409)
  assert_false(rejected_template.body.contains("private-key"))
  assert_eq(deployments.templates().length(), 0)
  assert_eq(
    service.handle(
      Post,
      "/v1/catalog/templates",
      headers,
      template.to_json().stringify(),
    ).status,
    201,
  )
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "console:service-1",
    deployment_id: "service-1",
    template: { template_id: template.template_id, version: template.version },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
  }
  for
    hostile_intent in [
      { ..intent, deployment_id: "../../service" },
      { ..intent, deployment_id: "service<script>" },
      { ..intent, replicas: 0 },
      { ..intent, replicas: 65 },
      { ..intent, lease_duration_ms: 0L },
      { ..intent, idempotency_key: "x".repeat(257) },
    ] {
    let plan_reply = service.handle(
      Post,
      "/v1/deployment-plans",
      headers,
      hostile_intent.to_json().stringify(),
    )
    assert_eq(plan_reply.status, 200)
    let plan : @deployment.DeploymentPlan = @json.from_json(
      @json.parse(plan_reply.body),
    )
    assert_false(plan.executable)
    assert_true(plan.findings.any(value => value.code == InvalidIntent))
    let deploy_reply = service.handle(
      Post,
      "/v1/service-deployments",
      headers,
      hostile_intent.to_json().stringify(),
    )
    assert_eq(deploy_reply.status, 409)
  }
  assert_eq(deployments.operations().length(), 0)
  assert_eq(durable.assignments().length(), 0)
  let first = service.handle(
    Post,
    "/v1/service-deployments",
    headers,
    intent.to_json().stringify(),
  )
  assert_eq(first.status, 202)
  let replay = service.handle(
    Post,
    "/v1/service-deployments",
    headers,
    intent.to_json().stringify(),
  )
  assert_eq(replay.status, 202)
  let first_operation : @deployment.DeploymentOperation = @json.from_json(
    @json.parse(first.body),
  )
  let replay_operation : @deployment.DeploymentOperation = @json.from_json(
    @json.parse(replay.body),
  )
  assert_eq(replay_operation.operation_id, first_operation.operation_id)
  assert_eq(deployments.operations().length(), 1)
  assert_eq(durable.assignments().length(), 1)
  let invalid_capacity = service.handle(
    Post,
    "/v1/service-deployments",
    headers,
    { ..intent, replicas: 2 }.to_json().stringify(),
  )
  assert_eq(invalid_capacity.status, 409)
  assert_true(invalid_capacity.body.contains("DeploymentRejected"))
  assert_eq(deployments.operations().length(), 1)
  assert_eq(durable.assignments().length(), 1)
  let conflict = service.handle(
    Post,
    "/v1/service-deployments",
    headers,
    { ..intent, lease_duration_ms: 120000L }.to_json().stringify(),
  )
  assert_eq(conflict.status, 409)
  assert_true(conflict.body.contains("IdempotencyConflict"))
  assert_eq(deployments.operations().length(), 1)
  assert_eq(durable.assignments().length(), 1)
  let oversized = "x".repeat(1048577)
  let oversized_reply = service.handle(
    Post,
    "/v1/service-deployments",
    headers,
    oversized,
  )
  assert_eq(oversized_reply.status, 413)
  for
    hostile_path in [
      "/v1/service-deployments/../../etc/passwd", "/v1/service-deployments/%2e%2e%2fsecret",
      "/v1/operations/<script>alert(1)</script>",
    ] {
    let reply = service.handle(Get, hostile_path, headers, "")
    assert_eq(reply.status, 404)
    assert_false(reply.body.contains(hostile_path))
  }
  for
    response in [
      first.body,
      replay.body,
      conflict.body,
      oversized_reply.body,
      rejected_template.body,
    ] {
    for
      forbidden in [
        "runtime-secret", "assignment-secret", "catalog-secret", "operator-token",
        "127.0.0.1", "/Users/", "private-key",
      ] {
      assert_false(response.contains(forbidden))
    }
  }
}
