///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required environment reference is missing: \{name}")
  }
  value
}

///| Optional readiness attestations are strict booleans. Typos must not turn

///|
/// an unverified external dependency into a green production gate.
fn strict_boolean_environment(name : String) -> Bool raise {
  match @env.get_env_var(name) {
    None | Some("") | Some("0") => false
    Some("1") => true
    Some(_) => raise Failure::Failure("\{name} must be exactly '0' or '1'")
  }
}

///|
fn validate_distinct_operational_secrets(
  values : Array[(String, String)],
) -> Unit raise {
  for index in 0..<values.length() {
    let (name, value) = values[index]
    if value.length() < 32 || value.length() > 4096 {
      raise Failure::Failure("\{name} must contain 32 to 4096 bytes")
    }
    for prior in 0..<index {
      if value == values[prior].1 {
        raise Failure::Failure("\{name} reuses authority \{values[prior].0}")
      }
    }
  }
}

///|
/// Parses `LUNANEXA_OPERATOR_TOKENS` (`alice=tok1,bob=tok2`) into
/// identity/token pairs for per-operator attribution on the
/// contract-document operator routes. Malformed entries, duplicate
/// identities, and duplicate tokens are rejected at startup rather than
/// silently weakening attribution; error messages never echo token bytes.
fn parse_operator_tokens(raw : String) -> Array[(String, String)] raise {
  let pairs : Array[(String, String)] = []
  for entry_view in raw.split(",") {
    let entry = entry_view.trim().to_owned()
    guard entry != "" else {
      raise Failure::Failure("LUNANEXA_OPERATOR_TOKENS contains an empty entry")
    }
    guard entry.find("=") is Some(separator) else {
      raise Failure::Failure(
        "LUNANEXA_OPERATOR_TOKENS entries must use the id=token form",
      )
    }
    let identity = entry[:separator].trim().to_owned()
    let token = entry[separator + 1:].trim().to_owned()
    guard @contracts.valid_identifier(identity) else {
      raise Failure::Failure(
        "LUNANEXA_OPERATOR_TOKENS identity is not a valid identifier: \{identity}",
      )
    }
    guard token.length() >= 32 && token.length() <= 4096 else {
      raise Failure::Failure(
        "LUNANEXA_OPERATOR_TOKENS token for \{identity} must contain 32 to 4096 bytes",
      )
    }
    guard !pairs.any(pair => pair.0 == identity || pair.1 == token) else {
      raise Failure::Failure(
        "LUNANEXA_OPERATOR_TOKENS repeats an identity or token: \{identity}",
      )
    }
    pairs.push((identity, token))
  }
  pairs
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

///| Object transfer is one optional, fail-closed adapter. Partial deployment

///|
/// would create unusable upload/download grants and is therefore fatal.
fn offline_transfer_adapter_configuration(
  endpoint : String?,
  token : String?,
  session_secret : String?,
) -> (String, String, String)? raise {
  match (endpoint, token, session_secret) {
    (None, None, None)
    | (Some(""), None, None)
    | (None, Some(""), None)
    | (None, None, Some(""))
    | (Some(""), Some(""), Some("")) => None
    (Some(endpoint), Some(token), Some(secret)) if endpoint != "" &&
      token != "" &&
      secret != "" => {
      if token.length() < 32 ||
        token.length() > 4096 ||
        secret.length() < 32 ||
        secret.length() > 4096 ||
        token == secret {
        raise Failure::Failure("offline transfer adapter identity is invalid")
      }
      Some((endpoint, token, secret))
    }
    _ =>
      raise Failure::Failure(
        "offline transfer endpoint token and session secret must be configured together",
      )
  }
}

///|
fn model_source_adapter_configuration(
  endpoint : String?,
  token : String?,
) -> (String, String)? raise {
  match (endpoint, token) {
    (None, None) | (Some(""), None) | (None, Some("")) | (Some(""), Some("")) =>
      None
    (Some(endpoint), Some(token)) if endpoint != "" && token != "" => {
      if token.length() < 32 || token.length() > 4096 {
        raise Failure::Failure("model-source adapter identity is invalid")
      }
      Some((endpoint, token))
    }
    _ =>
      raise Failure::Failure(
        "model-source adapter endpoint and token must be configured together",
      )
  }
}

///|
priv struct OfflineReadinessEvidenceDocument {
  schema_version : String
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  capabilities : Array[@offline.OfflineCommerceCapabilityEvidence]
  signature : String
} derive(FromJson)

///|
fn offline_readiness_material(
  document : OfflineReadinessEvidenceDocument,
) -> String {
  "lunanexa.offline-commerce-readiness.v1|\{document.issued_unix_ms}|\{document.expires_unix_ms}|\{document.capabilities.to_json().stringify()}"
}

///|
fn offline_readiness_signature(
  document : OfflineReadinessEvidenceDocument,
  secret : String,
) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).view(),
      @utf8.encode(offline_readiness_material(document)).view(),
    ),
  )
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}

///| A missing document is an intentional pending state. A configured document

///|
/// Kubernetes projected Secret files are symlinks. Their resolved target is
/// accepted only when it stays beneath the configured mount and is regular.
async fn load_offline_readiness_evidence(
  path : String?,
  secret : String?,
  now_unix_ms : Int64,
) -> (Array[@offline.OfflineCommerceCapabilityEvidence], Int64) {
  match (path, secret) {
    (None, None) | (Some(""), None) | (None, Some("")) => ([], 0L)
    (Some(path), Some(secret)) => {
      if !path.has_prefix("/") || secret.length() < 32 || secret.length() > 4096 {
        raise Failure::Failure(
          "offline readiness evidence path or signing secret is invalid",
        )
      }
      let resolved = @fs.realpath(path)
      guard path.rev_find("/") is Some(separator) && separator > 0 else {
        raise Failure::Failure("offline readiness evidence path is invalid")
      }
      let configured_directory = @fs.realpath(path[:separator])
      if !resolved.has_prefix("\{configured_directory}/") ||
        @fs.kind(resolved, follow_symlink=true) != Regular {
        raise Failure::Failure(
          "offline readiness evidence must resolve inside its configured directory",
        )
      }
      let bytes = @fs.read_file(resolved).binary()
      if bytes.length() == 0 || bytes.length() > 65536 {
        raise Failure::Failure("offline readiness evidence size is invalid")
      }
      let document : OfflineReadinessEvidenceDocument = @json.from_json(
        @json.parse(@utf8.decode(bytes)),
      ) catch {
        _ =>
          raise Failure::Failure("offline readiness evidence is invalid JSON")
      }
      if document.schema_version != "lunanexa.offline-commerce-readiness.v1" ||
        document.issued_unix_ms <= 0L ||
        document.issued_unix_ms > now_unix_ms ||
        document.expires_unix_ms <= now_unix_ms ||
        document.expires_unix_ms > document.issued_unix_ms + 2678400000L ||
        document.signature.length() != 64 ||
        !constant_time_equal(
          document.signature,
          offline_readiness_signature(document, secret),
        ) {
        raise Failure::Failure(
          "offline readiness evidence signature or validity window is invalid",
        )
      }
      let readiness = @offline.offline_commerce_readiness(
        document.capabilities,
        now_unix_ms,
      )
      if readiness.blocker_codes.any(code => code.has_prefix("Readiness")) {
        raise Failure::Failure(
          "offline readiness evidence capability set is ambiguous",
        )
      }
      (document.capabilities, document.expires_unix_ms)
    }
    _ =>
      raise Failure::Failure(
        "offline readiness evidence path and signing secret must be configured together",
      )
  }
}

///|
/// Loads retained proof for the privileged node helper adapter. Absence keeps
/// machine access pending; partial, escaping, oversized, expired or forged
/// evidence fails startup. Kubernetes projected Secret symlinks are accepted
/// only when their resolved target stays beneath the configured mount.
async fn load_machine_helper_adapter_evidence(
  path : String?,
  secret : String?,
  expected_node_scope : String,
  now_unix_ms : Int64,
) -> @nodelease.MachineHelperAdapterReadinessEvidence? {
  match (path, secret) {
    (None, None) | (Some(""), None) | (None, Some("")) => None
    (Some(path), Some(secret)) => {
      if !path.has_prefix("/") || secret.length() < 32 || secret.length() > 4096 {
        raise Failure::Failure(
          "machine helper evidence configuration is invalid",
        )
      }
      let resolved = @fs.realpath(path)
      guard path.rev_find("/") is Some(separator) && separator > 0 else {
        raise Failure::Failure("machine helper evidence path is invalid")
      }
      let configured_directory = @fs.realpath(path[:separator])
      if !resolved.has_prefix("\{configured_directory}/") ||
        @fs.kind(resolved, follow_symlink=true) != Regular {
        raise Failure::Failure(
          "machine helper evidence must resolve inside its configured directory",
        )
      }
      let bytes = @fs.read_file(resolved).binary()
      if bytes.length() == 0 || bytes.length() > 16384 {
        raise Failure::Failure("machine helper evidence size is invalid")
      }
      let evidence : @nodelease.MachineHelperAdapterReadinessEvidence = @json.from_json(
        @json.parse(@utf8.decode(bytes)),
      ) catch {
        _ => raise Failure::Failure("machine helper evidence is invalid JSON")
      }
      if !@nodelease.machine_helper_adapter_evidence_ready(
          evidence, now_unix_ms,
        ) ||
        evidence.node_scope != expected_node_scope ||
        !@nodelease.valid_machine_helper_adapter_evidence_signature(
          evidence, secret,
        ) {
        raise Failure::Failure(
          "machine helper evidence signature or validity window is invalid",
        )
      }
      Some(evidence)
    }
    _ =>
      raise Failure::Failure(
        "machine helper evidence path and signing secret must be configured together",
      )
  }
}

///|
fn entitlement_callback_token(
  token : String?,
  worker : String?,
  scanner : String?,
  operator : String,
  inference : String,
) -> String? raise {
  match token {
    None | Some("") => None
    Some(token) => {
      if token.length() < 32 ||
        token.length() > 4096 ||
        token == operator ||
        token == inference ||
        worker == Some(token) ||
        scanner == Some(token) {
        raise Failure::Failure(
          "entitlement authority callback identity is weak or reused",
        )
      }
      Some(token)
    }
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

///| Clock-driven expiry is independent of UI and API traffic. Fulfilled

///|
/// expirations become durable revocation sagas rather than orphaning access.
async fn run_offline_commerce_reconciler(service : @api.ApiService) -> Unit {
  for ;; {
    service.reconcile_offline_commerce(@async.now())
    @async.sleep(30000)
  }
}

///|
/// Contract obligations are a controller concern, not a page-read side
/// effect. Keep overdue payment/acceptance tasks current after restart.
async fn run_contract_governance_reconciler(service : @api.ApiService) -> Unit {
  for ;; {
    service.reconcile_contract_governance(@async.now())
    @async.sleep(30000)
  }
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
  let contract_document_path = @env.get_env_var(
    "LUNANEXA_CONTRACT_DOCUMENT_PATH",
  ).unwrap_or("lunanexa-contract-documents.json")
  let contract_document_worker_token = @env.get_env_var(
    "LUNANEXA_CONTRACT_DOCUMENT_WORKER_TOKEN",
  )
  // Four-eyes approval threshold for high-value execute/close transitions,
  // as a decimal CNY yuan string (for example `50000.00`). Unset disables
  // the approval matrix; a set but unparseable value fails startup.
  let contract_approval_threshold = match
    @env.get_env_var("LUNANEXA_CONTRACT_APPROVAL_THRESHOLD_CNY") {
    Some(raw) if raw.trim() != "" =>
      match @contractdoc.parse_cny_minor_units(raw) {
        Some(minor_units) => Some(minor_units)
        None =>
          raise Failure::Failure(
            "LUNANEXA_CONTRACT_APPROVAL_THRESHOLD_CNY must be a decimal CNY amount such as 50000.00",
          )
      }
    _ => None
  }
  let access_path = @env.get_env_var("LUNANEXA_ACCESS_PATH").unwrap_or(
    "lunanexa-access.json",
  )
  let account_path = @env.get_env_var("LUNANEXA_ACCOUNT_PATH").unwrap_or(
    "lunanexa-accounts.json",
  )
  let credential_handoff_path = @env.get_env_var(
    "LUNANEXA_CREDENTIAL_HANDOFF_PATH",
  ).unwrap_or("lunanexa-credential-handoffs.json")
  let client_handoff_path = @env.get_env_var("LUNANEXA_CLIENT_HANDOFF_PATH").unwrap_or(
    "lunanexa-client-handoffs.json",
  )
  let technical_path = @env.get_env_var("LUNANEXA_TECHNICAL_PATH").unwrap_or(
    "lunanexa-technical.json",
  )
  let guide_monitor_enabled = guide_monitor_enabled(
    @env.get_env_var("LUNANEXA_ENABLE_GUIDE_MONITOR"),
  )
  let guide_identity_secret = if guide_monitor_enabled {
    required_environment("LUNANEXA_GUIDE_IDENTITY_SECRET")
  } else {
    ""
  }
  let guide_observation_secret = if guide_monitor_enabled {
    required_environment("LUNANEXA_GUIDE_OBSERVATION_SECRET")
  } else {
    ""
  }
  let guide_diagnostics_secret = if guide_monitor_enabled {
    required_environment("LUNANEXA_GUIDE_DIAGNOSTICS_TOKEN")
  } else {
    ""
  }
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
  match @env.get_env_var("LUNANEXA_RUNTIME_PROTOCOL") {
    Some("lunaflux-responses-sse-v1") =>
      runtime = runtime.with_lunaflux_streaming_responses()
    None | Some("") => ()
    Some(value) =>
      raise Failure::Failure("unsupported LUNANEXA_RUNTIME_PROTOCOL: \{value}")
  }
  if @env.get_env_var("LUNANEXA_RUNTIME_ENDPOINTS_PATH") is Some(path) &&
    path != "" {
    runtime = runtime.with_node_endpoints_json(@fs.read_file(path).text())
  }
  let durable = @store.FileStore::open(state_path)
  durable.fence_controller(
    @string.parse_int64(required_environment("LUNANEXA_CONTROLLER_EPOCH")),
  ) catch {
    @store.DurableStoreError::InvalidState(message) => {
      println("[startup] controller epoch rejected: \{message}")
      raise @store.DurableStoreError::InvalidState(message)
    }
    error => raise error
  }
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
  let catalog_signing_secret = required_environment(
    "LUNANEXA_CATALOG_SIGNING_SECRET",
  )
  let deployment_store = @deployment_store.FileDeploymentStore::open(
    deployment_path, catalog_signing_secret,
  )
  let exclusive_lease_signing_secret = required_environment(
    "LUNANEXA_EXCLUSIVE_LEASE_SIGNING_SECRET",
  )
  let exclusive_lease_store = match management_database {
    Some(database) =>
      @nodelease_store.FileExclusiveLeaseStore::open_postgres(
        database, exclusive_lease_signing_secret,
      )
    None =>
      @nodelease_store.FileExclusiveLeaseStore::open(
        exclusive_lease_path, exclusive_lease_signing_secret,
      )
  }
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
        guide_identity_secret,
        guide_observation_secret,
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
  let guide_probe_worker = match guide_probe_worker {
    Some(worker) => Some(worker.with_observability_store(observability_store))
    None => None
  }
  let (notification_delivery_worker, notification_adapter_configured) = match
    (
      @env.get_env_var("LUNANEXA_NOTIFICATION_DELIVERY_ADAPTER_ENDPOINT"),
      @env.get_env_var("LUNANEXA_NOTIFICATION_DELIVERY_ADAPTER_TOKEN"),
    ) {
    (None, None) | (Some(""), None) | (None, Some("")) | (Some(""), Some("")) =>
      (
        @notification_worker.NotificationDeliveryWorker::adapters_pending(
          notification_store,
        ),
        false,
      )
    (Some(endpoint), Some(token)) if endpoint != "" && token != "" =>
      (
        @notification_worker.NotificationDeliveryWorker::configured(
          notification_store,
          endpoint,
          token,
          request_timeout_ms=@string.parse_int64(
            @env.get_env_var("LUNANEXA_NOTIFICATION_DELIVERY_TIMEOUT_MS").unwrap_or(
              "5000",
            ),
          ).to_int(),
          interval_ms=@string.parse_int64(
            @env.get_env_var("LUNANEXA_NOTIFICATION_DELIVERY_INTERVAL_MS").unwrap_or(
              "30000",
            ),
          ).to_int(),
        ),
        true,
      )
    _ =>
      raise Failure::Failure(
        "notification delivery adapter endpoint and token must be configured together",
      )
  }
  let external_observability_collector_configured = strict_boolean_environment(
    "LUNANEXA_EXTERNAL_OBSERVABILITY_COLLECTOR_CONFIGURED",
  )
  let notification_delivery_worker = notification_delivery_worker.with_observability_store(
    observability_store,
  )
  let offline_commerce_store = match management_database {
    Some(database) =>
      @offline_store.OfflineCommerceStore::open_postgres(database)
    None => @offline_store.OfflineCommerceStore::open(offline_commerce_path)
  }
  let contract_document_store = match management_database {
    Some(database) =>
      @contractdoc_store.ContractDocumentStore::open_postgres(database)
    None =>
      @contractdoc_store.ContractDocumentStore::open(contract_document_path)
  }
  let api_key_issuer_secret = required_environment(
    "LUNANEXA_API_KEY_ISSUER_SECRET",
  )
  let access_store = match management_database {
    Some(database) =>
      @access.AccessStore::open_postgres(database, api_key_issuer_secret)
    None => @access.AccessStore::open(access_path, api_key_issuer_secret)
  }
  let account_session_issuer_secret = required_environment(
    "LUNANEXA_ACCOUNT_SESSION_ISSUER_SECRET",
  )
  let identity_assertion_secret = @env.get_env_var(
    "LUNANEXA_IDENTITY_ASSERTION_SECRET",
  ).unwrap_or("")
  let account_store = match management_database {
    Some(database) =>
      @account.AccountStore::open_postgres(
        database, account_session_issuer_secret,
      )
    None =>
      @account.AccountStore::open(account_path, account_session_issuer_secret)
  }
  let credential_handoff_issuer_secret = required_environment(
    "LUNANEXA_CREDENTIAL_HANDOFF_ISSUER_SECRET",
  )
  let credential_handoff_store = match management_database {
    Some(database) =>
      @credential_store.CredentialHandoffStore::open_postgres(
        database, credential_handoff_issuer_secret,
      )
    None =>
      @credential_store.CredentialHandoffStore::open(
        credential_handoff_path, credential_handoff_issuer_secret,
      )
  }
  let credential_handoff_store = match
    @credential_store.load_issuer_readiness_evidence(
      @env.get_env_var("LUNANEXA_CREDENTIAL_ISSUER_READINESS_PATH"),
      @env.get_env_var("LUNANEXA_CREDENTIAL_ISSUER_READINESS_SECRET"),
      @async.now(),
    ) {
    Some(evidence) => credential_handoff_store.with_issuer_readiness(evidence)
    None => credential_handoff_store
  }
  let client_handoff_issuer_secret = required_environment(
    "LUNANEXA_CLIENT_HANDOFF_ISSUER_SECRET",
  )
  let client_handoff_store = match management_database {
    Some(database) =>
      @client_handoff_store.ClientHandoffStore::open_postgres(
        database, client_handoff_issuer_secret,
      )
    None =>
      @client_handoff_store.ClientHandoffStore::open(
        client_handoff_path, client_handoff_issuer_secret,
      )
  }
  let client_launch_config : @client_handoff.ClientLaunchConfig = {
    client_id: required_environment("LUNANEXA_CLIENT_ID"),
    display_name: required_environment("LUNANEXA_CLIENT_DISPLAY_NAME"),
    launch_uri: required_environment("LUNANEXA_CLIENT_LAUNCH_URI"),
    public_api_base_url: required_environment("LUNANEXA_PUBLIC_API_BASE_URL"),
    handoff_lifetime_ms: @string.parse_int64(
      @env.get_env_var("LUNANEXA_CLIENT_HANDOFF_LIFETIME_MS").unwrap_or(
        "120000",
      ),
    ),
    maximum_requests: @string.parse_int64(
      @env.get_env_var("LUNANEXA_CLIENT_MAXIMUM_REQUESTS").unwrap_or("100000"),
    ),
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
  let audit_token = required_environment("LUNANEXA_AUDIT_TOKEN")
  let monitoring_token = required_environment("LUNANEXA_MONITORING_TOKEN")
  let external_export_proof_token = if external_observability_collector_configured {
    required_environment("LUNANEXA_EXTERNAL_EXPORT_PROOF_TOKEN")
  } else {
    ""
  }
  let lease_helper_receipt_secret = required_environment(
    "LUNANEXA_LEASE_HELPER_RECEIPT_SECRET",
  )
  let callback_tokens = offline_callback_tokens(
    @env.get_env_var("LUNANEXA_ARTIFACT_WORKER_CALLBACK_TOKEN"),
    @env.get_env_var("LUNANEXA_ARTIFACT_SCANNER_CALLBACK_TOKEN"),
    operator_token,
    inference_token,
  )
  let entitlement_token = entitlement_callback_token(
    @env.get_env_var("LUNANEXA_ENTITLEMENT_AUTHORITY_CALLBACK_TOKEN"),
    @env.get_env_var("LUNANEXA_ARTIFACT_WORKER_CALLBACK_TOKEN"),
    @env.get_env_var("LUNANEXA_ARTIFACT_SCANNER_CALLBACK_TOKEN"),
    operator_token,
    inference_token,
  )
  let offline_transfer_adapter = offline_transfer_adapter_configuration(
    @env.get_env_var("LUNANEXA_OFFLINE_TRANSFER_ADAPTER_ENDPOINT"),
    @env.get_env_var("LUNANEXA_OFFLINE_TRANSFER_ADAPTER_TOKEN"),
    @env.get_env_var("LUNANEXA_OFFLINE_TRANSFER_SESSION_SECRET"),
  )
  let model_source_adapter = model_source_adapter_configuration(
    @env.get_env_var("LUNANEXA_MODEL_SOURCE_ADAPTER_ENDPOINT"),
    @env.get_env_var("LUNANEXA_MODEL_SOURCE_ADAPTER_TOKEN"),
  )
  let configured_provider_callback_secrets = provider_callback_secrets()
  let operational_secrets = [
    ("LUNANEXA_OPERATOR_TOKEN", operator_token),
    ("LUNANEXA_INFERENCE_TOKEN", inference_token),
    ("LUNANEXA_AUDIT_TOKEN", audit_token),
    ("LUNANEXA_MONITORING_TOKEN", monitoring_token),
    ("LUNANEXA_ASSIGNMENT_SIGNING_SECRET", assignment_signing_secret),
    ("LUNANEXA_CATALOG_SIGNING_SECRET", catalog_signing_secret),
    ("LUNANEXA_EXCLUSIVE_LEASE_SIGNING_SECRET", exclusive_lease_signing_secret),
    ("LUNANEXA_API_KEY_ISSUER_SECRET", api_key_issuer_secret),
    ("LUNANEXA_ACCOUNT_SESSION_ISSUER_SECRET", account_session_issuer_secret),
    (
      "LUNANEXA_CREDENTIAL_HANDOFF_ISSUER_SECRET", credential_handoff_issuer_secret,
    ),
    ("LUNANEXA_CLIENT_HANDOFF_ISSUER_SECRET", client_handoff_issuer_secret),
    ("LUNANEXA_LEASE_HELPER_RECEIPT_SECRET", lease_helper_receipt_secret),
  ]
  if identity_assertion_secret != "" {
    operational_secrets.push(
      ("LUNANEXA_IDENTITY_ASSERTION_SECRET", identity_assertion_secret),
    )
  }
  // Multi-operator attribution: when LUNANEXA_OPERATOR_TOKENS is set it
  // replaces the legacy single operator token on the contract-document
  // operator routes, and every token joins the distinct-secret validation.
  let operator_tokens = match @env.get_env_var("LUNANEXA_OPERATOR_TOKENS") {
    Some(raw) if raw.trim() != "" => {
      let pairs = parse_operator_tokens(raw)
      for pair in pairs {
        operational_secrets.push(("LUNANEXA_OPERATOR_TOKENS:\{pair.0}", pair.1))
      }
      pairs
    }
    _ => [("operator", operator_token)]
  }
  match @env.get_env_var("LUNANEXA_NOTIFICATION_DELIVERY_ADAPTER_TOKEN") {
    Some(secret) if secret != "" =>
      operational_secrets.push(
        ("LUNANEXA_NOTIFICATION_DELIVERY_ADAPTER_TOKEN", secret),
      )
    _ => ()
  }
  if guide_monitor_enabled {
    operational_secrets.push(
      ("LUNANEXA_GUIDE_IDENTITY_SECRET", guide_identity_secret),
    )
    operational_secrets.push(
      ("LUNANEXA_GUIDE_OBSERVATION_SECRET", guide_observation_secret),
    )
    operational_secrets.push(
      ("LUNANEXA_GUIDE_DIAGNOSTICS_TOKEN", guide_diagnostics_secret),
    )
  }
  if external_export_proof_token != "" {
    operational_secrets.push(
      ("LUNANEXA_EXTERNAL_EXPORT_PROOF_TOKEN", external_export_proof_token),
    )
  }
  match callback_tokens {
    Some(tokens) => {
      operational_secrets.push(
        ("LUNANEXA_ARTIFACT_WORKER_CALLBACK_TOKEN", tokens.0),
      )
      operational_secrets.push(
        ("LUNANEXA_ARTIFACT_SCANNER_CALLBACK_TOKEN", tokens.1),
      )
    }
    None => ()
  }
  match entitlement_token {
    Some(token) =>
      operational_secrets.push(
        ("LUNANEXA_ENTITLEMENT_AUTHORITY_CALLBACK_TOKEN", token),
      )
    None => ()
  }
  match @env.get_env_var("LUNANEXA_CREDENTIAL_ISSUER_READINESS_SECRET") {
    Some(secret) if secret != "" =>
      operational_secrets.push(
        ("LUNANEXA_CREDENTIAL_ISSUER_READINESS_SECRET", secret),
      )
    _ => ()
  }
  match @env.get_env_var("LUNANEXA_MACHINE_HELPER_READINESS_SECRET") {
    Some(secret) if secret != "" =>
      operational_secrets.push(
        ("LUNANEXA_MACHINE_HELPER_READINESS_SECRET", secret),
      )
    _ => ()
  }
  match offline_transfer_adapter {
    Some(configuration) => {
      operational_secrets.push(
        ("LUNANEXA_OFFLINE_TRANSFER_ADAPTER_TOKEN", configuration.1),
      )
      operational_secrets.push(
        ("LUNANEXA_OFFLINE_TRANSFER_SESSION_SECRET", configuration.2),
      )
    }
    None => ()
  }
  match model_source_adapter {
    Some(configuration) =>
      operational_secrets.push(
        ("LUNANEXA_MODEL_SOURCE_ADAPTER_TOKEN", configuration.1),
      )
    None => ()
  }
  match @env.get_env_var("LUNANEXA_OFFLINE_COMMERCE_READINESS_SECRET") {
    Some(secret) if secret != "" =>
      operational_secrets.push(
        ("LUNANEXA_OFFLINE_COMMERCE_READINESS_SECRET", secret),
      )
    _ => ()
  }
  match contract_document_worker_token {
    Some(secret) if secret != "" =>
      operational_secrets.push(
        ("LUNANEXA_CONTRACT_DOCUMENT_WORKER_TOKEN", secret),
      )
    _ => ()
  }
  for _, secret in configured_provider_callback_secrets {
    operational_secrets.push(("LUNANEXA_PROVIDER_CALLBACK_SECRET", secret))
  }
  validate_distinct_operational_secrets(operational_secrets)
  let offline_readiness = load_offline_readiness_evidence(
    @env.get_env_var("LUNANEXA_OFFLINE_COMMERCE_READINESS_PATH"),
    @env.get_env_var("LUNANEXA_OFFLINE_COMMERCE_READINESS_SECRET"),
    @async.now(),
  )
  let machine_helper_readiness = load_machine_helper_adapter_evidence(
    @env.get_env_var("LUNANEXA_MACHINE_HELPER_READINESS_PATH"),
    @env.get_env_var("LUNANEXA_MACHINE_HELPER_READINESS_SECRET"),
    @env.get_env_var("LUNANEXA_MACHINE_HELPER_NODE_SCOPE").unwrap_or(
      "dgx-spark-fleet",
    ),
    @async.now(),
  )
  let guide_diagnostics_token = if guide_monitor_enabled {
    Some(guide_diagnostics_secret)
  } else {
    None
  }
  let initial_service = @api.ApiService::with_control_plane(
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
    .with_account_store(account_store, identity_assertion_secret)
    .with_technical_store(technical_operations)
    .with_deployment_store(
      deployment_store,
      available_secret_refs=secret_references(),
    )
    .with_exclusive_lease_store(exclusive_lease_store)
    .with_credential_handoff_store(credential_handoff_store)
    .with_client_handoff_store(client_handoff_store, client_launch_config)
    .with_lease_helper_receipt_secret(lease_helper_receipt_secret)
    .with_portal_store(portal_store)
    .with_notification_store(notification_store)
    .with_observability_store(observability_store)
    .with_notification_delivery_adapter_configured(
      notification_adapter_configured,
    )
    .with_external_observability_collector_configured(
      external_observability_collector_configured,
    )
    .with_external_export_proof_token(external_export_proof_token)
    .with_offline_commerce_store(offline_commerce_store)
    .with_contract_document_store(contract_document_store)
    .with_reconciliation_only(
      @env.get_env_var("LUNANEXA_RECONCILIATION_ONLY") == Some("1"),
    )
    .with_role_tokens(audit_token, monitoring_token)
    .with_operator_tokens(operator_tokens)
    .with_retired_bootstrap_operator_token(
      @env.get_env_var("LUNANEXA_RETIRE_BOOTSTRAP_OPERATOR_TOKEN").unwrap_or(
        "1",
      ) ==
      "1",
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
    .with_inference_rate_card({
      rate_card_id: "inference-accelerator-second",
      version: @env.get_env_var("LUNANEXA_INFERENCE_RATE_VERSION").unwrap_or(
        "deployment-v1",
      ),
      meter: "accelerator-second",
      unit: "second",
      unit_price: @commercial.money(
        @string.parse_int64(
          @env.get_env_var(
            "LUNANEXA_INFERENCE_PRICE_PER_ACCELERATOR_SECOND_MINOR",
          ).unwrap_or("0"),
        ),
        @env.get_env_var("LUNANEXA_BILLING_CURRENCY").unwrap_or("CNY"),
        @string.parse_int64(
          @env.get_env_var("LUNANEXA_BILLING_SCALE").unwrap_or("2"),
        ).to_int(),
      ),
      effective_from_unix_ms: 1L,
      effective_until_unix_ms: 9223372036854775806L,
    })
    .with_provider_callback_secrets(configured_provider_callback_secrets)
    .with_global_admin_settings(global_settings)
  let configured_service = match offline_transfer_adapter {
    Some(configuration) =>
      initial_service.with_offline_transfer_adapter(
        configuration.0,
        configuration.1,
        configuration.2,
      )
    None => initial_service
  }
  let configured_service = match model_source_adapter {
    Some(configuration) =>
      configured_service.with_model_source_adapter(
        configuration.0,
        configuration.1,
      )
    None => configured_service
  }
  let configured_service = match contract_document_worker_token {
    Some(token) if token != "" => {
      if token.length() < 32 || token.length() > 4096 {
        raise Failure::Failure(
          "LUNANEXA_CONTRACT_DOCUMENT_WORKER_TOKEN must contain 32 to 4096 bytes",
        )
      }
      configured_service.with_contract_document_worker_token(token)
    }
    _ => configured_service
  }
  let configured_service = match contract_approval_threshold {
    Some(minor_units) =>
      configured_service.with_contract_approval_threshold(minor_units)
    None => configured_service
  }
  let configured_service = match machine_helper_readiness {
    Some(evidence) =>
      configured_service.with_machine_helper_adapter_evidence(evidence)
    None => configured_service
  }
  let diagnostic_service = match guide_diagnostics_token {
    Some(token) => configured_service.with_guide_diagnostics_token(token)
    None => configured_service
  }
  let base_service = match callback_tokens {
    Some(tokens) =>
      diagnostic_service.with_offline_artifact_callback_tokens(
        tokens.0,
        tokens.1,
      )
    None => diagnostic_service
  }
  let readiness_service = base_service.with_offline_commerce_capabilities(
    offline_readiness.0,
    offline_readiness.1,
  )
  let authority_service = match entitlement_token {
    Some(token) =>
      readiness_service.with_entitlement_authority_callback_token(token)
    None => readiness_service
  }
  let service = match management_database {
    Some(database) =>
      authority_service.with_commercial_persistence(
        commercial_store, commercial_integrations, database,
      )
    None => authority_service
  }
  let server = @http.Server(@socket.Addr::parse(address), reuse_addr=true)
  @async.with_task_group <| group => {
    group.spawn_bg(allow_failure=false) <| () => {
      service.run_notification_reconciler_forever(
        @string.parse_int64(
          @env.get_env_var("LUNANEXA_NOTIFICATION_RECONCILE_INTERVAL_MS").unwrap_or(
            "30000",
          ),
        ).to_int(),
      )
    }
    group.spawn_bg(allow_failure=false) <| () => {
      notification_delivery_worker.run_forever()
    }
    group.spawn_bg(allow_failure=false) <| () => {
      run_offline_commerce_reconciler(service)
    }
    group.spawn_bg(allow_failure=false) <| () => {
      run_contract_governance_reconciler(service)
    }
    group.spawn_bg(allow_failure=false) <| () => {
      service.run_exclusive_lease_expiry_reconciler_forever(
        @string.parse_int64(
          @env.get_env_var("LUNANEXA_EXCLUSIVE_LEASE_RECONCILE_INTERVAL_MS").unwrap_or(
            "30000",
          ),
        ).to_int(),
      )
    }
    group.spawn_bg(allow_failure=false) <| () => {
      service.run_contract_expiry_reconciler_forever(
        @string.parse_int64(
          @env.get_env_var("LUNANEXA_CONTRACT_EXPIRY_RECONCILE_INTERVAL_MS").unwrap_or(
            "3600000",
          ),
        ).to_int(),
        @string.parse_int64(
          @env.get_env_var("LUNANEXA_CONTRACT_EXPIRY_GRACE_DAYS").unwrap_or("7"),
        ),
      )
    }
    match guide_probe_worker {
      Some(worker) =>
        group.spawn_bg(allow_failure=false) <| () => { worker.run_forever() }
      None => ()
    }
    service.serve_on(server)
  }
}
