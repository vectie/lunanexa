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

///| Both machine callback identities are optional as one fail-closed feature,

///|
/// but partial, weak, or reused configuration is a startup error.
fn offline_callback_tokens(
  worker : String?,
  scanner : String?,
  operator : String,
  inference : String,
) -> (String, String)? raise {
  match (worker, scanner) {
    (None, None) => None
    (Some(worker), Some(scanner)) => {
      if worker.length() < 32 ||
        scanner.length() < 32 ||
        worker == scanner ||
        worker == operator ||
        worker == inference ||
        scanner == operator ||
        scanner == inference {
        raise Failure::Failure(
          "offline artifact callback identities are weak or reused",
        )
      }
      Some((worker, scanner))
    }
    _ =>
      raise Failure::Failure(
        "offline artifact callback identities must be configured together",
      )
  }
}

///|
fn guide_monitor_enabled(value : String?) -> Bool raise {
  match value {
    None | Some("") | Some("0") => false
    Some("1") => true
    Some(_) =>
      raise Failure::Failure(
        "LUNANEXA_ENABLE_GUIDE_MONITOR must be absent, '0', or '1'",
      )
  }
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
  let notification_path = @env.get_env_var("LUNANEXA_NOTIFICATION_PATH").unwrap_or(
    "lunanexa-notifications.json",
  )
  let observability_path = @env.get_env_var("LUNANEXA_OBSERVABILITY_PATH").unwrap_or(
    "lunanexa-observability.json",
  )
  let offline_commerce_path = @env.get_env_var("LUNANEXA_OFFLINE_COMMERCE_PATH").unwrap_or(
    "lunanexa-offline-commerce.json",
  )
  let access_path = @env.get_env_var("LUNANEXA_ACCESS_PATH").unwrap_or(
    "lunanexa-access.json",
  )
  let technical_path = @env.get_env_var("LUNANEXA_TECHNICAL_PATH").unwrap_or(
    "lunanexa-technical.json",
  )
  let guide_monitor_enabled = guide_monitor_enabled(
    @env.get_env_var("LUNANEXA_ENABLE_GUIDE_MONITOR"),
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
  let notification_store = match management_database {
    Some(database) =>
      @notification_store.NotificationStore::open_postgres(database)
    None => @notification_store.NotificationStore::open(notification_path)
  }
  let guide_probe_worker = if guide_monitor_enabled {
    Some(
      @guide_probe.GuideProbeWorker::open(
        {
          origin: required_environment("LUNANEXA_GUIDE_ORIGIN"),
          allow_https: @env.get_env_var("LUNANEXA_GUIDE_ALLOW_HTTPS") ==
          Some("1"),
          actor_ref: @env.get_env_var("LUNANEXA_GUIDE_ACTOR_REF").unwrap_or(
            "service:guide-monitor",
          ),
          role: "operator",
          maximum_response_bytes: @string.parse_int64(
            @env.get_env_var("LUNANEXA_GUIDE_MAX_RESPONSE_BYTES").unwrap_or(
              "65536",
            ),
          ).to_int(),
          request_timeout_ms: @string.parse_int64(
            @env.get_env_var("LUNANEXA_GUIDE_REQUEST_TIMEOUT_MS").unwrap_or(
              "2500",
            ),
          ).to_int(),
        },
        {
          target_ref: @env.get_env_var("LUNANEXA_GUIDE_TARGET_REF").unwrap_or(
            "coursebook-primary",
          ),
          probe_interval_ms: @string.parse_int64(
            @env.get_env_var("LUNANEXA_GUIDE_PROBE_INTERVAL_MS").unwrap_or(
              "60000",
            ),
          ),
          observation_max_age_ms: @string.parse_int64(
            @env.get_env_var("LUNANEXA_GUIDE_OBSERVATION_MAX_AGE_MS").unwrap_or(
              "120000",
            ),
          ),
          future_skew_ms: @string.parse_int64(
            @env.get_env_var("LUNANEXA_GUIDE_FUTURE_SKEW_MS").unwrap_or("5000"),
          ),
          knowledge_max_age_ms: @string.parse_int64(
            @env.get_env_var("LUNANEXA_GUIDE_KNOWLEDGE_MAX_AGE_MS").unwrap_or(
              "604800000",
            ),
          ),
        },
        @env.get_env_var("LUNANEXA_GUIDE_SCHEDULER_PATH").unwrap_or(
          "lunanexa-guide-probe.json",
        ),
        notification_store,
        required_environment("LUNANEXA_GUIDE_IDENTITY_SECRET"),
        required_environment("LUNANEXA_GUIDE_OBSERVATION_SECRET"),
      ),
    )
  } else {
    None
  }
  let observability_store = match management_database {
    Some(database) =>
      @observability.ObservabilityStore::open_postgres(
        database,
        emit_json_lines=true,
      )
    None =>
      @observability.ObservabilityStore::open(
        observability_path,
        emit_json_lines=true,
      )
  }
  let offline_commerce_store = match management_database {
    Some(database) =>
      @offline_store.OfflineCommerceStore::open_postgres(database)
    None => @offline_store.OfflineCommerceStore::open(offline_commerce_path)
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
  let operator_token = required_environment("LUNANEXA_OPERATOR_TOKEN")
  let inference_token = required_environment("LUNANEXA_INFERENCE_TOKEN")
  let callback_tokens = offline_callback_tokens(
    @env.get_env_var("LUNANEXA_ARTIFACT_WORKER_CALLBACK_TOKEN"),
    @env.get_env_var("LUNANEXA_ARTIFACT_SCANNER_CALLBACK_TOKEN"),
    operator_token,
    inference_token,
  )
  let configured_service = @api.ApiService::with_control_plane(
      durable, registry, enrollment, scheduler, telemetry, runtime, operator_token,
      inference_token, "", "0.1.0",
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
    .with_notification_store(notification_store)
    .with_observability_store(observability_store)
    .with_offline_commerce_store(offline_commerce_store)
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
  let base_service = match callback_tokens {
    Some(tokens) =>
      configured_service.with_offline_artifact_callback_tokens(
        tokens.0,
        tokens.1,
      )
    None => configured_service
  }
  let service = match management_database {
    Some(database) =>
      base_service.with_commercial_persistence(
        commercial_store, commercial_integrations, database,
      )
    None => base_service
  }
  match guide_probe_worker {
    None => service.serve(address)
    Some(worker) => {
      let server = @http.Server(@socket.Addr::parse(address))
      @async.with_task_group <| group => {
        group.spawn_bg(allow_failure=false) <| () => { worker.run_forever() }
        service.serve_on(server)
      }
    }
  }
}
