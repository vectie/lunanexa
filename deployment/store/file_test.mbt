///|
fn unsigned_template() -> @deployment.ModelServiceTemplate {
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
    secret_refs: [],
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
async test "catalog and operation state survive restart" {
  let directory = @fs.tmpdir(prefix="lunanexa-deployments-")
  let path = "\{directory}/deployments.json"
  let store = @store.FileDeploymentStore::open(path, "catalog-secret")
  let template = store.register_template(unsigned_template())
  assert_true(template.signature != "")
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "deploy-1",
    deployment_id: "service-1",
    template: { template_id: "text-small", version: "v1" },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
  }
  let plan = @deployment.preflight([template], intent, {
    registry: [],
    nodes: [],
    available_secret_refs: [],
  })
  let operation = store.create_operation(plan, 1L)
  assert_eq(operation.state, Blocked)
  let reopened = @store.FileDeploymentStore::open(path, "catalog-secret")
  assert_eq(reopened.templates().length(), 1)
  assert_eq(reopened.operation(operation.operation_id), Some(operation))
}

///|
async test "deployment snapshot rejects tampering and wrong authority" {
  let directory = @fs.tmpdir(prefix="lunanexa-deployments-integrity-")
  let path = "\{directory}/deployments.json"
  let signing_secret = "catalog-integrity-secret"
  let store = @store.FileDeploymentStore::open(path, signing_secret)
  ignore(store.register_template(unsigned_template()))
  let persisted = @fs.read_file(path).text()
  assert_true(persisted.contains("lunanexa.deployments.v2"))
  assert_true(persisted.contains("\"signature\":"))
  assert_false(persisted.contains(signing_secret))
  try @store.FileDeploymentStore::open(path, "wrong-authority") catch {
    @store.DeploymentStoreError::InvalidSnapshot(_) => ()
    error => fail("unexpected wrong-authority error: \{Repr(error)}")
  } noraise {
    _ => fail("snapshot opened under the wrong signing authority")
  }
  @fs.write_file(
    path,
    persisted.replace_all(old="Text small", new="Hostile template"),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  try @store.FileDeploymentStore::open(path, signing_secret) catch {
    @store.DeploymentStoreError::InvalidSnapshot(_) => ()
    error => fail("unexpected tamper error: \{Repr(error)}")
  } noraise {
    _ => fail("tampered deployment snapshot was accepted")
  }
}

///|
async test "concurrent idempotent deployment retries create one operation" {
  let directory = @fs.tmpdir(prefix="lunanexa-deployments-concurrency-")
  let store = @store.FileDeploymentStore::open(
    "\{directory}/deployments.json",
    "catalog-concurrency-secret",
  )
  let template = store.register_template(unsigned_template())
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "deploy-concurrent",
    deployment_id: "service-concurrent",
    template: { template_id: template.template_id, version: template.version },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
  }
  let plan = @deployment.preflight([template], intent, {
    registry: [],
    nodes: [],
    available_secret_refs: [],
  })
  @async.with_task_group(group => {
    for attempt in 0..<32 {
      group.spawn_bg(() => {
        ignore(store.create_operation(plan, attempt.to_int64() + 1L))
      })
    }
  })
  let operations = store.operations()
  assert_eq(operations.length(), 1)
  assert_eq(operations[0].plan.intent, intent)
  assert_eq(operations[0].generation, 1L)
}
