///|
priv struct BrowserStreamEvent {
  sequence : Int
  kind : String
  text : String
  receipt : String
} derive(FromJson)

///|
priv struct ConsoleTelemetrySnapshot {
  samples : Array[@contracts.TelemetrySample]
  benchmark_summaries : Array[@contracts.BenchmarkReadSummary]
} derive(FromJson)

///|
priv struct OfflineQuoteAction {
  order_id : String
  quote : @offline.ImmutableQuote
} derive(ToJson)

///|
extend OfflineQuoteAction with ToJson::{to_json}

///|
priv struct OfflineOrderAction {
  order_id : String
  expected_generation : Int64
} derive(ToJson)

///|
extend OfflineOrderAction with ToJson::{to_json}

///|
priv struct OfflineReversalAction {
  reversal_id : String
  idempotency_key : String
  order_id : String
  expected_generation : Int64
  reason : @offline.CommercialReversalReason
} derive(ToJson)

///|
extend OfflineReversalAction with ToJson::{to_json}

///|
priv struct OfflineFulfillmentAction {
  order_id : String
  expected_generation : Int64
  activation_id : String
  idempotency_key : String
  entitlement_kind : @offline.EntitlementKind
  authority_target_ref : String
} derive(ToJson)

///|
extend OfflineFulfillmentAction with ToJson::{to_json}

///|
priv struct OfflineReversalRecoveryAction {
  recovery_id : String
  idempotency_key : String
  order_id : String
  failed_reversal_id : String
  expected_generation : Int64
  decision : @offline.ReversalRecoveryDecision
  replacement_reversal_id : String?
  authority_receipt : String
  reason_code : String
} derive(ToJson)

///|
extend OfflineReversalRecoveryAction with ToJson::{to_json}

///|
priv struct OfflineActionRequest {
  path : String
  body : String
  english_success : String
  chinese_success : String
}

///|
priv struct ContractInformationUpdate {
  expected_revision : Int64
  changes : Array[@contractdoc.ContractFieldValue]
} derive(ToJson)

///|
extend ContractInformationUpdate with ToJson::{to_json}

///|
priv struct ContractPreviewIntent {
  expected_revision : Int64
  form : @contractdoc.ContractFormKind
  changes : Array[@contractdoc.ContractFieldValue]
} derive(ToJson)

///|
extend ContractPreviewIntent with ToJson::{to_json}

///|
priv struct ContractExecutionRegistration {
  expected_revision : Int64
  evidence_sha256 : String
  signed_on : String
} derive(ToJson)

///|
extend ContractExecutionRegistration with ToJson::{to_json}

///|
priv struct ContractClosureIntent {
  expected_revision : Int64
  kind : @contractdoc.ContractClosureKind
  reason : String
} derive(ToJson)

///|
extend ContractClosureIntent with ToJson::{to_json}

///|
priv struct ContractSupersessionIntent {
  expected_revision : Int64
  successor_ref : String
  reason : String
} derive(ToJson)

///|
extend ContractSupersessionIntent with ToJson::{to_json}

///|
priv struct ContractRenewalIntent {
  packet_id : String
  idempotency_key : String
} derive(ToJson)

///|
extend ContractRenewalIntent with ToJson::{to_json}

///|
priv struct ContractGovernanceTenantRequest {
  tenant_ref : String
} derive(ToJson)

///|
extend ContractGovernanceTenantRequest with ToJson::{to_json}

///|
priv struct AccountCreateIntent {
  account_id : String
  subject_ref : String
  identity_issuer : String
  identity_subject : String
  display_name : String
  email : String
  identity_receipt : String
  roles : Array[@ui.UiAccountRole]
  state : @ui.UiAccountState
} derive(ToJson)

///|
extend AccountCreateIntent with ToJson::{to_json}

///|
priv struct AccountRolesIntent {
  roles : Array[@ui.UiAccountRole]
} derive(ToJson)

///|
extend AccountRolesIntent with ToJson::{to_json}

///|
/// One-time same-origin handoff from the external identity gateway. Both
/// secrets remain in the Elm model only and are never put in a URL or storage.
priv struct GatewayBrowserSession {
  session_token : String
  csrf_token : String
  expires_unix_ms : Int64
} derive(FromJson)

///|
extern "js" fn configured_endpoint() -> String =
  #| () => globalThis.LUNANEXA_API_ENDPOINT || globalThis.location?.origin || ""

///|
extern "js" fn demo_mode() -> Bool =
  #| () => {
  #|   try {
  #|     const value = new URL(globalThis.location.href).searchParams.get("demo");
  #|     return value === "1" || value === "true";
  #|   } catch (_) {
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn current_unix_ms() -> Int64 = "() => BigInt(Date.now())"

///|
extern "js" fn model_import_poll_promise() -> @js.Promise = "() => new Promise(resolve => setTimeout(resolve, 1500))"

///|
extern "js" fn random_identifier(prefix : String) -> String =
  #| prefix => `${prefix}-${crypto.randomUUID()}`

///|
extern "js" fn scroll_console_top() -> Unit =
  #| () => {
  #|   try {
  #|     globalThis.requestAnimationFrame?.(() => globalThis.scrollTo?.(0, 0));
  #|   } catch (_) {}
  #| }

///|
extern "js" fn download_json_file(filename : String, content : String) -> Unit =
  #| (filename, content) => {
  #|   const blob = new Blob([content], { type: "application/json;charset=utf-8" });
  #|   const url = URL.createObjectURL(blob);
  #|   try {
  #|     const link = document.createElement("a");
  #|     link.href = url;
  #|     link.download = filename.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 180);
  #|     link.rel = "noopener";
  #|     link.click();
  #|   } finally {
  #|     setTimeout(() => URL.revokeObjectURL(url), 0);
  #|   }
  #| }

///|
extern "js" fn stored_locale_preference() -> String =
  #| () => {
  #|   try {
  #|     return globalThis.localStorage?.getItem("lunanexa.locale") || "";
  #|   } catch (_) {
  #|     return "";
  #|   }
  #| }

///|
extern "js" fn commit_locale_preference(
  storage_value : String,
  language_tag : String,
  title : String,
) -> Unit =
  #| (storageValue, languageTag, title) => {
  #|   try {
  #|     globalThis.localStorage?.setItem("lunanexa.locale", storageValue);
  #|   } catch (_) {}
  #|   try {
  #|     if (globalThis.document?.documentElement) {
  #|       globalThis.document.documentElement.lang = languageTag;
  #|     }
  #|     if (globalThis.document) globalThis.document.title = title;
  #|   } catch (_) {}
  #| }

///|
fn console_copy(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
}

///|
fn console_document_title(locale : @i18n.Locale) -> String {
  console_copy(
    locale, "LunaNexa | Cluster Operations", "LunaNexa | 集群运维",
  )
}

///|
fn commercial_organization_is_valid(value : String) -> Bool {
  value == "" ||
  (
    value.length() <= 160 &&
    value.all(character => {
      character.is_ascii_alphabetic() ||
      character.is_ascii_digit() ||
      character == '-' ||
      character == '_' ||
      character == ':' ||
      character == '.' ||
      character == '@'
    })
  )
}

///|
fn apply_console_locale(locale : @i18n.Locale) -> Unit {
  commit_locale_preference(
    locale.storage_value(),
    locale.language_tag(),
    console_document_title(locale),
  )
}

///|
extern "js" fn format_unix_ms(value : Int64, unavailable : String) -> String =
  #| (value, unavailable) => {
  #|   const milliseconds = Number(value);
  #|   if (!Number.isFinite(milliseconds) || Math.abs(milliseconds) > 8640000000000000) {
  #|     return unavailable;
  #|   }
  #|   try {
  #|     return new Date(milliseconds).toISOString().replace("T", " ").replace(/:\d\d\.\d\d\dZ$/, " UTC");
  #|   } catch (_) {
  #|     return unavailable;
  #|   }
  #| }

///|
extern "js" fn request_promise(
  verb : String,
  url : String,
  token : String,
  subject_ref : String,
  body : String,
) -> @js.Promise =
  #| async (verb, url, token, subject, body) => {
  #|   const headers = {
  #|     "Accept": "application/json",
  #|     "Content-Type": "application/json",
  #|     "Authorization": `Bearer ${token}`
  #|   };
  #|   if (subject) headers["X-LunaNexa-Subject"] = subject;
  #|   const response = await fetch(url, {
  #|     method: verb,
  #|     headers,
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|     body: verb === "GET" ? undefined : body
  #|   });
  #|   const text = await response.text();
  #|   if (!response.ok) {
  #|     const detail = text.slice(0, 1024).replace(/[\r\n\t]+/g, " ");
  #|     throw new Error(`HTTP ${response.status}${detail ? `: ${detail}` : ""}`);
  #|   }
  #|   return text;
  #| }

///|
extern "js" fn gateway_session_promise() -> @js.Promise =
  #| async () => {
  #|   const response = await fetch("/auth/session", {
  #|     method: "GET",
  #|     headers: { "Accept": "application/json" },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error"
  #|   });
  #|   if (response.status === 401 || response.status === 404) return "";
  #|   if (!response.ok) throw new Error(`gateway session HTTP ${response.status}`);
  #|   const text = await response.text();
  #|   if (text.length > 4096) throw new Error("gateway session response exceeds its bound");
  #|   return text;
  #| }

///|
extern "js" fn gateway_logout_promise(csrf_token : String) -> @js.Promise =
  #| async csrf => {
  #|   if (!csrf) return;
  #|   const response = await fetch("/auth/logout", {
  #|     method: "POST",
  #|     headers: { "Accept": "application/json", "X-LunaNexa-CSRF": csrf },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error"
  #|   });
  #|   if (!response.ok && response.status !== 401) throw new Error(`gateway logout HTTP ${response.status}`);
  #| }

///|
/// Loads only the checked, field-free MoonLeaf scene shipped with demo assets.
extern "js" fn demo_contract_preview_promise() -> @js.Promise =
  #| async () => {
  #|   const response = await fetch("/assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json", {
  #|     method: "GET",
  #|     headers: { "Accept": "application/json" },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|   });
  #|   if (!response.ok) throw new Error(`MoonLeaf demo scene HTTP ${response.status}`);
  #|   const text = await response.text();
  #|   if (text.length > 524288) throw new Error("MoonLeaf demo scene exceeds its bound");
  #|   return text;
  #| }

///|
extern "js" fn contract_preview_delay_promise(
  milliseconds : Int,
) -> @js.Promise =
  #| milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds))

///|
/// Readiness uses 503 as a typed not-ready response, so preserve its JSON body.
extern "js" fn readiness_request_promise(
  url : String,
  token : String,
) -> @js.Promise =
  #| async (url, token) => {
  #|   const response = await fetch(url, {
  #|     method: "GET",
  #|     headers: { "Accept": "application/json", "Authorization": `Bearer ${token}` },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error"
  #|   });
  #|   const text = await response.text();
  #|   if (response.status !== 200 && response.status !== 503) throw new Error(`HTTP ${response.status}`);
  #|   return text;
  #| }

///|
priv struct CentralReadinessResponse {
  ready : Bool
  blocker_codes : Array[String]
} derive(FromJson)

///|
async fn load_production_readiness(
  endpoint : String,
  token : String,
) -> @ui.ProductionReadinessState {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  try {
    let text : String = readiness_request_promise("\{base}/v1/readiness", token)
      .wait()
      .cast()
    let value : CentralReadinessResponse = @json.from_json(@json.parse(text))
    {
      ready: value.ready && value.blocker_codes.length() == 0,
      loading: false,
      blocker_codes: value.blocker_codes,
      error: None,
    }
  } catch {
    error =>
      {
        ready: false,
        loading: false,
        blocker_codes: [],
        error: Some("\{Repr(error)}"),
      }
  }
}

///|
extern "js" fn stream_request_promise(
  url : String,
  token : String,
  subject_ref : String,
  body : String,
) -> @js.Promise =
  #| async (url, token, subject, body) => {
  #|   const headers = {
  #|     "Accept": "text/event-stream",
  #|     "Content-Type": "application/json",
  #|     "Authorization": `Bearer ${token}`
  #|   };
  #|   if (subject) headers["X-LunaNexa-Subject"] = subject;
  #|   const response = await fetch(url, {
  #|     method: "POST",
  #|     headers,
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|     body
  #|   });
  #|   if (!response.ok || !response.body) throw new Error(`HTTP ${response.status}`);
  #|   const reader = response.body.getReader();
  #|   const decoder = new TextDecoder();
  #|   const encoder = new TextEncoder();
  #|   const events = [];
  #|   let buffer = "";
  #|   let outputBytes = 0;
  #|   const accept = block => {
  #|     for (const line of block.split("\n")) {
  #|       if (!line.startsWith("data:")) continue;
  #|       const data = line.slice(5).trim();
  #|       if (!data) continue;
  #|       const event = JSON.parse(data);
  #|       const output = event.output;
  #|       let text = "";
  #|       if (output && typeof output.text_delta === "string") text = output.text_delta;
  #|       else if (output != null) text = JSON.stringify(output);
  #|       const bytes = encoder.encode(text).byteLength;
  #|       if (bytes > 65536 || outputBytes + bytes > 1048576 || events.length >= 512) {
  #|         throw new Error("stream display limit exceeded");
  #|       }
  #|       outputBytes += bytes;
  #|       const receipt = event.response?.audit_receipt || event.response?.error?.correlation_receipt || "";
  #|       events.push({ sequence: event.sequence, kind: event.kind, text, receipt });
  #|     }
  #|   };
  #|   while (true) {
  #|     const { value, done } = await reader.read();
  #|     buffer += decoder.decode(value || new Uint8Array(), { stream: !done }).replaceAll("\r\n", "\n");
  #|     if (buffer.length > 2097152) throw new Error("stream framing limit exceeded");
  #|     let boundary;
  #|     while ((boundary = buffer.indexOf("\n\n")) >= 0) {
  #|       accept(buffer.slice(0, boundary));
  #|       buffer = buffer.slice(boundary + 2);
  #|     }
  #|     if (done) break;
  #|   }
  #|   if (!events.some(event => event.kind === "Completed" || event.kind === "Failed" || event.kind === "Cancelled")) {
  #|     throw new Error("stream ended without a terminal event");
  #|   }
  #|   return JSON.stringify(events);
  #| }

///|
async fn request(
  verb : String,
  endpoint : String,
  path : String,
  token : String,
  subject_ref? : String = "",
  body? : String = "",
) -> String {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  let value = request_promise(verb, "\{base}\{path}", token, subject_ref, body).wait()
  value.cast()
}

///|
async fn stream_request(
  endpoint : String,
  token : String,
  subject_ref : String,
  body : String,
) -> Array[@ui.StreamEventView] {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  let value = stream_request_promise(
    "\{base}/v1/workloads:stream",
    token,
    subject_ref,
    body,
  ).wait()
  let text : String = value.cast()
  let events : Array[BrowserStreamEvent] = @json.from_json(@json.parse(text))
  [
    for event in events => {
      {
        sequence: event.sequence,
        kind: event.kind,
        text: event.text,
        receipt: event.receipt,
      }
    }
  ]
}

///|
fn architecture(heartbeat : @contracts.NodeHeartbeat) -> String {
  heartbeat.inventory.accelerators
  .get(0)
  .map(device => device.architecture)
  .unwrap_or("unreported")
}

///|
fn free_memory(heartbeat : @contracts.NodeHeartbeat) -> Int {
  let mut total = 0
  for device in heartbeat.inventory.accelerators {
    total += device.memory_free_mib
  }
  total
}

///|
fn total_memory(heartbeat : @contracts.NodeHeartbeat) -> Int {
  let mut total = 0
  for device in heartbeat.inventory.accelerators {
    total += device.memory_total_mib
  }
  total
}

///|
fn latest_node_metric(
  samples : Array[@contracts.TelemetrySample],
  node_id : String,
  metric : String,
) -> Int {
  let mut latest_timestamp = 0L
  let mut value = 0
  for sample in samples {
    if sample.node_id == node_id &&
      sample.metric == metric &&
      sample.timestamp_unix_ms >= latest_timestamp {
      latest_timestamp = sample.timestamp_unix_ms
      value = sample.value.to_int()
    }
  }
  value
}

///|
fn heartbeat_age_label(locale : @i18n.Locale, age_ms : Int64) -> String {
  if age_ms < 15000L {
    if locale.is_chinese() {
      "刚刚"
    } else {
      "Just now"
    }
  } else if age_ms < 60000L {
    if locale.is_chinese() {
      "\{age_ms / 1000L} 秒前"
    } else {
      "\{age_ms / 1000L} seconds ago"
    }
  } else if locale.is_chinese() {
    "\{age_ms / 60000L} 分钟前"
  } else {
    "\{age_ms / 60000L} minutes ago"
  }
}

///|
fn portal_lease_holder(
  locale : @i18n.Locale,
  snapshot : @portal.PortalSnapshot?,
  node_id : String,
) -> String {
  match snapshot {
    Some(value) =>
      for request in value.lease_requests {
        if request.state == Approved &&
          request.assigned_node_id == Some(node_id) {
          return "\{request.submission.organization_id} · \{request.submission.unix_username}"
        }
      }
    None => ()
  }
  if locale.is_chinese() {
    "未分配"
  } else {
    "Unassigned"
  }
}

///|
fn license_status(
  registry : @contracts.RegistryReadContract,
  license_id : String,
) -> String {
  for license in registry.licenses {
    if license.license_id == license_id {
      return license.status
    }
  }
  "missing"
}

///|
fn evaluation_status(
  registry : @contracts.RegistryReadContract,
  model_id : String,
  version : String,
) -> String {
  for evaluation in registry.evaluations {
    if evaluation.model_id == model_id && evaluation.model_version == version {
      return if evaluation.passed { "passed" } else { "failed" }
    }
  }
  "missing"
}

///|
fn alias_name(
  registry : @contracts.RegistryReadContract,
  model_id : String,
  version : String,
) -> String {
  for alias_record in registry.aliases {
    if alias_record.model_id == model_id && alias_record.version == version {
      return alias_record.name
    }
  }
  "—"
}

///|
fn workspace_user_id(
  users : Array[@workspace.WorkspaceUser],
  subject_ref : String,
) -> String {
  users
  .iter()
  .find_first(user => user.subject_ref == subject_ref)
  .map(user => user.user_id)
  .unwrap_or(subject_ref)
}

///|
fn workspace_resource(limits : @workspace.WorkspaceLimits) -> String {
  if limits.capabilities.length() == 0 {
    return "No inference capabilities"
  }
  [
    for limit in limits.capabilities => {
      let name = match limit.capability {
        TextGenerate => "Text generation"
        EmbeddingCreate => "Embeddings"
        ImageGenerate => "Image generation"
        VideoGenerate => "Video generation"
        AudioGenerate => "Audio generation"
      }
      "\{name} · \{limit.max_concurrent_requests} concurrent"
    }
  ].join(", ")
}

///|
fn optional_subject_is_valid(value : String) -> Bool {
  let subject_ref = value.trim().to_owned()
  subject_ref == "" || @workspace.valid_identifier(subject_ref)
}

///|
fn catalog_template_key(template : @deployment.ModelServiceTemplate) -> String {
  "\{template.template_id}@\{template.version}"
}

///|
fn quick_deployment_intent(
  state : @ui.ConsoleState,
  _now_unix_ms : Int64,
) -> @deployment.ModelServiceIntent? {
  let deployment_id = state.quick_deployment_id.trim().to_owned()
  guard @contracts.valid_identifier(deployment_id, maximum_length=128) &&
    state.catalog_templates
    .iter()
    .find_first(template => {
      catalog_template_key(template) == state.quick_template
    })
    is Some(template) else {
    return None
  }
  Some({
    version: @contracts.contract_version,
    idempotency_key: "console:\{deployment_id}",
    deployment_id,
    template: { template_id: template.template_id, version: template.version },
    replicas: 1,
    data_class: template.data_policy.classification,
    lease_duration_ms: 86400000L,
    promote_when_ready: false,
  })
}

///|
fn service_deployment_action_path(
  deployment_id : String,
  action : String,
) -> String {
  "/v1/service-deployments/\{deployment_id}/\{action}"
}

///|
priv enum WorkspaceLifecycleAction {
  ActivateWorkspaceUser(String)
  SuspendWorkspaceUser(String)
  RevokeWorkspaceUser(String)
  ActivateWorkspaceLease(String)
}

///|
fn workspace_lifecycle_path(action : WorkspaceLifecycleAction) -> String {
  match action {
    ActivateWorkspaceUser(user_id) => "/v1/workspace/users/\{user_id}:activate"
    SuspendWorkspaceUser(user_id) => "/v1/workspace/users/\{user_id}:suspend"
    RevokeWorkspaceUser(user_id) => "/v1/workspace/users/\{user_id}:revoke"
    ActivateWorkspaceLease(lease_id) =>
      "/v1/workspace/leases/\{lease_id}:activate"
  }
}

///|
fn user_confirmation_scope(
  users : Array[@ui.UserAccessRow],
  user_id : String,
) -> String {
  users
  .iter()
  .find_first(user => user.user_id == user_id)
  .map(user => "\{user.user_id} · \{user.display_name} · \{user.email}")
  .unwrap_or(user_id)
}

///|
fn prepare_user_confirmation(
  state : @ui.ConsoleState,
  user_id : String,
  action : @ui.DestructiveAction,
) -> @ui.ConsoleState {
  {
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        action,
        user_confirmation_scope(state.users, user_id),
      ),
    ),
  }
}

///|
fn account_confirmation_scope(
  accounts : Array[@ui.AccountView],
  account_id : String,
) -> String {
  accounts
  .iter()
  .find_first(account => account.account_id == account_id)
  .map(account => {
    "\{account.account_id} · \{account.display_name} · \{account.email} · \{account.identity_issuer}"
  })
  .unwrap_or(account_id)
}

///|
fn prepare_account_confirmation(
  state : @ui.ConsoleState,
  account_id : String,
  action : @ui.DestructiveAction,
) -> @ui.ConsoleState {
  {
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        action,
        account_confirmation_scope(state.accounts, account_id),
      ),
    ),
  }
}

///|
async fn load_console(
  endpoint : String,
  token : String,
  audit_token : String,
  commercial_organization : String,
  route : @ui.OperatorRoute,
  locale : @i18n.Locale,
) -> @ui.ConsoleState {
  let production_readiness = load_production_readiness(endpoint, token)
  let heartbeats : Array[@contracts.NodeHeartbeat] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/nodes", token)),
  )
  let assignments : Array[@contracts.DesiredAssignment] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/assignments", token)),
  )
  let audit : Array[@contracts.AuditEvent] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/audit", audit_token)),
  )
  let registry : @contracts.RegistryReadContract = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/registry", token)),
  )
  let scheduler : @contracts.SchedulerReadContract = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/scheduler", token)),
  )
  let telemetry : ConsoleTelemetrySnapshot = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/telemetry", token)),
  )
  let workspace : @workspace.WorkspaceDirectorySnapshot = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/workspace", token)),
  )
  let accounts : Array[@ui.AccountView] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/accounts", token)),
  )
  let authenticated_account : @ui.AccountView? = if token.has_prefix("lnxs_") {
    Some(
      @json.from_json(
        @json.parse(request("GET", endpoint, "/v1/auth/self", token)),
      ),
    )
  } else {
    None
  }
  let account_sessions : Array[@ui.BrowserSessionView] = if token.has_prefix(
      "lnxs_",
    ) {
    @json.from_json(
      @json.parse(request("GET", endpoint, "/v1/auth/sessions", token)),
    )
  } else {
    []
  }
  let catalog_templates : Array[@deployment.ModelServiceTemplate] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/catalog/templates", token)),
  )
  let service_deployments : Array[@deployment.DeploymentOperation] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/service-deployments", token)),
  )
  let model_imports : Array[@ui.ModelImportRow] = @json.from_json(
    @json.parse(
      request("GET", endpoint, "/v1/model-sources/modelscope/imports", token),
    ),
  ) catch {
    _ => []
  }
  let exclusive_leases : Array[@nodelease.ExclusiveNodeLease] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/exclusive-node-leases", token)),
  )
  let notification_records : Array[@notifications.NotificationRecord] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/notifications/operator", token)),
  )
  let notification_delivery_records : Array[@notifications.NotificationDelivery] = @json.from_json(
    @json.parse(
      request("GET", endpoint, "/v1/notifications/operator/deliveries", token),
    ),
  ) catch {
    // Compatibility with the immediately preceding controller release, which
    // has notification records but not the operator delivery-list route.
    // Treating only this supplemental view as empty keeps authentication and
    // the rest of the console usable while the controller is upgraded.
    _ => []
  }
  // This snapshot carries release and fulfillment authority. Loading failures
  // must be visible and must never masquerade as an empty commerce queue.
  let offline_snapshot : @offline.OfflineCommerceSnapshot = @json.from_json(
    @json.parse(
      request("GET", endpoint, "/v1/offline-commerce/operator/snapshot", token),
    ),
  )
  // The manifest is a public, versioned product artifact compiled into the
  // console. Using the same source of truth here also keeps the web client
  // compatible with controllers that expose it only to the customer portal.
  let contract_manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let contract_snapshot : @contractdoc.ContractDocumentSnapshot = @json.from_json(
    @json.parse(
      request(
        "GET", endpoint, "/v1/contract-documents/operator/snapshot", token,
      ),
    ),
  )
  let contract_packets = contract_snapshot.packets
  let contract_approvals = contract_snapshot.approvals.filter(approval => {
    approval.status == Pending || approval.status == Approved
  })
  let contract_governance_dashboard : @contractdoc.ContractGovernanceDashboard? = {
    let tenant_ref = contract_packets
      .get(0)
      .map(packet => packet.tenant_ref)
      .unwrap_or(commercial_organization)
    if tenant_ref == "" {
      None
    } else {
      let body = ContractGovernanceTenantRequest::{ tenant_ref, }
        .to_json()
        .stringify()
      try
        Some(
          @json.from_json(
            @json.parse(
              request(
                "POST",
                endpoint,
                "/v1/contract-governance/operator/dashboard",
                token,
                body~,
              ),
            ),
          ),
        )
      catch {
        _ => None
      } noraise {
        value => value
      }
    }
  }
  let portal_snapshot : @portal.PortalSnapshot? = try
    Some(
      @json.from_json(
        @json.parse(
          request("GET", endpoint, "/v1/portal/operator/snapshot", token),
        ),
      ),
    )
  catch {
    _ => None
  } noraise {
    value => value
  }
  let commercial_snapshot : @commercial.CommercialSnapshot? = if commercial_organization ==
    "" {
    None
  } else {
    Some(
      @json.from_json(
        @json.parse(
          request(
            "GET",
            endpoint,
            "/v1/commercial/organizations/\{commercial_organization}/snapshot",
            token,
          ),
        ),
      ),
    )
  }
  let integration_snapshot : @commercial_integrations.IntegrationSnapshot? = if commercial_organization ==
    "" {
    None
  } else {
    Some(
      @json.from_json(
        @json.parse(
          request(
            "GET",
            endpoint,
            "/v1/commercial/organizations/\{commercial_organization}/integrations",
            token,
          ),
        ),
      ),
    )
  }
  let now = current_unix_ms()
  let nodes : Array[@ui.NodeRow] = [
    for heartbeat in heartbeats => {
      let reported_total = latest_node_metric(
        telemetry.samples,
        heartbeat.node_id,
        "accelerator_memory_total_mib",
      )
      let reported_used = latest_node_metric(
        telemetry.samples,
        heartbeat.node_id,
        "accelerator_memory_used_mib",
      )
      let assignments = heartbeat.running_deployments.join(", ")
      {
        node_id: heartbeat.node_id,
        state: if now - heartbeat.timestamp_unix_ms > 15000L {
          Unreachable
        } else {
          heartbeat.state
        },
        architecture: architecture(heartbeat),
        total_memory_mib: if reported_total > 0 {
          reported_total
        } else {
          total_memory(heartbeat)
        },
        free_memory_mib: free_memory(heartbeat),
        used_memory_mib: if reported_used > 0 {
          reported_used
        } else {
          (total_memory(heartbeat) - free_memory(heartbeat)).max(0)
        },
        utilization_per_mille: latest_node_metric(
          telemetry.samples,
          heartbeat.node_id,
          "accelerator_utilization_per_mille",
        ),
        temperature_celsius: latest_node_metric(
          telemetry.samples,
          heartbeat.node_id,
          "accelerator_temperature_celsius",
        ),
        power_watts: latest_node_metric(
          telemetry.samples,
          heartbeat.node_id,
          "accelerator_power_watts",
        ),
        workloads: heartbeat.running_deployments.length(),
        lease_holder: portal_lease_holder(
          locale,
          portal_snapshot,
          heartbeat.node_id,
        ),
        active_assignment: if assignments == "" {
          if locale.is_chinese() {
            "空闲"
          } else {
            "Idle"
          }
        } else {
          assignments
        },
        last_seen: heartbeat_age_label(
          locale,
          (now - heartbeat.timestamp_unix_ms).max(0L),
        ),
      }
    }
  ]
  let models : Array[@ui.ModelRow] = [
    for model in registry.models => {
      {
        model_id: model.model_id,
        version: model.version,
        state: model.state,
        license_status: license_status(registry, model.license_id),
        evaluation_status: evaluation_status(
          registry,
          model.model_id,
          model.version,
        ),
        compatibility: model.compatible_architectures.join(", "),
        alias_name: alias_name(registry, model.model_id, model.version),
      }
    }
  ]
  let deployments : Array[@ui.DeploymentRow] = [
    for assignment in assignments => {
      let running = heartbeats.any(heartbeat => {
        heartbeat.node_id == assignment.node_id &&
        now - heartbeat.timestamp_unix_ms <= 15000L &&
        heartbeat.running_deployments.any(id => id == assignment.deployment_id)
      })
      {
        assignment_id: assignment.assignment_id,
        deployment_id: assignment.deployment_id,
        desired: Ready,
        observed: if running {
          Ready
        } else {
          Preparing
        },
        placement_reason: "\{assignment.node_id} · #\{assignment.generation}",
      }
    }
  ]
  let active_nodes = nodes.count_if(node => node.state == Active)
  let users : Array[@ui.UserAccessRow] = [
    for user in workspace.users => {
      {
        user_id: user.user_id,
        display_name: user.display_name,
        email: user.email,
        state: user.state,
        last_active: user.last_active_unix_ms
        .map(timestamp => format_unix_ms(timestamp, "Unavailable"))
        .unwrap_or("Never"),
        grant_count: workspace.access_grants.count_if(grant => {
          grant.user_id == user.user_id
        }),
      }
    }
  ]
  let access_grants : Array[@ui.AccessGrantRow] = [
    for grant in workspace.access_grants => {
      {
        grant_id: grant.grant_id,
        user_id: grant.user_id,
        role: grant.access,
        scope: grant.tenant_ref,
        expires_at: format_unix_ms(grant.expires_unix_ms, "Unavailable"),
        state: grant.state,
      }
    }
  ]
  let compute_leases : Array[@ui.ComputeLeaseRow] = [
    for lease in workspace.leases => {
      {
        lease_id: lease.lease_id,
        user_id: workspace_user_id(workspace.users, lease.subject_ref),
        workspace: lease.tenant_ref,
        resource: workspace_resource(lease.limits),
        started_at: format_unix_ms(lease.starts_unix_ms, "Unavailable"),
        expires_at: format_unix_ms(lease.expires_unix_ms, "Unavailable"),
        state: lease.state,
      }
    }
  ]
  let exclusive_node_leases : Array[@ui.ExclusiveNodeLeaseRow] = [
    for lease in exclusive_leases => {
      {
        lease_id: lease.intent.lease_id,
        node_id: lease.intent.node_id,
        subject_ref: lease.intent.subject_ref,
        unix_username: lease.intent.unix_username,
        expires_at: format_unix_ms(lease.intent.expires_unix_ms, "Unavailable"),
        state: "\{Repr(lease.state)}",
        generation: lease.generation,
      }
    }
  ]
  let request_details : Array[@ui.RequestDetail] = []
  for event in audit {
    if event.action.has_prefix("workload.") {
      request_details.push({
        timestamp_unix_ms: event.timestamp_unix_ms,
        action: event.action,
        model_selector: event.target,
        result: event.result,
        receipt: event.correlation_receipt,
      })
    }
  }
  while request_details.length() > 50 {
    ignore(request_details.remove(0))
  }
  let notifications : Array[@ui.NotificationRow] = [
    for record in notification_records => {
      {
        notification_id: record.event.notification_id,
        code: record.event.code,
        severity: record.event.severity,
        lifecycle: record.lifecycle,
        topic: record.event.topic,
        created_unix_ms: record.event.created_unix_ms,
        generation: record.generation,
        node_ref: record.event.parameters.get("node_ref").unwrap_or(""),
        assigned_to: record.assigned_to.unwrap_or(""),
        silenced_until_unix_ms: record.silenced_until_unix_ms,
      }
    }
  ]
  let notification_deliveries : Array[@ui.NotificationDeliveryRow] = [
    for delivery in notification_delivery_records => {
      {
        delivery_id: delivery.delivery_id,
        notification_id: delivery.notification_id,
        channel: delivery.channel,
        state: delivery.state,
        attempt_count: delivery.attempt_count,
        updated_unix_ms: delivery.updated_unix_ms,
        last_error_code: delivery.last_error_code.unwrap_or(""),
      }
    }
  ]
  let cost_centers : Array[@ui.CostCenterRow] = match commercial_snapshot {
    Some(snapshot) =>
      [
        for center in snapshot.cost_centers => {
          let center_projects = snapshot.projects.filter(project => {
            project.cost_center_id == center.cost_center_id
          })
          let entries = snapshot.ledger_entries.filter(entry => {
            entry.cost_center_id == center.cost_center_id
          })
          let budget_count = snapshot.budgets.count_if(budget => {
            budget.project_id is None ||
            center_projects.any(project => {
              budget.project_id == Some(project.project_id)
            })
          })
          {
            cost_center_id: center.cost_center_id,
            organization_id: center.organization_id,
            display_name: center.display_name,
            parent_cost_center_id: center.parent_cost_center_id.unwrap_or("—"),
            project_count: center_projects.length(),
            provisional_spend: if entries.length() == 0 {
              "—"
            } else {
              let first = entries[0].amount
              let total : @commercial.FixedMoney? = try {
                let mut sum = @commercial.money(0L, first.currency, first.scale)
                for entry in entries {
                  sum = sum.add(entry.amount)
                }
                Some(sum)
              } catch {
                _ => None
              } noraise {
                value => value
              }
              match total {
                Some(value) =>
                  "\{value.currency} \{value.minor_units} minor units · scale \{value.scale}"
                None => "Unavailable"
              }
            },
            budget_posture: "\{budget_count} budget policies",
          }
        }
      ]
    None => []
  }
  let agreements : Array[@ui.AgreementRow] = match commercial_snapshot {
    Some(snapshot) =>
      [
        for agreement in snapshot.agreements => {
          {
            agreement_id: agreement.agreement_id,
            agreement_type: agreement.template_id,
            template_version: "\{agreement.template_id}@\{agreement.template_version}",
            organization_id: agreement.organization_id,
            state: "\{Repr(agreement.state)}",
            evidence_receipt: agreement.executed_artifact_hash.unwrap_or(
              agreement.rendered_document_hash,
            ),
          }
        }
      ]
    None => []
  }
  let qualified_services : Array[@ui.QualifiedServiceRow] = match
    integration_snapshot {
    Some(snapshot) =>
      [
        for record in snapshot.records => {
          {
            provider: record.provider,
            capability: "\{Repr(record.kind)}",
            environment: record.environment,
            state: "\{Repr(record.state)}",
            evidence_policy: "Hashed provider reference · tenant-bound record",
            production_ready: false,
          }
        }
      ]
    None => []
  }
  let enterprise_lease_requests : Array[@ui.EnterpriseLeaseRequestRow] = match
    portal_snapshot {
    Some(snapshot) =>
      [
        for request in snapshot.lease_requests => {
          {
            request_id: request.submission.request_id,
            organization_id: request.submission.organization_id,
            subject_ref: request.subject_ref,
            project_id: request.submission.project_id,
            unix_username: request.submission.unix_username,
            requested_models: request.submission.requested_model_ids.join(", "),
            state: "\{Repr(request.state)}",
            generation: request.generation,
            assigned_node_id: request.assigned_node_id.unwrap_or("—"),
          }
        }
      ]
    None => []
  }
  {
    locale,
    route,
    overview: {
      active_nodes,
      total_nodes: heartbeats.length(),
      active_models: models.count_if(model => model.state == Approved),
      queue_depth: scheduler.queued_count.unwrap_or(scheduler.active.length()),
      alerts: notifications.count_if(notification => {
        notification.lifecycle != Resolved
      }),
      recent_changes: audit.length().min(20),
    },
    nodes,
    models,
    deployments,
    catalog_templates,
    service_deployments,
    requests: {
      count: audit.count_if(event => event.action.has_prefix("workload.")),
      p95_ms: telemetry.benchmark_summaries
      .last()
      .map(summary => summary.latency_p95_ms)
      .unwrap_or(0),
      throughput_per_second: telemetry.benchmark_summaries
      .last()
      .map(summary => summary.throughput_units_per_second)
      .unwrap_or(0),
      errors: audit.count_if(event => {
        event.action == "workload.fail" || event.result != "accepted"
      }),
    },
    request_details,
    stream_events: [],
    benchmark_evidence: [
      for summary in telemetry.benchmark_summaries => {
        "\{summary.profile} · p95 \{summary.latency_p95_ms} ms · \{summary.throughput_units_per_second}/s · failures \{summary.failure_per_mille}‰ · \{summary.run_id}"
      }
    ],
    policies: {
      quota_count: scheduler.quotas.length(),
      data_class_count: 4,
      default_retention: Ephemeral,
      allowed_runtimes: [
        for runtime in registry.runtimes => runtime.name
      ],
    },
    audit: [
      for event in audit => {
        {
          actor: event.actor,
          decision: event.action,
          evidence: event.target,
          result: event.result,
          receipt: event.correlation_receipt,
        }
      }
    ],
    notifications,
    notification_deliveries,
    accounts,
    authenticated_account,
    account_sessions,
    account_invite: {
      account_id: "",
      subject_ref: "",
      identity_issuer: "",
      identity_subject: "",
      display_name: "",
      email: "",
      identity_receipt: "",
      roles: [EnterpriseUser],
    },
    users,
    access_grants,
    compute_leases,
    exclusive_node_leases,
    cost_centers,
    agreements,
    enterprise_lease_requests,
    portal_node_id: "",
    qualified_services,
    offline_commerce: {
      ..@offline_commerce.default_state(locale, OperatorCommerce),
      orders: offline_snapshot.orders,
      reversals: offline_snapshot.reversals,
      artifacts: [
        for value in offline_snapshot.artifacts => {
          {
            artifact_id: value.artifact_id,
            order_id: value.order_id,
            kind: value.kind,
            revision: value.revision,
            media_type: value.media_type,
            byte_count: value.byte_count,
            sha256: value.sha256,
            scan_state: value.scan_state,
            review_state: value.review_state,
            submitted_by: value.submitted_by,
            created_unix_ms: value.created_unix_ms,
          }
        }
      ],
      templates: offline_snapshot.templates,
      selected_order_id: if offline_snapshot.orders.length() > 0 {
        Some(offline_snapshot.orders[0].order_id)
      } else {
        None
      },
    },
    contract_documents: {
      ..@contract_documents.default_state(locale, actor_owner=ManagerOperator),
      manifest: Some(contract_manifest),
      packets: contract_packets,
      events: contract_snapshot.events,
      approvals: contract_approvals,
      amendments: contract_snapshot.amendments,
      obligations: contract_snapshot.obligations,
      closure_proposals: contract_snapshot.closure_proposals,
      contract_numbers: contract_snapshot.numbers,
      now_unix_ms: current_unix_ms(),
      governance_dashboard: contract_governance_dashboard,
      selected_packet_id: contract_packets
      .get(0)
      .map(packet => packet.packet_id),
      selected_form: match contract_packets.get(0) {
        Some(packet) => packet.active_forms.get(0)
        None => None
      },
      draft_values: contract_packets
      .get(0)
      .map_or([], packet => packet.values.copy()),
    },
    production_readiness,
    confirmation: None,
    error_message: None,
    success_message: None,
    loading: false,
    operator_authenticated: true,
    model_source_query: "MiniCPM",
    model_source_results: [],
    model_source_total: 0L,
    model_imports,
    operation_name: "register-model",
    operation_body: "",
    quick_deployment_id: "",
    quick_template: catalog_templates
    .get(0)
    .map(catalog_template_key)
    .unwrap_or(""),
  }
}

///|
priv enum LoadOutcome {
  Loaded(@ui.ConsoleState)
  LoadFailed(@i18n.Locale, String)
  ActionComplete(@i18n.Locale, String)
  ModelSourceSearchLoaded(@i18n.Locale, @ui.ModelSourceCatalogPage)
  ModelImportsLoaded(@i18n.Locale, Array[@ui.ModelImportRow], String?)
  ModelImportsPolled(Int64, Array[@ui.ModelImportRow])
  ModelImportPollFailed(Int64, @i18n.Locale)
  StreamComplete(Array[@ui.StreamEventView])
  ActionFailed(@i18n.Locale, String)
  ContractPacketUpdated(@contractdoc.ContractPacket)
  ContractLifecycleComplete(@i18n.Locale, @contractdoc.ContractPacket, String)
  ContractApprovalRequested(@i18n.Locale)
  ContractApprovalDecided(@i18n.Locale, String)
  ContractActionFailed(@i18n.Locale, String)
  ContractConflict(@i18n.Locale)
  ContractPreviewLoaded(Int64, @contractdoc.ContractPreviewDocument)
  ContractPreviewFailed(Int64, @i18n.Locale, String)
}

///|
priv struct AppModel {
  endpoint : String
  credential : String
  audit_credential : String
  csrf_token : String
  inference_credential : String
  inference_subject_ref : String
  commercial_organization : String
  demo_mode : Bool
  console : @ui.ConsoleState
  next_directive_generation : Int64
  contract_preview_generation : Int64
  model_import_poll_generation : Int64
} derive(Eq)

///|
priv enum AppMessage {
  GatewaySessionLoaded(GatewayBrowserSession)
  GatewaySessionUnavailable
  AccountSessionChanged(String)
  CredentialChanged(String)
  AuditCredentialChanged(String)
  InferenceCredentialChanged(String)
  InferenceSubjectChanged(String)
  CommercialOrganizationChanged(String)
  Connect
  Logout
  SessionLogoutFinished
  Console(@ui.ConsoleMessage)
  ContractPreviewDue(Int64, @contract_documents.ContractDocumentsMessage)
  ModelImportPollDue(Int64)
  Outcome(LoadOutcome)
}

///|
fn merge_loaded_console(
  current : @ui.ConsoleState,
  loaded : @ui.ConsoleState,
) -> @ui.ConsoleState {
  {
    ..loaded,
    locale: current.locale,
    route: current.route,
    model_source_query: current.model_source_query,
    model_source_results: current.model_source_results,
    model_source_total: current.model_source_total,
    model_imports: loaded.model_imports,
    operation_name: current.operation_name,
    operation_body: current.operation_body,
    quick_deployment_id: current.quick_deployment_id,
    quick_template: if current.quick_template == "" {
      loaded.quick_template
    } else {
      current.quick_template
    },
    portal_node_id: current.portal_node_id,
    offline_commerce: {
      ..loaded.offline_commerce,
      locale: current.locale,
      operator_actor_ref: current.offline_commerce.operator_actor_ref,
      quote_minor_units: current.offline_commerce.quote_minor_units,
      terms_digest: current.offline_commerce.terms_digest,
      entitlement_ref: current.offline_commerce.entitlement_ref,
    },
    contract_documents: {
      ..loaded.contract_documents,
      locale: current.locale,
      selected_tenant_ref: current.contract_documents.selected_tenant_ref,
      search_query: current.contract_documents.search_query,
      selected_packet_id: current.contract_documents.selected_packet_id,
      selected_form: current.contract_documents.selected_form,
      preview: current.contract_documents.preview,
      preview_loading: false,
    },
    success_message: current.success_message,
  }
}

///|
fn switch_console_locale(
  state : @ui.ConsoleState,
  locale : @i18n.Locale,
) -> @ui.ConsoleState {
  {
    ..state,
    locale,
    offline_commerce: { ..state.offline_commerce, locale, },
    contract_documents: { ..state.contract_documents, locale, },
    // Notices are UI-owned, ephemeral copy. Clear them rather than retaining a
    // message rendered in the previous language; operational state is kept.
    error_message: None,
    success_message: None,
  }
}

///|
fn switch_app_locale(model : AppModel, locale : @i18n.Locale) -> AppModel {
  { ..model, console: switch_console_locale(model.console, locale) }
}

///|
fn locale_fenced_notice(
  current : @i18n.Locale,
  dispatched : @i18n.Locale,
  detailed : String,
  generic_english : String,
  generic_chinese : String,
) -> String {
  if current == dispatched {
    detailed
  } else {
    console_copy(current, generic_english, generic_chinese)
  }
}

///|
fn selected_offline_order(
  state : @offline_commerce.OfflineCommerceState,
  order_id : String,
) -> @offline.CommercialOrder? {
  for order in state.orders {
    if order.order_id == order_id {
      return Some(order)
    }
  }
  None
}

///|
fn selected_offline_artifact(
  state : @offline_commerce.OfflineCommerceState,
  artifact_id : String,
) -> @offline_commerce.OfflineArtifactSummary? {
  for artifact in state.artifacts {
    if artifact.artifact_id == artifact_id {
      return Some(artifact)
    }
  }
  None
}

///|
fn offline_action_command(
  model : AppModel,
  path : String,
  body : String,
  english_success : String,
  chinese_success : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try request("POST", model.endpoint, path, model.credential, body~) catch {
      error =>
        ActionFailed(
          model.console.locale,
          console_copy(
            model.console.locale,
            "Offline commercial action failed: \{Repr(error)}",
            "线下商务操作失败：\{Repr(error)}",
          ),
        )
    } noraise {
      _ =>
        ActionComplete(
          model.console.locale,
          console_copy(model.console.locale, english_success, chinese_success),
        )
    }
  })
}

///|
fn replace_contract_packet(
  packets : Array[@contractdoc.ContractPacket],
  updated : @contractdoc.ContractPacket,
) -> Array[@contractdoc.ContractPacket] {
  let mut found = false
  let next = packets.map(packet => {
    if packet.packet_id == updated.packet_id {
      found = true
      updated
    } else {
      packet
    }
  })
  if !found {
    next.push(updated)
  }
  next
}

///|
fn operator_contract_command(
  model : AppModel,
  packet_id : String,
  revision : Int64,
  changes : Array[@contractdoc.ContractFieldValue],
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try {
      let response = request(
        "PUT",
        model.endpoint,
        "/v1/contract-documents/operator/packets/\{packet_id}:information",
        model.credential,
        body=ContractInformationUpdate::{ expected_revision: revision, changes }
          .to_json()
          .stringify(),
      )
      let updated : @contractdoc.ContractPacket = @json.from_json(
        @json.parse(response),
      )
      ContractPacketUpdated(updated)
    } catch {
      error =>
        if "\{Repr(error)}".contains("HTTP 409") {
          ContractConflict(model.console.locale)
        } else {
          ContractActionFailed(
            model.console.locale,
            console_copy(
              model.console.locale,
              "Contract information update failed.",
              "合同资料更新失败。",
            ),
          )
        }
    } noraise {
      value => value
    }
  })
}

///|
fn operator_contract_lifecycle_command(
  model : AppModel,
  action : @contract_documents.ContractDocumentConfirmation,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try {
      let request_spec = match action {
        RegisterExecution(packet_id, revision, evidence_sha256, signed_on) =>
          {
            path: "/v1/contract-documents/operator/packets/\{packet_id}:execute",
            body: ContractExecutionRegistration::{
              expected_revision: revision,
              evidence_sha256,
              signed_on,
            }
            .to_json()
            .stringify(),
            english_success: "Contract execution registered; the packet is now effective.",
            chinese_success: "合同签署已登记，数据包现已生效。",
          }
        ClosePacket(packet_id, revision, kind, reason) =>
          {
            path: "/v1/contract-documents/operator/packets/\{packet_id}:close",
            body: ContractClosureIntent::{
              expected_revision: revision,
              kind,
              reason,
            }
            .to_json()
            .stringify(),
            english_success: "Contract packet closed.",
            chinese_success: "合同数据包已关闭。",
          }
        SupersedePacket(packet_id, revision, successor_ref, reason) =>
          {
            path: "/v1/contract-documents/operator/packets/\{packet_id}:supersede",
            body: ContractSupersessionIntent::{
              expected_revision: revision,
              successor_ref,
              reason,
            }
            .to_json()
            .stringify(),
            english_success: "Contract packet superseded.",
            chinese_success: "合同数据包已被取代。",
          }
        RequestRenewal(packet_id) =>
          {
            path: "/v1/contract-documents/operator/packets/\{packet_id}:renew",
            body: ContractRenewalIntent::{
              packet_id: random_identifier("contract-renewal"),
              idempotency_key: random_identifier("contract-renewal-idempotency"),
            }
            .to_json()
            .stringify(),
            english_success: "Contract renewal draft created.",
            chinese_success: "合同续约草稿已创建。",
          }
        _ => fail("unsupported contract lifecycle action")
      }
      let response = request(
        "POST",
        model.endpoint,
        request_spec.path,
        model.credential,
        body=request_spec.body,
      )
      // An over-threshold execute/close is answered 202 with the approval
      // record instead of the transitioned packet.
      let document = @json.parse(response)
      match document {
        Object(fields) if fields.contains("approval_id") =>
          ContractApprovalRequested(model.console.locale)
        _ => {
          let updated : @contractdoc.ContractPacket = @json.from_json(document)
          ContractLifecycleComplete(
            model.console.locale,
            updated,
            console_copy(
              model.console.locale,
              request_spec.english_success,
              request_spec.chinese_success,
            ),
          )
        }
      }
    } catch {
      error =>
        if "\{Repr(error)}".contains("HTTP 409") {
          ContractConflict(model.console.locale)
        } else {
          ContractActionFailed(
            model.console.locale,
            console_copy(
              model.console.locale,
              "Contract lifecycle action failed.",
              "合同生命周期操作失败。",
            ),
          )
        }
    } noraise {
      value => value
    }
  })
}

///|
#warnings("-unused_value")
fn operator_contract_approval_command(
  model : AppModel,
  approval_id : String,
  approve : Bool,
  reason : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try {
      let (path, body) = if approve {
        ("/v1/contract-documents/operator/approvals/\{approval_id}:approve", "")
      } else {
        (
          "/v1/contract-documents/operator/approvals/\{approval_id}:reject",
          ({ "reason": reason } : Json).stringify(),
        )
      }
      let _ = request("POST", model.endpoint, path, model.credential, body~)
      ContractApprovalDecided(
        model.console.locale,
        console_copy(
          model.console.locale,
          if approve {
            "Approval granted; the transition was applied."
          } else {
            "Approval request rejected."
          },
          if approve {
            "已批准；过渡操作已执行。"
          } else {
            "审批请求已拒绝。"
          },
        ),
      )
    } catch {
      error =>
        if "\{Repr(error)}".contains("HTTP 409") {
          ContractConflict(model.console.locale)
        } else {
          ContractActionFailed(
            model.console.locale,
            console_copy(
              model.console.locale,
              "Contract approval decision failed.",
              "合同审批决定失败。",
            ),
          )
        }
    } noraise {
      value => value
    }
  })
}

///|
fn contract_governance_export_command(
  model : AppModel,
  tenant_ref : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try {
      let response = request(
        "POST",
        model.endpoint,
        "/v1/contract-governance/operator/export",
        model.credential,
        body=ContractGovernanceTenantRequest::{ tenant_ref, }
          .to_json()
          .stringify(),
      )
      // Parse before download so a transport/proxy error can never be saved as
      // a misleading audit report.
      ignore(@json.parse(response))
      download_json_file(
        "lunanexa-contract-governance-\{tenant_ref}.json",
        response,
      )
      ContractApprovalDecided(
        model.console.locale,
        console_copy(
          model.console.locale,
          "Contract governance report downloaded.",
          "合同治理报表已下载。",
        ),
      )
    } catch {
      _ =>
        ContractActionFailed(
          model.console.locale,
          console_copy(
            model.console.locale,
            "Contract governance export failed.",
            "合同治理报表导出失败。",
          ),
        )
    } noraise {
      value => value
    }
  })
}

///|
fn demo_contract_packet(
  model : AppModel,
  packet_id : String,
) -> @contractdoc.ContractPacket raise {
  guard model.console.contract_documents.packets.search_by(packet => {
      packet.packet_id == packet_id
    })
    is Some(index) else {
    fail("contract packet unavailable")
  }
  model.console.contract_documents.packets[index]
}

///|
/// Demo mode has no backend; the operator lifecycle actions replay the same
/// deterministic transition against the in-memory demo packet instead of
/// sending HTTP. The shared lifecycle guards still apply, so a packet in the
/// wrong state produces the same rejection the controller would return.
fn demo_contract_lifecycle_action(
  model : AppModel,
  action : @contract_documents.ContractDocumentConfirmation,
) -> (AppModel, @rabbita.Cmd) {
  try {
    let now = current_unix_ms()
    let (updated, english_success, chinese_success) = match action {
      RegisterExecution(packet_id, revision, evidence_sha256, signed_on) => {
        let packet = demo_contract_packet(model, packet_id)
        (
          packet.register_execution(
            revision,
            {
              evidence_sha256,
              signed_on,
              registered_by: "operator",
              registered_unix_ms: now,
            },
            now,
          ),
          "Demo registered the contract execution locally; no request was sent.",
          "演示已在本地登记合同签署生效；未发送请求。",
        )
      }
      ClosePacket(packet_id, revision, kind, reason) => {
        let packet = demo_contract_packet(model, packet_id)
        // The demo has no sibling packets to settle against; the operator's
        // confirmation dialog stands in for the store-level settlement check.
        (
          packet.close_packet(
            revision,
            { kind, reason, closed_by: "operator", closed_unix_ms: now },
            true,
            now,
          ),
          "Demo closed the contract packet locally; no request was sent.",
          "演示已在本地关闭合同数据包；未发送请求。",
        )
      }
      SupersedePacket(packet_id, revision, successor_ref, reason) => {
        let packet = demo_contract_packet(model, packet_id)
        (
          packet.supersede_packet(
            revision,
            {
              successor_ref,
              reason,
              superseded_by: "operator",
              superseded_unix_ms: now,
            },
            now,
          ),
          "Demo superseded the contract packet locally; no request was sent.",
          "演示已在本地取代合同数据包；未发送请求。",
        )
      }
      RequestRenewal(packet_id) => {
        let packet = demo_contract_packet(model, packet_id)
        let manifest = match model.console.contract_documents.manifest {
          Some(value) => value
          None => fail("contract manifest unavailable")
        }
        (
          packet.renewal_draft(
            manifest,
            random_identifier("contract-renewal"),
            random_identifier("contract-renewal-idempotency"),
            now,
          ),
          "Demo created the contract renewal draft locally; no request was sent.",
          "演示已在本地创建合同续约草稿；未发送请求。",
        )
      }
      _ => fail("unsupported contract lifecycle action")
    }
    (
      {
        ..model,
        console: {
          ..model.console,
          contract_documents: {
            ..model.console.contract_documents,
            packets: replace_contract_packet(
              model.console.contract_documents.packets,
              updated,
            ),
            selected_packet_id: Some(updated.packet_id),
            draft_values: updated.values.copy(),
            loading: false,
            error_message: None,
            success_message: Some(
              console_copy(
                model.console.locale,
                english_success,
                chinese_success,
              ),
            ),
          },
        },
      },
      @rabbita.none,
    )
  } catch {
    error =>
      (
        {
          ..model,
          console: {
            ..model.console,
            contract_documents: {
              ..model.console.contract_documents,
              loading: false,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Demo contract lifecycle action was rejected: \{Repr(error)}",
                  "演示合同生命周期操作被拒绝：\{Repr(error)}",
                ),
              ),
            },
          },
        },
        @rabbita.none,
      )
  }
}

///|
fn operator_contract_preview_command(
  model : AppModel,
  generation : Int64,
  packet_id : String,
  revision : Int64,
  form : @contractdoc.ContractFormKind,
  changes : Array[@contractdoc.ContractFieldValue],
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try {
      let response = request(
        "POST",
        model.endpoint,
        "/v1/contract-documents/operator/packets/\{packet_id}:preview",
        model.credential,
        body=ContractPreviewIntent::{
            expected_revision: revision,
            form,
            changes,
          }
          .to_json()
          .stringify(),
      )
      ContractPreviewLoaded(generation, @json.from_json(@json.parse(response)))
    } catch {
      _ =>
        ContractPreviewFailed(
          generation,
          model.console.locale,
          console_copy(
            model.console.locale,
            "MoonLeaf contract preview failed.",
            "MoonLeaf 合同预览失败。",
          ),
        )
    }
  })
}

///|
fn demo_operator_contract_preview_command(
  model : AppModel,
  generation : Int64,
  packet_id : String,
  form : @contractdoc.ContractFormKind,
  changes : Array[@contractdoc.ContractFieldValue],
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try {
      let text : String = demo_contract_preview_promise().wait().cast()
      let template : @contractdoc.ContractPreviewTemplate = @json.from_json(
        @json.parse(text),
      )
      guard model.console.contract_documents.manifest is Some(manifest) else {
        fail("contract manifest unavailable")
      }
      guard model.console.contract_documents.packets.search_by(packet => {
          packet.packet_id == packet_id
        })
        is Some(index) else {
        fail("contract packet unavailable")
      }
      ContractPreviewLoaded(
        generation,
        @contractdoc.materialize_preview_template(
          template,
          manifest,
          model.console.contract_documents.packets[index],
          ManagerOperator,
          form,
          changes,
        ),
      )
    } catch {
      _ =>
        ContractPreviewFailed(
          generation,
          model.console.locale,
          console_copy(
            model.console.locale,
            "MoonLeaf demo preview failed.",
            "MoonLeaf 演示预览失败。",
          ),
        )
    }
  })
}

///|
fn schedule_contract_preview(
  model : AppModel,
  documents : @contract_documents.ContractDocumentsState,
  delay_ms : Int,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  guard documents.preview_request() is Some(request) else {
    return (
      { ..model, console: { ..model.console, contract_documents: documents } },
      @rabbita.none,
    )
  }
  let generation = model.contract_preview_generation + 1L
  let pending = documents.update(request)
  let next = {
    ..model,
    contract_preview_generation: generation,
    console: { ..model.console, contract_documents: pending },
  }
  let command = @rabbita.perform(message => emit(message), async fn() noraise {
    try contract_preview_delay_promise(delay_ms).wait() catch {
      _ => ContractPreviewDue(generation, request)
    } noraise {
      _ => ContractPreviewDue(generation, request)
    }
  })
  (next, command)
}

///|
fn generation_template(
  state : @offline_commerce.OfflineCommerceState,
  kind : @offline.DocumentArtifactKind,
) -> @offline.DocumentTemplate? {
  let wanted = match kind {
    QuoteScheduleXlsx => @offline.DocumentTemplateKind::QuoteScheduleTemplate
    EditableContractDocx | PrintReadyContractPdf => ContractTemplate
    _ => return None
  }
  for template in state.templates {
    if template.kind == wanted && template.superseded_unix_ms is None {
      return Some(template)
    }
  }
  None
}

///|
fn load_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try
      load_console(
        model.endpoint,
        model.credential,
        model.audit_credential,
        model.commercial_organization,
        model.console.route,
        model.console.locale,
      )
    catch {
      _ =>
        LoadFailed(
          model.console.locale,
          console_copy(
            model.console.locale,
            "The controller could not be reached or rejected this credential.",
            "无法连接控制器，或控制器拒绝了此凭据。",
          ),
        )
    } noraise {
      state => Loaded(state)
    }
  })
}

///|
fn gateway_session_bootstrap_command(
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(message => emit(message), async fn() noraise {
    try {
      let text : String = gateway_session_promise().wait().cast()
      if text == "" {
        GatewaySessionUnavailable
      } else {
        let session : GatewayBrowserSession = @json.from_json(@json.parse(text))
        if !session.session_token.has_prefix("lnxs_") ||
          session.csrf_token.trim() == "" ||
          session.expires_unix_ms <= current_unix_ms() {
          GatewaySessionUnavailable
        } else {
          GatewaySessionLoaded(session)
        }
      }
    } catch {
      _ => GatewaySessionUnavailable
    }
  })
}

///|
fn model_imports_active(imports : Array[@ui.ModelImportRow]) -> Bool {
  imports.any(value => value.state == Queued || value.state == Downloading)
}

///|
fn model_import_poll_delay_command(
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(message => emit(message), async fn() noraise {
    try model_import_poll_promise().wait() catch {
      _ => ModelImportPollDue(generation)
    } noraise {
      _ => ModelImportPollDue(generation)
    }
  })
}

///|
fn model_import_poll_request_command(
  model : AppModel,
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try {
      let imports : Array[@ui.ModelImportRow] = @json.from_json(
        @json.parse(
          request(
            "GET",
            model.endpoint,
            "/v1/model-sources/modelscope/imports",
            model.credential,
          ),
        ),
      )
      ModelImportsPolled(generation, imports)
    } catch {
      _ => ModelImportPollFailed(generation, model.console.locale)
    }
  })
}

///|
fn update_live(
  model : AppModel,
  message : AppMessage,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  match message {
    GatewaySessionLoaded(session) => {
      let next = {
        ..model,
        credential: session.session_token,
        audit_credential: session.session_token,
        csrf_token: session.csrf_token,
        console: {
          ..model.console,
          loading: true,
          error_message: None,
          success_message: None,
        },
      }
      (next, load_command(next, emit))
    }
    GatewaySessionUnavailable => (model, @rabbita.none)
    AccountSessionChanged(value) =>
      (
        {
          ..model,
          credential: value,
          audit_credential: value,
          csrf_token: "",
          model_import_poll_generation: model.model_import_poll_generation + 1L,
          console: { ..model.console, operator_authenticated: false },
        },
        @rabbita.none,
      )
    CredentialChanged(value) =>
      (
        {
          ..model,
          credential: value,
          csrf_token: "",
          model_import_poll_generation: model.model_import_poll_generation + 1L,
          console: { ..model.console, operator_authenticated: false },
        },
        @rabbita.none,
      )
    AuditCredentialChanged(value) =>
      ({ ..model, audit_credential: value }, @rabbita.none)
    InferenceCredentialChanged(value) =>
      ({ ..model, inference_credential: value }, @rabbita.none)
    InferenceSubjectChanged(value) =>
      ({ ..model, inference_subject_ref: value }, @rabbita.none)
    CommercialOrganizationChanged(value) =>
      ({ ..model, commercial_organization: value }, @rabbita.none)
    Console(AccountInviteIdChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            account_invite: {
              ..model.console.account_invite,
              account_id: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccountInviteSubjectRefChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            account_invite: {
              ..model.console.account_invite,
              subject_ref: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccountInviteIssuerChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            account_invite: {
              ..model.console.account_invite,
              identity_issuer: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccountInviteProviderSubjectChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            account_invite: {
              ..model.console.account_invite,
              identity_subject: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccountInviteDisplayNameChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            account_invite: {
              ..model.console.account_invite,
              display_name: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccountInviteEmailChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            account_invite: { ..model.console.account_invite, email: value },
          },
        },
        @rabbita.none,
      )
    Console(AccountInviteReceiptChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            account_invite: {
              ..model.console.account_invite,
              identity_receipt: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccountInviteRoleToggled(role)) => {
      let roles = @ui.account_roles_after_toggle(
        model.console.account_invite.roles,
        role,
      )
      (
        {
          ..model,
          console: {
            ..model.console,
            account_invite: { ..model.console.account_invite, roles, },
          },
        },
        @rabbita.none,
      )
    }
    Console(SubmitAccountInvite) => {
      let draft = model.console.account_invite
      let body = AccountCreateIntent::{
          account_id: draft.account_id.trim().to_owned(),
          subject_ref: draft.subject_ref.trim().to_owned(),
          identity_issuer: draft.identity_issuer.trim().to_owned(),
          identity_subject: draft.identity_subject,
          display_name: draft.display_name.trim().to_owned(),
          email: draft.email.trim().to_owned(),
          identity_receipt: draft.identity_receipt.trim().to_owned(),
          roles: draft.roles,
          state: Invited,
        }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/accounts",
              model.credential,
              body~,
            ),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The external identity invitation was rejected.",
                "外部身份邀请被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Account \{draft.account_id} was invited.",
                "账户 \{draft.account_id} 已邀请。",
              ),
            )
        }
      })
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: true,
            error_message: None,
            success_message: None,
          },
        },
        cmd,
      )
    }
    Console(BeginActivateAccount(account_id)) =>
      (
        {
          ..model,
          console: prepare_account_confirmation(
            model.console,
            account_id,
            ActivateAccount(account_id),
          ),
        },
        @rabbita.none,
      )
    Console(BeginSuspendAccount(account_id)) =>
      (
        {
          ..model,
          console: prepare_account_confirmation(
            model.console,
            account_id,
            SuspendAccount(account_id),
          ),
        },
        @rabbita.none,
      )
    Console(BeginRevokeAccount(account_id)) =>
      (
        {
          ..model,
          console: prepare_account_confirmation(
            model.console,
            account_id,
            RevokeAccount(account_id),
          ),
        },
        @rabbita.none,
      )
    Console(BeginSetAccountRoles(account_id, roles)) =>
      (
        {
          ..model,
          console: prepare_account_confirmation(
            model.console,
            account_id,
            SetAccountRoles(account_id, roles),
          ),
        },
        @rabbita.none,
      )
    Logout => {
      let logout_command = if model.credential.has_prefix("lnxs_") {
        @rabbita.perform(_ => emit(SessionLogoutFinished), async fn() noraise {
          ignore(
            request("POST", model.endpoint, "/v1/auth/logout", model.credential),
          ) catch {
            _ => ()
          }
          ignore(gateway_logout_promise(model.csrf_token).wait()) catch {
            _ => ()
          }
        })
      } else {
        @rabbita.none
      }
      (
        {
          ..model,
          credential: "",
          audit_credential: "",
          csrf_token: "",
          inference_credential: "",
          inference_subject_ref: "",
          commercial_organization: "",
          model_import_poll_generation: model.model_import_poll_generation + 1L,
          console: {
            ..@ui.default_state(),
            locale: model.console.locale,
            route: Overview,
            offline_commerce: {
              ..@ui.default_state().offline_commerce,
              locale: model.console.locale,
            },
            contract_documents: {
              ..@ui.default_state().contract_documents,
              locale: model.console.locale,
            },
          },
        },
        logout_command,
      )
    }
    SessionLogoutFinished => (model, @rabbita.none)
    Console(LocaleChanged(locale)) => {
      apply_console_locale(locale)
      (switch_app_locale(model, locale), @rabbita.none)
    }
    ContractPreviewDue(generation, request) =>
      if generation != model.contract_preview_generation {
        (model, @rabbita.none)
      } else {
        match request {
          RequestPreview(packet_id, revision, form, changes) =>
            (
              model,
              if model.demo_mode {
                demo_operator_contract_preview_command(
                  model, generation, packet_id, form, changes, emit,
                )
              } else {
                operator_contract_preview_command(
                  model, generation, packet_id, revision, form, changes, emit,
                )
              },
            )
          _ => (model, @rabbita.none)
        }
      }
    ModelImportPollDue(generation) =>
      if generation != model.model_import_poll_generation ||
        !model.console.operator_authenticated ||
        !model_imports_active(model.console.model_imports) {
        (model, @rabbita.none)
      } else {
        (model, model_import_poll_request_command(model, generation, emit))
      }
    Connect => {
      if !commercial_organization_is_valid(model.commercial_organization) {
        return (
          {
            ..model,
            console: {
              ..model.console,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "The optional commercial organization must be an opaque identifier of at most 160 safe characters.",
                  "可选商业组织必须是最多 160 个安全字符的不透明标识符。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let next = {
        ..model,
        console: { ..model.console, loading: true, error_message: None },
      }
      (next, load_command(next, emit))
    }
    Outcome(Loaded(state)) => {
      let generation = model.model_import_poll_generation + 1L
      let next = {
        ..model,
        console: merge_loaded_console(model.console, state),
        model_import_poll_generation: generation,
      }
      (
        next,
        if model_imports_active(next.console.model_imports) {
          model_import_poll_delay_command(generation, emit)
        } else {
          @rabbita.none
        },
      )
    }
    Outcome(LoadFailed(dispatched_locale, message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: false,
            operator_authenticated: false,
            error_message: Some(
              locale_fenced_notice(
                model.console.locale,
                dispatched_locale,
                message,
                "Controller refresh failed.",
                "控制器刷新失败。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Outcome(ActionComplete(dispatched_locale, message)) => {
      let next = {
        ..model,
        next_directive_generation: model.next_directive_generation + 1L,
        console: {
          ..model.console,
          confirmation: None,
          loading: true,
          success_message: Some(
            locale_fenced_notice(
              model.console.locale,
              dispatched_locale,
              message,
              "Operation completed.",
              "操作已完成。",
            ),
          ),
        },
      }
      (next, load_command(next, emit))
    }
    Outcome(ModelSourceSearchLoaded(dispatched_locale, page)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_source_results: page.models,
            model_source_total: page.total_count,
            loading: false,
            error_message: None,
            success_message: Some(
              locale_fenced_notice(
                model.console.locale,
                dispatched_locale,
                "Found \{page.total_count} matching ModelScope models.",
                "ModelScope search completed.",
                "魔搭搜索已完成。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Outcome(ModelImportsLoaded(dispatched_locale, imports, notice)) => {
      let generation = model.model_import_poll_generation + 1L
      let next = {
        ..model,
        model_import_poll_generation: generation,
        console: {
          ..model.console,
          model_imports: imports,
          loading: false,
          error_message: None,
          success_message: notice.map(message => {
            locale_fenced_notice(
              model.console.locale,
              dispatched_locale,
              message,
              "Model import status updated.",
              "模型导入状态已更新。",
            )
          }),
        },
      }
      (
        next,
        if model_imports_active(imports) {
          model_import_poll_delay_command(generation, emit)
        } else {
          @rabbita.none
        },
      )
    }
    Outcome(ModelImportsPolled(generation, imports)) =>
      if generation != model.model_import_poll_generation ||
        !model.console.operator_authenticated {
        (model, @rabbita.none)
      } else {
        let next = {
          ..model,
          console: {
            ..model.console,
            model_imports: imports,
            error_message: None,
            success_message: model.console.success_message,
          },
        }
        (
          next,
          if model_imports_active(imports) {
            model_import_poll_delay_command(generation, emit)
          } else {
            @rabbita.none
          },
        )
      }
    Outcome(ModelImportPollFailed(generation, dispatched_locale)) =>
      if generation != model.model_import_poll_generation ||
        !model.console.operator_authenticated {
        (model, @rabbita.none)
      } else {
        (
          {
            ..model,
            console: {
              ..model.console,
              error_message: Some(
                locale_fenced_notice(
                  model.console.locale,
                  dispatched_locale,
                  "Automatic download status refresh failed; retrying.",
                  "Automatic model import refresh failed.",
                  "模型下载状态自动刷新失败，正在重试。",
                ),
              ),
            },
          },
          if model_imports_active(model.console.model_imports) {
            model_import_poll_delay_command(generation, emit)
          } else {
            @rabbita.none
          },
        )
      }
    Outcome(StreamComplete(events)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            route: Requests,
            stream_events: events,
            loading: false,
            error_message: None,
            success_message: Some(
              console_copy(
                model.console.locale,
                "Streaming invocation completed.",
                "流式调用已完成。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Outcome(ActionFailed(dispatched_locale, message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: false,
            error_message: Some(
              locale_fenced_notice(
                model.console.locale,
                dispatched_locale,
                message,
                "Operation failed.",
                "操作失败。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Outcome(ContractPacketUpdated(packet)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            contract_documents: {
              ..model.console.contract_documents,
              packets: replace_contract_packet(
                model.console.contract_documents.packets,
                packet,
              ),
              selected_packet_id: Some(packet.packet_id),
              draft_values: packet.values.copy(),
              loading: false,
              error_message: None,
              success_message: Some(
                console_copy(
                  model.console.locale,
                  "Manager contract information saved.",
                  "经理/运营方合同资料已保存。",
                ),
              ),
            },
          },
        },
        @rabbita.none,
      )
    Outcome(ContractLifecycleComplete(dispatched_locale, packet, message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            contract_documents: {
              ..model.console.contract_documents,
              packets: replace_contract_packet(
                model.console.contract_documents.packets,
                packet,
              ),
              selected_packet_id: Some(packet.packet_id),
              draft_values: packet.values.copy(),
              loading: false,
              error_message: None,
              success_message: Some(
                locale_fenced_notice(
                  model.console.locale,
                  dispatched_locale,
                  message,
                  "Contract lifecycle action completed.",
                  "合同生命周期操作已完成。",
                ),
              ),
            },
          },
        },
        @rabbita.none,
      )
    Outcome(ContractApprovalRequested(dispatched_locale)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            contract_documents: {
              ..model.console.contract_documents,
              loading: false,
              error_message: None,
              success_message: Some(
                locale_fenced_notice(
                  model.console.locale,
                  dispatched_locale,
                  "Approval requested, pending a second operator.",
                  "approval requested, pending a second operator",
                  "已提交审批，等待第二位运营商审批。",
                ),
              ),
            },
          },
        },
        load_command(model, emit),
      )
    Outcome(ContractApprovalDecided(dispatched_locale, message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            contract_documents: {
              ..model.console.contract_documents,
              loading: false,
              error_message: None,
              success_message: Some(
                locale_fenced_notice(
                  model.console.locale,
                  dispatched_locale,
                  message,
                  "Contract approval decision recorded.",
                  "合同审批决定已记录。",
                ),
              ),
            },
          },
        },
        load_command(model, emit),
      )
    Outcome(ContractActionFailed(dispatched_locale, message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            contract_documents: {
              ..model.console.contract_documents,
              loading: false,
              error_message: Some(
                locale_fenced_notice(
                  model.console.locale,
                  dispatched_locale,
                  message,
                  "Contract lifecycle action failed.",
                  "合同生命周期操作失败。",
                ),
              ),
            },
          },
        },
        @rabbita.none,
      )
    Outcome(ContractConflict(dispatched_locale)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            contract_documents: {
              ..model.console.contract_documents,
              loading: true,
              success_message: None,
              error_message: Some(
                locale_fenced_notice(
                  model.console.locale,
                  dispatched_locale,
                  "Another operator updated this contract. The latest revision is being loaded.",
                  "Another operator updated this contract. The latest revision is being loaded.",
                  "其他运营人员已更新此合同，正在加载最新版本。",
                ),
              ),
            },
          },
        },
        load_command(model, emit),
      )
    Outcome(ContractPreviewLoaded(generation, preview)) =>
      if generation != model.contract_preview_generation {
        (model, @rabbita.none)
      } else {
        (
          {
            ..model,
            console: {
              ..model.console,
              contract_documents: model.console.contract_documents.update(
                PreviewLoaded(preview),
              ),
            },
          },
          @rabbita.none,
        )
      }
    Outcome(ContractPreviewFailed(generation, dispatched_locale, message)) =>
      if generation != model.contract_preview_generation {
        (model, @rabbita.none)
      } else {
        (
          {
            ..model,
            console: {
              ..model.console,
              contract_documents: model.console.contract_documents.update(
                PreviewFailed(
                  locale_fenced_notice(
                    model.console.locale,
                    dispatched_locale,
                    message,
                    "MoonLeaf preview failed.",
                    "MoonLeaf 预览失败。",
                  ),
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
    Console(Navigate(route)) => {
      scroll_console_top()
      let next = {
        ..model,
        console: {
          ..model.console,
          route,
          confirmation: None,
          error_message: None,
          success_message: None,
        },
      }
      match route {
        ContractDocuments =>
          schedule_contract_preview(
            next,
            next.console.contract_documents,
            0,
            emit,
          )
        _ => (next, @rabbita.none)
      }
    }
    Console(BeginDrain(node_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(DrainNode(node_id), node_id),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginCordon(node_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(CordonNode(node_id), node_id),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginRollback(alias_name)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(RollbackAlias(alias_name), alias_name),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginStopDeployment(assignment_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                StopDeployment(assignment_id),
                assignment_id,
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginRollbackServiceDeployment(deployment_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                RollbackServiceDeployment(deployment_id),
                deployment_id,
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginDeleteServiceDeployment(deployment_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                DeleteServiceDeployment(deployment_id),
                deployment_id,
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(PromoteServiceDeployment(deployment_id)) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            service_deployment_action_path(deployment_id, "promote"),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The model service promotion was rejected.",
                "模型服务提升被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model service \{deployment_id} was promoted.",
                "模型服务 \{deployment_id} 已提升。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ActivateUser(user_id)) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            workspace_lifecycle_path(ActivateWorkspaceUser(user_id)),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The user could not be activated.",
                "无法激活该用户。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "User \{user_id} was activated.",
                "用户 \{user_id} 已激活。",
              ),
            )
        }
      })
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: true,
            error_message: None,
            success_message: None,
          },
        },
        cmd,
      )
    }
    Console(BeginSuspendUser(user_id)) =>
      (
        {
          ..model,
          console: prepare_user_confirmation(
            model.console,
            user_id,
            SuspendUser(user_id),
          ),
        },
        @rabbita.none,
      )
    Console(BeginRevokeUser(user_id)) =>
      (
        {
          ..model,
          console: prepare_user_confirmation(
            model.console,
            user_id,
            RevokeUser(user_id),
          ),
        },
        @rabbita.none,
      )
    Console(BeginRevokeAccessGrant(grant_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                RevokeAccessGrant(grant_id),
                model.console.access_grants
                .iter()
                .find_first(grant => grant.grant_id == grant_id)
                .map(grant => {
                  "\{grant.grant_id} · \{grant.user_id} · \{grant.scope}"
                })
                .unwrap_or(grant_id),
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(ActivateComputeLease(lease_id)) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            workspace_lifecycle_path(ActivateWorkspaceLease(lease_id)),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The workspace lease could not be activated.",
                "无法激活该工作区租约。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Workspace lease \{lease_id} was activated.",
                "工作区租约 \{lease_id} 已激活。",
              ),
            )
        }
      })
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: true,
            error_message: None,
            success_message: None,
          },
        },
        cmd,
      )
    }
    Console(BeginEndComputeLease(lease_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                EndComputeLease(lease_id),
                model.console.compute_leases
                .iter()
                .find_first(lease => lease.lease_id == lease_id)
                .map(lease => {
                  "\{lease.lease_id} · \{lease.user_id} · \{lease.workspace}"
                })
                .unwrap_or(lease_id),
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginTerminateExclusiveNodeLease(lease_id, generation)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                TerminateExclusiveNodeLease(lease_id, generation),
                model.console.exclusive_node_leases
                .iter()
                .find_first(lease => lease.lease_id == lease_id)
                .map(lease => {
                  "\{lease.lease_id} · \{lease.node_id} · \{lease.unix_username} · generation \{lease.generation}"
                })
                .unwrap_or(lease_id),
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(
      BeginRedriveNotificationDelivery(
        delivery_id,
        expected_attempt_count,
        expected_updated_unix_ms
      )
    ) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                RedriveNotificationDelivery(
                  delivery_id, expected_attempt_count, expected_updated_unix_ms,
                ),
                "\{delivery_id} · attempt \{expected_attempt_count} · generation \{expected_updated_unix_ms}",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(DismissConfirmation) =>
      (
        { ..model, console: { ..model.console, confirmation: None } },
        @rabbita.none,
      )
    Console(AcknowledgeAlert(notification_id, generation)) => {
      let body = { "expected_generation": generation.to_json() }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/notifications/operator/\{notification_id}:acknowledge",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The alert could not be acknowledged.",
                "无法确认该告警。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Alert acknowledged.",
                "告警已确认。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(AssignAlertToSelf(notification_id, generation)) => {
      let body = {
          "expected_generation": generation.to_json(),
          "assignee_ref": "platform-operator".to_json(),
        }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/notifications/operator/\{notification_id}:assign",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The alert could not be assigned.",
                "无法分配该告警。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Alert assigned to you.",
                "告警已分配给您。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(SilenceAlert(notification_id, generation)) => {
      let body = {
          "expected_generation": generation.to_json(),
          "silenced_until_unix_ms": (current_unix_ms() + 3600000L).to_json(),
        }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/notifications/operator/\{notification_id}:silence",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The alert could not be silenced.",
                "无法静默该告警。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Alert silenced for one hour.",
                "告警已静默一小时。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ResolveAlert(notification_id, generation)) => {
      let body = { "expected_generation": generation.to_json() }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/notifications/operator/\{notification_id}:resolve",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The alert could not be resolved.",
                "无法解决该告警。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Alert resolved.",
                "告警已解决。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(Refresh) => (model, load_command(model, emit))
    Console(ModelSourceQueryChanged(value)) =>
      (
        { ..model, console: { ..model.console, model_source_query: value } },
        @rabbita.none,
      )
    Console(SearchModelSource) => {
      let query = model.console.model_source_query.trim().to_owned()
      if query == "" {
        return (
          {
            ..model,
            console: {
              ..model.console,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Enter a ModelScope search term.",
                  "请输入魔搭搜索关键词。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let body = {
          "query": query.to_json(),
          "page_number": Json::number(1.0),
          "page_size": Json::number(12.0),
        }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          let page : @ui.ModelSourceCatalogPage = @json.from_json(
            @json.parse(
              request(
                "POST",
                model.endpoint,
                "/v1/model-sources/modelscope/search",
                model.credential,
                body~,
              ),
            ),
          )
          ModelSourceSearchLoaded(model.console.locale, page)
        } catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "ModelScope search is unavailable. Check the model-source adapter and its egress policy.",
                "魔搭搜索不可用。请检查模型源适配器及其出口网络策略。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(DownloadModelSource(model_id)) => {
      let body = { "model_id": model_id, "revision": "master" }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          let created : @ui.ModelImportRow = @json.from_json(
            @json.parse(
              request(
                "POST",
                model.endpoint,
                "/v1/model-sources/modelscope/imports",
                model.credential,
                body~,
              ),
            ),
          )
          let imports = model.console.model_imports.filter(value => {
            value.import_id != created.import_id
          })
          imports.push(created)
          ModelImportsLoaded(
            model.console.locale,
            imports,
            Some(
              console_copy(
                model.console.locale,
                "Model download queued. Progress survives controller restarts.",
                "模型下载已排队；控制器重启后进度状态仍会保留。",
              ),
            ),
          )
        } catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The model download could not be queued.",
                "无法将模型下载加入队列。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(CancelModelImport(import_id)) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/model-sources/modelscope/imports/\{import_id}/cancel",
              model.credential,
              body="{}",
            ),
          )
          let imports : Array[@ui.ModelImportRow] = @json.from_json(
            @json.parse(
              request(
                "GET",
                model.endpoint,
                "/v1/model-sources/modelscope/imports",
                model.credential,
              ),
            ),
          )
          ModelImportsLoaded(
            model.console.locale,
            imports,
            Some(
              console_copy(
                model.console.locale,
                "Cancellation requested.",
                "已请求取消。",
              ),
            ),
          )
        } catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The import could not be cancelled.",
                "无法取消导入任务。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(RetryModelImport(import_id)) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/model-sources/modelscope/imports/\{import_id}/retry",
              model.credential,
              body="{}",
            ),
          )
          let imports : Array[@ui.ModelImportRow] = @json.from_json(
            @json.parse(
              request(
                "GET",
                model.endpoint,
                "/v1/model-sources/modelscope/imports",
                model.credential,
              ),
            ),
          )
          ModelImportsLoaded(
            model.console.locale,
            imports,
            Some(
              console_copy(
                model.console.locale,
                "The import was requeued and will reuse verified partial files.",
                "导入任务已重新排队，并将复用已验证的部分文件。",
              ),
            ),
          )
        } catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The import could not be retried.",
                "无法重试导入任务。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(RefreshModelImports) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          let imports : Array[@ui.ModelImportRow] = @json.from_json(
            @json.parse(
              request(
                "GET",
                model.endpoint,
                "/v1/model-sources/modelscope/imports",
                model.credential,
              ),
            ),
          )
          ModelImportsLoaded(model.console.locale, imports, None)
        } catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Download status is unavailable.",
                "下载状态不可用。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(OperationChanged(value)) =>
      (
        { ..model, console: { ..model.console, operation_name: value } },
        @rabbita.none,
      )
    Console(OperationBodyChanged(value)) =>
      (
        { ..model, console: { ..model.console, operation_body: value } },
        @rabbita.none,
      )
    Console(QuickDeploymentIdChanged(value)) =>
      (
        { ..model, console: { ..model.console, quick_deployment_id: value } },
        @rabbita.none,
      )
    Console(QuickTemplateChanged(value)) =>
      (
        { ..model, console: { ..model.console, quick_template: value } },
        @rabbita.none,
      )
    Console(PortalNodeChanged(value)) =>
      (
        { ..model, console: { ..model.console, portal_node_id: value } },
        @rabbita.none,
      )
    Console(ApproveEnterpriseLease(request_id, generation)) => {
      let node_id = model.console.portal_node_id.trim().to_owned()
      if node_id == "" ||
        !@contracts.valid_identifier(node_id, maximum_length=128) {
        return (
          {
            ..model,
            console: {
              ..model.console,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Choose a valid enrolled node before approval.",
                  "批准前请选择一个有效的已纳管节点。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let body = @portal.LeaseReview::{
          request_id,
          expected_generation: generation,
          decision: Approve,
          node_id: Some(node_id),
          evidence_receipt: "console:approve:\{request_id}:\{generation}",
        }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/portal/operator/lease-reviews",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The enterprise lease request could not be approved.",
                "无法批准该企业租用申请。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Lease request \{request_id} reserved node \{node_id}.",
                "租用申请 \{request_id} 已预留节点 \{node_id}。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(RejectEnterpriseLease(request_id, generation)) => {
      let body = @portal.LeaseReview::{
          request_id,
          expected_generation: generation,
          decision: Reject,
          node_id: None,
          evidence_receipt: "console:reject:\{request_id}:\{generation}",
        }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/portal/operator/lease-reviews",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The enterprise lease request could not be rejected.",
                "无法拒绝该企业租用申请。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Lease request \{request_id} was rejected.",
                "租用申请 \{request_id} 已拒绝。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(SubmitQuickDeployment) => {
      guard quick_deployment_intent(model.console, current_unix_ms())
        is Some(intent) else {
        return (
          {
            ..model,
            console: {
              ..model.console,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Choose an approved template and a valid service name.",
                  "请选择已批准模板和有效服务名称。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let deployment_id = intent.deployment_id
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/service-deployments",
            model.credential,
            body=intent.to_json().stringify(),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Deployment preflight blocked or rejected this model service.",
                "部署预检阻止或拒绝了此模型服务。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model service \{deployment_id} entered reconciliation.",
                "模型服务 \{deployment_id} 已进入协调流程。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(SubmitOperation) => {
      let (verb, path, inference) = match model.console.operation_name {
        "issue-enrollment-token" => ("POST", "/v1/enrollment/tokens", false)
        "register-runtime" => ("POST", "/v1/runtimes", false)
        "register-model" => ("POST", "/v1/models", false)
        "register-template" => ("POST", "/v1/catalog/templates", false)
        "plan-deployment" => ("POST", "/v1/deployment-plans", false)
        "deploy-service" => ("POST", "/v1/service-deployments", false)
        "record-license" => ("POST", "/v1/licenses", false)
        "record-verification" => ("POST", "/v1/verifications", false)
        "record-evaluation" => ("POST", "/v1/evaluations", false)
        "approve-model" => ("POST", "/v1/models/approve", false)
        "promote-alias" => ("POST", "/v1/aliases/promote", false)
        "set-quota" => ("PUT", "/v1/quotas", false)
        "create-organization" => ("POST", "/v1/commercial/organizations", false)
        "create-cost-center" => ("POST", "/v1/commercial/cost-centers", false)
        "create-project" => ("POST", "/v1/commercial/projects", false)
        "record-commercial-usage" => ("POST", "/v1/commercial/usage", false)
        "rate-commercial-usage" => ("POST", "/v1/commercial/usage:rate", false)
        "create-commercial-budget" => ("POST", "/v1/commercial/budgets", false)
        "create-commercial-quota" => ("POST", "/v1/commercial/quotas", false)
        "register-agreement-template" =>
          ("POST", "/v1/commercial/agreement-templates", false)
        "create-agreement" => ("POST", "/v1/commercial/agreements", false)
        "create-enterprise-membership" =>
          ("POST", "/v1/portal/operator/memberships", false)
        "publish-portal-agreement" =>
          ("POST", "/v1/portal/operator/agreements", false)
        "register-external-record" =>
          ("POST", "/v1/commercial/external-records", false)
        "decide-backpressure" =>
          ("POST", "/v1/technical/backpressure:decide", false)
        "validate-transfer-grant" =>
          ("POST", "/v1/technical/transfer-grants:validate", false)
        "invite-user" => ("POST", "/v1/workspace/users", false)
        "grant-access" => ("POST", "/v1/workspace/access-grants", false)
        "create-compute-lease" => ("POST", "/v1/workspace/leases", false)
        "publish-assignment" => ("PUT", "/v1/assignments", false)
        "invoke-workload" => ("POST", "/v1/workloads", true)
        "record-benchmark" => ("POST", "/v1/benchmarks", false)
        _ => ("", "", false)
      }
      let inference_subject = model.inference_subject_ref.trim().to_owned()
      if path == "" ||
        (inference && model.inference_credential == "") ||
        (inference && !optional_subject_is_valid(inference_subject)) {
        let message = if inference &&
          !optional_subject_is_valid(inference_subject) {
          console_copy(
            model.console.locale,
            "The optional opaque subject reference must use only letters, digits, '.', '-', '_', or ':', up to 256 characters. Leave it empty when verified mTLS derives identity; the header is accepted only for loopback acceptance.",
            "可选的不透明主体引用只能包含字母、数字、句点、连字符、下划线或冒号，且不超过 256 个字符。经验证的 mTLS 可推导身份时请留空；仅回环验收客户端可直接发送此标头。",
          )
        } else {
          console_copy(
            model.console.locale,
            "Select a supported operation and provide the inference token when invoking.",
            "请选择受支持的操作，并在调用时提供推理令牌。",
          )
        }
        return (
          {
            ..model,
            console: { ..model.console, error_message: Some(message) },
          },
          @rabbita.none,
        )
      }
      let token = if inference {
        model.inference_credential
      } else {
        model.credential
      }
      let wants_stream = if model.console.operation_name == "invoke-workload" {
        try
          @contracts.decode_workload(model.console.operation_body).stream
        catch {
          _ => false
        } noraise {
          value => value
        }
      } else {
        false
      }
      let cmd = if wants_stream {
        @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
          try
            stream_request(
              model.endpoint,
              token,
              inference_subject,
              model.console.operation_body,
            )
          catch {
            _ =>
              ActionFailed(
                model.console.locale,
                console_copy(
                  model.console.locale,
                  "The streaming invocation was rejected.",
                  "流式调用被拒绝。",
                ),
              )
          } noraise {
            events => StreamComplete(events)
          }
        })
      } else {
        @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
          try
            request(
              verb,
              model.endpoint,
              path,
              token,
              subject_ref=if inference { inference_subject } else { "" },
              body=model.console.operation_body,
            )
          catch {
            _ =>
              ActionFailed(
                model.console.locale,
                console_copy(
                  model.console.locale,
                  "The typed operation was rejected.",
                  "类型化操作被拒绝。",
                ),
              )
          } noraise {
            _ =>
              ActionComplete(
                model.console.locale,
                console_copy(
                  model.console.locale,
                  "Operation \{model.console.operation_name} completed.",
                  "操作 \{model.console.operation_name} 已完成。",
                ),
              )
          }
        })
      }
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(DrainNode(node_id))) => {
      let generation = current_unix_ms()
      let directive : @contracts.NodeDirective = {
        node_id,
        desired_state: Draining,
        generation,
        issued_unix_ms: generation,
        receipt: "console:drain:\{node_id}:\{generation}",
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "PUT",
            model.endpoint,
            "/v1/nodes/directive",
            model.credential,
            body=directive.to_json().stringify(),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The drain request was rejected.",
                "排空请求被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Drain requested for \{node_id}.",
                "已请求排空 \{node_id}。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(CordonNode(node_id))) => {
      let generation = current_unix_ms()
      let directive : @contracts.NodeDirective = {
        node_id,
        desired_state: Cordoned,
        generation,
        issued_unix_ms: generation,
        receipt: "console:cordon:\{node_id}:\{generation}",
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "PUT",
            model.endpoint,
            "/v1/nodes/directive",
            model.credential,
            body=directive.to_json().stringify(),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The cordon request was rejected.",
                "封锁调度请求被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Cordon requested for \{node_id}.",
                "已请求封锁调度 \{node_id}。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(RollbackAlias(alias_name))) => {
      let body : Json = {
        "alias_name": alias_name,
        "actor": "console-operator",
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/aliases/rollback",
            model.credential,
            body=body.stringify(),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The model alias rollback was rejected.",
                "模型别名回滚被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model alias \{alias_name} was rolled back.",
                "模型别名 \{alias_name} 已回滚。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(StopDeployment(assignment_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/assignments/\{assignment_id}/stop",
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The deployment stop was rejected.",
                "停止部署的请求被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Deployment assignment \{assignment_id} was stopped.",
                "部署分配 \{assignment_id} 已停止。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(RollbackServiceDeployment(deployment_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            service_deployment_action_path(deployment_id, "rollback"),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The model service rollback was rejected.",
                "模型服务回滚被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model service \{deployment_id} was rolled back.",
                "模型服务 \{deployment_id} 已回滚。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(DeleteServiceDeployment(deployment_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            service_deployment_action_path(deployment_id, "delete"),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The model service deletion was rejected.",
                "模型服务删除被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model service \{deployment_id} was deleted.",
                "模型服务 \{deployment_id} 已删除。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(ActivateAccount(account_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/accounts/\{account_id}:activate",
              model.credential,
            ),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The account could not be activated.",
                "无法激活该账户。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Account \{account_id} was activated.",
                "账户 \{account_id} 已激活。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(SuspendAccount(account_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/accounts/\{account_id}:suspend",
              model.credential,
            ),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The account could not be suspended.",
                "无法暂停该账户。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Account \{account_id} was suspended and its sessions were revoked.",
                "账户 \{account_id} 已暂停，其会话已撤销。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(RevokeAccount(account_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/accounts/\{account_id}:revoke",
              model.credential,
            ),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The account could not be revoked.",
                "无法撤销该账户。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Account \{account_id} was revoked and its sessions were revoked.",
                "账户 \{account_id} 已撤销，其会话已撤销。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(SetAccountRoles(account_id, roles))) => {
      let body = AccountRolesIntent::{ roles, }.to_json().stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/accounts/\{account_id}:set-roles",
              model.credential,
              body~,
            ),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The account roles could not be changed.",
                "无法更改账户角色。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Account \{account_id} roles were changed.",
                "账户 \{account_id} 的角色已更改。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(SuspendUser(user_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            workspace_lifecycle_path(SuspendWorkspaceUser(user_id)),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The user could not be suspended.",
                "无法暂停该用户。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "User \{user_id} was suspended.",
                "用户 \{user_id} 已暂停。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(RevokeUser(user_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            workspace_lifecycle_path(RevokeWorkspaceUser(user_id)),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The user could not be revoked.",
                "无法撤销该用户。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "User \{user_id} was revoked.",
                "用户 \{user_id} 已撤销。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(RevokeAccessGrant(grant_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/workspace/access-grants/\{grant_id}:revoke",
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The access grant could not be revoked.",
                "无法撤销该访问授权。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Access grant \{grant_id} was revoked.",
                "访问授权 \{grant_id} 已撤销。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(EndComputeLease(lease_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/workspace/leases/\{lease_id}:end",
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The workspace lease could not be ended.",
                "无法结束该工作区租约。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Workspace lease \{lease_id} was ended.",
                "工作区租约 \{lease_id} 已结束。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(TerminateExclusiveNodeLease(lease_id, generation))) => {
      let body = @nodelease.ExclusiveLeaseTerminationRequest::{
          expected_generation: generation,
          reason: "operator-requested",
        }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/exclusive-node-leases/\{lease_id}:terminate",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Exclusive lease termination was rejected or stale. Refresh before retrying.",
                "独占租约终止请求被拒绝或已过期。请刷新后重试。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Exclusive lease \{lease_id} entered fail-closed cleanup. The node remains unavailable until sanitization is verified.",
                "独占租约 \{lease_id} 已进入故障关闭式清理。节点将在清理验证完成前保持不可用。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(
      ConfirmAction(
        RedriveNotificationDelivery(
          delivery_id,
          expected_attempt_count,
          expected_updated_unix_ms
        )
      )
    ) => {
      let body = {
          "expected_attempt_count": expected_attempt_count.to_json(),
          "expected_updated_unix_ms": expected_updated_unix_ms.to_json(),
        }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/notifications/operator/deliveries/\{delivery_id}:redrive",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Delivery redrive was rejected or stale. Refresh the delivery record before retrying.",
                "重新投递请求被拒绝或已过期。请刷新投递记录后重试。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Delivery \{delivery_id} was accepted for redrive.",
                "投递 \{delivery_id} 已接受重新投递。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(OfflineCommerce(Refresh)) => (model, load_command(model, emit))
    Console(OfflineCommerce(RequestGeneration(order_id, kind))) => {
      guard selected_offline_order(model.console.offline_commerce, order_id)
        is Some(order) else {
        return (
          {
            ..model,
            console: {
              ..model.console,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "A current order, quote, and active matching template are required.",
                  "必须存在当前订单、有效报价及匹配的启用模板。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      guard order.quote is Some(quote) else { return (model, @rabbita.none) }
      guard generation_template(model.console.offline_commerce, kind)
        is Some(template) else {
        return (model, @rabbita.none)
      }
      let artifact_id = random_identifier("offline-artifact")
      let action : @offline.ArtifactGenerationRequest = {
        request_id: random_identifier("offline-generation"),
        order_id,
        organization_id: order.organization_id,
        artifact_id,
        kind,
        template_id: template.template_id,
        template_version: template.version,
        locale: if model.console.locale.is_chinese() {
          "zh-CN"
        } else {
          "en-US"
        },
        expected_object_ref: "object://offline-generated/\{order.organization_id}/\{order_id}/\{artifact_id}",
        input_snapshot_sha256: quote.terms_digest,
        requested_by: model.console.offline_commerce.operator_actor_ref,
        requested_unix_ms: current_unix_ms(),
      }
      let cmd = offline_action_command(
        model,
        "/v1/offline-commerce/operator/generation-requests",
        action.to_json().stringify(),
        "Verified document generation was requested.",
        "已请求生成并验证文档。",
        emit,
      )
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(OfflineCommerce(ConfirmAction(action))) => {
      let now = current_unix_ms()
      let actor = model.console.offline_commerce.operator_actor_ref
        .trim()
        .to_owned()
      let request_spec : OfflineActionRequest = match action {
        QuoteOrder(order_id, terms_digest, price_text, confirmed_actor) => {
          guard selected_offline_order(model.console.offline_commerce, order_id)
            is Some(order) else {
            return (model, @rabbita.none)
          }
          let minor_units = try @string.parse_int64(price_text) catch {
            _ =>
              return (
                {
                  ..model,
                  console: {
                    ..model.console,
                    error_message: Some(
                      console_copy(
                        model.console.locale,
                        "Price must be a non-negative integer in minor units.",
                        "价格必须是以最小货币单位表示的非负整数。",
                      ),
                    ),
                  },
                },
                @rabbita.none,
              )
          } noraise {
            value => value
          }
          if minor_units < 0L {
            return (model, @rabbita.none)
          }
          let proposed = now + 604800000L
          let valid_until = if proposed < order.expires_unix_ms {
            proposed
          } else {
            order.expires_unix_ms
          }
          let money : @commercial.FixedMoney = {
            minor_units,
            currency: "CNY",
            scale: 2,
          }
          let quote : @offline.ImmutableQuote = {
            quote_id: random_identifier("offline-quote"),
            version: "v1",
            service_code: order.selected_service_code,
            sla_code: order.selected_sla_code,
            currency: "CNY",
            lines: [
              {
                line_id: "service-capacity",
                description: "Exclusive machine capacity",
                quantity: 1L,
                unit: "lease",
                unit_price: money,
                line_total: money,
              },
            ],
            subtotal: money,
            tax: { minor_units: 0L, currency: "CNY", scale: 2 },
            total: money,
            valid_until_unix_ms: valid_until,
            terms_digest,
            created_unix_ms: now,
          }
          let value : OfflineQuoteAction = { order_id, quote }
          ignore(confirmed_actor)
          {
            path: "/v1/offline-commerce/operator/quotes",
            body: value.to_json().stringify(),
            english_success: "The immutable quote was created.",
            chinese_success: "不可变报价已创建。",
          }
        }
        BeginOrder(order_id, generation) => {
          let value : OfflineOrderAction = {
            order_id,
            expected_generation: generation,
          }
          {
            path: "/v1/offline-commerce/operator/begin",
            body: value.to_json().stringify(),
            english_success: "The offline workflow started.",
            chinese_success: "线下办理流程已启动。",
          }
        }
        ReleaseVerifiedPacket(order_id, generation) => {
          let value : OfflineOrderAction = {
            order_id,
            expected_generation: generation,
          }
          {
            path: "/v1/offline-commerce/operator/release-packets",
            body: value.to_json().stringify(),
            english_success: "The verified print packet was released.",
            chinese_success: "已发布验证通过的打印材料。",
          }
        }
        AcceptEvidence(artifact_id, digest) => {
          guard selected_offline_artifact(
              model.console.offline_commerce,
              artifact_id,
            )
            is Some(artifact) else {
            return (model, @rabbita.none)
          }
          let review : @offline.EvidenceReview = {
            review_id: random_identifier("offline-review"),
            order_id: artifact.order_id,
            artifact_id,
            expected_artifact_sha256: digest,
            reviewer_ref: actor,
            accepted: true,
            reason_code: "evidence-accepted",
            audit_receipt: random_identifier("offline-review-receipt"),
            reviewed_unix_ms: now,
          }
          {
            path: "/v1/offline-commerce/operator/reviews",
            body: review.to_json().stringify(),
            english_success: "The exact evidence digest was accepted.",
            chinese_success: "已接受该凭证的精确摘要。",
          }
        }
        RejectEvidence(artifact_id, digest) => {
          guard selected_offline_artifact(
              model.console.offline_commerce,
              artifact_id,
            )
            is Some(artifact) else {
            return (model, @rabbita.none)
          }
          let review : @offline.EvidenceReview = {
            review_id: random_identifier("offline-review"),
            order_id: artifact.order_id,
            artifact_id,
            expected_artifact_sha256: digest,
            reviewer_ref: actor,
            accepted: false,
            reason_code: "correction-required",
            audit_receipt: random_identifier("offline-review-receipt"),
            reviewed_unix_ms: now,
          }
          {
            path: "/v1/offline-commerce/operator/reviews",
            body: review.to_json().stringify(),
            english_success: "A corrected evidence revision was requested.",
            chinese_success: "已要求提交补正后的凭证版本。",
          }
        }
        FulfillVerifiedOrder(order_id, generation) => {
          let value : OfflineFulfillmentAction = {
            order_id,
            expected_generation: generation,
            activation_id: random_identifier("offline-activation"),
            idempotency_key: random_identifier("offline-activate"),
            entitlement_kind: ExclusiveMachineLease,
            authority_target_ref: model.console.offline_commerce.entitlement_ref
            .trim()
            .to_owned(),
          }
          {
            path: "/v1/offline-commerce/operator/fulfillments",
            body: value.to_json().stringify(),
            english_success: "All policy evidence passed; entitlement activation is pending authority confirmation.",
            chinese_success: "全部策略凭证已通过；权益激活正在等待授权方确认。",
          }
        }
        CancelOrder(order_id, generation) => {
          let value : OfflineOrderAction = {
            order_id,
            expected_generation: generation,
          }
          {
            path: "/v1/offline-commerce/operator/cancellations",
            body: value.to_json().stringify(),
            english_success: "The order was cancelled with generation-fenced authority.",
            chinese_success: "已使用受状态版本保护的权限取消订单。",
          }
        }
        RequestEntitlementReversal(order_id, generation) => {
          let reversal_id = random_identifier("offline-reversal")
          let value : OfflineReversalAction = {
            reversal_id,
            idempotency_key: reversal_id,
            order_id,
            expected_generation: generation,
            reason: PolicyRevoked,
          }
          {
            path: "/v1/offline-commerce/operator/reversals",
            body: value.to_json().stringify(),
            english_success: "Entitlement revocation is pending external authority confirmation.",
            chinese_success: "权益撤销正在等待外部授权方确认。",
          }
        }
        RecoverFailedReversal(
          order_id,
          failed_reversal_id,
          generation,
          decision
        ) => {
          let recovery_id = random_identifier("offline-reversal-recovery")
          let value : OfflineReversalRecoveryAction = {
            recovery_id,
            idempotency_key: recovery_id,
            order_id,
            failed_reversal_id,
            expected_generation: generation,
            decision,
            replacement_reversal_id: if decision == RetryReversal {
              Some(random_identifier("offline-reversal-retry"))
            } else {
              None
            },
            authority_receipt: "operator-reconciled-authority-state",
            reason_code: "manual-entitlement-reconciliation",
          }
          {
            path: "/v1/offline-commerce/operator/reversal-recoveries",
            body: value.to_json().stringify(),
            english_success: "The failed entitlement reversal was reconciled with generation-fenced evidence.",
            chinese_success: "已使用受状态版本保护的凭证完成失败权益撤销的核对处理。",
          }
        }
      }
      let cmd = offline_action_command(
        model,
        request_spec.path,
        request_spec.body,
        request_spec.english_success,
        request_spec.chinese_success,
        emit,
      )
      (
        {
          ..model,
          console: {
            ..model.console,
            offline_commerce: {
              ..model.console.offline_commerce,
              confirmation: None,
              loading: true,
            },
          },
        },
        cmd,
      )
    }
    Console(OfflineCommerce(offline_message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            offline_commerce: model.console.offline_commerce.update(
              offline_message,
            ),
          },
        },
        @rabbita.none,
      )
    Console(ContractDocuments(Refresh)) => (model, load_command(model, emit))
    Console(ContractDocuments(SelectPacket(packet_id))) => {
      let documents = model.console.contract_documents.update(
        SelectPacket(packet_id),
      )
      schedule_contract_preview(model, documents, 0, emit)
    }
    Console(ContractDocuments(SelectTenant(tenant_ref))) => {
      let documents = model.console.contract_documents.update(
        SelectTenant(tenant_ref),
      )
      schedule_contract_preview(model, documents, 0, emit)
    }
    Console(ContractDocuments(SearchChanged(query))) => {
      let documents = model.console.contract_documents.update(
        SearchChanged(query),
      )
      schedule_contract_preview(model, documents, 0, emit)
    }
    Console(ContractDocuments(SelectForm(form))) => {
      let documents = model.console.contract_documents.update(SelectForm(form))
      schedule_contract_preview(model, documents, 0, emit)
    }
    Console(ContractDocuments(FieldChanged(field_id, value))) => {
      let documents = model.console.contract_documents.update(
        FieldChanged(field_id, value),
      )
      schedule_contract_preview(model, documents, 250, emit)
    }
    Console(
      ContractDocuments(RequestPreview(packet_id, revision, form, changes))
    ) => {
      let next_documents = model.console.contract_documents.update(
        RequestPreview(packet_id, revision, form, changes),
      )
      schedule_contract_preview(model, next_documents, 0, emit)
    }
    Console(ContractDocuments(SaveInformation(packet_id, revision, changes))) => {
      let next_documents = model.console.contract_documents.update(
        SaveInformation(packet_id, revision, changes),
      )
      (
        {
          ..model,
          console: { ..model.console, contract_documents: next_documents },
        },
        operator_contract_command(model, packet_id, revision, changes, emit),
      )
    }
    Console(ContractDocuments(ApproveApproval(approval_id))) => {
      let next_documents = model.console.contract_documents.update(
        ApproveApproval(approval_id),
      )
      (
        {
          ..model,
          console: { ..model.console, contract_documents: next_documents },
        },
        @rabbita.none,
      )
    }
    Console(ContractDocuments(ExportGovernance(tenant_ref))) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            contract_documents: model.console.contract_documents.update(
              ExportGovernance(tenant_ref),
            ),
          },
        },
        contract_governance_export_command(model, tenant_ref, emit),
      )
    Console(ContractDocuments(ConfirmAction(action))) => {
      let next_documents = model.console.contract_documents.update(
        ConfirmAction(action),
      )
      let next = {
        ..model,
        console: { ..model.console, contract_documents: next_documents },
      }
      match action {
        RegisterExecution(_)
        | ClosePacket(_)
        | SupersedePacket(_)
        | RequestRenewal(_) =>
          if model.demo_mode {
            demo_contract_lifecycle_action(next, action)
          } else {
            (next, operator_contract_lifecycle_command(model, action, emit))
          }
        ApprovePending(approval_id) =>
          if model.demo_mode {
            (
              {
                ..next,
                console: {
                  ..next.console,
                  contract_documents: {
                    ..next.console.contract_documents,
                    loading: false,
                    confirmation: None,
                    success_message: Some(
                      console_copy(
                        model.console.locale,
                        "Demo is read-only; approval was previewed but not sent.",
                        "演示为只读；已预览审批操作，但未发送请求。",
                      ),
                    ),
                  },
                },
              },
              @rabbita.none,
            )
          } else {
            (
              next,
              operator_contract_approval_command(
                model, approval_id, true, "", emit,
              ),
            )
          }
        RejectApproval(approval_id, reason) =>
          if model.demo_mode {
            (
              {
                ..next,
                console: {
                  ..next.console,
                  contract_documents: {
                    ..next.console.contract_documents,
                    loading: false,
                    confirmation: None,
                    success_message: Some(
                      console_copy(
                        model.console.locale,
                        "Demo is read-only; rejection was previewed but not sent.",
                        "演示为只读；已预览拒绝操作，但未发送请求。",
                      ),
                    ),
                  },
                },
              },
              @rabbita.none,
            )
          } else {
            (
              next,
              operator_contract_approval_command(
                model, approval_id, false, reason, emit,
              ),
            )
          }
        _ =>
          // Customer attestations are never offered to the operator; drop them
          // defensively so the confirmation dialog never spins.
          (
            {
              ..next,
              console: {
                ..next.console,
                contract_documents: {
                  ..next.console.contract_documents,
                  loading: false,
                  error_message: Some(
                    console_copy(
                      model.console.locale,
                      "This contract attestation belongs to the customer portal.",
                      "该合同确认操作属于客户门户。",
                    ),
                  ),
                },
              },
            },
            @rabbita.none,
          )
      }
    }
    Console(ContractDocuments(message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            contract_documents: model.console.contract_documents.update(message),
          },
        },
        @rabbita.none,
      )
  }
}

/// Demo mode keeps navigation and language switching interactive while making
/// all controller mutations and refreshes no-ops.

///|
fn update(
  model : AppModel,
  message : AppMessage,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  if model.demo_mode {
    match message {
      Console(LocaleChanged(_))
      | Console(Navigate(_))
      | Console(QuickDeploymentIdChanged(_))
      | Console(QuickTemplateChanged(_))
      | Console(PortalNodeChanged(_))
      | Console(ModelSourceQueryChanged(_))
      | Console(OperationChanged(_))
      | Console(OperationBodyChanged(_))
      | Console(BeginDrain(_))
      | Console(BeginCordon(_))
      | Console(BeginRollback(_))
      | Console(BeginStopDeployment(_))
      | Console(BeginRollbackServiceDeployment(_))
      | Console(BeginDeleteServiceDeployment(_))
      | Console(BeginSuspendUser(_))
      | Console(BeginRevokeUser(_))
      | Console(BeginRevokeAccessGrant(_))
      | Console(BeginEndComputeLease(_))
      | Console(BeginTerminateExclusiveNodeLease(_, _))
      | Console(BeginRedriveNotificationDelivery(_, _, _))
      | Console(ContractDocuments(_))
      | Console(DismissConfirmation)
      | ContractPreviewDue(_, _)
      | Outcome(ContractPreviewLoaded(_, _))
      | Outcome(ContractPreviewFailed(_, _, _)) =>
        update_live(model, message, emit)
      Console(OfflineCommerce(RequestGeneration(_, _)))
      | Console(OfflineCommerce(ConfirmAction(_)))
      | Console(OfflineCommerce(Refresh)) =>
        (
          {
            ..model,
            console: {
              ..model.console,
              offline_commerce: {
                ..model.console.offline_commerce,
                confirmation: None,
                loading: false,
                error_message: None,
                success_message: Some(
                  console_copy(
                    model.console.locale,
                    "Demo is read-only; the commercial action was previewed but not sent.",
                    "演示为只读；已预览商务操作，但未发送请求。",
                  ),
                ),
              },
            },
          },
          @rabbita.none,
        )
      Console(OfflineCommerce(_)) => update_live(model, message, emit)
      Console(ConfirmAction(_)) =>
        (
          {
            ..model,
            console: {
              ..model.console,
              confirmation: None,
              error_message: None,
              success_message: Some(
                console_copy(
                  model.console.locale,
                  "Demo is read-only; the operation was previewed but not persisted.",
                  "演示为只读；已预览该操作，但未持久化任何更改。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      Console(PromoteServiceDeployment(_))
      | Console(ActivateUser(_))
      | Console(ActivateComputeLease(_))
      | Console(SearchModelSource)
      | Console(DownloadModelSource(_))
      | Console(CancelModelImport(_))
      | Console(RetryModelImport(_))
      | Console(RefreshModelImports)
      | Console(SubmitOperation) =>
        (
          {
            ..model,
            console: {
              ..model.console,
              error_message: None,
              success_message: Some(
                console_copy(
                  model.console.locale,
                  "Demo is read-only; no controller operation was sent or persisted.",
                  "演示为只读；未向控制器发送或持久化任何操作。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      Console(Refresh) =>
        (
          {
            ..model,
            console: {
              ..model.console,
              error_message: None,
              success_message: Some(
                console_copy(
                  model.console.locale,
                  "Demo snapshot is already current.",
                  "演示快照已是最新状态。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      Console(ApproveEnterpriseLease(_, _))
      | Console(RejectEnterpriseLease(_, _)) =>
        (
          {
            ..model,
            console: {
              ..model.console,
              error_message: None,
              success_message: Some(
                console_copy(
                  model.console.locale,
                  "Demo is read-only; no lease decision was persisted.",
                  "演示为只读；未持久化租约决策。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      Console(SubmitQuickDeployment) => {
        guard quick_deployment_intent(model.console, 0L) is Some(intent) else {
          return (
            {
              ..model,
              console: {
                ..model.console,
                success_message: None,
                error_message: Some(
                  console_copy(
                    model.console.locale,
                    "Choose an approved template and a valid service name.",
                    "请选择已批准模板和有效服务名称。",
                  ),
                ),
              },
            },
            @rabbita.none,
          )
        }
        (
          {
            ..model,
            console: {
              ..model.console,
              error_message: None,
              success_message: Some(
                console_copy(
                  model.console.locale,
                  "Demo preflight passed for \{intent.deployment_id}. No controller operation was created.",
                  "\{intent.deployment_id} 的演示预检已通过。未创建控制器操作。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      _ => (model, @rabbita.none)
    }
  } else {
    update_live(model, message, emit)
  }
}

///|
fn app_view(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Html {
  let locale = model.console.locale
  if !model.demo_mode && !model.console.operator_authenticated {
    return login_view(model, emit)
  }
  @html.div(class="console-root", [
    @html.details(
      class="connection-panel",
      attrs=@html.Attrs::build().aria_label(
        console_copy(locale, "Controller connection", "控制器连接"),
      ),
      [
        @html.summary([
          @html.span(
            class=if model.credential != "" && model.audit_credential != "" {
              "connection-state connection-state-ready"
            } else {
              "connection-state connection-state-needed"
            },
            if model.credential.has_prefix("lnxs_") {
              console_copy(
                locale, "Account session active", "账户会话有效",
              )
            } else if model.credential != "" && model.audit_credential != "" {
              console_copy(
                locale, "Local fallback active", "本地回退有效",
              )
            } else {
              console_copy(locale, "Credentials required", "需要凭据")
            },
          ),
          @html.span(
            class="connection-summary-label",
            console_copy(locale, "Controller connection", "控制器连接"),
          ),
          @html.span(class="connection-endpoint", model.endpoint),
        ]),
        @html.div(class="connection-form", [
          @html.div(class="connection-field", [
            @html.label(
              for_="account-session",
              console_copy(locale, "Account session", "账户会话"),
            ),
            @html.input(
              id="account-session",
              input_type=Password,
              value=if model.credential.has_prefix("lnxs_") {
                model.credential
              } else {
                ""
              },
              auto_complete=Off,
              on_input=emit.map(value => AccountSessionChanged(value)),
            ),
            @html.span(
              class="connection-help",
              console_copy(
                locale, "One lnxs_ PlatformOperator session authorizes operator and audit APIs.",
                "一个 lnxs_ PlatformOperator 会话同时授权运维和审计 API。",
              ),
            ),
          ]),
          @html.div(class="connection-field", [
            @html.label(
              for_="commercial-organization",
              console_copy(
                locale, "Commercial organization (optional)", "商业组织（可选）",
              ),
            ),
            @html.input(
              id="commercial-organization",
              value=model.commercial_organization,
              maxlength=160,
              auto_complete=Off,
              on_input=emit.map(value => CommercialOrganizationChanged(value)),
            ),
            @html.span(
              class="connection-help",
              console_copy(
                locale, "Loads tenant-scoped cost centers, agreements, and normalized provider evidence on refresh.",
                "刷新时加载限定租户范围的成本中心、协议与规范化供应商证据。",
              ),
            ),
          ]),
          if localhost_dev_fallback_allowed(model.endpoint) {
            @html.div(class="connection-field", [
              @html.label(
                for_="operator-token",
                console_copy(
                  locale, "Local static operator token", "本地静态运维令牌",
                ),
              ),
              @html.input(
                id="operator-token",
                input_type=Password,
                value=if model.credential.has_prefix("lnxs_") {
                  ""
                } else {
                  model.credential
                },
                auto_complete=Off,
                on_input=emit.map(value => CredentialChanged(value)),
              ),
              @html.span(
                class="connection-help",
                console_copy(
                  locale, "Development bootstrap only; unavailable on remote endpoints.",
                  "仅用于开发引导；远程端点不可用。",
                ),
              ),
            ])
          } else {
            @html.nothing
          },
          if localhost_dev_fallback_allowed(model.endpoint) {
            @html.div(class="connection-field", [
              @html.label(
                for_="audit-token",
                console_copy(
                  locale, "Local static audit token", "本地静态审计令牌",
                ),
              ),
              @html.input(
                id="audit-token",
                input_type=Password,
                value=if model.audit_credential.has_prefix("lnxs_") {
                  ""
                } else {
                  model.audit_credential
                },
                auto_complete=Off,
                on_input=emit.map(value => AuditCredentialChanged(value)),
              ),
            ])
          } else {
            @html.nothing
          },
          @html.div(class="connection-field", [
            @html.label(
              for_="inference-token",
              console_copy(
                locale, "Inference token (optional)", "推理令牌（可选）",
              ),
            ),
            @html.input(
              id="inference-token",
              input_type=Password,
              value=model.inference_credential,
              auto_complete=Off,
              on_input=emit.map(value => InferenceCredentialChanged(value)),
            ),
          ]),
          @html.div(class="connection-field", [
            @html.label(
              for_="inference-subject",
              console_copy(
                locale, "Opaque inference subject reference (optional)", "不透明主体引用（可选）",
              ),
            ),
            @html.input(
              id="inference-subject",
              value=model.inference_subject_ref,
              maxlength=256,
              auto_complete=Off,
              attrs=@html.Attrs::build().aria_describedby(
                "inference-subject-help",
              ),
              on_input=emit.map(value => InferenceSubjectChanged(value)),
            ),
            @html.span(
              id="inference-subject-help",
              class="connection-help",
              console_copy(
                locale, "Leave empty when verified mTLS derives identity. Only loopback acceptance clients may send this header directly.",
                "经验证的 mTLS 可推导身份时请留空。仅回环验收客户端可直接发送此标头。",
              ),
            ),
          ]),
          @html.div(class="connection-actions", [
            @html.span(
              class="secondary",
              console_copy(
                locale, "Account sessions stay in browser memory and are revoked through the controller on logout.",
                "账户会话仅保存在浏览器内存中，并在退出时通过控制器撤销。",
              ),
            ),
            @html.button(
              type_="button",
              class="primary-button",
              disabled=(
                  !model.credential.has_prefix("lnxs_") &&
                  (
                    !localhost_dev_fallback_allowed(model.endpoint) ||
                    model.credential == "" ||
                    model.audit_credential == ""
                  )
                ) ||
                model.console.loading,
              on_click=emit(Connect),
              console_copy(locale, "Connect and refresh", "连接并刷新"),
            ),
            @html.button(
              type_="button",
              class="danger-secondary",
              on_click=emit(Logout),
              console_copy(locale, "Log out", "退出登录"),
            ),
          ]),
        ]),
      ],
    ),
    if model.demo_mode {
      @html.div(class="demo-banner", [
        @html.span(class="demo-banner-mark", "DEMO"),
        @html.strong(
          console_copy(locale, "Read-only demo snapshot", "只读演示快照"),
        ),
        @html.span(
          console_copy(
            locale, "4/4 machines running · 9 models available · controller mutations disabled",
            "4/4 台机器运行中 · 9 个模型可用 · 控制器变更已禁用",
          ),
        ),
      ])
    } else {
      @html.nothing
    },
    @ui.interactive_view(model.console, emit.map(message => Console(message))),
  ])
}

///|
fn login_transport_allowed(endpoint : String) -> Bool {
  endpoint.has_prefix("https://") ||
  endpoint.has_prefix("http://127.0.0.1:") ||
  endpoint.has_prefix("http://localhost:")
}

///|
fn localhost_dev_fallback_allowed(endpoint : String) -> Bool {
  endpoint.has_prefix("http://127.0.0.1:") ||
  endpoint.has_prefix("http://localhost:") ||
  endpoint.has_prefix("https://127.0.0.1:") ||
  endpoint.has_prefix("https://localhost:")
}

///|
fn login_styles() -> String {
  (
    #|*{box-sizing:border-box}html,body,#app{min-height:100%;margin:0}body{background:#f4f6fa;color:#152033;font:14px/1.5 Inter,"PingFang SC","Noto Sans SC",system-ui,sans-serif}.login-shell{min-height:100vh;display:grid;grid-template-columns:minmax(18rem,.8fr) minmax(28rem,1.2fr);background:radial-gradient(circle at 15% 15%,rgba(69,105,233,.2),transparent 28rem),#f4f6fa}.login-context{padding:clamp(2rem,6vw,6rem);display:flex;flex-direction:column;justify-content:space-between;background:#0b1324;color:#f7f9ff}.login-brand{display:flex;align-items:center;gap:.8rem}.login-mark{width:2.7rem;height:2.7rem;border-radius:.75rem;background:#fff;color:#111a2d;display:grid;place-items:center;font-weight:900}.login-context h1{max-width:14ch;margin:.4rem 0 1rem;font-size:clamp(2rem,4vw,4.2rem);line-height:1.02}.login-context p{max-width:42rem;color:#b8c3db}.login-boundary{padding:1rem;border:1px solid #2c3d5d;border-radius:.8rem;background:rgba(255,255,255,.04)}.login-boundary strong,.login-boundary span{display:block}.login-boundary span{margin-top:.35rem;color:#aab8d3}.login-main{padding:clamp(1.5rem,6vw,6rem);display:grid;place-items:center}.login-card{width:min(34rem,100%);padding:clamp(1.4rem,3vw,2.3rem);border:1px solid #d8deea;border-radius:1rem;background:#fff;box-shadow:0 1.5rem 5rem rgba(24,39,75,.12)}.login-card-header{display:flex;justify-content:space-between;gap:1rem;align-items:start}.login-card h2{margin:.15rem 0;font-size:1.75rem}.login-card-header p{margin:.45rem 0 0;color:#63708a}.login-locale{display:grid;gap:.3rem;color:#63708a;font-size:.75rem}.login-locale select,.login-field input{min-height:44px;border:1px solid #b9c4d6;border-radius:.55rem;background:#fff;color:#152033;font:inherit}.login-locale select{padding:.5rem 1.9rem .5rem .65rem}.login-form{display:grid;gap:1rem;margin-top:1.6rem}.login-field label{display:block;margin-bottom:.35rem;font-weight:750}.login-field input{width:100%;padding:.65rem .75rem}.login-help{display:block;margin-top:.3rem;color:#63708a;font-size:.75rem}.login-endpoint{padding:.65rem .75rem;border-radius:.55rem;background:#f0f3f8;color:#53617b;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.login-alert{padding:.75rem .85rem;border:1px solid #db8f8f;border-radius:.55rem;background:#fff3f3;color:#9a2424}.login-transport-warning{padding:.8rem;border-left:3px solid #c17a00;background:#fff8e8;color:#775000}.login-sso-link{display:flex;align-items:center;justify-content:center;min-height:44px;padding:.65rem 1rem;border:1px solid #345de0;border-radius:.55rem;background:#4569e9;color:#fff;font-weight:800;text-decoration:none}.login-sso-link:hover{background:#345de0}.login-sso-link:focus-visible{outline:3px solid #152f85;outline-offset:2px}.login-divider{display:flex;align-items:center;gap:.6rem;color:#63708a;font-size:.72rem}.login-divider::before,.login-divider::after{height:1px;flex:1;background:#d8deea;content:""}.login-actions{display:flex;align-items:center;justify-content:space-between;gap:1rem;margin-top:.4rem}.login-actions button{min-height:44px;padding:.65rem 1rem;border:1px solid #345de0;border-radius:.55rem;background:#4569e9;color:#fff;font:inherit;font-weight:800;cursor:pointer}.login-actions button:disabled{opacity:.45;cursor:not-allowed}.login-actions span{color:#63708a;font-size:.75rem}.login-dev-fallback{border:1px solid #d8deea;border-radius:.6rem;background:#f8fafc}.login-dev-fallback summary{min-height:44px;padding:.7rem .8rem;cursor:pointer;color:#53617b;font-weight:750}.login-dev-fields{display:grid;gap:.8rem;padding:.8rem;border-top:1px solid #d8deea}.login-dev-warning{margin:0;color:#8a4b00;font-size:.75rem}@media(max-width:52rem){.login-shell{grid-template-columns:1fr}.login-context{min-height:18rem;padding:2rem}.login-context h1{font-size:2.2rem}.login-main{padding:1rem}.login-card-header{display:grid}.login-locale{justify-self:start}.login-actions{align-items:stretch;flex-direction:column}.login-actions button{width:100%}}@media(prefers-reduced-motion:reduce){*{transition:none!important}}
  )
}

///|
fn login_view(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Html {
  let locale = model.console.locale
  let transport_allowed = login_transport_allowed(model.endpoint)
  @html.main_(class="login-shell", [
    @html.style_tag(login_styles()),
    @html.section(class="login-context", [
      @html.div(class="login-brand", [
        @html.span(class="login-mark", "LN"),
        @html.strong("LunaNexa"),
      ]),
      @html.div([
        @html.p(
          console_copy(
            locale, "Private GPU infrastructure", "私有 GPU 基础设施",
          ),
        ),
        @html.h1(
          console_copy(
            locale, "Operator access starts here.", "运维访问从这里开始。",
          ),
        ),
        @html.p(
          console_copy(
            locale, "Cluster inventory, model governance, leases, contracts, and audit evidence stay hidden until the controller authenticates this session.",
            "在控制器验证本次会话之前，集群清单、模型治理、租约、合同和审计证据均保持隐藏。",
          ),
        ),
      ]),
      @html.div(class="login-boundary", [
        @html.strong(
          console_copy(locale, "Management boundary", "管理边界"),
        ),
        @html.span(
          console_copy(
            locale, "Credentials remain in browser memory and are cleared on logout or reload.",
            "凭据仅保留在浏览器内存中，并在退出或重新加载时清除。",
          ),
        ),
      ]),
    ]),
    @html.section(class="login-main", [
      @html.div(class="login-card", [
        @html.div(class="login-card-header", [
          @html.div([
            @html.h2(console_copy(locale, "Operator login", "运维登录")),
            @html.p(
              console_copy(
                locale, "Authenticate against the LunaNexa controller.", "通过 LunaNexa 控制器进行身份验证。",
              ),
            ),
          ]),
          @html.div(class="login-locale", [
            @html.label(
              for_="login-locale",
              console_copy(locale, "Language", "语言"),
            ),
            @html.select(
              id="login-locale",
              on_change=emit.map(value => {
                Console(LocaleChanged(@i18n.parse_locale(value)))
              }),
              [
                @html.option(
                  value=@i18n.English.storage_value(),
                  selected=locale == English,
                  @i18n.English.label(),
                ),
                @html.option(
                  value=@i18n.ChineseSimplified.storage_value(),
                  selected=locale == ChineseSimplified,
                  @i18n.ChineseSimplified.label(),
                ),
              ],
            ),
          ]),
        ]),
        @html.p(class="login-endpoint", model.endpoint),
        if !transport_allowed {
          @html.p(
            class="login-transport-warning",
            console_copy(
              locale, "Administrative login is blocked on public plain HTTP. Use the protected localhost URL or install TLS first.",
              "公共明文 HTTP 已禁止运维登录。请使用受保护的本机地址，或先部署 TLS。",
            ),
          )
        } else {
          @html.nothing
        },
        match model.console.error_message {
          Some(message) =>
            @html.p(
              class="login-alert",
              attrs=@html.Attrs::build().role("alert"),
              message,
            )
          None => @html.nothing
        },
        @html.div(class="login-form", [
          if transport_allowed {
            @html.a(
              href="/auth/oidc/start?audience=operator",
              class="login-sso-link",
              console_copy(
                locale, "Continue with organization sign-in", "使用组织账户继续",
              ),
            )
          } else {
            @html.span(
              class="login-sso-link",
              attrs=@html.Attrs::build().aria_disabled("true"),
              console_copy(
                locale, "Organization sign-in requires HTTPS", "组织登录需要 HTTPS",
              ),
            )
          },
          @html.div(
            class="login-divider",
            console_copy(
              locale, "or use an issued session", "或使用已签发会话",
            ),
          ),
          @html.div(class="login-field", [
            @html.label(
              for_="login-account-session",
              console_copy(locale, "Account session", "账户会话"),
            ),
            @html.input(
              id="login-account-session",
              input_type=Password,
              value=model.credential,
              auto_complete=Off,
              attrs=@html.Attrs::build()
                .disabled(!transport_allowed)
                .aria_describedby("login-account-session-help"),
              on_input=emit.map(value => AccountSessionChanged(value)),
            ),
            @html.span(
              id="login-account-session-help",
              class="login-help",
              console_copy(
                locale, "Use the short-lived lnxs_ session issued after organization sign-in. One PlatformOperator session authorizes both operations and audit reads.",
                "使用组织登录后签发的短期 lnxs_ 会话。一个 PlatformOperator 会话同时授权运维操作和审计读取。",
              ),
            ),
          ]),
          @html.div(class="login-actions", [
            @html.span(
              console_copy(
                locale, "The console appears only after a successful authenticated load.",
                "仅在身份验证并成功加载后显示控制台。",
              ),
            ),
            @html.button(
              type_="button",
              disabled=!transport_allowed ||
                !model.credential.has_prefix("lnxs_") ||
                model.console.loading,
              on_click=emit(Connect),
              if model.console.loading {
                console_copy(locale, "Signing in…", "正在登录…")
              } else {
                console_copy(locale, "Sign in", "登录")
              },
            ),
          ]),
          if localhost_dev_fallback_allowed(model.endpoint) {
            @html.details(class="login-dev-fallback", [
              @html.summary(
                console_copy(
                  locale, "Local development token fallback", "本地开发令牌回退",
                ),
              ),
              @html.div(class="login-dev-fields", [
                @html.p(
                  class="login-dev-warning",
                  console_copy(
                    locale, "For localhost bootstrap only. Production browsers must use an external identity-provider account session.",
                    "仅用于本机引导。生产环境浏览器必须使用外部身份提供商账户会话。",
                  ),
                ),
                @html.div(class="login-field", [
                  @html.label(
                    for_="login-operator-token",
                    console_copy(
                      locale, "Static operator token", "静态运维令牌",
                    ),
                  ),
                  @html.input(
                    id="login-operator-token",
                    input_type=Password,
                    value=if model.credential.has_prefix("lnxs_") {
                      ""
                    } else {
                      model.credential
                    },
                    auto_complete=Off,
                    on_input=emit.map(value => CredentialChanged(value)),
                  ),
                ]),
                @html.div(class="login-field", [
                  @html.label(
                    for_="login-audit-token",
                    console_copy(
                      locale, "Static audit token", "静态审计令牌",
                    ),
                  ),
                  @html.input(
                    id="login-audit-token",
                    input_type=Password,
                    value=if model.audit_credential.has_prefix("lnxs_") {
                      ""
                    } else {
                      model.audit_credential
                    },
                    auto_complete=Off,
                    on_input=emit.map(value => AuditCredentialChanged(value)),
                  ),
                ]),
                @html.div(class="login-actions", [
                  @html.span(
                    console_copy(
                      locale, "Static tokens are never stored.", "静态令牌不会被存储。",
                    ),
                  ),
                  @html.button(
                    type_="button",
                    disabled=model.credential == "" ||
                      model.audit_credential == "" ||
                      model.console.loading,
                    on_click=emit(Connect),
                    console_copy(
                      locale, "Use local fallback", "使用本地回退",
                    ),
                  ),
                ]),
              ]),
            ])
          } else {
            @html.nothing
          },
        ]),
      ]),
    ]),
  ])
}

///|
fn main {
  let locale = @i18n.parse_locale(stored_locale_preference())
  let is_demo = demo_mode()
  apply_console_locale(locale)
  let initial_model : AppModel = {
    endpoint: configured_endpoint(),
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: is_demo,
    console: if is_demo {
      {
        ..@ui.demo_state(),
        locale,
        offline_commerce: { ..@ui.demo_state().offline_commerce, locale, },
      }
    } else {
      {
        ..@ui.default_state(),
        locale,
        offline_commerce: { ..@ui.default_state().offline_commerce, locale, },
      }
    },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
  }
  @rabbita.new(fn() {
    let (model, emit) = @rabbita.create_state_with_init(
      init=fn(emit) {
        (
          initial_model,
          if is_demo {
            @rabbita.none
          } else {
            gateway_session_bootstrap_command(emit)
          },
        )
      },
      update~,
    )
    model.map(model => app_view(model, emit))
  }).mount("app")
}
