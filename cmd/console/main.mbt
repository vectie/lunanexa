///|
fn model_local_component(directory : String) -> String {
  if directory.has_suffix("/FL2VA") {
    "FL2VA"
  } else if directory.has_suffix("/Ref2VA") {
    "Ref2VA"
  } else {
    ""
  }
}

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
priv struct MembershipRevocationIntent {
  membership_id : String
} derive(ToJson)

///|
extend MembershipRevocationIntent with ToJson::{to_json}

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
priv struct AccessPackageIntent {
  identity_issuer : String
  identity_subject : String
  display_name : String
  email : String
  organization_id : String
  tenant_ref : String
  template_id : String
  lifetime_days : Int
  identity_verified : Bool
} derive(ToJson)

///|
priv struct TechnicalPreparedTarget {
  order_id : String
  authority_target_ref : String
  grant_id : String
  expires_unix_ms : Int64
} derive(FromJson)

///|
extend AccessPackageIntent with ToJson::{to_json}

///|
priv struct ModelAdoptionIntent {
  model_id : String
  version : String
  license_id : String
  compatible_architectures : Array[String]
  minimum_memory_mib : Int
} derive(ToJson)

///|
extend ModelAdoptionIntent with ToJson::{to_json}

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
/// What the gateway's username/password route answered. The status is kept
/// apart from the body so a rejected login can be reported without echoing
/// anything the gateway did not deliberately send.
priv struct PasswordLoginOutcome {
  status : Int
  body : String
} derive(FromJson)

///|
extern "js" fn configured_endpoint() -> String =
  #| () => globalThis.LUNANEXA_API_ENDPOINT || (globalThis.location?.pathname?.startsWith("/mana/") ? `${globalThis.location.origin}/mana` : globalThis.location?.origin || "")

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
/// Deployment-declared open operator origin. When this meta value exactly
/// matches the page origin, the console skips the login gate and lets the
/// same-origin gateway attach operator authority server-side.
extern "js" fn operator_open_origin() -> String =
  #| () => globalThis.document?.querySelector('meta[name="lunanexa-operator-open"]')?.getAttribute('content') || ''

///|
extern "js" fn console_page_origin() -> String =
  #| () => globalThis.location?.origin || ''

///|
extern "js" fn current_unix_ms() -> Int64 = "() => BigInt(Date.now())"

///|
extern "js" fn model_import_poll_promise() -> @js.Promise = "() => new Promise(resolve => setTimeout(resolve, 1500))"

///|
extern "js" fn cluster_poll_promise() -> @js.Promise = "() => new Promise(resolve => setTimeout(resolve, 5000))"

///|

///|
/// A fresh opaque identifier.
///
/// `crypto.randomUUID` exists only in a secure context, so on this deployment's
/// plain-HTTP pages it is `undefined` and calling it throws a `TypeError`. That
/// exception is not a LunaNexa error: it escapes the command that raised it, and
/// because the command runs inside the runtime's message drain it leaves the
/// application unable to process any further message until the page is
/// reloaded -- a silent freeze with no notice on screen.
///
/// The bytes come from `crypto.getRandomValues`, which is available without a
/// secure context, and the fallback keeps the function total. An identifier only
/// has to be unique; it must never be the reason a page stops working.
extern "js" fn random_identifier(prefix : String) -> String =
  #| prefix => {
  #|   const bytes = new Uint8Array(16);
  #|   if (globalThis.crypto && typeof crypto.getRandomValues === "function") {
  #|     crypto.getRandomValues(bytes);
  #|   } else {
  #|     for (let i = 0; i < bytes.length; i++) {
  #|       bytes[i] = Math.floor(Math.random() * 256);
  #|     }
  #|   }
  #|   bytes[6] = (bytes[6] & 0x0f) | 0x40;
  #|   bytes[8] = (bytes[8] & 0x3f) | 0x80;
  #|   const hex = Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");
  #|   return `${prefix}-${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  #| }

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
  #|     return globalThis.localStorage?.getItem("lunanexa.locale") || "zh-CN";
  #|   } catch (_) {
  #|     return "zh-CN";
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
  @i18n.copy(locale, english, chinese)
}

///|
fn console_document_title(locale : @i18n.Locale) -> String {
  console_copy(
    locale, "能源谷“创未来”生态街区 | Cluster Operations", "能源谷“创未来”生态街区 | 集群运维",
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
  #|     return new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Shanghai", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" }).format(new Date(milliseconds)) + " 北京时间";
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
  #|   const prefix = globalThis.location?.pathname?.startsWith("/mana/") ? "/mana" : "";
  #|   const response = await fetch(`${prefix}/auth/session`, {
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
  #|   const prefix = globalThis.location?.pathname?.startsWith("/mana/") ? "/mana" : "";
  #|   const response = await fetch(`${prefix}/auth/logout`, {
  #|     method: "POST",
  #|     headers: { "Accept": "application/json", "X-LunaNexa-CSRF": csrf },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error"
  #|   });
  #|   if (!response.ok && response.status !== 401) throw new Error(`gateway logout HTTP ${response.status}`);
  #| }

///|
/// Submit the operator's username and password to the same-origin gateway.
/// The audience is fixed by the caller, so the page cannot ask for the
/// customer portal's audience from the operator page.
extern "js" fn password_login_promise(
  username : String,
  password : String,
  audience : String,
) -> @js.Promise =
  #| async (username, password, audience) => {
  #|   if (!username || !password) return JSON.stringify({ status: 0, body: "" });
  #|   const prefix = globalThis.location?.pathname?.startsWith("/mana/") ? "/mana" : "";
  #|   const response = await fetch(`${prefix}/auth/password`, {
  #|     method: "POST",
  #|     headers: { "Accept": "application/json", "Content-Type": "application/json" },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|     body: JSON.stringify({ username, password, audience })
  #|   });
  #|   const text = await response.text();
  #|   return JSON.stringify({ status: response.status, body: text.slice(0, 4096) });
  #| }

///|
/// Loads only the checked, field-free MoonLeaf scene shipped with demo assets.
extern "js" fn demo_contract_preview_promise(
  template_id : String,
) -> @js.Promise =
  #| async templateId => {
  #|   const path = templateId === "youthpolicy-device-undertaking-ofl-v2" ? "/assets/contracts/youthpolicy/undertaking-ofl-v2/moonleaf-preview-template.v2.json" : templateId === "youthpolicy-device-undertaking-v1" ? "/assets/contracts/youthpolicy/undertaking-v1/moonleaf-preview-template.v1.json" : "/assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json";
  #|   const response = await fetch(path, {
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
        error: Some(http_failure_detail(error)),
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
/// Start every initial console read at once; `request` consumes these
/// promises when the load path reaches them, so the page waits on the
/// slowest call instead of the sum of all of them.
extern "js" fn prefetch_get(urls : FixedArray[String], token : String) -> Unit =
  #| (urls, token) => {
  #|   const cache = {};
  #|   globalThis.__lunanexaGetCache = cache;
  #|   for (const url of urls) {
  #|     cache[url] = fetch(url, {
  #|       method: "GET",
  #|       headers: {
  #|         "Accept": "application/json",
  #|         "Content-Type": "application/json",
  #|         "Authorization": `Bearer ${token}`
  #|       },
  #|       credentials: "same-origin",
  #|       cache: "no-store",
  #|       redirect: "error"
  #|     }).then(async response => {
  #|       const text = await response.text();
  #|       if (!response.ok) {
  #|         const detail = text.slice(0, 1024).replace(/[\r\n\t]+/g, " ");
  #|         throw new Error(`HTTP ${response.status}${detail ? `: ${detail}` : ""}`);
  #|       }
  #|       return text;
  #|     });
  #|   }
  #| }

///|
/// The GET side of `request`: consume the prefetched promise for this exact URL
/// when one is outstanding, and issue the request only when there is none. The
/// entry is removed as it is taken, so a later refresh still reads fresh data.
/// Without this the prefetch above would be dead weight and every read in the
/// load path would travel to the controller a second time.
extern "js" fn get_promise(url : String, token : String) -> @js.Promise =
  #| async (url, token) => {
  #|   const cache = globalThis.__lunanexaGetCache;
  #|   if (cache && Object.prototype.hasOwnProperty.call(cache, url)) {
  #|     const pending = cache[url];
  #|     delete cache[url];
  #|     return await pending;
  #|   }
  #|   const response = await fetch(url, {
  #|     method: "GET",
  #|     headers: {
  #|       "Accept": "application/json",
  #|       "Content-Type": "application/json",
  #|       "Authorization": `Bearer ${token}`
  #|     },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error"
  #|   });
  #|   const text = await response.text();
  #|   if (!response.ok) {
  #|     const detail = text.slice(0, 1024).replace(/[\r\n\t]+/g, " ");
  #|     throw new Error(`HTTP ${response.status}${detail ? `: ${detail}` : ""}`);
  #|   }
  #|   return text;
  #| }

///|
/// Read paths owned by one deferred, page-scoped read group. The commercial
/// snapshot paths only exist when the deployment declares an organization.
fn console_read_group_paths(
  group : ConsoleReadGroup,
  commercial_organization : String,
) -> Array[String] {
  match group {
    AlertsReads =>
      ["/v1/notifications/operator", "/v1/notifications/operator/deliveries"]
    ModelsReads => ["/v1/model-sources/modelscope/imports"]
    AuditReads => ["/v1/audit"]
    /// Accounts, sessions, access packages, and the workspace directory are
    /// read by `Users` and `Leases` and by nothing else.
    AccessReads =>
      [
        "/v1/accounts", "/v1/accounts/trial-summary", "/v1/onboarding/access-packages",
        "/v1/workspace", "/v1/exclusive-node-leases",
      ]
    /// Desired assignments and service deployments are read by `Deployments`
    /// and `Catalog` and by nothing else. Assignments are the only source of
    /// the deployment rows, so they travel with the pages that list them.
    DeploymentReads => ["/v1/assignments", "/v1/service-deployments"]
    ContractReads =>
      [
        "/v1/contract-documents/manifest/catalog", "/v1/contract-documents/operator/snapshot",
      ]
    CommerceReads =>
      if commercial_organization == "" {
        [
          "/v1/portal/operator/snapshot", "/v1/offline-commerce/operator/snapshot",
          "/v1/offline-commerce/operator/readiness",
        ]
      } else {
        [
          "/v1/portal/operator/snapshot",
          "/v1/offline-commerce/operator/snapshot",
          "/v1/offline-commerce/operator/readiness",
          "/v1/commercial/organizations/\{commercial_organization}/snapshot",
          "/v1/commercial/organizations/\{commercial_organization}/integrations",
        ]
      }
  }
}

///|
/// Warm the read cache for one operator load. Paths must match the ones the
/// load path requests so every lookup hits the cache exactly once: the always
/// loaded core reads plus the group owned by the route being opened.
fn prefetch_console_reads(
  endpoint : String,
  token : String,
  route : @ui.OperatorRoute,
  commercial_organization : String,
) -> Unit {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  let paths = [
    "/v1/nodes", "/v1/storage-nodes", "/v1/registry", "/v1/scheduler", "/v1/telemetry",
    "/v1/catalog/templates",
  ]
  match console_read_group_for_route(route) {
    Some(group) =>
      for path in console_read_group_paths(group, commercial_organization) {
        paths.push(path)
      }
    None => ()
  }
  prefetch_get(
    FixedArray::from_array([ for path in paths => "\{base}\{path}" ]),
    token,
  )
}

///|

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
  let url = "\{base}\{path}"
  let value = if verb == "GET" {
    get_promise(url, token).wait()
  } else {
    request_promise(verb, url, token, subject_ref, body).wait()
  }
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
fn total_memory(heartbeat : @contracts.NodeHeartbeat) -> Int {
  let mut total = 0
  for device in heartbeat.inventory.accelerators {
    total += device.memory_total_mib
  }
  total
}

///|
/// The newest value the node reported for one metric, or `None` when it never
/// reported it at all. A measured zero is a real reading for a rate such as CPU
/// busy share, so presence stays distinct from the value.
fn latest_node_metric_value(
  samples : Array[@contracts.TelemetrySample],
  node_id : String,
  metric : String,
) -> Int? {
  latest_node_sensor_value(samples, node_id, metric).map(value => value.to_int())
}

///|
fn latest_node_sensor_value(
  samples : Array[@contracts.TelemetrySample],
  node_id : String,
  metric : String,
) -> Double? {
  let mut latest_timestamp = 0L
  let mut value : Double? = None
  let now = current_unix_ms()
  for sample in samples {
    if sample.node_id == node_id &&
      sample.deployment_id == "" &&
      sample.metric == metric &&
      sample.timestamp_unix_ms <= now + 5000L &&
      now - sample.timestamp_unix_ms < node_heartbeat_stale_ms &&
      sample.timestamp_unix_ms >= latest_timestamp {
      latest_timestamp = sample.timestamp_unix_ms
      value = Some(sample.value)
    }
  }
  value
}

///|
fn latest_node_metric(
  samples : Array[@contracts.TelemetrySample],
  node_id : String,
  metric : String,
) -> Int {
  latest_node_metric_value(samples, node_id, metric).unwrap_or(-1)
}

///|
/// One node liveness threshold for node state, the deployment reachability
/// filter, and the last-seen label. It must match the controller's
/// `control_timing.heartbeat_timeout_ms`, which this console binds to.
let node_heartbeat_stale_ms : Int64 = 60000L

///|
fn heartbeat_age_label(locale : @i18n.Locale, age_ms : Int64) -> String {
  if age_ms < node_heartbeat_stale_ms {
    if locale.is_chinese() {
      "刚刚"
    } else {
      "Just now"
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
    None =>
      return if locale.is_chinese() {
        "尚未读取租约"
      } else {
        "Lease not loaded"
      }
  }
  if locale.is_chinese() {
    "未分配"
  } else {
    "Unassigned"
  }
}

///|
fn build_node_rows(
  heartbeats : Array[@contracts.NodeHeartbeat],
  telemetry : ConsoleTelemetrySnapshot,
  portal_snapshot : @portal.PortalSnapshot?,
  locale : @i18n.Locale,
) -> Array[@ui.NodeRow] {
  let now = current_unix_ms()
  [
    for heartbeat in heartbeats => {
      // Memory is read as a pair: a total and a used figure from different
      // pools would make the derived free and percentage meaningless, so the
      // earlier source is used whole or not at all.
      let host_total = latest_node_metric_value(
        telemetry.samples,
        heartbeat.node_id,
        "host_memory_total_mib",
      )
      let host_used = latest_node_metric_value(
        telemetry.samples,
        heartbeat.node_id,
        "host_memory_used_mib",
      )
      let accelerator_total = latest_node_metric_value(
        telemetry.samples,
        heartbeat.node_id,
        "accelerator_memory_total_mib",
      )
      let accelerator_used = latest_node_metric_value(
        telemetry.samples,
        heartbeat.node_id,
        "accelerator_memory_used_mib",
      )
      // Measured memory wins over the declared inventory, and host memory wins
      // over accelerator telemetry: on a unified-memory node the accelerator
      // reports no memory of its own and the host figure is the whole pool. A
      // node that measured neither keeps the declared capacity as its total and
      // is flagged unmeasured, so the console can say so instead of printing 0.
      let host_measured = host_total is Some(_) && host_used is Some(_)
      let accelerator_measured = accelerator_total is Some(_) &&
        accelerator_used is Some(_)
      let memory_measured = host_measured || accelerator_measured
      let measured_total = if host_measured {
        host_total
      } else {
        accelerator_total
      }
      let measured_used = if host_measured {
        host_used
      } else {
        accelerator_used
      }
      let total_memory_mib = measured_total.unwrap_or(total_memory(heartbeat))
      let used_memory_mib = measured_used.unwrap_or(0)
      let cpu = latest_node_metric_value(
        telemetry.samples,
        heartbeat.node_id,
        "host_cpu_utilization_per_mille",
      )
      let assignments = heartbeat.running_deployments.join(", ")
      {
        node_id: heartbeat.node_id,
        state: if now - heartbeat.timestamp_unix_ms > node_heartbeat_stale_ms {
          Unreachable
        } else {
          heartbeat.state
        },
        architecture: architecture(heartbeat),
        total_memory_mib,
        free_memory_mib: (total_memory_mib - used_memory_mib).max(0),
        used_memory_mib,
        memory_measured,
        utilization_per_mille: latest_node_metric(
          telemetry.samples,
          heartbeat.node_id,
          "accelerator_utilization_per_mille",
        ),
        cpu_per_mille: cpu.unwrap_or(0),
        cpu_measured: cpu is Some(_),
        temperature_celsius: latest_node_metric(
          telemetry.samples,
          heartbeat.node_id,
          "accelerator_temperature_celsius",
        ),
        power_watts: latest_node_sensor_value(
          telemetry.samples,
          heartbeat.node_id,
          "accelerator_power_watts",
        ).unwrap_or(-1.0),
        workloads: heartbeat.running_deployments.length(),
        lease_holder: portal_lease_holder(
          locale,
          portal_snapshot,
          heartbeat.node_id,
        ),
        active_assignment: if assignments == "" {
          if locale.is_chinese() {
            "无控制器托管部署（不代表机器空闲）"
          } else {
            "No controller-managed deployments (not machine idle)"
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
/// Add a freshly registered template to the catalog, replacing the revision it
/// supersedes. A template is immutable, so a re-registration only ever answers
/// a conflict; this keeps one row per template and version either way.
fn append_catalog_template(
  templates : Array[@deployment.ModelServiceTemplate],
  accepted : @deployment.ModelServiceTemplate,
) -> Array[@deployment.ModelServiceTemplate] {
  let key = catalog_template_key(accepted)
  let next = templates.filter(template => catalog_template_key(template) != key)
  next.push(accepted)
  next
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
    template: { template_id: template.template_id, version: template.version, },
    replicas: 1,
    data_class: template.data_policy.classification,
    lease_duration_ms: 86400000L,
    promote_when_ready: false,
    topology_profile: state.quick_topology.topology_profile(),
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
/// The control plane encodes absent optional fields as explicit `null`, while
/// MoonBit's derived `Option` decoder accepts only an absent key. Drop null
/// object entries before decoding so both encodings agree.

///|
/// True when the tree contains any `null`, so payloads without one keep their
/// parsed form and skip the rebuild below entirely.
fn json_contains_null(value : Json) -> Bool {
  match value {
    Null => true
    Array(items) => items.any(json_contains_null)
    Object(entries) => entries.values().any(json_contains_null)
    _ => false
  }
}

///|
fn parse_console_json(text : String) -> Json raise {
  let parsed = @json.parse(text)
  if !json_contains_null(parsed) {
    return parsed
  }
  let replacer = @json.Replacer((_, value) => {
    match value {
      Null => None
      _ => Some(value)
    }
  })
  parsed.transform(replacer)
}

///|

///|
/// The always-loaded core read set. Page-scoped reads (audit, contract
/// documents, commerce and portal snapshots) are loaded by the read group that
/// owns them, the first time their route is opened.
async fn load_console(
  endpoint : String,
  token : String,
  commercial_organization : String,
  route : @ui.OperatorRoute,
  locale : @i18n.Locale,
) -> @ui.ConsoleState {
  prefetch_console_reads(endpoint, token, route, commercial_organization)
  let production_readiness = load_production_readiness(endpoint, token)
  let heartbeats : Array[@contracts.NodeHeartbeat] = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/nodes", token)),
  )
  let storage_nodes : Array[@ui.StorageNodeRow] = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/storage-nodes", token)),
  )
  let registry : @contracts.RegistryReadContract = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/registry", token)),
  )
  let scheduler : @contracts.SchedulerReadContract = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/scheduler", token)),
  )
  let telemetry : ConsoleTelemetrySnapshot = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/telemetry", token)),
  )
  let authenticated_account : @ui.AccountView? = if token.has_prefix("lnxs_") {
    Some(
      @json.from_json(
        parse_console_json(request("GET", endpoint, "/v1/auth/self", token)),
      ),
    )
  } else {
    None
  }
  let account_sessions : Array[@ui.BrowserSessionView] = if token.has_prefix(
      "lnxs_",
    ) {
    @json.from_json(
      parse_console_json(request("GET", endpoint, "/v1/auth/sessions", token)),
    )
  } else {
    []
  }
  let catalog_templates : Array[@deployment.ModelServiceTemplate] = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/catalog/templates", token)),
  )
  // The operator alert list and its delivery outbox are the alerts read group;
  // at ~137 KB they dominate the core read set and are only needed by the
  // `Alerts` page. The modelscope import list belongs to the models read group
  // because its source service can be slow or down without the console being
  // unusable. The accounts, sessions, access packages, workspace directory, and
  // exclusive node leases are the access read group, and the assignments,
  // service deployments, and deployment rows are the deployment read group;
  // both are read by `load_console_group_reads` when the operator opens a route
  // that needs them, so the first paint only waits on the core read set above.
  let nodes = build_node_rows(heartbeats, telemetry, None, locale)
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
        license_id: model.license_id,
        artifact_uri: model.artifact.uri,
        artifact_digest: model.artifact.digest,
      }
    }
  ]
  let active_nodes = nodes.count_if(node => node.state == Active)
  // The overview claims an alert count, so it must actually read the evidence.
  let alerts = load_console_alerts_reads(endpoint, token)
  // Accounts, trial statistics, access packages, workspace users, access
  // grants, compute leases, and exclusive node leases are built by the access
  // read group; deployments and service deployments are built by the deployment
  // read group. Cost centers, agreements, qualified services, and portal lease
  // requests are built by the commerce read group.
  {
    locale,
    route,
    overview: {
      active_nodes,
      total_nodes: heartbeats.length(),
      active_models: models.count_if(model => model.state == Approved),
      queue_depth: scheduler.queued_count.unwrap_or(scheduler.active.length()),
      alerts: alerts.notifications.count_if(record => {
        record.lifecycle != Resolved
      }),
      recent_changes: -1,
    },
    nodes,
    storage_nodes,
    models,
    // Owned by the deployment read group.
    deployments: [],
    catalog_templates,
    service_deployments: [],
    requests: {
      count: 0,
      p95_ms: telemetry.benchmark_summaries
      .last()
      .map(summary => summary.latency_p95_ms)
      .unwrap_or(0),
      throughput_per_second: telemetry.benchmark_summaries
      .last()
      .map(summary => summary.throughput_units_per_second)
      .unwrap_or(0),
      errors: 0,
    },
    request_details: [],
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
    audit: [],
    notifications: alerts.notifications,
    notification_deliveries: alerts.notification_deliveries,
    // Owned by the access read group.
    accounts: [],
    trial_summary: None,
    announcement_draft: @ui.empty_announcement_draft(),
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
    access_package_draft: {
      identity_issuer: authenticated_account
      .map(account => account.identity_issuer)
      .unwrap_or(""),
      identity_subject: "",
      display_name: "",
      email: "",
      organization_id: commercial_organization,
      tenant_ref: "",
      lifetime_days: 30,
      identity_verified: false,
    },
    access_packages: [],
    users: [],
    pending_organizations: [],
    access_grants: [],
    compute_leases: [],
    exclusive_node_leases: [],
    resource_delivery: @ui.default_resource_delivery_panel(),
    cost_centers: [],
    agreements: [],
    enterprise_lease_requests: [],
    portal_node_id: "",
    qualified_services: [],
    offline_commerce: @offline_commerce.default_state(locale, OperatorCommerce),
    contract_documents: @contract_documents.default_state(
      locale,
      actor_owner=ManagerOperator,
    ),
    production_readiness,
    confirmation: None,
    error_message: None,
    success_message: None,
    loading: false,
    operator_authenticated: true,
    model_source_query: "MiniCPM",
    model_source_results: [],
    model_source_total: 0L,
    model_imports: [],
    model_adoption_draft: {
      import_id: "",
      model_id: "",
      version: "",
      license_id: "",
      compatible_architectures: "",
      minimum_memory_mib: "",
    },
    model_adopted_imports: [],
    model_local_directories: [],
    model_local_draft: { directory: "", repository: "", revision: "master", },
    model_license_draft: @ui.empty_model_license_draft(),
    model_alias_draft: @ui.empty_model_alias_draft(),
    runtime_draft: @ui.default_runtime_draft(),
    template_draft: @ui.empty_template_draft(),
    registered_runtimes: registry.runtimes,
    operation_name: "register-model",
    operation_body: "",
    quick_deployment_id: "",
    quick_template: catalog_templates
    .get(0)
    .map(catalog_template_key)
    .unwrap_or(""),
    quick_topology: SingleMachine,
  }
}

///|
/// The read group a route depends on. Routes that are served completely by the
/// core read set have none.
///
/// Overview reads alert evidence in the core load; Alerts additionally refreshes
/// its own list when opened. A missing request must never imply zero alerts.
fn console_read_group_for_route(route : @ui.OperatorRoute) -> ConsoleReadGroup? {
  match route {
    Alerts => Some(AlertsReads)
    // The import/adoption surfaces only live on this page.
    Models => Some(ModelsReads)
    Catalog | Deployments => Some(DeploymentReads)
    Users | Leases => Some(AccessReads)
    Audit | Requests => Some(AuditReads)
    ContractDocuments => Some(ContractReads)
    CostCenters | Agreements | QualifiedServices | OfflineCommerce =>
      Some(CommerceReads)
    _ => None
  }
}

///|
/// The read group a route still needs, or `None` when its read is already
/// scheduled, already merged, or owned by the read-only demo snapshot.
fn deferred_read_pending(
  model : AppModel,
  route : @ui.OperatorRoute,
) -> ConsoleReadGroup? {
  if model.demo_mode || !model.console.operator_authenticated {
    None
  } else {
    match console_read_group_for_route(route) {
      Some(group) =>
        if model.console_read_groups.contains(group) {
          None
        } else {
          Some(group)
        }
      None => None
    }
  }
}

///|
/// Schedule the deferred read a route needs, exactly once per group.
fn schedule_deferred_reads(
  model : AppModel,
  route : @ui.OperatorRoute,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  match deferred_read_pending(model, route) {
    Some(group) => {
      let groups = model.console_read_groups.copy()
      groups.set(group, false)
      (
        { ..model, console_read_groups: groups, },
        deferred_read_command(model, group, emit),
      )
    }
    None => (model, @rabbita.none)
  }
}

///|
fn deferred_read_command(
  model : AppModel,
  group : ConsoleReadGroup,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let endpoint = model.endpoint
  let token = model.credential
  let audit_token = model.audit_credential
  let organization = model.commercial_organization
  let locale = model.console.locale
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try
      DeferredReadLoaded(
        locale,
        group,
        load_console_group_reads(
          endpoint, token, audit_token, organization, locale, group,
        ),
      )
    catch {
      _ => DeferredReadFailed(group)
    } noraise {
      value => value
    }
  })
}

///|
/// Everything the audit read group contributes to the typed state.
priv struct AuditReadPayload {
  rows : Array[@ui.AuditRow]
  request_details : Array[@ui.RequestDetail]
  request_count : Int
  request_errors : Int
  recent_changes : Int
}

///|
/// The alerts read group's slice of the console state. The operator alert list
/// and its delivery outbox are the largest core-shaped reads (~137 KB in the
/// measured deployment), so they belong to the page that shows them.
priv struct AlertsReadPayload {
  notifications : Array[@ui.NotificationRow]
  notification_deliveries : Array[@ui.NotificationDeliveryRow]
}

///|
/// The model-import read group's slice of the console state. The modelscope
/// import list is served by the model-source service, which is allowed to be
/// slow or down without delaying the first paint.
priv struct ModelImportReadPayload {
  imports : Array[@ui.ModelImportRow]
}

///|
/// The access read group's slice of the console state. Accounts, sessions,
/// access packages, and the workspace directory are read by the `Users` and
/// `Leases` pages and by nothing else.
priv struct AccessReadPayload {
  accounts : Array[@ui.AccountView]
  pending_organizations : Array[@ui.PendingOrganizationRow]
  trial_summary : @ui.TrialSummary?
  access_packages : Array[@ui.AccessPackageView]
  users : Array[@ui.UserAccessRow]
  access_grants : Array[@ui.AccessGrantRow]
  compute_leases : Array[@ui.ComputeLeaseRow]
  exclusive_node_leases : Array[@ui.ExclusiveNodeLeaseRow]
}

///|
/// The deployment read group's slice of the console state. Assignments are the
/// only source of the deployment rows and are read by the `Catalog` and
/// `Deployments` pages and by nothing else. Each row's `observed` state
/// compares the assignment with the node heartbeats, so the loader reads
/// `/v1/nodes` itself instead of approximating the flag from the core read set.
priv struct DeploymentReadPayload {
  deployments : Array[@ui.DeploymentRow]
  service_deployments : Array[@deployment.DeploymentOperation]
}

///|
/// The contract read group's slice of the console state.
priv struct ContractReadPayload {
  documents : @contract_documents.ContractDocumentsState
}

///|
/// The commerce read group's slice of the console state. `node_lease_holders`
/// carries the portal projection of each node's current lessee so the node
/// table can show it without holding the whole portal snapshot.
priv struct CommerceReadPayload {
  cost_centers : Array[@ui.CostCenterRow]
  agreements : Array[@ui.AgreementRow]
  qualified_services : Array[@ui.QualifiedServiceRow]
  enterprise_lease_requests : Array[@ui.EnterpriseLeaseRequestRow]
  offline_commerce : @offline_commerce.OfflineCommerceState
  node_lease_holders : Array[(String, String)]
}

///|
priv enum ConsoleGroupRead {
  GroupAlerts(AlertsReadPayload)
  GroupModels(ModelImportReadPayload)
  GroupAudit(AuditReadPayload)
  GroupAccess(AccessReadPayload)
  GroupDeployment(DeploymentReadPayload)
  GroupContracts(ContractReadPayload)
  GroupCommerce(CommerceReadPayload)
}

///|
/// Fetch one page-scoped read group. The core read set is not touched, so a
/// group load stays as small as the page it belongs to.
async fn load_console_group_reads(
  endpoint : String,
  token : String,
  audit_token : String,
  commercial_organization : String,
  locale : @i18n.Locale,
  group : ConsoleReadGroup,
) -> ConsoleGroupRead {
  match group {
    AlertsReads => GroupAlerts(load_console_alerts_reads(endpoint, token))
    ModelsReads => GroupModels(load_console_models_reads(endpoint, token))
    AuditReads => GroupAudit(load_console_audit_reads(endpoint, audit_token))
    AccessReads => GroupAccess(load_console_access_reads(endpoint, token))
    DeploymentReads =>
      GroupDeployment(load_console_deployment_reads(endpoint, token))
    ContractReads =>
      GroupContracts(
        load_console_contract_reads(
          endpoint, token, commercial_organization, locale,
        ),
      )
    CommerceReads =>
      GroupCommerce(
        load_console_commerce_reads(
          endpoint, token, commercial_organization, locale,
        ),
      )
  }
}

///|
async fn load_console_models_reads(
  endpoint : String,
  token : String,
) -> ModelImportReadPayload {
  {
    imports: @json.from_json(
      parse_console_json(
        request("GET", endpoint, "/v1/model-sources/modelscope/imports", token),
      ),
    ) catch {
      // Compatibility with controllers that predate the modelscope import
      // route: the import list is supplemental, so an unreachable or older
      // source service renders as an empty list instead of failing the page.
      _ => []
    },
  }
}

///|
async fn load_console_alerts_reads(
  endpoint : String,
  token : String,
) -> AlertsReadPayload {
  let notification_records : Array[@notifications.NotificationRecord] = @json.from_json(
    parse_console_json(
      request("GET", endpoint, "/v1/notifications/operator", token),
    ),
  )
  let notification_delivery_records : Array[@notifications.NotificationDelivery] = @json.from_json(
    parse_console_json(
      request("GET", endpoint, "/v1/notifications/operator/deliveries", token),
    ),
  ) catch {
    // Compatibility with the immediately preceding controller release, which
    // has notification records but not the operator delivery-list route.
    // Treating only this supplemental view as empty keeps authentication and
    // the rest of the console usable while the controller is upgraded.
    _ => []
  }
  {
    notifications: [
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
    ],
    notification_deliveries: [
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
    ],
  }
}

///|
async fn load_console_access_reads(
  endpoint : String,
  token : String,
) -> AccessReadPayload {
  let workspace : @workspace.WorkspaceDirectorySnapshot = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/workspace", token)),
  )
  let accounts : Array[@ui.AccountView] = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/accounts", token)),
  )
  let organizations : Array[@commercial.Organization] = @json.from_json(
    parse_console_json(
      request("GET", endpoint, "/v1/commercial/organizations/pending", token),
    ),
  )
  let trial_summary : @ui.TrialSummary? = Some(
    @json.from_json(
      parse_console_json(
        request("GET", endpoint, "/v1/accounts/trial-summary", token),
      ),
    ),
  ) catch {
    // Supplemental statistics are unavailable, never zero, on older controllers.
    _ => None
  }
  let access_packages : Array[@ui.AccessPackageView] = @json.from_json(
    parse_console_json(
      request("GET", endpoint, "/v1/onboarding/access-packages", token),
    ),
  )
  let exclusive_leases : Array[@nodelease.ExclusiveNodeLease] = @json.from_json(
    parse_console_json(
      request("GET", endpoint, "/v1/exclusive-node-leases", token),
    ),
  )
  let pending_organizations : Array[@ui.PendingOrganizationRow] = []
  for organization in organizations {
    match organization.legal_profile {
      Some(profile) =>
        pending_organizations.push({
          organization_id: organization.organization_id,
          display_name: organization.display_name,
          legal_name: profile.legal_name,
          country_code: profile.country_code,
          registration_number: profile.registration_number.unwrap_or(""),
          registered_address: profile.registered_address,
          contact_email: profile.billing_contact.email,
        })
      None => ()
    }
  }
  {
    accounts,
    pending_organizations,
    trial_summary,
    access_packages,
    users: [
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
    ],
    access_grants: [
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
    ],
    compute_leases: [
      for lease in workspace.leases => {
        {
          lease_id: lease.lease_id,
          user_id: workspace_user_id(workspace.users, lease.subject_ref),
          subject_ref: lease.subject_ref,
          workspace: lease.tenant_ref,
          resource: workspace_resource(lease.limits),
          started_at: format_unix_ms(lease.starts_unix_ms, "Unavailable"),
          expires_at: format_unix_ms(lease.expires_unix_ms, "Unavailable"),
          state: lease.state,
        }
      }
    ],
    exclusive_node_leases: [
      for lease in exclusive_leases => {
        {
          lease_id: lease.intent.lease_id,
          node_id: lease.intent.node_id,
          subject_ref: lease.intent.subject_ref,
          unix_username: lease.intent.unix_username,
          expires_at: format_unix_ms(
            lease.intent.expires_unix_ms,
            "Unavailable",
          ),
          state: "\{Repr(lease.state)}",
          generation: lease.generation,
        }
      }
    ],
  }
}

///|
async fn load_console_deployment_reads(
  endpoint : String,
  token : String,
) -> DeploymentReadPayload {
  // The heartbeats are part of the core read set, but the merge of a group read
  // only sees the state it returns. Reading `/v1/nodes` again here keeps each
  // row's `observed` flag a truthful comparison instead of an approximation.
  let heartbeats : Array[@contracts.NodeHeartbeat] = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/nodes", token)),
  )
  let assignments : Array[@contracts.DesiredAssignment] = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/assignments", token)),
  )
  let service_deployments : Array[@deployment.DeploymentOperation] = @json.from_json(
    parse_console_json(
      request("GET", endpoint, "/v1/service-deployments", token),
    ),
  )
  let now = current_unix_ms()
  {
    deployments: [
      for assignment in assignments => {
        let running = heartbeats.any(heartbeat => {
          heartbeat.node_id == assignment.node_id &&
          now - heartbeat.timestamp_unix_ms <= node_heartbeat_stale_ms &&
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
    ],
    service_deployments,
  }
}

///|
async fn load_console_audit_reads(
  endpoint : String,
  audit_token : String,
) -> AuditReadPayload {
  let audit : Array[@contracts.AuditEvent] = @json.from_json(
    parse_console_json(request("GET", endpoint, "/v1/audit", audit_token)),
  )
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
  {
    rows: [
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
    request_details,
    request_count: audit.count_if(event => event.action.has_prefix("workload.")),
    request_errors: audit.count_if(event => {
      event.action == "workload.fail" || event.result != "accepted"
    }),
    recent_changes: audit.length().min(20),
  }
}

///|
async fn load_console_contract_reads(
  endpoint : String,
  token : String,
  commercial_organization : String,
  locale : @i18n.Locale,
) -> ContractReadPayload {
  // The manifest is a public, versioned product artifact compiled into the
  // console. Using the same source of truth here also keeps the web client
  // compatible with controllers that expose it only to the customer portal.
  let contract_manifests : Array[@contractdoc.ContractTemplateManifest] = @json.from_json(
    parse_console_json(
      request("GET", endpoint, "/v1/contract-documents/manifest/catalog", token),
    ),
  )
  let contract_snapshot : @contractdoc.ContractDocumentSnapshot = @json.from_json(
    parse_console_json(
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
            parse_console_json(
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
  {
    documents: {
      ..@contract_documents.default_state(locale, actor_owner=ManagerOperator),
      manifest: contract_manifests.get(0),
      available_manifests: contract_manifests,
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
  }
}

///|
async fn load_console_commerce_reads(
  endpoint : String,
  token : String,
  commercial_organization : String,
  locale : @i18n.Locale,
) -> CommerceReadPayload {
  // This snapshot carries release and fulfillment authority. Loading failures
  // must be visible and must never masquerade as an empty commerce queue.
  let offline_snapshot : @offline.OfflineCommerceSnapshot = @json.from_json(
    parse_console_json(
      request("GET", endpoint, "/v1/offline-commerce/operator/snapshot", token),
    ),
  )
  // The production-readiness document is signed out of band and read-only.
  // Like the snapshot above it is fail-loud: a failed read must surface rather
  // than masquerade as "no readiness document is configured".
  let offline_readiness : @offline.OfflineCommerceReadiness = @json.from_json(
    parse_console_json(
      request("GET", endpoint, "/v1/offline-commerce/operator/readiness", token),
    ),
  )
  let technical_read = parse_console_json(
    request(
      "GET", endpoint, "/v1/offline-commerce/operator/technical-acceptance-authorization",
      token,
    ),
  )
  let technical_scopes : Array[@offline.TechnicalAcceptanceAuthorization] = match
    technical_read {
    { "authorizations": values, .. } => @json.from_json(values)
    _ => fail("invalid technical authorization read model")
  }
  let prepared_targets : Array[TechnicalPreparedTarget] = match technical_read {
    { "prepared_targets": values, .. } => @json.from_json(values)
    _ => []
  }
  let prepared_target = prepared_targets
    .iter()
    .find_first(t => {
      technical_scopes.any(s => s.order_id == t.order_id) &&
      t.expires_unix_ms > current_unix_ms()
    })
  let portal_snapshot : @portal.PortalSnapshot? = try
    Some(
      @json.from_json(
        parse_console_json(
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
        parse_console_json(
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
        parse_console_json(
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
    cost_centers,
    agreements,
    qualified_services,
    enterprise_lease_requests,
    offline_commerce: {
      ..@offline_commerce.default_state(locale, OperatorCommerce),
      orders: offline_snapshot.orders,
      technical_authorization: technical_scopes.get(0),
      technical_target_ref: prepared_target.map_or("", t => {
        t.authority_target_ref
      }),
      technical_grant_id: prepared_target.map_or("", t => t.grant_id),
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
      readiness_status: offline_readiness.status,
      readiness_capabilities: offline_readiness.capabilities,
      readiness_blocker_codes: offline_readiness.blocker_codes,
    },
    node_lease_holders: portal_node_lease_holders(portal_snapshot),
  }
}

///|
/// Node id to lessee label, projected from the portal snapshot the commerce
/// read group just fetched.
fn portal_node_lease_holders(
  snapshot : @portal.PortalSnapshot?,
) -> Array[(String, String)] {
  let holders : Array[(String, String)] = []
  match snapshot {
    Some(value) =>
      for request in value.lease_requests {
        match request.assigned_node_id {
          Some(node_id) =>
            if request.state == Approved {
              holders.push(
                (
                  node_id,
                  "\{request.submission.organization_id} · \{request.submission.unix_username}",
                ),
              )
            }
          None => ()
        }
      }
    None => ()
  }
  holders
}

///|
/// Apply freshly read lessee labels to the node rows already on screen. Every
/// other node field is left untouched.
fn node_rows_with_lease_holders(
  locale : @i18n.Locale,
  rows : Array[@ui.NodeRow],
  holders : Array[(String, String)],
) -> Array[@ui.NodeRow] {
  rows.map(row => {
    let holder = holders
      .iter()
      .find_first(entry => entry.0 == row.node_id)
      .map(entry => entry.1)
    let lease_holder = match holder {
      Some(value) => value
      None => if locale.is_chinese() { "未分配" } else { "Unassigned" }
    }
    { ..row, lease_holder, }
  })
}

///|
/// Merge one deferred read into the console state. Only the fields owned by
/// that read group change; every other field is carried over untouched. A
/// counter that is a direct projection of the group's own rows (the open-alert
/// count, the per-node lessee label) is refreshed with them, because nothing
/// else can recompute it.
fn merge_console_group_read(
  current : @ui.ConsoleState,
  read : ConsoleGroupRead,
) -> @ui.ConsoleState {
  match read {
    GroupAlerts(payload) =>
      {
        ..current,
        notifications: payload.notifications,
        notification_deliveries: payload.notification_deliveries,
        overview: {
          ..current.overview,
          alerts: payload.notifications.count_if(notification => {
            notification.lifecycle != Resolved
          }),
        },
      }
    GroupModels(payload) => { ..current, model_imports: payload.imports, }
    GroupAudit(payload) =>
      {
        ..current,
        audit: payload.rows,
        request_details: payload.request_details,
        requests: {
          ..current.requests,
          count: payload.request_count,
          errors: payload.request_errors,
        },
        overview: {
          ..current.overview,
          recent_changes: payload.recent_changes,
        },
      }
    GroupAccess(payload) =>
      {
        ..current,
        accounts: payload.accounts,
        pending_organizations: payload.pending_organizations,
        trial_summary: payload.trial_summary,
        access_packages: payload.access_packages,
        users: payload.users,
        access_grants: payload.access_grants,
        compute_leases: payload.compute_leases,
        exclusive_node_leases: payload.exclusive_node_leases,
      }
    GroupDeployment(payload) =>
      {
        ..current,
        deployments: payload.deployments,
        service_deployments: payload.service_deployments,
      }
    GroupContracts(payload) =>
      {
        ..current,
        contract_documents: {
          ..payload.documents,
          locale: current.locale,
          selected_tenant_ref: current.contract_documents.selected_tenant_ref,
          search_query: current.contract_documents.search_query,
          selected_packet_id: if current.contract_documents.selected_packet_id
            is None {
            payload.documents.selected_packet_id
          } else {
            current.contract_documents.selected_packet_id
          },
          selected_form: if current.contract_documents.selected_form is None {
            payload.documents.selected_form
          } else {
            current.contract_documents.selected_form
          },
          preview: current.contract_documents.preview,
        },
      }
    GroupCommerce(payload) =>
      {
        ..current,
        cost_centers: payload.cost_centers,
        agreements: payload.agreements,
        qualified_services: payload.qualified_services,
        enterprise_lease_requests: payload.enterprise_lease_requests,
        offline_commerce: {
          ..payload.offline_commerce,
          locale: current.locale,
          selected_order_id: match current.offline_commerce.selected_order_id {
            Some(id) if payload.offline_commerce.orders.any(order => {
                order.order_id == id
              }) => Some(id)
            _ => payload.offline_commerce.selected_order_id
          },
          operator_actor_ref: current.offline_commerce.operator_actor_ref,
          quote_minor_units: current.offline_commerce.quote_minor_units,
          terms_digest: current.offline_commerce.terms_digest,
          entitlement_ref: current.offline_commerce.entitlement_ref,
        },
        nodes: node_rows_with_lease_holders(
          current.locale,
          current.nodes,
          payload.node_lease_holders,
        ),
      }
  }
}

///|
priv enum LoadOutcome {
  Loaded(@ui.ConsoleState)
  LoadFailed(@i18n.Locale, String)
  ActionComplete(@i18n.Locale, String)
  LocalCopyComplete(Bool)
  ModelSourceSearchLoaded(@i18n.Locale, @ui.ModelSourceCatalogPage)
  ModelImportsLoaded(@i18n.Locale, Array[@ui.ModelImportRow], String?)
  ModelLocalDirectoriesLoaded(@i18n.Locale, Array[@ui.ModelLocalDirectoryRow])
  ModelImportsPolled(Int64, Array[@ui.ModelImportRow])
  ModelImportPollFailed(Int64, @i18n.Locale)
  ClusterPolled(Int64, Array[@ui.NodeRow], Array[@ui.StorageNodeRow])
  ClusterPollFailed(Int64, Bool)
  DeferredReadLoaded(@i18n.Locale, ConsoleReadGroup, ConsoleGroupRead)
  DeferredReadFailed(ConsoleReadGroup)
  ModelAdopted(@i18n.Locale, String, String)
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
  /// The signed template the control plane returned, so the picker offers it
  /// without a second read.
  TemplateRegistered(@deployment.ModelServiceTemplate)
}

///|
/// Page-scoped operator reads. The first paint loads only the core read set;
/// each group is fetched the first time a route that needs it is opened.
priv enum ConsoleReadGroup {
  AlertsReads
  ModelsReads
  AuditReads
  AccessReads
  DeploymentReads
  ContractReads
  CommerceReads
} derive(Eq, Hash)

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
  alerts_window : @ui.AlertsWindow
  console : @ui.ConsoleState
  /// Read groups already scheduled or merged. A key is absent until a route
  /// needs the group, `false` while its read is in flight, and `true` once its
  /// fields were merged. A failed read removes the key so the next visit
  /// retries it.
  console_read_groups : Map[ConsoleReadGroup, Bool]
  next_directive_generation : Int64
  contract_preview_generation : Int64
  model_import_poll_generation : Int64
  cluster_poll_generation : Int64
  /// The operator login draft. The password stays in memory only: it is sent
  /// to the same-origin gateway and never written to a URL or browser storage.
  login_username : String
  personal_login : Bool
  login_password : String
} derive(Eq)

///|
priv enum AppMessage {
  ResourcesLoaded(String, Result[@ui.ResourceDeliveryPanel, String])
  GatewaySessionLoaded(GatewayBrowserSession)
  GatewaySessionUnavailable
  AccountSessionChanged(String)
  CredentialChanged(String)
  AuditCredentialChanged(String)
  InferenceCredentialChanged(String)
  InferenceSubjectChanged(String)
  CommercialOrganizationChanged(String)
  LoginUsernameChanged(String)
  PersonalLoginRequested
  LoginPasswordChanged(String)
  OperatorLoginSubmitted
  OperatorLoginRefused(@i18n.Locale, String)
  Connect
  Logout
  SessionLogoutFinished
  Console(@ui.ConsoleMessage)
  ContractPreviewDue(Int64, @contract_documents.ContractDocumentsMessage)
  ModelImportPollDue(Int64)
  ClusterPollDue(Int64)
  Outcome(LoadOutcome)
}

///|
/// Keep the lessee each node already displayed. The core read set does not
/// carry the portal snapshot, so a rebuilt node row would otherwise fall back
/// to "unassigned".
fn preserve_node_lease_holders(
  current : Array[@ui.NodeRow],
  refreshed : Array[@ui.NodeRow],
) -> Array[@ui.NodeRow] {
  refreshed.map(row => {
    ..row,
    lease_holder: current
    .iter()
    .find_first(existing => existing.node_id == row.node_id)
    .map(existing => existing.lease_holder)
    .unwrap_or(row.lease_holder),
  })
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
    // The import list is owned by a deferred read group, so a core reload must
    // keep the rows the group already merged.
    model_imports: current.model_imports,
    model_adoption_draft: current.model_adoption_draft,
    model_adopted_imports: current.model_adopted_imports,
    model_local_directories: current.model_local_directories,
    model_local_draft: current.model_local_draft,
    // The per-candidate onboarding drafts and the runtime registration form are
    // UI-owned: a reload must not erase what the operator is editing.
    model_license_draft: current.model_license_draft,
    model_alias_draft: current.model_alias_draft,
    runtime_draft: current.runtime_draft,
    template_draft: current.template_draft,
    operation_name: current.operation_name,
    operation_body: current.operation_body,
    access_package_draft: {
      ..current.access_package_draft,
      identity_issuer: if current.access_package_draft.identity_issuer == "" {
        loaded.access_package_draft.identity_issuer
      } else {
        current.access_package_draft.identity_issuer
      },
      organization_id: if current.access_package_draft.organization_id == "" {
        loaded.access_package_draft.organization_id
      } else {
        current.access_package_draft.organization_id
      },
    },
    quick_deployment_id: current.quick_deployment_id,
    quick_template: if current.quick_template == "" {
      loaded.quick_template
    } else {
      current.quick_template
    },
    quick_topology: current.quick_topology,
    portal_node_id: current.portal_node_id,
    // Deferred, page-scoped reads own these fields. A core reload must not
    // erase a group that was already merged.
    audit: current.audit,
    request_details: current.request_details,
    requests: {
      ..loaded.requests,
      count: current.requests.count,
      errors: current.requests.errors,
    },
    overview: {
      ..loaded.overview,
      alerts: loaded.overview.alerts,
      recent_changes: if current.operator_authenticated {
        current.overview.recent_changes
      } else {
        loaded.overview.recent_changes
      },
    },
    notifications: loaded.notifications,
    notification_deliveries: loaded.notification_deliveries,
    accounts: current.accounts,
    trial_summary: current.trial_summary,
    access_packages: current.access_packages,
    users: current.users,
    pending_organizations: current.pending_organizations,
    access_grants: current.access_grants,
    compute_leases: current.compute_leases,
    exclusive_node_leases: current.exclusive_node_leases,
    resource_delivery: current.resource_delivery,
    deployments: current.deployments,
    service_deployments: current.service_deployments,
    cost_centers: current.cost_centers,
    agreements: current.agreements,
    qualified_services: current.qualified_services,
    enterprise_lease_requests: current.enterprise_lease_requests,
    nodes: preserve_node_lease_holders(current.nodes, loaded.nodes),
    storage_nodes: loaded.storage_nodes,
    offline_commerce: { ..current.offline_commerce, locale: current.locale, },
    contract_documents: {
      ..current.contract_documents,
      locale: current.locale,
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
  { ..model, console: switch_console_locale(model.console, locale), }
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
            "Offline commercial action failed: \{http_failure_detail(error)}",
            "线下商务操作失败：\{http_failure_detail(error)}",
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
        body=ContractInformationUpdate::{
            expected_revision: revision,
            changes,
          }
          .to_json()
          .stringify(),
      )
      let updated : @contractdoc.ContractPacket = @json.from_json(
        @json.parse(response),
      )
      ContractPacketUpdated(updated)
    } catch {
      error =>
        if http_status_is(error, 409) {
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
        if http_status_is(error, 409) {
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
        if http_status_is(error, 409) {
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
            { kind, reason, closed_by: "operator", closed_unix_ms: now, },
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
        let manifest = match
          model.console.contract_documents.current_manifest() {
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
                  "Demo contract lifecycle action was rejected: \{http_failure_detail(error)}",
                  "演示合同生命周期操作被拒绝：\{http_failure_detail(error)}",
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
      guard model.console.contract_documents.current_manifest()
        is Some(manifest) else {
        fail("contract manifest unavailable")
      }
      let text : String = demo_contract_preview_promise(manifest.template_id)
        .wait()
        .cast()
      let template : @contractdoc.ContractPreviewTemplate = @json.from_json(
        @json.parse(text),
      )
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
      { ..model, console: { ..model.console, contract_documents: documents, }, },
      @rabbita.none,
    )
  }
  let generation = model.contract_preview_generation + 1L
  let pending = documents.update(request)
  let next = {
    ..model,
    contract_preview_generation: generation,
    console: { ..model.console, contract_documents: pending, },
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
/// The gateway's refusal body. Its `error` code is the only thing the browser
/// is told, so the copy below is driven by that code and never by upstream text.
priv struct PasswordLoginError {
  error : String
} derive(FromJson)

///|
fn password_login_error_code(body : String) -> String {
  (@json.from_json(@json.parse(body)) : PasswordLoginError).error catch {
    _ => ""
  }
}

///|
fn password_login_refusal(
  locale : @i18n.Locale,
  outcome : PasswordLoginOutcome,
) -> String {
  match password_login_error_code(outcome.body) {
    "invalid-credentials" =>
      console_copy(
        locale, "The username or password was not accepted. Check both and try again.",
        "用户名或密码不正确，请检查后重试。",
      )
    "identity-rejected" =>
      console_copy(
        locale, "Signed in, but this identity cannot be used yet. Ask a platform administrator to enable the account.",
        "登录成功，但该身份暂时不可用。请联系平台管理员启用账户。",
      )
    "identity-provider-unavailable" =>
      console_copy(
        locale, "The identity provider is unavailable. Try again shortly.", "身份提供商当前不可用，请稍后重试。",
      )
    "too-many-attempts" =>
      console_copy(
        locale, "Too many failed attempts from this address. Wait five minutes and try again.",
        "此地址的失败尝试过多，请等待五分钟后再试。",
      )
    _ =>
      console_copy(
        locale, "The gateway refused the sign-in.", "网关拒绝了本次登录。",
      )
  }
}

///|
/// Exchange the operator's username and password for a gateway session. The
/// gateway is the only party that sees the identity provider's client secret;
/// what comes back is the same session document the OIDC callback produces, so
/// the rest of the console cannot tell the two paths apart.
fn operator_login_command(
  locale : @i18n.Locale,
  username : String,
  password : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(message => emit(message), async fn() noraise {
    try {
      let text : String = password_login_promise(username, password, "operator")
        .wait()
        .cast()
      let outcome : PasswordLoginOutcome = @json.from_json(@json.parse(text))
      if outcome.status != 200 {
        OperatorLoginRefused(locale, password_login_refusal(locale, outcome))
      } else {
        let session : GatewayBrowserSession = @json.from_json(
          @json.parse(outcome.body),
        )
        if session.session_token.has_prefix("lnxs_") &&
          session.csrf_token.trim() != "" &&
          session.expires_unix_ms > current_unix_ms() {
          GatewaySessionLoaded(session)
        } else {
          OperatorLoginRefused(
            locale,
            console_copy(
              locale, "The gateway accepted the sign-in but the session it returned is unusable.",
              "网关已接受登录，但返回的会话不可用。",
            ),
          )
        }
      }
    } catch {
      _ =>
        OperatorLoginRefused(
          locale,
          console_copy(
            locale, "The identity gateway could not be reached.", "无法连接身份网关。",
          ),
        )
    }
  })
}

///|
fn model_imports_active(imports : Array[@ui.ModelImportRow]) -> Bool {
  imports.any(value => value.state == Queued || value.state == Downloading)
}

///|
fn empty_model_adoption_draft() -> @ui.ModelAdoptionDraft {
  {
    import_id: "",
    model_id: "",
    version: "",
    license_id: "",
    compatible_architectures: "",
    minimum_memory_mib: "",
  }
}

///|
fn model_adoption_path(import_id : String) -> String {
  "/v1/model-sources/modelscope/imports/\{import_id}:adopt"
}

///|
/// The body of `POST /v1/licenses`. The control plane decodes this shape into
/// its own licence record; the console only owns the operator-supplied
/// identity and citation.
priv struct ConsoleLicenseRecord {
  license_id : String
  model_id : String
  status : String
  accepted_by : String
  evidence_ref : String
} derive(ToJson)

///|
extend ConsoleLicenseRecord with ToJson::{to_json}

///|
/// The body of `POST /v1/verifications` for a managed revision.
priv struct ConsoleVerificationRequest {
  kind : String
  subject : String
  digest : String
  provenance_verified : Bool
} derive(ToJson)

///|
extend ConsoleVerificationRequest with ToJson::{to_json}

///|
/// The body of `POST /v1/models/approve`.
priv struct ConsoleApprovalRequest {
  model_id : String
  version : String
} derive(ToJson)

///|
extend ConsoleApprovalRequest with ToJson::{to_json}

///|
/// The body of `POST /v1/aliases/promote`.
priv struct ConsolePromotionRequest {
  alias_name : String
  model_id : String
  version : String
  stage : String
  actor : String
} derive(ToJson)

///|
extend ConsolePromotionRequest with ToJson::{to_json}

///|
/// The body of `POST /v1/runtimes`.
priv struct ConsoleRuntimeSpec {
  name : String
  image_digest : String
  version : String
  architectures : Array[String]
  capabilities : Array[String]
  supports_batching : Bool
  supports_multi_node : Bool
} derive(ToJson)

///|
extend ConsoleRuntimeSpec with ToJson::{to_json}

///|
fn console_model_row(
  state : @ui.ConsoleState,
  model_id : String,
  version : String,
) -> @ui.ModelRow? {
  state.models
  .iter()
  .find_first(row => row.model_id == model_id && row.version == version)
}

///|
/// Split a picker value of the form `name@version`. An identifier in this plane
/// never carries an '@', so the first separator is the only one.
fn split_selection_key(key : String) -> (String, String)? {
  match key.split("@").collect() {
    [name, version] => Some((name.to_owned(), version.to_owned()))
    _ => None
  }
}

///|
/// The byte count the console already knows for an artifact, so a template does
/// not make the operator retype what the import reported. Empty when the
/// console has never seen this artifact.
fn template_artifact_size(state : @ui.ConsoleState, uri : String) -> String {
  for import_ in state.model_imports {
    if import_.artifact_uri == uri && import_.bytes_total > 0L {
      return import_.bytes_total.to_string()
    }
  }
  for directory in state.model_local_directories {
    if uri == "\{@contracts.model_store_scheme}\{directory.directory}" &&
      directory.bytes > 0L {
      return directory.bytes.to_string()
    }
  }
  ""
}

///|
/// Fill the model half of a template draft from a registered model. The
/// registry attested one artifact per model version, and a managed revision is
/// signed by the source manifest the control plane wrote next to it, so both
/// can be named without asking the operator to retype them.
fn template_draft_for_model(
  state : @ui.ConsoleState,
  key : String,
) -> @ui.TemplateDraft {
  let draft = state.template_draft
  guard split_selection_key(key) is Some((model_id, version)) &&
    console_model_row(state, model_id, version) is Some(row) else {
    return draft
  }
  let signature_ref = if row.artifact_uri.has_prefix(
      @contracts.model_store_scheme,
    ) {
    "\{row.artifact_uri}/\{@contracts.model_store_manifest_name}"
  } else {
    ""
  }
  let size_bytes = template_artifact_size(state, row.artifact_uri)
  // The registry alias is the name workloads address; a model without one is
  // still shaped like a selector by its own id. Either way the preflight has
  // the last word on whether the alias is approved.
  let selector = if @contracts.valid_identifier(
      row.alias_name.trim().to_owned(),
      maximum_length=128,
    ) {
    row.alias_name.trim().to_owned()
  } else {
    model_id
  }
  {
    ..draft,
    model_id,
    model_version: version,
    model_selector: selector,
    artifact_uri: row.artifact_uri,
    artifact_digest: row.artifact_digest,
    artifact_size_bytes: if size_bytes == "" {
      draft.artifact_size_bytes
    } else {
      size_bytes
    },
    artifact_signature_ref: if signature_ref == "" {
      draft.artifact_signature_ref
    } else {
      signature_ref
    },
  }
}

///|
/// Fill the runtime half of a template draft from the roster the registry read
/// reported. The architecture defaults to the runtime's first admitted one,
/// which is what the template must place on, and the capability to the first
/// one this console can serve at all.
fn template_draft_for_runtime(
  state : @ui.ConsoleState,
  key : String,
) -> @ui.TemplateDraft {
  let draft = state.template_draft
  guard @ui.known_runtimes(state)
    .iter()
    .find_first(runtime => @ui.runtime_key(runtime) == key)
    is Some(runtime) else {
    return draft
  }
  let capability = if runtime.capabilities.length() > 0 &&
    @ui.runtime_capability_options().contains(runtime.capabilities[0]) {
    runtime.capabilities[0]
  } else {
    draft.capability
  }
  {
    ..draft,
    runtime_name: runtime.name,
    runtime_version: runtime.version,
    runtime_image_digest: runtime.image_digest,
    runtime_architectures: runtime.architectures.join(", "),
    architecture: if runtime.architectures.length() > 0 {
      runtime.architectures[0]
    } else {
      draft.architecture
    },
    runtime_multi_node: runtime.supports_multi_node,
    capability,
  }
}

///|
/// The evidence citation a candidate's licence review starts from. The exact
/// upstream SPDX text the import declared is preferred; the registry licence
/// identity is the fallback. Neither is a path or a digest.
fn license_evidence_default(
  state : @ui.ConsoleState,
  row : @ui.ModelRow,
) -> String {
  let mut spdx = ""
  if row.artifact_digest != "" {
    for import_ in state.model_imports {
      if import_.manifest_digest == row.artifact_digest &&
        import_.license.trim() != "" {
        spdx = import_.license.trim().to_owned()
      }
    }
  }
  if spdx == "" {
    spdx = row.license_id.trim().to_owned()
  }
  "modelscope-license:\{spdx}"
}

///|
/// The first JSON string value stored under `key`, or `None` when the text
/// carries no such member. Debug `Repr` escapes the quotes of an embedded
/// body, so the escaping is undone before the member is read.
fn json_string_member(text : String, key : String) -> String? {
  let plain = text
    .replace_all(old="\\\"", new="\"")
    .replace_all(old="\\\\", new="\\")
  let needle = "\"" + key + "\""
  guard plain.find(needle) is Some(start) else { return None }
  let after_key = plain[start + needle.length():]
  guard after_key.find(":") is Some(colon) else { return None }
  let after_colon = after_key[colon + 1:]
  guard after_colon.find("\"") is Some(open) else { return None }
  let body = after_colon[open + 1:]
  guard body.find("\"") is Some(close) else { return None }
  Some(body[:close].to_owned())
}

///|
/// True when the control plane refused a console call with exactly this HTTP
/// status. The status lives only in the transport text: the debug `Repr` of a
/// Rabbita error is opaque, and the detail helper below strips the envelope that
/// carries the status line, so a handler that must tell one refusal from
/// another keys on `Show` alone.
fn http_status_is(error : Error, status : Int) -> Bool {
  error.to_string().contains("HTTP \{status}")
}

///|
/// A console write that the control plane refused carries its own explanation:
/// the registry answers an out-of-order or unverified step with
/// `{"error":{"code":...,"message":...}}`. Report that message verbatim, and
/// fall back to the raw transport detail when the body is not that envelope.
fn http_failure_detail(error : Error) -> String {
  // `Show` carries the transport text; the debug `Repr` of the JSON-layer
  // error type is opaque and would hide the control plane's own words.
  let detail = error.to_string()
  match json_string_member(detail, "message") {
    Some(message) => if message == "" { detail } else { message }
    None => detail
  }
}

///|
/// The canonical endpoint of one model-onboarding action. The registry owns
/// the order; the console only addresses the route.
priv enum ModelOnboardingAction {
  AcceptLicense
  VerifyArtifact
  ApproveVersion
  PromoteAlias
}

///|
fn model_onboarding_path(action : ModelOnboardingAction) -> String {
  match action {
    AcceptLicense => "/v1/licenses"
    VerifyArtifact => "/v1/verifications"
    ApproveVersion => "/v1/models/approve"
    PromoteAlias => "/v1/aliases/promote"
  }
}

///|
fn runtime_registration_path() -> String {
  "/v1/runtimes"
}

///|
fn model_license_body(draft : @ui.ModelLicenseDraft) -> String {
  ConsoleLicenseRecord::{
    license_id: draft.license_id.trim().to_owned(),
    model_id: draft.model_id,
    status: "Accepted",
    accepted_by: "operator",
    evidence_ref: draft.evidence_ref.trim().to_owned(),
  }
  .to_json()
  .stringify()
}

///|
/// A `modelstore://` subject is correct here: the control plane attests the
/// managed revision itself and refuses a digest it cannot re-derive.
fn model_verification_body(row : @ui.ModelRow) -> String {
  ConsoleVerificationRequest::{
    kind: "managed-revision",
    subject: row.artifact_uri,
    digest: row.artifact_digest,
    provenance_verified: true,
  }
  .to_json()
  .stringify()
}

///|
fn model_approval_body(model_id : String, version : String) -> String {
  ConsoleApprovalRequest::{ model_id, version, }.to_json().stringify()
}

///|
fn model_promotion_body(draft : @ui.ModelAliasDraft) -> String {
  ConsolePromotionRequest::{
    alias_name: draft.alias_name.trim().to_owned(),
    model_id: draft.model_id,
    version: draft.version,
    stage: "Canary",
    actor: "operator",
  }
  .to_json()
  .stringify()
}

///|
fn runtime_registration_body(draft : @ui.RuntimeProfileDraft) -> String {
  ConsoleRuntimeSpec::{
    name: draft.name.trim().to_owned(),
    image_digest: draft.image_digest.trim().to_owned(),
    version: draft.version.trim().to_owned(),
    architectures: [draft.architecture.trim().to_owned()],
    capabilities: [@ui.runtime_capability_name(draft.capability)],
    supports_batching: draft.supports_batching,
    supports_multi_node: draft.supports_multi_node,
  }
  .to_json()
  .stringify()
}

///|
/// The body of `POST /v1/catalog/templates`. The control plane signs a catalog
/// template itself and refuses a caller that supplies either half, so the two
/// signature fields go out empty. An empty list answers `None`: the draft is
/// then one the client-side mirror already refused to submit.
fn template_registration_body(draft : @ui.TemplateDraft) -> String? {
  guard @ui.template_draft_valid(draft) &&
    @ui.template_identifier_list(
      draft.runtime_architectures,
      maximum=64,
      identifier_length=128,
    )
    is Some(architectures) &&
    @ui.template_identifier_list(draft.secret_refs, maximum=64)
    is Some(secret_refs) &&
    @ui.template_int_field(draft.accelerator_count, maximum=64)
    is Some(accelerator_count) &&
    @ui.template_int_field(draft.accelerator_memory_mib, maximum=1048576)
    is Some(accelerator_memory_mib) &&
    @ui.template_int_field(draft.cpu_millis, maximum=1000000)
    is Some(cpu_millis) &&
    @ui.template_int_field(draft.memory_mib, maximum=1048576)
    is Some(memory_mib) &&
    @ui.template_int_field(draft.health_interval_ms, maximum=3600000)
    is Some(interval_ms) &&
    @ui.template_int_field(draft.failure_threshold, maximum=100)
    is Some(failure_threshold) &&
    @ui.template_int_field(draft.termination_grace_ms, maximum=3600000)
    is Some(termination_grace_ms) &&
    @ui.template_int_field(draft.canary_replicas, maximum=64)
    is Some(canary_replicas) &&
    @ui.template_int64_field(draft.artifact_size_bytes, maximum=1099511627776L)
    is Some(size_bytes) &&
    @ui.template_int64_field(draft.readiness_timeout_ms, maximum=86400000L)
    is Some(readiness_timeout_ms) else {
    return None
  }
  let retention : @contracts.RetentionPolicy = if draft.capture_for_evaluation {
    EvaluationCapture(
      consent_receipt=draft.evaluation_consent_receipt.trim().to_owned(),
    )
  } else {
    Ephemeral
  }
  Some(
    @deployment.ModelServiceTemplate::{
      template_id: draft.template_id.trim().to_owned(),
      version: draft.version.trim().to_owned(),
      display_name: draft.display_name.trim().to_owned(),
      description: draft.description,
      model_selector: draft.model_selector.trim().to_owned(),
      model_id: draft.model_id.trim().to_owned(),
      model_version: draft.model_version.trim().to_owned(),
      artifact: {
        digest: draft.artifact_digest.trim().to_owned(),
        uri: draft.artifact_uri.trim().to_owned(),
        size_bytes,
        signature_ref: draft.artifact_signature_ref.trim().to_owned(),
      },
      runtime: {
        name: draft.runtime_name.trim().to_owned(),
        image_digest: draft.runtime_image_digest.trim().to_owned(),
        version: draft.runtime_version.trim().to_owned(),
        architectures,
        capabilities: [draft.capability],
        // The planner refuses a template that asks for batching; the switch is
        // a runtime property, never a template one.
        supports_batching: false,
        supports_multi_node: draft.runtime_multi_node,
      },
      capability: draft.capability,
      architecture: draft.architecture.trim().to_owned(),
      resources: {
        accelerator_count,
        accelerator_memory_mib,
        cpu_millis,
        memory_mib,
      },
      // A template that reached a node reaches only the controller and the
      // artifact store, so both are admitted and no egress is.
      network: {
        allow_controller: true,
        allow_artifact_store: true,
        allowed_egress: [],
      },
      health: {
        readiness_path: draft.readiness_path.trim().to_owned(),
        interval_ms,
        failure_threshold,
        termination_grace_ms,
      },
      data_policy: {
        classification: draft.classification,
        retention,
        allow_cache: draft.allow_cache,
        allow_training_reuse: draft.allow_training_reuse,
      },
      secret_refs,
      rollout: {
        canary_replicas,
        automatic_promotion: draft.automatic_promotion,
        automatic_rollback: draft.automatic_rollback,
        readiness_timeout_ms,
      },
      approval_receipt: "",
      signature: "",
    }
    .to_json()
    .stringify(),
  )
}

///|
fn model_adoption_architectures(value : String) -> Array[String]? {
  let architectures : Array[String] = []
  for part in value.split(",") {
    let architecture = part.trim().to_owned()
    if !@contracts.valid_identifier(architecture, maximum_length=128) {
      return None
    }
    architectures.push(architecture)
    if architectures.length() > 16 {
      return None
    }
  }
  if architectures.length() == 0 {
    None
  } else {
    Some(architectures)
  }
}

///|
fn model_adoption_intent(
  draft : @ui.ModelAdoptionDraft,
) -> ModelAdoptionIntent? {
  let model_id = draft.model_id.trim().to_owned()
  let version = draft.version.trim().to_owned()
  let license_id = draft.license_id.trim().to_owned()
  guard @contracts.valid_identifier(model_id) &&
    @contracts.valid_identifier(version) &&
    @contracts.valid_identifier(license_id) &&
    model_adoption_architectures(draft.compatible_architectures)
    is Some(compatible_architectures) else {
    return None
  }
  let minimum_memory_mib = @string.parse_int(draft.minimum_memory_mib.trim()) catch {
    _ => return None
  }
  if minimum_memory_mib <= 0 {
    return None
  }
  Some({
    model_id,
    version,
    license_id,
    compatible_architectures,
    minimum_memory_mib,
  })
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
        parse_console_json(
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
fn cluster_poll_delay_command(
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(message => emit(message), async fn() noraise {
    try cluster_poll_promise().wait() catch {
      _ => ClusterPollDue(generation)
    } noraise {
      _ => ClusterPollDue(generation)
    }
  })
}

///|
fn cluster_poll_request_command(
  model : AppModel,
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try {
      let heartbeats : Array[@contracts.NodeHeartbeat] = @json.from_json(
        parse_console_json(
          request("GET", model.endpoint, "/v1/nodes", model.credential),
        ),
      )
      let storage_nodes : Array[@ui.StorageNodeRow] = @json.from_json(
        parse_console_json(
          request("GET", model.endpoint, "/v1/storage-nodes", model.credential),
        ),
      )
      let telemetry : ConsoleTelemetrySnapshot = @json.from_json(
        parse_console_json(
          request("GET", model.endpoint, "/v1/telemetry", model.credential),
        ),
      )
      let existing = model.console.nodes
      let nodes = preserve_node_lease_holders(
        existing,
        build_node_rows(heartbeats, telemetry, None, model.console.locale),
      )
      ClusterPolled(generation, nodes, storage_nodes)
    } catch {
      error =>
        ClusterPollFailed(
          generation,
          http_status_is(error, 401) || http_status_is(error, 403),
        )
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
        // The session replaces the password, so the draft is dropped as soon
        // as it has served its purpose.
        login_password: "",
        personal_login: false,
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
    PersonalLoginRequested =>
      (
        {
          ..model,
          personal_login: true,
          console: { ..model.console, loading: false, error_message: None, },
        },
        @rabbita.none,
      )
    LoginUsernameChanged(value) =>
      ({ ..model, login_username: value, }, @rabbita.none)
    LoginPasswordChanged(value) =>
      ({ ..model, login_password: value, }, @rabbita.none)
    OperatorLoginSubmitted => {
      if !operator_login_draft_complete(model) {
        return (model, @rabbita.none)
      }
      let next = {
        ..model,
        console: {
          ..model.console,
          loading: true,
          error_message: None,
          success_message: None,
        },
      }
      (
        next,
        operator_login_command(
          model.console.locale,
          model.login_username,
          model.login_password,
          emit,
        ),
      )
    }
    OperatorLoginRefused(dispatched_locale, message) =>
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
                "Sign-in failed.",
                "登录失败。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    AccountSessionChanged(value) =>
      (
        {
          ..model,
          credential: value,
          audit_credential: value,
          csrf_token: "",
          model_import_poll_generation: model.model_import_poll_generation + 1L,
          cluster_poll_generation: model.cluster_poll_generation + 1L,
          console: { ..model.console, operator_authenticated: false, },
          console_read_groups: Map([]),
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
          cluster_poll_generation: model.cluster_poll_generation + 1L,
          console: { ..model.console, operator_authenticated: false, },
          console_read_groups: Map([]),
        },
        @rabbita.none,
      )
    AuditCredentialChanged(value) =>
      ({ ..model, audit_credential: value, }, @rabbita.none)
    InferenceCredentialChanged(value) =>
      ({ ..model, inference_credential: value, }, @rabbita.none)
    InferenceSubjectChanged(value) =>
      ({ ..model, inference_subject_ref: value, }, @rabbita.none)
    CommercialOrganizationChanged(value) => {
      // The commerce read group belongs to the previous organization.
      let groups = model.console_read_groups.copy()
      groups.remove(CommerceReads)
      (
        {
          ..model,
          commercial_organization: value,
          console_read_groups: groups,
        },
        @rabbita.none,
      )
    }
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
            account_invite: { ..model.console.account_invite, email: value, },
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
    Console(AnnouncementIdChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            announcement_draft: {
              ..model.console.announcement_draft,
              announcement_id: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AnnouncementTenantChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            announcement_draft: {
              ..model.console.announcement_draft,
              tenant_ref: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AnnouncementTitleChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            announcement_draft: {
              ..model.console.announcement_draft,
              title: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AnnouncementBodyChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            announcement_draft: {
              ..model.console.announcement_draft,
              body: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AnnouncementExpiryChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            announcement_draft: {
              ..model.console.announcement_draft,
              expires_unix_ms: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AnnouncementLifetimeChosen(days)) => {
      guard days == 1 || days == 7 || days == 30 else {
        return (model, @rabbita.none)
      }
      let expiry = (current_unix_ms() + days.to_int64() * 86400000L).to_string()
      (
        {
          ..model,
          console: {
            ..model.console,
            announcement_draft: {
              ..model.console.announcement_draft,
              expires_unix_ms: expiry,
            },
          },
        },
        @rabbita.none,
      )
    }
    Console(SubmitAnnouncement) => {
      let draft = model.console.announcement_draft
      guard !model.demo_mode &&
        model.console.operator_authenticated &&
        @ui.announcement_ready(draft) else {
        return (model, @rabbita.none)
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          let expiry = @string.parse_int64(draft.expires_unix_ms)
          guard expiry > current_unix_ms() else {
            fail("announcement expiry must be future")
          }
          let body : Json = {
            "announcement_id": draft.announcement_id.trim().to_owned(),
            "tenant_ref": draft.tenant_ref.trim().to_owned(),
            "title": draft.title.trim().to_owned(),
            "body": draft.body.trim().to_owned(),
            "expires_unix_ms": expiry.to_string(),
          }
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/notifications/operator/announcements",
              model.credential,
              body=body.stringify(),
            ),
          )
        } catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Announcement was not published. Check the active tenant, plain-text message, future expiry within 30 days, and whether this ID already has different content.",
                "公告未发布。请检查有效租户、纯文本内容、30 天内的未来到期时间，以及该编号是否已用于其他内容。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Announcement published to the selected tenant.",
                "公告已发布给指定租户。",
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
    Console(AccessPackageIssuerChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            access_package_draft: {
              ..model.console.access_package_draft,
              identity_issuer: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccessPackageSubjectChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            access_package_draft: {
              ..model.console.access_package_draft,
              identity_subject: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccessPackageDisplayNameChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            access_package_draft: {
              ..model.console.access_package_draft,
              display_name: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccessPackageEmailChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            access_package_draft: {
              ..model.console.access_package_draft,
              email: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccessPackageOrganizationChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            access_package_draft: {
              ..model.console.access_package_draft,
              organization_id: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccessPackageTenantChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            access_package_draft: {
              ..model.console.access_package_draft,
              tenant_ref: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(AccessPackageLifetimeChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            access_package_draft: {
              ..model.console.access_package_draft,
              lifetime_days: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(ToggleAccessPackageIdentityVerified) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            access_package_draft: {
              ..model.console.access_package_draft,
              identity_verified: !model.console.access_package_draft.identity_verified,
            },
          },
        },
        @rabbita.none,
      )
    Console(SubmitAccessPackage) => {
      let draft = model.console.access_package_draft
      let intent = AccessPackageIntent::{
        identity_issuer: draft.identity_issuer.trim().to_owned(),
        identity_subject: draft.identity_subject,
        display_name: draft.display_name.trim().to_owned(),
        email: draft.email.trim().to_owned(),
        organization_id: draft.organization_id.trim().to_owned(),
        tenant_ref: draft.tenant_ref.trim().to_owned(),
        template_id: "webide-developer",
        lifetime_days: draft.lifetime_days,
        identity_verified: draft.identity_verified,
      }.to_json()
      let body = match intent {
        Object(fields) if draft.lifetime_days == 0 => {
          fields["lifetime_minutes"] = 60
          Json::object(fields).stringify()
        }
        _ => intent.stringify()
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/onboarding/access-packages",
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
                "The WebIDE access package was rejected. Review the identity and organization fields.",
                "WebIDE 访问软件包被拒绝。请检查身份与组织字段。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "WebIDE access was prepared. The next incomplete milestone is shown below.",
                "WebIDE 访问已准备。下方会显示下一个未完成的里程碑。",
              ),
            )
        }
      })
      (
        {
          ..model,
          console: {
            ..model.console,
            access_package_draft: {
              ..draft,
              identity_subject: "",
              display_name: "",
              email: "",
              identity_verified: false,
            },
            loading: true,
            error_message: None,
            success_message: None,
          },
        },
        cmd,
      )
    }
    Console(EnableAccessPackage(account_id)) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/onboarding/access-packages/\{account_id}:enable",
              model.credential,
            ),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "WebIDE access is not ready to enable. Complete the highlighted milestone first.",
                "WebIDE 访问尚不能启用。请先完成突出显示的里程碑。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "WebIDE access is enabled.",
                "WebIDE 访问已启用。",
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
          cluster_poll_generation: model.cluster_poll_generation + 1L,
          console_read_groups: Map([]),
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
    Console(AlertsWindowChanged(window)) =>
      ({ ..model, alerts_window: window, }, @rabbita.none)
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
    ClusterPollDue(generation) =>
      if generation != model.cluster_poll_generation ||
        model.demo_mode ||
        !model.console.operator_authenticated {
        (model, @rabbita.none)
      } else {
        (model, cluster_poll_request_command(model, generation, emit))
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
        console: { ..model.console, loading: true, error_message: None, },
      }
      (next, load_command(next, emit))
    }
    Outcome(Loaded(state)) => {
      let generation = model.model_import_poll_generation + 1L
      let cluster_generation = model.cluster_poll_generation + 1L
      // The core read set does not carry the current page's deferred group, so
      // that group is reloaded for the page the operator is looking at.
      let stale_groups = model.console_read_groups.copy()
      match console_read_group_for_route(model.console.route) {
        Some(group) => stale_groups.remove(group)
        None => ()
      }
      let next = {
        ..model,
        console: merge_loaded_console(model.console, state),
        console_read_groups: stale_groups,
        model_import_poll_generation: generation,
        cluster_poll_generation: cluster_generation,
      }
      let (scheduled, deferred) = schedule_deferred_reads(
        next,
        next.console.route,
        emit,
      )
      (
        scheduled,
        @rabbita.batch([
          if model_imports_active(scheduled.console.model_imports) {
            model_import_poll_delay_command(generation, emit)
          } else {
            @rabbita.none
          },
          if scheduled.demo_mode {
            @rabbita.none
          } else {
            cluster_poll_delay_command(cluster_generation, emit)
          },
          deferred,
        ]),
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
    Outcome(LocalCopyComplete(ok)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            success_message: if ok {
              Some(
                console_copy(
                  model.console.locale,
                  "Identifier copied.",
                  "标识符已复制。",
                ),
              )
            } else {
              None
            },
            error_message: if ok {
              None
            } else {
              Some(
                console_copy(
                  model.console.locale,
                  "Clipboard unavailable. Select the visible identifier and copy it manually.",
                  "无法使用剪贴板，请选中可见标识符手动复制。",
                ),
              )
            },
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
    Outcome(ModelLocalDirectoriesLoaded(dispatched_locale, directories)) => {
      let registered = directories.iter().find_first(row => !row.registered)
      (
        {
          ..model,
          console: {
            ..model.console,
            model_local_directories: directories,
            model_local_draft: if registered is Some(row) &&
              model.console.model_local_draft.directory == "" {
              { ..model.console.model_local_draft, directory: row.directory, }
            } else {
              model.console.model_local_draft
            },
            loading: false,
            error_message: None,
            success_message: Some(
              locale_fenced_notice(
                model.console.locale,
                dispatched_locale,
                "Found \{directories.length()} directories in the managed model store.",
                "Managed model store scanned.",
                "受管模型库扫描完成。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    }
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
    Outcome(ClusterPolled(generation, nodes, storage_nodes)) =>
      if generation != model.cluster_poll_generation ||
        !model.console.operator_authenticated {
        (model, @rabbita.none)
      } else {
        (
          {
            ..model,
            console: {
              ..model.console,
              nodes,
              storage_nodes,
              overview: {
                ..model.console.overview,
                active_nodes: nodes.count_if(node => node.state == Active),
                total_nodes: nodes.length(),
              },
            },
          },
          cluster_poll_delay_command(generation, emit),
        )
      }
    Outcome(ClusterPollFailed(generation, unauthorized)) =>
      if generation != model.cluster_poll_generation ||
        !model.console.operator_authenticated ||
        unauthorized {
        (model, @rabbita.none)
      } else {
        (model, cluster_poll_delay_command(generation, emit))
      }
    Outcome(DeferredReadLoaded(dispatched_locale, group, read)) => {
      let groups = model.console_read_groups.copy()
      if !groups.contains(group) {
        // The read was invalidated (sign-out, credential or organization
        // change) before it finished. Drop it rather than merge state the
        // current session did not ask for.
        (model, @rabbita.none)
      } else if dispatched_locale != model.console.locale ||
        !model.console.operator_authenticated {
        // Locale- or session-bound labels came back stale. Drop the read and
        // let the next visit reload it.
        groups.remove(group)
        ({ ..model, console_read_groups: groups, }, @rabbita.none)
      } else {
        groups.set(group, true)
        let next = {
          ..model,
          console_read_groups: groups,
          console: merge_console_group_read(model.console, read),
        }
        match read {
          GroupContracts(_) =>
            if next.console.route == ContractDocuments {
              // The preview that navigating to this page schedules needs the
              // packets that just arrived.
              schedule_contract_preview(
                next,
                next.console.contract_documents,
                0,
                emit,
              )
            } else {
              (next, @rabbita.none)
            }
          GroupModels(_) =>
            if model_imports_active(next.console.model_imports) {
              // The core load no longer carries the import list, so the poll
              // that watches an in-flight download is armed here instead.
              let generation = next.model_import_poll_generation + 1L
              (
                { ..next, model_import_poll_generation: generation, },
                model_import_poll_delay_command(generation, emit),
              )
            } else {
              (next, @rabbita.none)
            }
          _ => (next, @rabbita.none)
        }
      }
    }
    Outcome(DeferredReadFailed(group)) => {
      // Preserve the session, but never present failed reads as empty records.
      // The absent group projects to a visible retry state on the current page.
      let groups = model.console_read_groups.copy()
      groups.remove(group)
      ({ ..model, console_read_groups: groups, }, @rabbita.none)
    }
    Outcome(ModelAdopted(dispatched_locale, import_id, message)) => {
      let adopted_imports = model.console.model_adopted_imports.filter(value => {
        value != import_id
      })
      adopted_imports.push(import_id)
      let next = {
        ..model,
        console: {
          ..model.console,
          model_adoption_draft: empty_model_adoption_draft(),
          model_adopted_imports: adopted_imports,
          loading: true,
          error_message: None,
          success_message: Some(
            locale_fenced_notice(
              model.console.locale,
              dispatched_locale,
              message,
              "Model candidate registered.",
              "候选模型已登记。",
            ),
          ),
        },
      }
      (next, load_command(next, emit))
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
    Outcome(TemplateRegistered(template)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            // The control plane signed the template it returned, so the picker
            // and the table can offer it without a second read.
            catalog_templates: append_catalog_template(
              model.console.catalog_templates,
              template,
            ),
            loading: false,
            error_message: None,
            success_message: Some(
              console_copy(
                model.console.locale,
                "Template \{template.template_id}@\{template.version} was signed and registered.",
                "模板 \{template.template_id}@\{template.version} 已签名并注册。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    ResourcesLoaded(credential, result) => {
      if credential != model.credential {
        return (model, @rabbita.none)
      }
      let panel = model.console.resource_delivery
      let resource_delivery = match result {
        Ok(loaded) =>
          {
            ..loaded,
            selected_lease: panel.selected_lease,
            selected_nodes: panel.selected_nodes,
            confirmed_idle: panel.confirmed_idle,
            reservation_id: panel.reservation_id,
            reservation_starts_ms: panel.reservation_starts_ms,
          }
        Err(error) => { ..panel, loading: false, error: Some(error), }
      }
      (
        { ..model, console: { ..model.console, resource_delivery, }, },
        @rabbita.none,
      )
    }
    Console(ResourceDelivery(message)) => {
      let panel = model.console.resource_delivery
      if panel.loading || model.demo_mode {
        return (model, @rabbita.none)
      }
      if message == ReserveResources &&
        !@ui.resource_reservation_available(panel) {
        return (model, @rabbita.none)
      }
      let updated = panel.update(message)
      let updated = if message == ReserveResources &&
        updated.reservation_id == "" {
        {
          ..updated,
          reservation_id: random_identifier("reservation"),
          reservation_starts_ms: current_unix_ms(),
        }
      } else {
        updated
      }
      let next = {
        ..model,
        console: { ..model.console, resource_delivery: updated, },
      }
      match message {
        RefreshResources | ReserveResources =>
          (
            next,
            resource_delivery_command(next, message == ReserveResources, emit),
          )
        _ => (next, @rabbita.none)
      }
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
      let (scheduled, deferred) = schedule_deferred_reads(next, route, emit)
      let (previewed, preview) = match route {
        ContractDocuments =>
          schedule_contract_preview(
            scheduled,
            scheduled.console.contract_documents,
            0,
            emit,
          )
        _ => (scheduled, @rabbita.none)
      }
      let resources = if route == Leases && !model.demo_mode {
        resource_delivery_command(previewed, false, emit)
      } else {
        @rabbita.none
      }
      (previewed, @rabbita.batch([deferred, preview, resources]))
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
        { ..model, console: { ..model.console, confirmation: None, }, },
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(Refresh) => (model, load_command(model, emit))
    Console(ApproveOrganization(organization_id, legal_name)) => {
      let body = { "expected_legal_name": legal_name.to_json() }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/commercial/organizations/\{organization_id}:approve",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Company registration could not be approved. Refresh and review its details again.",
                "企业注册未能审核通过。请刷新并重新核对资料。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Company registration approved. The customer can refresh and continue.",
                "企业注册已审核通过；用户刷新后即可继续。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(ModelSourceQueryChanged(value)) =>
      (
        { ..model, console: { ..model.console, model_source_query: value, }, },
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
            parse_console_json(
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(DownloadModelSource(model_id)) => {
      let body = { "model_id": model_id, "revision": "master" }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          let created : @ui.ModelImportRow = @json.from_json(
            parse_console_json(
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(RefreshModelLocalDirectories) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          let listing : @ui.ModelLocalDirectoryListing = @json.from_json(
            parse_console_json(
              request(
                "GET",
                model.endpoint,
                "/v1/model-sources/modelscope/local-directories",
                model.credential,
              ),
            ),
          )
          ModelLocalDirectoriesLoaded(model.console.locale, listing.directories)
        } catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The managed model store could not be scanned. Check the model-source adapter and its model-store mount.",
                "无法扫描受管模型库。请检查模型源适配器及其模型库挂载。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(ModelLocalDirectoryChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_local_draft: {
              ..model.console.model_local_draft,
              directory: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(ModelLocalRepositoryChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_local_draft: {
              ..model.console.model_local_draft,
              repository: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(ModelLocalRevisionChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_local_draft: {
              ..model.console.model_local_draft,
              revision: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(SubmitModelLocalRegistration) => {
      let draft = model.console.model_local_draft
      if !@ui.model_local_registration_valid(model.console, draft) {
        return (
          {
            ..model,
            console: {
              ..model.console,
              loading: false,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Select a non-registered directory and name its exact ModelScope repository and revision.",
                  "请选择一个尚未登记的目录，并填写其确切的魔搭仓库与版本。",
                ),
              ),
              success_message: None,
            },
          },
          @rabbita.none,
        )
      }
      let body = {
          "model_id": draft.repository.trim().to_json(),
          "revision": draft.revision.trim().to_json(),
          "directory": draft.directory.to_json(),
          "component": model_local_component(draft.directory).to_json(),
        }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          let created : @ui.ModelImportRow = @json.from_json(
            parse_console_json(
              request(
                "POST",
                model.endpoint,
                "/v1/model-sources/modelscope/imports:register-local",
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
                "Registration queued. The selected revision or component will be checked against ModelScope before it becomes a registry candidate; license acceptance, artifact verification and operator approval remain required. Evaluation is optional.",
                "登记已排队。所选版本或组件会按魔搭清单校验；成为候选模型后仍需接受许可证、验证制品和运维批准，评测可选。",
              ),
            ),
          )
        } catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The local revision could not be registered. Check that the directory exists in the model store and that the ModelScope repository and revision are reachable.",
                "无法登记本地版本。请确认该目录存在于模型库中，且魔搭仓库与版本可访问。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(BeginLicenseAcceptance(model_id, version)) => {
      guard console_model_row(model.console, model_id, version) is Some(row) else {
        return (model, @rabbita.none)
      }
      (
        {
          ..model,
          console: {
            ..model.console,
            model_license_draft: {
              model_id,
              version,
              license_id: row.license_id,
              evidence_ref: license_evidence_default(model.console, row),
            },
            model_alias_draft: @ui.empty_model_alias_draft(),
            error_message: None,
            success_message: None,
          },
        },
        @rabbita.none,
      )
    }
    Console(DismissLicenseAcceptance) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_license_draft: @ui.empty_model_license_draft(),
          },
        },
        @rabbita.none,
      )
    Console(LicenseRecordIdChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_license_draft: {
              ..model.console.model_license_draft,
              license_id: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(LicenseEvidenceChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_license_draft: {
              ..model.console.model_license_draft,
              evidence_ref: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(SubmitModelLicense) => {
      let draft = model.console.model_license_draft
      if !model.console.operator_authenticated ||
        !@ui.model_license_draft_valid(draft) {
        return (
          {
            ..model,
            console: {
              ..model.console,
              loading: false,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Enter a valid licence record ID and a non-empty evidence citation.",
                  "请填写有效的许可证记录 ID 与非空证据引用。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let license_id = draft.license_id.trim().to_owned()
      let body = model_license_body(draft)
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              model_onboarding_path(AcceptLicense),
              model.credential,
              body~,
            ),
          )
        catch {
          error =>
            ActionFailed(model.console.locale, http_failure_detail(error))
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Licence \{license_id} recorded as Accepted for \{draft.model_id} · \{draft.version}.",
                "已将 \{draft.model_id} · \{draft.version} 的许可证 \{license_id} 记录为已接受。",
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
    Console(VerifyModelArtifact(model_id, version)) => {
      guard model.console.operator_authenticated &&
        console_model_row(model.console, model_id, version) is Some(row) &&
        @contracts.valid_sha256_digest(row.artifact_digest) &&
        row.artifact_uri != "" else {
        return (
          {
            ..model,
            console: {
              ..model.console,
              loading: false,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "This registered artifact has no attestable managed revision yet.",
                  "该已注册制品尚无可以证明的受管版本。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let body = model_verification_body(row)
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              model_onboarding_path(VerifyArtifact),
              model.credential,
              body~,
            ),
          )
        catch {
          error =>
            ActionFailed(model.console.locale, http_failure_detail(error))
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The managed revision \{row.artifact_digest} was verified for \{model_id} · \{version}.",
                "已为 \{model_id} · \{version} 验证受管版本 \{row.artifact_digest}。",
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
    Console(ApproveModelVersion(model_id, version)) => {
      guard model.console.operator_authenticated else {
        return (model, @rabbita.none)
      }
      let body = model_approval_body(model_id, version)
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              model_onboarding_path(ApproveVersion),
              model.credential,
              body~,
            ),
          )
        catch {
          error =>
            ActionFailed(model.console.locale, http_failure_detail(error))
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "\{model_id} · \{version} is approved for users.",
                "\{model_id} · \{version} 已批准供用户使用。",
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
    Console(BeginAliasPromotion(model_id, version)) => {
      guard console_model_row(model.console, model_id, version) is Some(row) else {
        return (model, @rabbita.none)
      }
      let existing = if row.alias_name == "—" {
        @ui.model_alias_slug(model_id)
      } else {
        row.alias_name
      }
      (
        {
          ..model,
          console: {
            ..model.console,
            model_alias_draft: { model_id, version, alias_name: existing, },
            model_license_draft: @ui.empty_model_license_draft(),
            error_message: None,
            success_message: None,
          },
        },
        @rabbita.none,
      )
    }
    Console(DismissAliasPromotion) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_alias_draft: @ui.empty_model_alias_draft(),
          },
        },
        @rabbita.none,
      )
    Console(AliasNameChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_alias_draft: {
              ..model.console.model_alias_draft,
              alias_name: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(SubmitAliasPromotion) => {
      let draft = model.console.model_alias_draft
      if !model.console.operator_authenticated ||
        !@ui.model_alias_draft_valid(draft) {
        return (
          {
            ..model,
            console: {
              ..model.console,
              loading: false,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Enter a valid serving alias before promoting.",
                  "提升前请填写有效的服务别名。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let alias_name = draft.alias_name.trim().to_owned()
      let body = model_promotion_body(draft)
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              model_onboarding_path(PromoteAlias),
              model.credential,
              body~,
            ),
          )
        catch {
          error =>
            ActionFailed(model.console.locale, http_failure_detail(error))
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Alias \{alias_name} now points at \{draft.model_id} · \{draft.version} as Canary.",
                "别名 \{alias_name} 现以 Canary 指向 \{draft.model_id} · \{draft.version}。",
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
    Console(RuntimeNameChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            runtime_draft: { ..model.console.runtime_draft, name: value, },
          },
        },
        @rabbita.none,
      )
    Console(RuntimeVersionChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            runtime_draft: { ..model.console.runtime_draft, version: value, },
          },
        },
        @rabbita.none,
      )
    Console(RuntimeImageDigestChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            runtime_draft: {
              ..model.console.runtime_draft,
              image_digest: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(RuntimeArchitectureChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            runtime_draft: {
              ..model.console.runtime_draft,
              architecture: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(RuntimeCapabilityChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            runtime_draft: {
              ..model.console.runtime_draft,
              capability: @ui.parse_runtime_capability(value),
            },
          },
        },
        @rabbita.none,
      )
    Console(RuntimeBatchingToggled) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            runtime_draft: {
              ..model.console.runtime_draft,
              supports_batching: !model.console.runtime_draft.supports_batching,
            },
          },
        },
        @rabbita.none,
      )
    Console(RuntimeMultiNodeToggled) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            runtime_draft: {
              ..model.console.runtime_draft,
              supports_multi_node: !model.console.runtime_draft.supports_multi_node,
            },
          },
        },
        @rabbita.none,
      )
    Console(SubmitRuntimeRegistration) => {
      let draft = model.console.runtime_draft
      if !model.console.operator_authenticated ||
        !@ui.runtime_profile_draft_valid(draft) {
        return (
          {
            ..model,
            console: {
              ..model.console,
              loading: false,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Name the runtime, give a sha256:<64 hex> image digest and a valid version and architecture.",
                  "请填写运行时名称、sha256:<64 位十六进制> 镜像摘要，以及有效的版本与架构。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let runtime_name = draft.name.trim().to_owned()
      let body = runtime_registration_body(draft)
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              runtime_registration_path(),
              model.credential,
              body~,
            ),
          )
        catch {
          error =>
            ActionFailed(model.console.locale, http_failure_detail(error))
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Runtime \{runtime_name} was registered. Verify its image digest before any deployment can use it.",
                "运行时 \{runtime_name} 已登记。在任何部署使用它之前，请先验证其镜像摘要。",
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
    Console(TemplateTextChanged(field, value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            template_draft: @ui.template_draft_with_text(
              model.console.template_draft,
              field,
              value,
            ),
          },
        },
        @rabbita.none,
      )
    Console(TemplateFlagToggled(flag)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            template_draft: @ui.template_draft_with_flag(
              model.console.template_draft,
              flag,
              !@ui.template_flag_value(model.console.template_draft, flag),
            ),
          },
        },
        @rabbita.none,
      )
    Console(TemplateCapabilityChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            template_draft: {
              ..model.console.template_draft,
              capability: @ui.parse_runtime_capability(value),
            },
          },
        },
        @rabbita.none,
      )
    Console(TemplateClassificationChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            template_draft: {
              ..model.console.template_draft,
              classification: @ui.parse_data_class(value),
            },
          },
        },
        @rabbita.none,
      )
    Console(TemplateModelSelected(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            template_draft: template_draft_for_model(model.console, value),
          },
        },
        @rabbita.none,
      )
    Console(TemplateRuntimeSelected(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            template_draft: template_draft_for_runtime(model.console, value),
          },
        },
        @rabbita.none,
      )
    Console(SubmitTemplateRegistration) => {
      let draft = model.console.template_draft
      guard model.console.operator_authenticated &&
        template_registration_body(draft) is Some(body) else {
        return (
          {
            ..model,
            console: {
              ..model.console,
              loading: false,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Name the template, pick a registered model and runtime, and give every admitted value its rule's shape.",
                  "请命名模板、选择已注册的模型与运行时，并让每个被接纳的值符合其规则。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          let response = request(
            "POST",
            model.endpoint,
            "/v1/catalog/templates",
            model.credential,
            body~,
          )
          let accepted : @deployment.ModelServiceTemplate = @json.from_json(
            @json.parse(response),
          )
          TemplateRegistered(accepted)
        } catch {
          error =>
            ActionFailed(model.console.locale, http_failure_detail(error))
        } noraise {
          value => value
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
            parse_console_json(
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
            parse_console_json(
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(RefreshModelImports) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          let imports : Array[@ui.ModelImportRow] = @json.from_json(
            parse_console_json(
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(BeginModelAdoption(import_id)) => {
      guard model.console.operator_authenticated &&
        model.console.model_imports
        .iter()
        .find_first(import_ => {
          import_.import_id == import_id &&
          @ui.model_import_needs_registration(import_, model.console.models)
        })
        is Some(_) else {
        return (
          {
            ..model,
            console: {
              ..model.console,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Only a complete, checksum-verified import in immutable S3 or the managed model store can be adopted.",
                  "只有完整、通过校验且位于不可变 S3 或受管模型库的导入才能登记。",
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
            model_adoption_draft: { ..empty_model_adoption_draft(), import_id, },
            error_message: None,
            success_message: None,
          },
        },
        @rabbita.none,
      )
    }
    Console(DismissModelAdoption) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_adoption_draft: empty_model_adoption_draft(),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Console(ModelAdoptionIdChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_adoption_draft: {
              ..model.console.model_adoption_draft,
              model_id: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(ModelAdoptionVersionChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_adoption_draft: {
              ..model.console.model_adoption_draft,
              version: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(ModelAdoptionLicenseChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_adoption_draft: {
              ..model.console.model_adoption_draft,
              license_id: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(ModelAdoptionArchitecturesChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_adoption_draft: {
              ..model.console.model_adoption_draft,
              compatible_architectures: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(ModelAdoptionMemoryChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            model_adoption_draft: {
              ..model.console.model_adoption_draft,
              minimum_memory_mib: value,
            },
          },
        },
        @rabbita.none,
      )
    Console(SubmitModelAdoption) => {
      let draft = model.console.model_adoption_draft
      guard model.console.operator_authenticated &&
        model.console.model_imports
        .iter()
        .find_first(import_ => {
          import_.import_id == draft.import_id &&
          @ui.model_import_needs_registration(import_, model.console.models)
        })
        is Some(_) &&
        model_adoption_intent(draft) is Some(intent) else {
        return (
          {
            ..model,
            console: {
              ..model.console,
              loading: false,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Complete every valid registry field and confirm the import remains checksum-verified in immutable S3 or the managed model store.",
                  "请填写全部有效的注册表字段，并确认导入仍已通过校验且位于不可变 S3 或受管模型库。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let body = intent.to_json().stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try {
          ignore(
            request(
              "POST",
              model.endpoint,
              model_adoption_path(draft.import_id),
              model.credential,
              body~,
            ),
          )
          ModelAdopted(
            model.console.locale,
            draft.import_id,
            console_copy(
              model.console.locale,
              "The verified import was registered as a Candidate. License acceptance, artifact verification and explicit approval are still required; evaluation is optional.",
              "已将通过校验的导入登记为候选模型；仍需接受许可证、验证制品并明确批准，评测可选。",
            ),
          )
        } catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The import could not be adopted. Refresh it and check for a registry identity conflict.",
                "无法登记该导入。请刷新状态并检查注册表身份冲突。",
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
    Console(OperationChanged(value)) =>
      (
        { ..model, console: { ..model.console, operation_name: value, }, },
        @rabbita.none,
      )
    Console(OperationBodyChanged(value)) =>
      (
        { ..model, console: { ..model.console, operation_body: value, }, },
        @rabbita.none,
      )
    Console(QuickDeploymentIdChanged(value)) =>
      (
        { ..model, console: { ..model.console, quick_deployment_id: value, }, },
        @rabbita.none,
      )
    Console(QuickTemplateChanged(value)) =>
      (
        { ..model, console: { ..model.console, quick_template: value, }, },
        @rabbita.none,
      )
    Console(QuickTopologyChanged(value)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            quick_topology: @ui.parse_quick_topology(value),
          },
        },
        @rabbita.none,
      )
    Console(PortalNodeChanged(value)) =>
      (
        { ..model, console: { ..model.console, portal_node_id: value, }, },
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(SubmitOperation) => {
      if model.console.operation_name == "revoke-enterprise-membership" {
        let membership_id = try
          @json.parse(model.console.operation_body)
        catch {
          _ => None
        } noraise {
          { "membership_id": String(value), .. } if value != "" => Some(value)
          _ => None
        }
        return match membership_id {
          Some(id) =>
            (
              {
                ..model,
                console: {
                  ..model.console,
                  confirmation: Some(
                    @ui.confirmation_receipt(RevokeEnterpriseMembership(id), id),
                  ),
                  error_message: None,
                },
              },
              @rabbita.none,
            )
          None =>
            (
              {
                ..model,
                console: {
                  ..model.console,
                  error_message: Some(
                    console_copy(
                      model.console.locale,
                      "Provide a membership_id in the JSON body.",
                      "请在 JSON 正文中填写 membership_id。",
                    ),
                  ),
                },
              },
              @rabbita.none,
            )
        }
      }
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
            console: { ..model.console, error_message: Some(message), },
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(ConfirmAction(RevokeEnterpriseMembership(membership_id))) => {
      let body = MembershipRevocationIntent::{ membership_id, }
        .to_json()
        .stringify()
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/portal/operator/memberships:revoke",
            model.credential,
            body~,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The enterprise membership could not be revoked.",
                "无法撤销企业成员关系。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Enterprise membership \{membership_id} was revoked.",
                "企业成员关系 \{membership_id} 已撤销。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(OfflineCommerce(Refresh)) => (model, load_command(model, emit))
    Console(OfflineCommerce(RequestArtifactDownload(artifact_id))) =>
      (model, operator_evidence_download_command(model, artifact_id, emit))
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
      ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
    }
    Console(OfflineCommerce(ConfirmAction(action))) => {
      let now = current_unix_ms()
      let actor = model.console.offline_commerce.operator_actor_ref
        .trim()
        .to_owned()
      let request_spec : OfflineActionRequest = match action {
        PrepareTechnicalWorkspace(order_id, generation) =>
          {
            path: "/v1/offline-commerce/operator/technical-acceptance-targets",
            body: (
              { "order_id": order_id, "expected_generation": generation } : Json).stringify(),
            english_success: "Limited workspace grant prepared; lease remains requested, not active.",
            chinese_success: "限时工作区授权已准备；租约仍待开通，尚未激活。",
          }
        AuthorizeTechnicalOrder(
          order_id,
          generation,
          target,
          grant,
          reference,
          expires
        ) => {
          let value : Json = {
            "order_id": order_id,
            "expected_generation": generation,
            "waiver_id": "technical-waiver-" + order_id,
            "authority_target_ref": target,
            "grant_id": grant,
            "expires_unix_ms": expires,
            "user_authorization_ref": reference,
            "reason": "Unsigned, unpaid, non-commercial UI acceptance; existing grants and automatic expiry remain mandatory.",
          }
          if expires == 0L && value is Object(fields) {
            fields.remove("expires_unix_ms")
          }
          {
            path: "/v1/offline-commerce/operator/technical-acceptance-waivers",
            body: value.stringify(),
            english_success: "Limited test waiver recorded. Unsigned and unpaid; resources are not activated yet.",
            chinese_success: "已记录限定测试豁免：未签署、未付款；资源尚未开通。",
          }
        }
        QuoteUndertakingOrder(order_id, term, quantity) => {
          guard selected_offline_order(model.console.offline_commerce, order_id)
            is Some(order) else {
            return (model, @rabbita.none)
          }
          let quote = try
            undertaking_quote(
              order,
              term,
              quantity,
              random_identifier("undertaking-quote"),
              now,
            )
          catch {
            _ =>
              return (
                {
                  ..model,
                  console: {
                    ..model.console,
                    offline_commerce: {
                      ..model.console.offline_commerce,
                      loading: false,
                      error_message: Some(
                        console_copy(
                          model.console.locale,
                          "Choose a valid tariff and 1–10000 devices.",
                          "请选择有效档位，设备台数须为 1–10000。",
                        ),
                      ),
                    },
                  },
                },
                @rabbita.none,
              )
          } noraise {
            value => value
          }
          let value : OfflineQuoteAction = { order_id, quote, }
          {
            path: "/v1/offline-commerce/operator/quotes",
            body: value.to_json().stringify(),
            english_success: "Fixed-tariff undertaking quote created.",
            chinese_success: "已创建承诺函固定档位报价。",
          }
        }
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
            tax: { minor_units: 0L, currency: "CNY", scale: 2, },
            total: money,
            valid_until_unix_ms: valid_until,
            terms_digest,
            created_unix_ms: now,
          }
          let value : OfflineQuoteAction = { order_id, quote, }
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
        AcceptEvidence(artifact_id, digest)
        | VerifyFullPrepayment(artifact_id, digest) => {
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
            reason_code: if action is VerifyFullPrepayment(_, _) {
              "FullPrepaymentVerified"
            } else {
              "evidence-accepted"
            },
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
          let waiver = selected_offline_order(
            model.console.offline_commerce,
            order_id,
          ).bind(order => order.technical_acceptance_waiver)
          let value : OfflineFulfillmentAction = {
            order_id,
            expected_generation: generation,
            activation_id: random_identifier("offline-activation"),
            idempotency_key: random_identifier("offline-activate"),
            entitlement_kind: waiver.map_or(ExclusiveMachineLease, w => {
              w.entitlement_kind()
            }),
            authority_target_ref: waiver.map_or(
              model.console.offline_commerce.entitlement_ref.trim().to_owned(),
              w => w.authority_target_ref,
            ),
          }
          {
            path: "/v1/offline-commerce/operator/fulfillments",
            body: value.to_json().stringify(),
            english_success: "Entitlement request accepted; activation is pending authority confirmation. A technical waiver does not imply payment or signing.",
            chinese_success: "权益申请已受理，正在等待授权方确认；技术豁免不代表已付款或签署。",
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
          console: { ..model.console, contract_documents: next_documents, },
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
          console: { ..model.console, contract_documents: next_documents, },
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
        console: { ..model.console, contract_documents: next_documents, },
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
    Console(ContractDocuments(DownloadDocument(artifact_id))) =>
      (model, operator_evidence_download_command(model, artifact_id, emit))
    Console(ContractDocuments(CopyPublicIdentifier(value))) =>
      (
        model,
        @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
          try copy_public_identifier_promise(value).wait() catch {
            _ => LocalCopyComplete(false)
          } noraise {
            _ => LocalCopyComplete(true)
          }
        }),
      )
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
      | Console(AlertsWindowChanged(_))
      | Console(QuickDeploymentIdChanged(_))
      | Console(QuickTemplateChanged(_))
      | Console(QuickTopologyChanged(_))
      | Console(PortalNodeChanged(_))
      | Console(ModelSourceQueryChanged(_))
      | Console(BeginModelAdoption(_))
      | Console(DismissModelAdoption)
      | Console(ModelAdoptionIdChanged(_))
      | Console(ModelAdoptionVersionChanged(_))
      | Console(ModelAdoptionLicenseChanged(_))
      | Console(ModelAdoptionArchitecturesChanged(_))
      | Console(ModelAdoptionMemoryChanged(_))
      | Console(ModelLocalDirectoryChanged(_))
      | Console(ModelLocalRepositoryChanged(_))
      | Console(ModelLocalRevisionChanged(_))
      | Console(BeginLicenseAcceptance(_, _))
      | Console(DismissLicenseAcceptance)
      | Console(LicenseRecordIdChanged(_))
      | Console(LicenseEvidenceChanged(_))
      | Console(BeginAliasPromotion(_, _))
      | Console(DismissAliasPromotion)
      | Console(AliasNameChanged(_))
      | Console(RuntimeNameChanged(_))
      | Console(RuntimeVersionChanged(_))
      | Console(RuntimeImageDigestChanged(_))
      | Console(RuntimeArchitectureChanged(_))
      | Console(RuntimeCapabilityChanged(_))
      | Console(RuntimeBatchingToggled)
      | Console(RuntimeMultiNodeToggled)
      | Console(TemplateTextChanged(_, _))
      | Console(TemplateFlagToggled(_))
      | Console(TemplateCapabilityChanged(_))
      | Console(TemplateClassificationChanged(_))
      | Console(TemplateModelSelected(_))
      | Console(TemplateRuntimeSelected(_))
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
      | Outcome(LocalCopyComplete(_))
      | Outcome(ContractPreviewFailed(_, _, _)) =>
        update_live(model, message, emit)
      Console(OfflineCommerce(RequestArtifactDownload(_)))
      | Console(OfflineCommerce(RequestGeneration(_, _)))
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
      | Console(SubmitModelAdoption)
      | Console(RefreshModelLocalDirectories)
      | Console(SubmitModelLocalRegistration)
      | Console(SubmitModelLicense)
      | Console(VerifyModelArtifact(_, _))
      | Console(ApproveModelVersion(_, _))
      | Console(SubmitAliasPromotion)
      | Console(SubmitRuntimeRegistration)
      | Console(SubmitTemplateRegistration)
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
      | Console(ApproveOrganization(_, _))
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
/// True when this deployment declared the console open (see `main`). The
/// gateway then attaches operator authority to every same-origin request, so
/// the credential field only needs a marker instead of a real token.
fn deployment_console_open() -> Bool {
  operator_open_matches(operator_open_origin(), console_page_origin())
}

///|
fn operator_open_matches(declared : String, page_origin : String) -> Bool {
  if declared == "" || page_origin == "" {
    return false
  }
  if declared == "*" {
    return true
  }
  for candidate in declared.split(",") {
    if candidate == page_origin {
      return true
    }
  }
  false
}

///|
fn console_loading_view(
  locale : @i18n.Locale,
  detail : String,
  open_deployment : Bool,
) -> @rabbita.Html {
  let copy = console_copy(
    locale, "Loading the operator console…", "正在加载运维控制台…",
  )
  @html.main_(
    class="login-shell",
    attrs=@html.Attrs::build().style(
      "login-shell", "display:grid;place-items:center;min-height:100vh",
    ),
    [
      @html.div(class="login-card", [
        @html.h2(copy),
        @html.p(
          class="login-help",
          if open_deployment {
            console_copy(
              locale, "Fetching cluster inventory, telemetry and governance state from the controller.",
              "正在从控制器获取集群清单、遥测与治理状态。",
            )
          } else {
            console_copy(
              locale, "Contacting the controller with the credentials from this session.",
              "正在使用本会话的凭据连接控制器。",
            )
          },
        ),
        // A read that fails while the deployment is open leaves the console
        // with nothing to show. Reporting the reason here turns a silent
        // "loading" screen into something an operator can act on.
        if detail == "" {
          @html.nothing
        } else {
          @html.p(class="login-help", detail)
        },
      ]),
    ],
  )
}

///|
fn app_view(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Html {
  let locale = model.console.locale
  // A deployment that declares itself open authenticates every request at the
  // same-origin gateway, so a session flag must not send the operator back to
  // the login form. Without this the console falls back to the login view the
  // moment any background read reports an authentication failure, even though
  // the gateway is still attaching operator authority to each request.
  if model.personal_login {
    return login_view(model, emit)
  }
  if !model.demo_mode && !model.console.operator_authenticated {
    if model.console.loading || deployment_console_open() {
      // Progress while the first read is in flight. The reason is carried
      // through so a read that fails does not leave an unexplained spinner.
      return console_loading_view(
        locale,
        model.console.error_message.unwrap_or(""),
        deployment_console_open(),
      )
    }
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
            class=if deployment_console_open() ||
              (model.credential != "" && model.audit_credential != "") {
              "connection-state connection-state-ready"
            } else {
              "connection-state connection-state-needed"
            },
            if model.credential.has_prefix("lnxs_") {
              console_copy(
                locale, "Account session active", "账户会话有效",
              )
            } else if deployment_console_open() {
              console_copy(
                locale, "Deployment open — the same-origin proxy attaches operator authority",
                "部署已开放 —— 同源代理会附加运维权限",
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
            if !model.credential.has_prefix("lnxs_") {
              @html.button(
                type_="button",
                class="primary-button",
                on_click=emit(PersonalLoginRequested),
                console_copy(
                  locale, "Sign in as a named operator", "以个人管理员账户登录",
                ),
              )
            } else {
              @html.nothing
            },
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
    @ui.interactive_view(
      model.console,
      emit.map(message => Console(message)),
      alerts_window=model.alerts_window,
      now_unix_ms=current_unix_ms(),
      page_read_state=console_page_read_state(model),
    ),
  ])
}

///|
fn console_page_read_state(model : AppModel) -> @ui.PageReadState {
  if model.demo_mode {
    return Ready
  }
  match console_read_group_for_route(model.console.route) {
    None => Ready
    Some(group) =>
      match model.console_read_groups.get(group) {
        Some(true) => Ready
        Some(false) => Loading
        None => if model.console.loading { Loading } else { Failed }
      }
  }
}

///|
/// The gateway needs both halves, so the form stays inert until they are there.
fn operator_login_draft_complete(model : AppModel) -> Bool {
  model.login_username.trim() != "" && model.login_password != ""
}

///|
fn login_transport_allowed(endpoint : String) -> Bool {
  @browser_transport.endpoint_allowed(endpoint)
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
        @html.span(
          class="login-mark",
          style=[
            "overflow: hidden", "flex-shrink: 0", "width: 3.5rem", "height: 3.5rem",
          ],
          [
            @html.img(src="/assets/platform-logo-light.png", alt="", style=[
              "display: block", "width: 100%", "height: 100%", "object-fit: contain",
              "transform: scale(1.22)", "transform-origin: center",
            ]),
          ],
        ),
        @html.strong("能源谷“创未来”生态街区"),
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
                locale, "This is the operator console for platform administrators. The customer portal uses a separate browser session; signing in there does not sign you in here.",
                "这里是平台管理员使用的运维控制台。用户门户使用独立的浏览器会话，在那里登录不会自动登录此处。",
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
              locale, "This address is not the configured Operator origin. Open the deployment's exact HTTP console address to use auto-login.",
              "当前地址不是已配置的 Operator 入口。请打开本部署的准确 HTTP 控制台地址使用免登录。",
            ),
          )
        } else if model.endpoint.has_prefix("http://") &&
          !localhost_dev_fallback_allowed(model.endpoint) {
          @html.p(
            class="login-transport-warning",
            console_copy(
              locale, "Temporary HTTP mode is enabled by this deployment. Browser traffic is not encrypted; use only on a trusted network.",
              "此部署已开启临时 HTTP 模式。浏览器流量未加密，请仅在可信网络中使用。",
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
        @html.form(class="login-form", on_submit=emit(OperatorLoginSubmitted), [
          @html.div(class="login-field", [
            @html.label(
              for_="login-username",
              console_copy(locale, "Username", "用户名"),
            ),
            @html.input(
              id="login-username",
              value=model.login_username,
              auto_complete=On,
              maxlength=320,
              attrs=@html.Attrs::build()
                .disabled(!transport_allowed)
                .aria_describedby("login-credentials-help"),
              on_input=emit.map(value => LoginUsernameChanged(value)),
            ),
          ]),
          @html.div(class="login-field", [
            @html.label(
              for_="login-password",
              console_copy(locale, "Password", "密码"),
            ),
            @html.input(
              id="login-password",
              input_type=Password,
              value=model.login_password,
              auto_complete=On,
              maxlength=256,
              attrs=@html.Attrs::build().disabled(!transport_allowed),
              on_input=emit.map(value => LoginPasswordChanged(value)),
            ),
            @html.span(
              id="login-credentials-help",
              class="login-help",
              console_copy(
                locale, "The gateway checks these against the identity provider and returns a short-lived lnxs_ session. The console never sees the password or the provider's client secret.",
                "网关用这两个字段向身份提供商换取短期 lnxs_ 会话。控制台不会接触密码，也接触不到提供商的客户端密钥。",
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
              type_="submit",
              disabled=!transport_allowed ||
                !operator_login_draft_complete(model) ||
                model.console.loading,
              if model.console.loading {
                console_copy(locale, "Signing in…", "正在登录…")
              } else {
                console_copy(locale, "Sign in", "登录")
              },
            ),
          ]),
        ]),
        if configured_endpoint().has_suffix("/mana") {
          @html.nothing
        } else {
          @html.div(
            class="login-divider",
            console_copy(
              locale, "or use organization sign-in", "或使用组织账户登录",
            ),
          )
        },
        if configured_endpoint().has_suffix("/mana") {
          @html.nothing
        } else if transport_allowed {
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
              locale, "Open the configured Operator address", "请打开已配置的 Operator 地址",
            ),
          )
        },
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
  ])
}

///|
fn main {
  let locale = @i18n.parse_locale(stored_locale_preference())
  let is_demo = demo_mode()
  // "*" declares the deployment open for every origin that can reach it;
  // otherwise one of the declared exact origins must match the page.
  let open_origin = operator_open_origin()
  let open_mode = operator_open_matches(open_origin, console_page_origin())
  apply_console_locale(locale)
  let base_model : AppModel = {
    endpoint: configured_endpoint(),
    credential: if open_mode {
      "deployment-open"
    } else {
      ""
    },
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: is_demo,
    alerts_window: Today,
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
        loading: open_mode,
        offline_commerce: { ..@ui.default_state().offline_commerce, locale, },
      }
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
  }
  @rabbita.new(fn() {
    let (model, emit) = @rabbita.create_state_with_init(
      init=fn(emit) {
        (
          base_model,
          if is_demo {
            @rabbita.none
          } else if open_mode {
            // Open deployment: the same-origin gateway injects operator
            // authority into API calls, so the console loads immediately
            // without a browser-held credential.
            load_command(base_model, emit)
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
