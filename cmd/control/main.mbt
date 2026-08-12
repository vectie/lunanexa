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
fn provider_callback_secrets() -> Map[String, String] raise {
  guard @env.get_env_var("LUNANEXA_PROVIDER_CALLBACK_SECRET") is Some(secret) &&
    secret != "" else {
    return Map([])
  }
  let provider = required_environment("LUNANEXA_PROVIDER_CALLBACK_NAME")
  let environment = required_environment(
    "LUNANEXA_PROVIDER_CALLBACK_ENVIRONMENT",
  )
  let secrets : Map[String, String] = Map([])
  secrets["\{provider}|\{environment}"] = secret
  secrets
}

///|
/// Global policy is an administrator-owned startup artifact. It is validated
/// before any durable service or listener is opened, so a hostile or mistyped
/// value fails closed. The two legacy environment overrides remain supported
/// only when no settings document is supplied.
async fn load_global_admin_settings() -> @settings.GlobalAdminSettings {
  let configured = match @env.get_env_var("LUNANEXA_ADMIN_SETTINGS_PATH") {
    Some(path) if path != "" =>
      @settings.parse_global_admin_settings(@fs.read_file(path).text())
    _ => {
      let defaults = @settings.default_global_admin_settings()
      let scheduler = {
        ..defaults.scheduler,
        admission_capacity: @string.parse_int64(
          @env.get_env_var("LUNANEXA_ADMISSION_CAPACITY").unwrap_or("128"),
        ).to_int(),
        runtime_concurrency: @string.parse_int64(
          @env.get_env_var("LUNANEXA_RUNTIME_CONCURRENCY").unwrap_or("4"),
        ).to_int(),
      }
      { ..defaults, scheduler, }
    }
  }
  @settings.validate_global_admin_settings(configured)
  configured
}

///|
async fn main {
  let global_settings = load_global_admin_settings()
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
  let portal_path = @env.get_env_var("LUNANEXA_PORTAL_PATH").unwrap_or(
    "lunanexa-enterprise-portal.json",
  )
  let access_path = @env.get_env_var("LUNANEXA_ACCESS_PATH").unwrap_or(
    "lunanexa-access.json",
  )
  let technical_path = @env.get_env_var("LUNANEXA_TECHNICAL_PATH").unwrap_or(
    "lunanexa-technical.json",
  )
  let persistence_backend = @env.get_env_var("LUNANEXA_PERSISTENCE_BACKEND").unwrap_or(
    "file",
  )
  let management_database : @database.PostgresDatabase? = match
    persistence_backend {
    "file" => None
    "postgres" =>
      Some(
        @database.PostgresDatabase::open(
          required_environment("LUNANEXA_DATABASE_URL"),
        ),
      )
    _ =>
      raise Failure::Failure(
        "LUNANEXA_PERSISTENCE_BACKEND must be 'postgres' or 'file'",
      )
  }
  let runtime_endpoint = required_environment("LUNANEXA_RUNTIME_ENDPOINT")
  let mut runtime = @runtimes.OpenAiTextRuntime::new(
    runtime_endpoint,
    required_environment("LUNANEXA_RUNTIME_CREDENTIAL"),
    required_environment("LUNANEXA_RUNTIME_VERSION"),
    required_environment("LUNANEXA_RUNTIME_IMAGE_DIGEST"),
    required_environment("LUNANEXA_MODEL_ARTIFACT_DIGEST"),
    allow_http_loopback=@env.get_env_var("LUNANEXA_ALLOW_HTTP_LOOPBACK") ==
      Some("1"),
  ).with_response_budgets(
    global_settings.request_budgets.runtime_stream_event_bytes,
    global_settings.request_budgets.runtime_stream_total_bytes,
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
    scheduler_path,
    global_settings.scheduler.admission_capacity,
    decision_history_limit=global_settings.retention.scheduler_decision_entries,
    background_capacity_percent=global_settings.scheduler.background_capacity_percent,
    normal_capacity_percent=global_settings.scheduler.normal_capacity_percent,
  )
  let telemetry = @telemetry.FileTelemetry::open(
    telemetry_path,
    sample_history_limit=global_settings.retention.telemetry_sample_entries,
    benchmark_history_limit=global_settings.retention.benchmark_run_entries,
    safety_limits=global_settings.telemetry_safety,
  )
  let workspace_directory = match management_database {
    Some(database) => @directory.FileWorkspaceDirectory::open_postgres(database)
    None => @directory.FileWorkspaceDirectory::open(workspace_path)
  }
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
  let portal_store = match management_database {
    Some(database) => @portal_store.FilePortalStore::open_postgres(database)
    None => @portal_store.FilePortalStore::open(portal_path)
  }
  let api_key_issuer_secret = required_environment(
    "LUNANEXA_API_KEY_ISSUER_SECRET",
  )
  let access_store = match management_database {
    Some(database) =>
      @access.AccessStore::open_postgres(database, api_key_issuer_secret)
    None => @access.AccessStore::open(access_path, api_key_issuer_secret)
  }
  let technical_operations = match management_database {
    Some(database) => @technical_store.TechnicalStore::open_postgres(database)
    None => @technical_store.TechnicalStore::open(technical_path)
  }
  let commercial_store = match management_database {
    Some(database) =>
      match
        database.load_snapshot(
          "commercial", @commercial.snapshot_schema_version,
        ) {
        Some(payload) =>
          @commercial.CommercialStore::from_durable_snapshot(
            @json.from_json(@json.parse(payload)),
          )
        None => @commercial.CommercialStore::new()
      }
    None => @commercial.CommercialStore::new()
  }
  let commercial_integrations = match management_database {
    Some(database) =>
      match
        database.load_snapshot(
          "commercial_integrations", @commercial_integrations.integration_schema_version,
        ) {
        Some(payload) =>
          @commercial_integrations.IntegrationStore::from_durable_snapshot(
            @json.from_json(@json.parse(payload)),
          )
        None => @commercial_integrations.IntegrationStore::new()
      }
    None => @commercial_integrations.IntegrationStore::new()
  }
  let base_service = @api.ApiService::with_control_plane(
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
    .with_access_store(access_store)
    .with_technical_store(technical_operations)
    .with_deployment_store(
      deployment_store,
      available_secret_refs=secret_references(),
    )
    .with_exclusive_lease_store(exclusive_lease_store)
    .with_portal_store(portal_store)
    .with_reconciliation_only(
      @env.get_env_var("LUNANEXA_RECONCILIATION_ONLY") == Some("1"),
    )
    .with_role_tokens(
      required_environment("LUNANEXA_AUDIT_TOKEN"),
      required_environment("LUNANEXA_MONITORING_TOKEN"),
    )
    .with_assignment_signing_secret(assignment_signing_secret)
    .with_artifact_root(
      @env.get_env_var("LUNANEXA_MODEL_STORE_ROOT").unwrap_or("/data/models"),
    )
    .with_exclusive_lease_unit_price(
      @commercial.money(
        @string.parse_int64(
          @env.get_env_var("LUNANEXA_EXCLUSIVE_LEASE_PRICE_PER_SECOND_MINOR").unwrap_or(
            "0",
          ),
        ),
        @env.get_env_var("LUNANEXA_BILLING_CURRENCY").unwrap_or("CNY"),
        @string.parse_int64(
          @env.get_env_var("LUNANEXA_BILLING_SCALE").unwrap_or("2"),
        ).to_int(),
      ),
    )
    .with_provider_callback_secrets(provider_callback_secrets())
    .with_global_admin_settings(global_settings)
  let service = match management_database {
    Some(database) =>
      base_service.with_commercial_persistence(
        commercial_store, commercial_integrations, database,
      )
    None => base_service
  }
  service.serve(address)
}
