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
      supports_batching: true,
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
fn management_heartbeat(running : Array[String]) -> @contracts.NodeHeartbeat {
  {
    node_id: "node-a",
    state: Active,
    observed_generation: 1L,
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
  let scaled = service.handle(
    Post,
    "/v1/service-deployments/\{intent.deployment_id}/scale",
    headers,
    (
      { replicas: 1, idempotency_key: "scale-text-small" } :
      @deployment.ScaleRequest)
    .to_json()
    .stringify(),
  )
  assert_eq(scaled.status, 202)
  let scaled_operation : @deployment.DeploymentOperation = @json.from_json(
    @json.parse(scaled.body),
  )
  assert_eq(scaled_operation.generation, 2L)
  assert_eq(scaled_operation.state, Ready)
  assert_eq(durable.assignments()[0].generation, 2L)
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
