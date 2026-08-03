///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required environment reference is missing: \{name}")
  }
  value
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
    .with_reconciliation_only(
      @env.get_env_var("LUNANEXA_RECONCILIATION_ONLY") == Some("1"),
    )
    .with_role_tokens(
      required_environment("LUNANEXA_AUDIT_TOKEN"),
      required_environment("LUNANEXA_MONITORING_TOKEN"),
    )
    .with_assignment_signing_secret(
      required_environment("LUNANEXA_ASSIGNMENT_SIGNING_SECRET"),
    )
    .with_runtime_concurrency(
      @string.parse_int64(
        @env.get_env_var("LUNANEXA_RUNTIME_CONCURRENCY").unwrap_or("4"),
      ).to_int(),
    )
  service.serve(address)
}
