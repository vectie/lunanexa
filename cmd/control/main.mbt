///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required environment reference is missing: \{name}")
  }
  value
}

///|
fn secret_references() -> Array[String] {
  @env.get_env_var("LUNANEXA_AVAILABLE_SECRET_REFS")
  .unwrap_or("")
  .split(",")
  .map(value => value.trim().to_owned())
  .filter(value => value != "")
  .collect()
}

///|
async fn main {
  let address = @env.get_env_var("LUNANEXA_LISTEN_ADDRESS").unwrap_or(
    "127.0.0.1:8080",
  )
  let state_path = @env.get_env_var("LUNANEXA_STATE_PATH").unwrap_or(
    "lunanexa-state.json",
  )
  let registry_path = @env.get_env_var("LUNANEXA_REGISTRY_PATH").unwrap_or(
    "lunanexa-registry.json",
  )
  let enrollment_path = @env.get_env_var("LUNANEXA_ENROLLMENT_PATH").unwrap_or(
    "lunanexa-enrollment.json",
  )
  let scheduler_path = @env.get_env_var("LUNANEXA_SCHEDULER_PATH").unwrap_or(
    "lunanexa-scheduler.json",
  )
  let telemetry_path = @env.get_env_var("LUNANEXA_TELEMETRY_PATH").unwrap_or(
    "lunanexa-telemetry.json",
  )
  let workspace_path = @env.get_env_var("LUNANEXA_WORKSPACE_PATH").unwrap_or(
    "lunanexa-workspace.json",
  )
  let deployment_path = @env.get_env_var("LUNANEXA_DEPLOYMENT_PATH").unwrap_or(
    "lunanexa-deployments.json",
  )
  let exclusive_lease_path = @env.get_env_var("LUNANEXA_EXCLUSIVE_LEASE_PATH").unwrap_or(
    "lunanexa-exclusive-leases.json",
  )
  let scheduler_capacity = @string.parse_int64(
    @env.get_env_var("LUNANEXA_ADMISSION_CAPACITY").unwrap_or("128"),
  ).to_int()
  let runtime_endpoint = required_environment("LUNANEXA_RUNTIME_ENDPOINT")
  let mut runtime = @runtimes.OpenAiTextRuntime::new(
    runtime_endpoint,
    required_environment("LUNANEXA_RUNTIME_CREDENTIAL"),
    required_environment("LUNANEXA_RUNTIME_VERSION"),
    required_environment("LUNANEXA_RUNTIME_IMAGE_DIGEST"),
    required_environment("LUNANEXA_MODEL_ARTIFACT_DIGEST"),
    allow_http_loopback=@env.get_env_var("LUNANEXA_ALLOW_HTTP_LOOPBACK") ==
      Some("1"),
  )
  if @env.get_env_var("LUNANEXA_RUNTIME_ENDPOINTS_PATH") is Some(path) &&
    path != "" {
    runtime = runtime.with_node_endpoints_json(@fs.read_file(path).text())
  }
  let durable = @store.FileStore::open(state_path)
  durable.fence_controller(
    @string.parse_int64(required_environment("LUNANEXA_CONTROLLER_EPOCH")),
  )
  let registry = @registry.FileRegistry::open(registry_path)
  let enrollment = @node.FileEnrollmentService::open(enrollment_path)
  let scheduler = @scheduler.FileScheduler::open(
    scheduler_path, scheduler_capacity,
  )
  let telemetry = @telemetry.FileTelemetry::open(telemetry_path)
  let workspace_directory = @directory.FileWorkspaceDirectory::open(
    workspace_path,
  )
  let assignment_signing_secret = required_environment(
    "LUNANEXA_ASSIGNMENT_SIGNING_SECRET",
  )
  let deployment_store = @deployment_store.FileDeploymentStore::open(
    deployment_path,
    required_environment("LUNANEXA_CATALOG_SIGNING_SECRET"),
  )
  let exclusive_lease_store = @nodelease_store.FileExclusiveLeaseStore::open(
    exclusive_lease_path,
    required_environment("LUNANEXA_EXCLUSIVE_LEASE_SIGNING_SECRET"),
  )
  let service = @api.ApiService::with_control_plane(
      durable,
      registry,
      enrollment,
      scheduler,
      telemetry,
      runtime,
      required_environment("LUNANEXA_OPERATOR_TOKEN"),
      required_environment("LUNANEXA_INFERENCE_TOKEN"),
      "",
      "0.1.0",
    )
    .with_signature_verifier(
      @registry.CosignVerifier::new(
        required_environment("LUNANEXA_COSIGN_BINARY"),
        required_environment("LUNANEXA_COSIGN_PUBLIC_KEY_PATH"),
      ),
    )
    .with_workspace_directory(
      workspace_directory,
      @env.get_env_var("LUNANEXA_REQUIRE_WORKSPACE_LEASE") == Some("1"),
    )
    .with_deployment_store(
      deployment_store,
      available_secret_refs=secret_references(),
    )
    .with_exclusive_lease_store(exclusive_lease_store)
    .with_reconciliation_only(
      @env.get_env_var("LUNANEXA_RECONCILIATION_ONLY") == Some("1"),
    )
    .with_role_tokens(
      required_environment("LUNANEXA_AUDIT_TOKEN"),
      required_environment("LUNANEXA_MONITORING_TOKEN"),
    )
    .with_assignment_signing_secret(assignment_signing_secret)
    .with_runtime_concurrency(
      @string.parse_int64(
        @env.get_env_var("LUNANEXA_RUNTIME_CONCURRENCY").unwrap_or("4"),
      ).to_int(),
    )
  service.serve(address)
}
