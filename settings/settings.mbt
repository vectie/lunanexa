///|
/// Identifies who may choose a setting. Global settings are loaded by the
/// management node; request preferences are bounded by that global policy;
/// local preferences never leave the client; hard ceilings cannot be raised
/// by either administrators or users.
pub(all) enum SettingAuthority {
  GlobalAdministrator
  EnterpriseUser
  LocalClient
  FixedSafetyBoundary
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SettingDescriptor {
  key : String
  authority : SettingAuthority
  restart_required : Bool
  description : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ControlTimingSettings {
  heartbeat_timeout_ms : Int64
  heartbeat_replay_window_ms : Int64
  provider_callback_replay_window_ms : Int64
  lease_observation_replay_window_ms : Int64
  artifact_transfer_grant_lifetime_ms : Int64
  bootstrap_token_max_lifetime_ms : Int64
  node_certificate_lifetime_ms : Int64
  node_certificate_renewal_lead_ms : Int64
  node_reconcile_interval_ms : Int
  materialization_heartbeat_interval_ms : Int
  lease_receipt_stale_after_ms : Int64
  workspace_reservation_max_lifetime_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RequestBudgetSettings {
  maximum_request_body_bytes : Int
  response_cache_entries : Int
  openai_default_deadline_ms : Int64
  openai_max_deadline_ms : Int64
  openai_default_output_units : Int
  openai_max_output_units : Int
  openai_max_input_units : Int
  openai_max_accelerator_memory_mib : Int
  runtime_stream_event_bytes : Int
  runtime_stream_total_bytes : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SchedulerPolicySettings {
  admission_capacity : Int
  runtime_concurrency : Int
  retry_attempts : Int
  background_capacity_percent : Int
  normal_capacity_percent : Int
  warm_model_weight : Int
  headroom_weight : Int
  queue_weight : Int
  reliability_weight : Int
  utilization_weight : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RetentionSettings {
  scheduler_decision_entries : Int
  telemetry_sample_entries : Int
  benchmark_run_entries : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeRuntimeSettings {
  container_pid_limit : Int
  artifact_io_chunk_bytes : Int
  signature_artifact_maximum_bytes : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TelemetrySafetySettings {
  maximum_sensor_rows : Int
  maximum_sensor_row_characters : Int
  maximum_memory_mib : Double
  maximum_accelerator_count : Double
  maximum_temperature_celsius : Double
  maximum_power_watts : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GlobalAdminSettings {
  schema_version : String
  generation : Int64
  control_timing : ControlTimingSettings
  request_budgets : RequestBudgetSettings
  scheduler : SchedulerPolicySettings
  retention : RetentionSettings
  node_runtime : NodeRuntimeSettings
  telemetry_safety : TelemetrySafetySettings
} derive(Debug, Eq, ToJson, FromJson)

///|
/// User-selectable request preferences. These may be sent with a request, but
/// they never weaken the global administrator policy or hard safety ceilings.
pub(all) struct UserRequestPreferences {
  model_alias : String
  deadline_ms : Int64
  max_output_units : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Browser/editor-only preferences. LunaNexa's management database does not
/// store these values and the GPU node never receives them.
pub(all) struct UserLocalPreferences {
  locale : String
  default_model_alias : String
  output_display_characters : Int
  remember_last_model : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EffectiveUserRequest {
  model_alias : String
  deadline_ms : Int64
  max_output_units : Int
  global_generation : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PublicSettingsView {
  schema_version : String
  global_generation : Int64
  request_budgets : RequestBudgetSettings
  control_timing : ControlTimingSettings
  authorities : Array[SettingDescriptor]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror SettingsError {
  InvalidGlobalSetting(String)
  UserPreferenceExceedsGlobalPolicy(String)
  InvalidLocalPreference(String)
} derive(Debug, Eq, ToJson)

///|
pub fn default_global_admin_settings() -> GlobalAdminSettings {
  {
    schema_version: "lunanexa.settings.v1",
    generation: 1L,
    control_timing: {
      heartbeat_timeout_ms: 15000L,
      heartbeat_replay_window_ms: 60000L,
      provider_callback_replay_window_ms: 300000L,
      lease_observation_replay_window_ms: 60000L,
      artifact_transfer_grant_lifetime_ms: 300000L,
      bootstrap_token_max_lifetime_ms: 900000L,
      node_certificate_lifetime_ms: 3600000L,
      node_certificate_renewal_lead_ms: 300000L,
      node_reconcile_interval_ms: 5000,
      materialization_heartbeat_interval_ms: 3000,
      lease_receipt_stale_after_ms: 45000L,
      workspace_reservation_max_lifetime_ms: 86400000L,
    },
    request_budgets: {
      maximum_request_body_bytes: 1048576,
      response_cache_entries: 1024,
      openai_default_deadline_ms: 120000L,
      openai_max_deadline_ms: 120000L,
      openai_default_output_units: 1024,
      openai_max_output_units: 131072,
      openai_max_input_units: 1048576,
      openai_max_accelerator_memory_mib: 1048576,
      runtime_stream_event_bytes: 1048576,
      runtime_stream_total_bytes: 16777216,
    },
    scheduler: {
      admission_capacity: 128,
      runtime_concurrency: 4,
      retry_attempts: 2,
      background_capacity_percent: 75,
      normal_capacity_percent: 90,
      warm_model_weight: 10000,
      headroom_weight: 1,
      queue_weight: 2,
      reliability_weight: 1,
      utilization_weight: 1,
    },
    retention: {
      scheduler_decision_entries: 1024,
      telemetry_sample_entries: 10000,
      benchmark_run_entries: 256,
    },
    node_runtime: {
      container_pid_limit: 512,
      artifact_io_chunk_bytes: 1048576,
      signature_artifact_maximum_bytes: 1048576L,
    },
    telemetry_safety: {
      maximum_sensor_rows: 1024,
      maximum_sensor_row_characters: 512,
      maximum_memory_mib: 1000000000.0,
      maximum_accelerator_count: 1024.0,
      maximum_temperature_celsius: 200.0,
      maximum_power_watts: 100000.0,
    },
  }
}

///|
pub fn parse_global_admin_settings(
  payload : String,
) -> GlobalAdminSettings raise SettingsError {
  let decoded : GlobalAdminSettings = @json.from_json(@json.parse(payload)) catch {
    _ => raise InvalidGlobalSetting("document")
  }
  validate_global_admin_settings(decoded)
  decoded
}

///|
fn positive_bounded(value : Int64, maximum : Int64) -> Bool {
  value > 0L && value <= maximum
}

///|
fn safe_model_alias(value : String) -> Bool {
  value != "" &&
  value.length() <= 128 &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '.' ||
    character == '-' ||
    character == '_' ||
    character == ':'
  })
}

///|
pub fn validate_global_admin_settings(
  settings : GlobalAdminSettings,
) -> Unit raise SettingsError {
  if settings.schema_version != "lunanexa.settings.v1" ||
    settings.generation <= 0L {
    raise InvalidGlobalSetting("schema_version or generation")
  }
  let timing = settings.control_timing
  if !positive_bounded(timing.heartbeat_timeout_ms, 300000L) ||
    !positive_bounded(timing.heartbeat_replay_window_ms, 900000L) ||
    !positive_bounded(timing.provider_callback_replay_window_ms, 900000L) ||
    !positive_bounded(timing.lease_observation_replay_window_ms, 300000L) ||
    !positive_bounded(timing.artifact_transfer_grant_lifetime_ms, 900000L) ||
    !positive_bounded(timing.bootstrap_token_max_lifetime_ms, 900000L) ||
    !positive_bounded(timing.node_certificate_lifetime_ms, 86400000L) ||
    !positive_bounded(timing.node_certificate_renewal_lead_ms, 3600000L) ||
    timing.node_certificate_renewal_lead_ms >=
    timing.node_certificate_lifetime_ms ||
    timing.node_reconcile_interval_ms < 250 ||
    timing.node_reconcile_interval_ms > 60000 ||
    timing.materialization_heartbeat_interval_ms < 250 ||
    timing.materialization_heartbeat_interval_ms > 60000 ||
    !positive_bounded(timing.lease_receipt_stale_after_ms, 300000L) ||
    !positive_bounded(timing.workspace_reservation_max_lifetime_ms, 86400000L) {
    raise InvalidGlobalSetting("control_timing")
  }
  let budgets = settings.request_budgets
  if budgets.maximum_request_body_bytes < 65536 ||
    budgets.maximum_request_body_bytes > 16777216 ||
    budgets.response_cache_entries < 16 ||
    budgets.response_cache_entries > 65536 ||
    !positive_bounded(budgets.openai_default_deadline_ms, 86400000L) ||
    !positive_bounded(budgets.openai_max_deadline_ms, 86400000L) ||
    budgets.openai_default_deadline_ms > budgets.openai_max_deadline_ms ||
    budgets.openai_default_output_units <= 0 ||
    budgets.openai_default_output_units > budgets.openai_max_output_units ||
    budgets.openai_max_output_units > 1000000 ||
    budgets.openai_max_input_units <= 0 ||
    budgets.openai_max_input_units > 10000000 ||
    budgets.openai_max_accelerator_memory_mib <= 0 ||
    budgets.openai_max_accelerator_memory_mib > 1048576 ||
    budgets.runtime_stream_event_bytes < 65536 ||
    budgets.runtime_stream_event_bytes > 1048576 ||
    budgets.runtime_stream_total_bytes < budgets.runtime_stream_event_bytes ||
    budgets.runtime_stream_total_bytes > 16777216 {
    raise InvalidGlobalSetting("request_budgets")
  }
  let scheduler = settings.scheduler
  if scheduler.admission_capacity <= 0 ||
    scheduler.admission_capacity > 65536 ||
    scheduler.runtime_concurrency <= 0 ||
    scheduler.runtime_concurrency > 4096 ||
    scheduler.retry_attempts <= 0 ||
    scheduler.retry_attempts > 3 ||
    scheduler.background_capacity_percent <= 0 ||
    scheduler.background_capacity_percent > scheduler.normal_capacity_percent ||
    scheduler.normal_capacity_percent > 100 ||
    scheduler.warm_model_weight < 0 ||
    scheduler.headroom_weight < 0 ||
    scheduler.queue_weight < 0 ||
    scheduler.reliability_weight < 0 ||
    scheduler.utilization_weight < 0 {
    raise InvalidGlobalSetting("scheduler")
  }
  let retention = settings.retention
  if retention.scheduler_decision_entries < 16 ||
    retention.scheduler_decision_entries > 65536 ||
    retention.telemetry_sample_entries < 100 ||
    retention.telemetry_sample_entries > 1000000 ||
    retention.benchmark_run_entries < 16 ||
    retention.benchmark_run_entries > 10000 {
    raise InvalidGlobalSetting("retention")
  }
  let runtime = settings.node_runtime
  if runtime.container_pid_limit < 32 ||
    runtime.container_pid_limit > 65536 ||
    runtime.artifact_io_chunk_bytes < 65536 ||
    runtime.artifact_io_chunk_bytes > 1048576 ||
    runtime.signature_artifact_maximum_bytes <= 0L ||
    runtime.signature_artifact_maximum_bytes > 16777216L {
    raise InvalidGlobalSetting("node_runtime")
  }
  let telemetry = settings.telemetry_safety
  if telemetry.maximum_sensor_rows <= 0 ||
    telemetry.maximum_sensor_rows > 4096 ||
    telemetry.maximum_sensor_row_characters < 64 ||
    telemetry.maximum_sensor_row_characters > 4096 ||
    telemetry.maximum_memory_mib <= 0.0 ||
    telemetry.maximum_memory_mib > 1000000000.0 ||
    telemetry.maximum_accelerator_count <= 0.0 ||
    telemetry.maximum_accelerator_count > 4096.0 ||
    telemetry.maximum_temperature_celsius < 80.0 ||
    telemetry.maximum_temperature_celsius > 250.0 ||
    telemetry.maximum_power_watts <= 0.0 ||
    telemetry.maximum_power_watts > 100000.0 {
    raise InvalidGlobalSetting("telemetry_safety")
  }
}

///|
pub fn default_user_local_preferences() -> UserLocalPreferences {
  {
    locale: "system",
    default_model_alias: "text.default",
    output_display_characters: 32768,
    remember_last_model: true,
  }
}

///|
pub fn validate_user_local_preferences(
  preferences : UserLocalPreferences,
) -> Unit raise SettingsError {
  if preferences.locale != "system" &&
    preferences.locale != "en" &&
    preferences.locale != "zh-CN" {
    raise InvalidLocalPreference("locale")
  }
  if !safe_model_alias(preferences.default_model_alias) ||
    preferences.output_display_characters < 1024 ||
    preferences.output_display_characters > 1048576 {
    raise InvalidLocalPreference("model or output display limit")
  }
}

///|
pub fn resolve_user_request(
  global : GlobalAdminSettings,
  preferences : UserRequestPreferences,
) -> EffectiveUserRequest raise SettingsError {
  validate_global_admin_settings(global)
  if !safe_model_alias(preferences.model_alias) {
    raise UserPreferenceExceedsGlobalPolicy("model_alias")
  }
  if preferences.deadline_ms <= 0L ||
    preferences.deadline_ms > global.request_budgets.openai_max_deadline_ms {
    raise UserPreferenceExceedsGlobalPolicy("deadline_ms")
  }
  if preferences.max_output_units <= 0 ||
    preferences.max_output_units >
    global.request_budgets.openai_max_output_units {
    raise UserPreferenceExceedsGlobalPolicy("max_output_units")
  }
  {
    model_alias: preferences.model_alias,
    deadline_ms: preferences.deadline_ms,
    max_output_units: preferences.max_output_units,
    global_generation: global.generation,
  }
}

///|
pub fn setting_authority_catalog() -> Array[SettingDescriptor] {
  [
    {
      key: "global.control_timing",
      authority: GlobalAdministrator,
      restart_required: true,
      description: "Cluster heartbeat, certificate, replay, and reconciliation timing",
    },
    {
      key: "global.request_budgets",
      authority: GlobalAdministrator,
      restart_required: true,
      description: "Cluster request, response-cache, and stream budgets",
    },
    {
      key: "global.scheduler",
      authority: GlobalAdministrator,
      restart_required: true,
      description: "Fixed-fleet admission, concurrency, retry, and placement policy",
    },
    {
      key: "request.model_alias",
      authority: EnterpriseUser,
      restart_required: false,
      description: "User-selected model within the tenant entitlement and global policy",
    },
    {
      key: "request.deadline_ms",
      authority: EnterpriseUser,
      restart_required: false,
      description: "Per-request deadline no greater than the global administrator ceiling",
    },
    {
      key: "request.max_output_units",
      authority: EnterpriseUser,
      restart_required: false,
      description: "Per-request output budget no greater than tenant and global ceilings",
    },
    {
      key: "local.locale",
      authority: LocalClient,
      restart_required: false,
      description: "Browser/editor language stored only on the local device",
    },
    {
      key: "local.output_display_characters",
      authority: LocalClient,
      restart_required: false,
      description: "Local rendering limit that cannot increase network or model budgets",
    },
    {
      key: "hard.security_ceilings",
      authority: FixedSafetyBoundary,
      restart_required: false,
      description: "Cryptographic, parser, replay, and resource maxima that configuration cannot raise",
    },
  ]
}

///|
pub fn public_settings_view(
  settings : GlobalAdminSettings,
) -> PublicSettingsView raise SettingsError {
  validate_global_admin_settings(settings)
  {
    schema_version: settings.schema_version,
    global_generation: settings.generation,
    request_budgets: settings.request_budgets,
    control_timing: settings.control_timing,
    authorities: setting_authority_catalog(),
  }
}
