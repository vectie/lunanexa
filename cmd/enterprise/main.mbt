///|
priv struct AppModel {
  endpoint : String
  token : String
  csrf_token : String
  subject_ref : String
  connecting : Bool
  bootstrap_started : Bool
  demo_mode : Bool
  session_generation : Int64
  session_expires_unix_ms : Int64?
  machine_clock_generation : Int64
  contract_preview_generation : Int64
  contract_poll_generation : Int64
  portal : @enterprise_ui.EnterpriseState
  /// The customer sign-in and registration draft. The password stays in memory
  /// only: it is sent to the same-origin gateway and never written to a URL or
  /// browser storage.
  login_email : String
  login_password : String
  register_display_name : String
  registering : Bool
} derive(Eq)

///|
priv struct GatewayBrowserBootstrap {
  session_token : String
  csrf_token : String
  expires_unix_ms : Int64
} derive(FromJson)

///|
/// What the gateway's username/password and registration routes answered. The
/// status is kept apart from the body so a refusal can be reported without
/// echoing anything the gateway did not deliberately send.
priv struct GatewayAuthOutcome {
  status : Int
  body : String
} derive(FromJson)

///|
/// The gateway's refusal body. Its `error` code is the only thing the browser
/// is told, so the copy below is driven by that code and never by upstream text.
priv struct GatewayAuthError {
  error : String
} derive(FromJson)

///|
priv struct SelfServiceOrganizationsResponse {
  version : String
  organizations : Array[@enterprise_ui.SelfServiceOrganizationView]
} derive(FromJson)

///|
priv struct SelfServiceOrganizationCreateIntent {
  idempotency_key : String
  display_name : String
  legal_profile : @commercial.OrganizationLegalProfile
} derive(ToJson)

///|
extend SelfServiceOrganizationCreateIntent with ToJson::{to_json}

///|
priv struct SelfServiceInvitationAcceptIntent {
  invitation_secret : String
} derive(ToJson)

///|
extend SelfServiceInvitationAcceptIntent with ToJson::{to_json}

///|
priv struct SelfServiceInvitationAcceptView {
  invitation : Json
  membership : @portal.EnterpriseMembership
} derive(FromJson)

///|
priv struct SelfServiceMachineQuoteIntent {
  quote_id : String
  idempotency_key : String
  project_id : String
  offering_id : String
  quantity : Int64
  duration_seconds : Int64
  unix_username : String?
  requested_model_selector : String?
  model_template_ref : String?
} derive(ToJson)

///|
extend SelfServiceMachineQuoteIntent with ToJson::{to_json}

///|
priv struct SelfServiceMachineOrderIntent {
  order_id : String
  idempotency_key : String
  quote_id : String
} derive(ToJson)

///|
extend SelfServiceMachineOrderIntent with ToJson::{to_json}

///|
priv struct SelfServiceMachineOrderAction {
  idempotency_key : String
  expected_generation : Int64
  reason : String
} derive(ToJson)

///|
extend SelfServiceMachineOrderAction with ToJson::{to_json}

///|
priv struct SelfServiceMachineTermsAcceptanceIntent {
  idempotency_key : String
  template_version : String
  rendered_document_hash : String
  document_uri : String
  presentation_context_hash : String
  network_context_hash : String
} derive(ToJson)

///|
extend SelfServiceMachineTermsAcceptanceIntent with ToJson::{to_json}

///|
priv struct SelfServiceMachineOrderResponse {
  order : @machinecommerce.MachineOrder
  checkout : @commercial_integrations.ExternalRecordView
  entitlement_transaction_ref : String
} derive(FromJson)

///|
priv struct PortalApiKeyIssueIntent {
  key_id : String
  project_id : String
  display_name : String
  scopes : Array[@enterprise_ui.ApiKeyScope]
  allowed_models : Array[String]
  expires_unix_ms : Int64
  maximum_requests : Int64
} derive(ToJson)

///|
extend PortalApiKeyIssueIntent with ToJson::{to_json}

///|
priv struct PortalApiKeyRevokeView {
  key_id : String
  revoked_unix_ms : Int64?
} derive(FromJson)

///|
priv struct PaymentCheckoutIntent {
  idempotency_key : String
  period_id : String
} derive(ToJson)

///|
extend PaymentCheckoutIntent with ToJson::{to_json}

///|
priv struct OfflineOrderIntent {
  order_id : String
  idempotency_key : String
  project_id : String
  selected_service_code : String
  selected_sla_code : String
  expires_unix_ms : Int64
  /// The tier the customer chose, from the same list the operator's tariff
  /// picker renders. It is a request the operator quotes, not a price.
  requested_undertaking_term : String?
} derive(ToJson)

///|
extend OfflineOrderIntent with ToJson::{to_json}

///|
priv struct SelfUploadIntent {
  grant_id : String
  idempotency_key : String
  order_id : String
  artifact_id : String
  kind : @offline.DocumentArtifactKind
  revision : Int
  allowed_media_types : Array[String]
  maximum_byte_count : Int64
  expires_unix_ms : Int64
} derive(ToJson)

///|
extend SelfUploadIntent with ToJson::{to_json}

///|
priv struct SelfDownloadIntent {
  session_id : String
  idempotency_key : String
} derive(ToJson)

///|
extend SelfDownloadIntent with ToJson::{to_json}

///|
priv struct SelfOfflineOrderAction {
  order_id : String
  expected_generation : Int64
} derive(ToJson)

///|
extend SelfOfflineOrderAction with ToJson::{to_json}

///|
priv struct OfflineUploadTransferView {
  evidence : @offline.OfflineUploadGrantView
  transfer : @offline.OfflineTransferGrant
} derive(FromJson)

///|
priv struct OfflineArtifactView {
  artifact_id : String
  order_id : String
  kind : @offline.DocumentArtifactKind
  revision : Int
  locale : String
  media_type : String
  byte_count : Int64
  sha256 : String
  generation_state : @offline.ArtifactGenerationState
  scan_state : @offline.ArtifactScanState
  review_state : @offline.ArtifactReviewState
  created_unix_ms : Int64
} derive(FromJson)

///|
priv struct ContractInformationUpdate {
  expected_revision : Int64
  changes : Array[@contractdoc.ContractFieldValue]
} derive(ToJson)

///|
extend ContractInformationUpdate with ToJson::{to_json}

///|
priv struct ContractRevisionAction {
  expected_revision : Int64
  expected_values_sha256 : String?
} derive(ToJson)

///|
extend ContractRevisionAction with ToJson::{to_json}

///|
priv struct ContractPreviewIntent {
  expected_revision : Int64
  form : @contractdoc.ContractFormKind
  changes : Array[@contractdoc.ContractFieldValue]
} derive(ToJson)

///|
extend ContractPreviewIntent with ToJson::{to_json}

///|
priv struct ContractRenewalIntent {
  packet_id : String
  idempotency_key : String
} derive(ToJson)

///|
extend ContractRenewalIntent with ToJson::{to_json}

///|
priv struct ContractSelfGovernance {
  approvals : Array[@contractdoc.ContractApproval]
  obligations : Array[@contractdoc.ContractObligation]
  amendments : Array[@contractdoc.ContractAmendment]
  closure_proposals : Array[@contractdoc.ContractClosureProposal]
  numbers : Array[@contractdoc.ContractNumber]
} derive(FromJson)

///|
priv struct DesktopClientResponse {
  client_id : String
  display_name : String
  launch_uri : String
  handoff_lifetime_ms : Int64
  contract_ready : Bool
  workspace_ready : Bool
  models_ready : Bool
  ready : Bool
  blocker_codes : Array[String]
  approved_model_aliases : Array[String]
  handoffs : Array[Json]
} derive(FromJson)

///|
priv struct DesktopClientHandoffLaunch {
  client_id : String
  display_name : String
  launch_uri : String
  handoff_code : String
  handoff_expires_unix_ms : Int64
  one_time : Bool
} derive(FromJson)

///|
priv enum Outcome {
  OrganizationsLoaded(
    Int64,
    Array[@enterprise_ui.SelfServiceOrganizationView],
    String?
  )
  OrganizationCreated(@enterprise_ui.SelfServiceOrganizationView)
  OrganizationJoined
  MachineCommerceLoaded(
    Array[@machinecommerce.MachineOfferingView],
    Array[@machinecommerce.MachineOrder],
    @commercial.AgreementTemplate?,
    Array[@commercial_integrations.ExternalRecordView]
  )
  MachineQuoteLoaded(@machinecommerce.MachineQuote)
  MachineTermsAccepted
  MachineOrderCreated(SelfServiceMachineOrderResponse)
  MachineOrderUpdated(@machinecommerce.MachineOrder, String)
  Loaded(
    Int64,
    @portal.EnterpriseSelfView,
    @enterprise_ui.AccountView?,
    @enterprise_ui.TrialEntitlementView?,
    Array[@enterprise_ui.BrowserSessionView],
    Array[@enterprise_ui.EnterpriseCostCenterRow],
    String,
    Array[@portal.EnterpriseModelSummary],
    Array[@notifications.NotificationRecord],
    Array[@notifications.NotificationPreferenceView],
    Array[@nodelease.CustomerExclusiveMachineView],
    Array[@offline.CommercialOrder],
    Array[@offline_commerce.OfflineArtifactSummary],
    Array[@contractdoc.ContractTemplateManifest],
    Array[@contractdoc.ContractPacket],
    Array[@contractdoc.ContractPacketEvent],
    ContractSelfGovernance,
    Array[@enterprise_ui.EnterpriseDesktopClient],
    Array[@enterprise_ui.ApiCredentialView],
    Array[@commercial_integrations.ExternalRecordView],
    @enterprise_ui.PaymentCheckoutQuote?
  )
  AgreementUpdated(
    @portal.PortalAgreement,
    Array[@commercial_integrations.ExternalRecordView]
  )
  ProviderRequestsLoaded(Array[@commercial_integrations.ExternalRecordView])
  PaymentCheckoutCreated(@commercial_integrations.ExternalRecordView)
  LeaseCreated(@portal.EnterpriseLeaseRequest)
  NotificationRead(@notifications.NotificationRecord)
  NotificationPreferenceUpdated(@notifications.NotificationPreferenceView)
  MachineTerminated(@nodelease.CustomerExclusiveMachineView)
  CredentialRedeemed(@credential.CredentialHandoffRedemption)
  MachineClockAdvanced(Int64, Int64)
  OfflineOrderCreated(@offline.CommercialOrder)
  OfflineOrderCancelled(@offline.CommercialOrder)
  EvidenceUploaded(String)
  ArtifactDownloaded(String)
  ContractPacketUpdated(@contractdoc.ContractPacket)
  ContractActionNeedsRefresh
  ContractApprovalNudged
  DesktopClientLaunched(String)
  ContractPreviewLoaded(Int64, @contractdoc.ContractPreviewDocument)
  ContractPreviewFailed(Int64, @i18n.Locale, String)
  ApiKeyIssued(Int64, @enterprise_ui.IssuedApiKeyView)
  ApiKeyRevoked(Int64, String, Int64?)
  ApiKeySecretCopied(Int64)
  Failed(@i18n.Locale, String)
}

///|
priv enum AppMessage {
  DeliveryAccessIssued(
    Int64,
    String?,
    Int64,
    Result[@enterprise_ui.DeliveryApiAccess, String]
  )
  DeliveriesLoaded(
    Int64,
    String?,
    Int64,
    Result[
      (
        @enterprise_ui.DeliveryOptions,
        Array[@enterprise_ui.DeliveryView],
        String?,
      ),
      String,
    ]
  )
  DeliveryPollDue(Int64, String?, Int64)
  EndpointChanged(String)
  TokenChanged(String)
  SubjectChanged(String)
  LoginEmailChanged(String)
  LoginPasswordChanged(String)
  RegisterDisplayNameChanged(String)
  ToggleRegistration
  EnterpriseSignInSubmitted
  EnterpriseRegistrationSubmitted
  EnterpriseAuthRefused(@i18n.Locale, String)
  Connect
  Bootstrap
  BootstrapReady(Int64, GatewayBrowserBootstrap)
  BootstrapUnavailable(Int64)
  Logout
  LogoutCompleted(Int64)
  Portal(@enterprise_ui.EnterpriseMessage)
  ContractPreviewDue(Int64, @contract_documents.ContractDocumentsMessage)
  ContractPollDue(Int64, String, Int)
  ContractPollResult(
    Int64,
    String,
    Int,
    Result[Array[@contractdoc.ContractPacket], String]
  )
  Outcome(Outcome)
}

///|
extern "js" fn configured_endpoint() -> String =
  #| () => globalThis.LUNANEXA_API_ENDPOINT || globalThis.location?.origin || ""

///|
extern "js" fn configured_docs_url() -> String =
  #| () => { try { const u = new URL(globalThis.LUNANEXA_DOCS_URL); if (u.username || u.password) return ''; u.search=''; u.hash=''; return u.protocol === 'https:' || (u.protocol === 'http:' && ['localhost','127.0.0.1','[::1]'].includes(u.hostname)) ? u.href : ''; } catch (_) { return ''; } }

///|
extern "js" fn install_dialog_focus() -> Unit =
  #| () => {
  #|   if (globalThis.__lunanexaEnterpriseDialogFocus) return;
  #|   globalThis.__lunanexaEnterpriseDialogFocus = true;
  #|   let active = null, previous = null;
  #|   const tabbables = d => [...d.querySelectorAll('button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex="0"]')].filter(e => e.getClientRects().length && e.tabIndex >= 0);
  #|   const sync = () => { const dialogs = document.querySelectorAll('[aria-modal="true"]'); const next = dialogs[dialogs.length - 1] || null; if (next === active) return; if (!active && next) previous = document.activeElement; active = next; if (active) { active.tabIndex = -1; (tabbables(active)[0] || active).focus(); } else if (previous?.isConnected) { previous.focus(); previous = null; } };
  #|   new MutationObserver(sync).observe(document.documentElement, {childList:true, subtree:true});
  #|   document.addEventListener('keydown', e => { if (!active) return; if (e.key === 'Tab') { const els = tabbables(active); const first = els[0] || active, last = els[els.length - 1] || active; if (e.shiftKey && (document.activeElement === first || !active.contains(document.activeElement))) { e.preventDefault(); last.focus(); } else if (!e.shiftKey && (document.activeElement === last || !active.contains(document.activeElement))) { e.preventDefault(); first.focus(); } } else if (e.key === 'Escape') { const cancel = active.querySelector('#api-key-issue-cancel,#api-key-revoke-cancel,#api-key-secret-dismiss'); if (cancel && !cancel.disabled) { e.preventDefault(); cancel.click(); } } });
  #|   document.addEventListener('focusin', e => { if (active && !active.contains(e.target)) (tabbables(active)[0] || active).focus(); });
  #|   sync();
  #| }

///|
extern "js" fn download_costs_csv(value : String) -> Bool =
  #| (value) => { try { const url = URL.createObjectURL(new Blob(['\ufeff', value], {type:'text/csv;charset=utf-8'})); const a = document.createElement('a'); a.href=url; a.download='lunanexa-costs.csv'; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000); return true; } catch (_) { return false; } }

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
extern "js" fn stored_locale_preference() -> String =
  #| () => {
  #|   try { return globalThis.localStorage?.getItem("lunanexa.locale") || ""; }
  #|   catch (_) { return ""; }
  #| }

///|
extern "js" fn stored_organization_preference() -> String =
  #| () => {
  #|   try { return globalThis.localStorage?.getItem("lunanexa.organization") || ""; }
  #|   catch (_) { return ""; }
  #| }

///|
extern "js" fn commit_enterprise_organization(organization_id : String) -> Unit =
  #| organizationId => {
  #|   globalThis.LUNANEXA_ACTIVE_ORGANIZATION = organizationId || "";
  #|   try {
  #|     if (organizationId) globalThis.localStorage?.setItem("lunanexa.organization", organizationId);
  #|     else globalThis.localStorage?.removeItem("lunanexa.organization");
  #|   } catch (_) {}
  #| }

///|
extern "js" fn commit_enterprise_locale(
  storage_value : String,
  language_tag : String,
  title : String,
) -> Unit =
  #| (storageValue, languageTag, title) => {
  #|   try { globalThis.localStorage?.setItem("lunanexa.locale", storageValue); }
  #|   catch (_) {}
  #|   try {
  #|     if (globalThis.document?.documentElement) {
  #|       globalThis.document.documentElement.lang = languageTag;
  #|     }
  #|     if (globalThis.document) globalThis.document.title = title;
  #|   } catch (_) {}
  #| }

///|
fn portal_copy(
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
/// The portal's user-facing failure text. Every `Failed` outcome below builds its
/// message by interpolating the transport `Show` of the error, because
/// `friendly_failure` tells one refusal from another by looking for the status
/// line (`HTTP 409: {"error":...}`) and the control plane's own error code. The
/// debug `Repr` of a Rabbita error is opaque, so interpolating it instead would
/// silently downgrade every refusal to the generic "the action failed" copy.
fn portal_failure_message(locale : @i18n.Locale, message : String) -> String {
  @enterprise_ui.friendly_failure(
    locale,
    portal_copy(locale, "Operation", "操作"),
    message,
  )
}

///|
fn apply_enterprise_locale(locale : @i18n.Locale) -> Unit {
  commit_enterprise_locale(
    locale.storage_value(),
    locale.language_tag(),
    portal_copy(
      locale, "能源谷“创未来”街区算力平台 | Enterprise Portal", "能源谷“创未来”街区算力平台 | 企业门户",
    ),
  )
}

///|
extern "js" fn current_unix_ms() -> Int64 = "() => BigInt(Date.now())"

///|
extern "js" fn copy_text_promise(value : String) -> @js.Promise =
  #| async value => {
  #|   if (!globalThis.navigator?.clipboard?.writeText) {
  #|     throw new Error("Clipboard API is unavailable; select and copy the secret manually.");
  #|   }
  #|   await globalThis.navigator.clipboard.writeText(value);
  #| }

///|
extern "js" fn machine_clock_promise(expires_unix_ms : Int64) -> @js.Promise =
  #| expires => new Promise(resolve => {
  #|   const remaining = expires - BigInt(Date.now());
  #|   const delay = remaining <= 0n ? 0 : Number(remaining > 60000n ? 60000n : remaining);
  #|   setTimeout(() => resolve(BigInt(Date.now())), delay);
  #| })

///|
extern "js" fn contract_preview_delay_promise(
  milliseconds : Int,
) -> @js.Promise =
  #| milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds))

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

///| The short-lived handoff code is placed only in a URL fragment. Browsers do

///| not send fragments to HTTP servers, and the receiving client removes it

///|
/// after redemption.
extern "js" fn open_desktop_client(
  launch_uri : String,
  client_id : String,
  handoff_code : String,
) -> Unit =
  #| (launchUri, clientId, handoffCode) => {
  #|   const fragment = new URLSearchParams({
  #|     lunanexa_client_id: clientId,
  #|     lunanexa_handoff: handoffCode,
  #|   }).toString();
  #|   const target = `${launchUri}${launchUri.includes("#") ? "&" : "#"}${fragment}`;
  #|   globalThis.location.assign(target);
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
  #|   const organization = globalThis.LUNANEXA_ACTIVE_ORGANIZATION || "";
  #|   if (organization) headers["X-LunaNexa-Organization"] = organization;
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
  #|     // The status stays in the message. Replacing it with the body's own text
  #|     // read better and cost the only thing a caller can classify on: every
  #|     // refusal -- a permanent 403 included -- arrived as an unclassifiable
  #|     // string and was reported as "the action failed, retry".
  #|     let detail = "";
  #|     try { detail = JSON.parse(text)?.error?.message || ""; } catch (_) {}
  #|     throw new Error(detail ? `HTTP ${response.status}: ${detail}` : `HTTP ${response.status}`);
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
  #|     redirect: "error",
  #|   });
  #|   if (!response.ok) throw new Error(`gateway session HTTP ${response.status}`);
  #|   return await response.text();
  #| }

///|
extern "js" fn gateway_logout_promise(csrf_token : String) -> @js.Promise =
  #| async csrfToken => {
  #|   const response = await fetch("/auth/logout", {
  #|     method: "POST",
  #|     headers: {
  #|       "Accept": "application/json",
  #|       "X-LunaNexa-CSRF": csrfToken,
  #|     },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|   });
  #|   if (!response.ok) throw new Error(`gateway logout HTTP ${response.status}`);
  #| }

///|
/// Submit the customer's username and password to the same-origin gateway.
/// The audience is fixed here, so the portal cannot ask the operator page's
/// audience from a customer form. The password is read at submit time and goes
/// straight into the request; it is never placed in a URL or browser storage.
extern "js" fn password_login_promise(
  username : String,
  password : String,
) -> @js.Promise =
  #| async (username, password) => {
  #|   if (!username || !password) return JSON.stringify({ status: 0, body: "" });
  #|   const response = await fetch("/auth/password", {
  #|     method: "POST",
  #|     headers: { "Accept": "application/json", "Content-Type": "application/json" },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|     body: JSON.stringify({ username, password, audience: "enterprise" })
  #|   });
  #|   const text = await response.text();
  #|   return JSON.stringify({ status: response.status, body: text.slice(0, 4096) });
  #| }

///|
/// Ask the gateway to create the account and sign it in. Registration and
/// sign-in answer with the same session document, so the portal treats a
/// successful registration as a successful sign-in.
extern "js" fn registration_promise(
  email : String,
  display_name : String,
  password : String,
) -> @js.Promise =
  #| async (email, displayName, password) => {
  #|   if (!email || !displayName || !password) return JSON.stringify({ status: 0, body: "" });
  #|   const response = await fetch("/auth/register", {
  #|     method: "POST",
  #|     headers: { "Accept": "application/json", "Content-Type": "application/json" },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|     body: JSON.stringify({ email, display_name: displayName, password, audience: "enterprise" })
  #|   });
  #|   const text = await response.text();
  #|   return JSON.stringify({ status: response.status, body: text.slice(0, 4096) });
  #| }

///| The raw one-time capability lives only in this browser operation. It is

///|
/// never written to application state or local storage.
extern "js" fn upload_file_promise(
  url : String,
  session_token : String,
  accepted_media_types : String,
  maximum_byte_count : Int64,
) -> @js.Promise =
  #| (url, sessionToken, acceptedMediaTypes, maximumByteCount) => new Promise((resolve, reject) => {
  #|   const input = document.createElement("input");
  #|   input.type = "file";
  #|   input.accept = acceptedMediaTypes;
  #|   input.onchange = async () => {
  #|     try {
  #|       const file = input.files?.[0];
  #|       if (!file) throw new Error("No file was selected");
  #|       if (BigInt(file.size) > maximumByteCount) throw new Error("Selected file exceeds the authorized size");
  #|       const accepted = acceptedMediaTypes.split(",").filter(Boolean);
  #|       if (accepted.length && !accepted.includes(file.type)) throw new Error("Selected file type is not authorized");
  #|       const headers = {
  #|         "Authorization": `Bearer ${sessionToken}`,
  #|         "Content-Type": file.type,
  #|       };
  #|       const organization = globalThis.LUNANEXA_ACTIVE_ORGANIZATION || "";
  #|       if (organization) headers["X-LunaNexa-Organization"] = organization;
  #|       const response = await fetch(url, {
  #|         method: "PUT",
  #|         headers,
  #|         body: file,
  #|         cache: "no-store",
  #|         credentials: "omit",
  #|         redirect: "error",
  #|       });
  #|       if (!response.ok) throw new Error(`Upload failed with HTTP ${response.status}`);
  #|       resolve(file.name);
  #|     } catch (error) { reject(error); }
  #|   };
  #|   input.oncancel = () => reject(new Error("File selection was cancelled"));
  #|   input.click();
  #| })

///|
extern "js" fn download_file_promise(
  url : String,
  session_token : String,
  maximum_byte_count : Int64,
  expected_sha256 : String,
  filename : String,
  digest_bytes : (Bytes) -> String,
) -> @js.Promise =
  #| async (url, sessionToken, maximumByteCount, expectedSha256, filename, digestBytes) => {
  #|   const headers = { "Authorization": `Bearer ${sessionToken}` };
  #|   const organization = globalThis.LUNANEXA_ACTIVE_ORGANIZATION || "";
  #|   if (organization) headers["X-LunaNexa-Organization"] = organization;
  #|   const response = await fetch(url, {
  #|     method: "GET",
  #|     headers,
  #|     cache: "no-store",
  #|     credentials: "omit",
  #|     redirect: "error",
  #|   });
  #|   if (!response.ok) throw new Error(`Download failed with HTTP ${response.status}`);
  #|   const bytes = await response.arrayBuffer();
  #|   if (BigInt(bytes.byteLength) > maximumByteCount) throw new Error("Downloaded file exceeds its authorized size");
  #|   const actual = digestBytes(new Uint8Array(bytes));
  #|   if (actual !== expectedSha256) throw new Error("Downloaded file digest does not match the verified artifact");
  #|   const link = document.createElement("a");
  #|   const objectUrl = URL.createObjectURL(new Blob([bytes]));
  #|   try {
  #|     link.href = objectUrl;
  #|     link.download = filename;
  #|     link.click();
  #|   } finally { URL.revokeObjectURL(objectUrl); }
  #|   return filename;
  #| }

///|
async fn request(
  verb : String,
  endpoint : String,
  path : String,
  token : String,
  subject_ref : String,
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
async fn load_self_service_organizations(
  model : AppModel,
) -> Array[@enterprise_ui.SelfServiceOrganizationView] {
  let response : SelfServiceOrganizationsResponse = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/portal/self/organizations",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  if response.version == "" {
    raise Failure("organization response omitted its contract version")
  }
  response.organizations
}

///|
fn preferred_organization(
  organizations : Array[@enterprise_ui.SelfServiceOrganizationView],
  requested_id : String,
) -> @enterprise_ui.SelfServiceOrganizationView? {
  match
    organizations
    .iter()
    .find_first(value => {
      value.organization.organization_id == requested_id &&
      value.membership.active
    }) {
    Some(value) => Some(value)
    None =>
      if organizations.length() == 1 && organizations[0].membership.active {
        Some(organizations[0])
      } else {
        None
      }
  }
}

///|
fn organization_bootstrap_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let generation = model.session_generation
  let requested = model.portal.selected_organization_id.unwrap_or(
    stored_organization_preference(),
  )
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try load_self_service_organizations(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to load your organizations: \{error.to_string()}",
            "无法加载您的组织：\{error.to_string()}",
          ),
        )
    } noraise {
      organizations =>
        OrganizationsLoaded(generation, organizations, Some(requested))
    }
  })
}

///|
fn optional_trimmed(value : String) -> String? {
  let normalized = value.trim().to_owned()
  if normalized == "" {
    None
  } else {
    Some(normalized)
  }
}

///|
async fn create_self_service_organization(
  model : AppModel,
) -> @enterprise_ui.SelfServiceOrganizationView {
  let draft = model.portal.self_service
  let intent : SelfServiceOrganizationCreateIntent = {
    idempotency_key: random_identifier("organization-create"),
    display_name: draft.display_name.trim().to_owned(),
    legal_profile: {
      subject_kind: if draft.subject_kind == "Individual" {
        Individual
      } else {
        Company
      },
      legal_name: draft.legal_name.trim().to_owned(),
      country_code: draft.country_region.trim().to_owned().to_upper(),
      registration_number: optional_trimmed(draft.registration_number),
      tax_identifier: optional_trimmed(draft.tax_identifier),
      registered_address: draft.registered_address.trim().to_owned(),
      billing_contact: {
        display_name: draft.billing_contact_name.trim().to_owned(),
        email: draft.billing_email.trim().to_owned().to_lower(),
        phone: None,
      },
    },
  }
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/self/organizations",
    model.token,
    model.subject_ref,
    body=intent.to_json().stringify(),
  )
  @json.from_json(@json.parse(response))
}

///|
async fn join_self_service_organization(
  model : AppModel,
) -> @portal.EnterpriseMembership {
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/self/invitations:accept",
    model.token,
    model.subject_ref,
    body=SelfServiceInvitationAcceptIntent::{
        invitation_secret: model.portal.self_service.invitation_code
        .trim()
        .to_owned(),
      }
      .to_json()
      .stringify(),
  )
  let accepted : SelfServiceInvitationAcceptView = @json.from_json(
    @json.parse(response),
  )
  ignore(accepted.invitation)
  accepted.membership
}

///|
fn organization_create_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try create_self_service_organization(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to create the company: \{error.to_string()}",
            "无法创建公司：\{error.to_string()}",
          ),
        )
    } noraise {
      value => OrganizationCreated(value)
    }
  })
}

///|
fn organization_join_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try join_self_service_organization(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to accept the company invitation: \{error.to_string()}",
            "无法接受公司邀请：\{error.to_string()}",
          ),
        )
    } noraise {
      _ => OrganizationJoined
    }
  })
}

///|
fn machine_product(
  kind : @machinecommerce.MachineOfferingKind,
) -> @enterprise_ui.SelfServiceProduct {
  match kind {
    BareMachine => BareGpu
    DedicatedEndpoint => DedicatedMaaS
  }
}

///|
fn machine_order_status(
  state : @machinecommerce.MachineOrderState,
) -> @enterprise_ui.MachineOrderStatus {
  match state {
    AwaitingPayment => AwaitingPayment
    PaymentSettled => PaymentSettled
    Provisioning => ProvisioningOrder
    Active => ActiveOrder
    CancellationPending => CancellationPending
    TerminationPending => TerminationPending
    CompensationPending => CompensationPending
    Cancelled => CancelledOrder
    Terminated => TerminatedOrder
    Failed => FailedOrder
  }
}

///|
fn machine_money(value : @commercial.FixedMoney) -> String {
  if value.currency == "CNY" && value.scale == 2 {
    "CNY " + @contractdoc.format_cny_minor_units(value.minor_units)
  } else {
    value.currency +
    " " +
    value.minor_units.to_string() +
    " minor units · scale " +
    value.scale.to_string()
  }
}

///|
fn machine_offering_view(
  value : @machinecommerce.MachineOfferingView,
) -> @enterprise_ui.SelfServiceOfferingView {
  let offering = value.offering
  {
    offering_id: offering.offering_id,
    kind: machine_product(offering.kind),
    display_name: offering.display_name,
    gpu_sku: offering.accelerator_class,
    accelerator_count: offering.accelerator_count.to_int(),
    accelerator_memory_mib: offering.memory_mib.to_int(),
    regions: [offering.region],
    minimum_duration_hours: (offering.minimum_duration_seconds / 3600L).to_int(),
    maximum_duration_hours: (offering.maximum_duration_seconds / 3600L).to_int(),
    price_summary: machine_money(offering.unit_price) + " / second",
    allowed_model_template_refs: offering.allowed_model_template_refs,
    available: value.availability.capacity_available > 0L,
  }
}

///|
fn machine_quote_view(
  quote : @machinecommerce.MachineQuote,
) -> @enterprise_ui.SelfServiceQuoteView {
  {
    quote_id: quote.quote_id,
    offering_id: quote.offering_id,
    display_amount: machine_money(quote.total),
    expected_amount_minor: quote.total.minor_units,
    currency: quote.total.currency,
    money_scale: quote.total.scale,
    valid_until_unix_ms: quote.valid_until_unix_ms,
    terms_digest: quote.terms_digest,
  }
}

///|
fn machine_order_view(
  order : @machinecommerce.MachineOrder,
  offerings : Array[@enterprise_ui.SelfServiceOfferingView],
) -> @enterprise_ui.SelfServiceOrderView {
  let offering = offerings
    .iter()
    .find_first(value => value.offering_id == order.offering_id)
  {
    order_id: order.order_id,
    kind: machine_product(order.offering_kind),
    status: machine_order_status(order.state),
    project_id: order.project_id,
    gpu_sku: offering.map(value => value.gpu_sku).unwrap_or(order.offering_id),
    region: match offering {
      Some(value) => value.regions[0]
      None => "—"
    },
    duration_hours: (order.duration_seconds / 3600L).to_int(),
    model_selector: order.requested_model_selector,
    display_amount: machine_money(order.quoted_total),
    lease_ref: order.target_lease_ref,
    deployment_ref: order.target_deployment_ref,
    generation: order.generation,
    updated_unix_ms: order.updated_unix_ms,
  }
}

///|
fn checkout_state(
  state : @commercial_integrations.ExternalRecordState,
) -> String {
  match state {
    Pending => "Pending"
    Submitted => "Submitted"
    Verified => "Verified"
    Authorized => "Authorized"
    Settled => "Settled"
    Issued => "Issued"
    Failed => "Failed"
    Expired => "Expired"
    Voided => "Voided"
    Credited => "Credited"
    Refunded => "Refunded"
  }
}

///|
fn machine_checkout_view(
  checkout : @commercial_integrations.ExternalRecordView,
) -> @enterprise_ui.SelfServiceCheckoutView {
  {
    state: checkout_state(checkout.state),
    provider: checkout.provider,
    action_url: checkout.action_url,
    action_expires_unix_ms: checkout.action_expires_unix_ms,
  }
}

///|
fn machine_terms_view(
  terms : @commercial.AgreementTemplate,
) -> @enterprise_ui.SelfServiceTermsView? {
  match terms.document_uri {
    Some(document_uri) =>
      Some({
        template_id: terms.template_id,
        version: terms.version,
        locale: terms.locale,
        rendered_document_hash: terms.rendered_document_hash,
        document_uri,
      })
    None => None
  }
}

///|
fn sha256_label(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn machine_terms_acceptance_intent(
  terms : @enterprise_ui.SelfServiceTermsView,
  endpoint : String,
  organization_id : String,
  idempotency_key : String,
) -> SelfServiceMachineTermsAcceptanceIntent {
  {
    idempotency_key,
    template_version: terms.version,
    rendered_document_hash: terms.rendered_document_hash,
    document_uri: terms.document_uri,
    presentation_context_hash: sha256_label(
      "enterprise-ui:" +
      terms.template_id +
      ":" +
      terms.version +
      ":" +
      terms.rendered_document_hash,
    ),
    network_context_hash: sha256_label(
      "browser-session:" + endpoint + ":" + organization_id,
    ),
  }
}

///|
fn checkout_for_order(
  order : @enterprise_ui.SelfServiceOrderView?,
  records : Array[@commercial_integrations.ExternalRecordView],
) -> @enterprise_ui.SelfServiceCheckoutView? {
  guard order is Some(value) else { return None }
  let digest = sha256_label("machine-order:" + value.order_id)
  let mut selected : @commercial_integrations.ExternalRecordView? = None
  for record in records {
    if record.entitlement_transaction_ref_sha256 == Some(digest) {
      match selected {
        Some(current) if current.updated_unix_ms >= record.updated_unix_ms => ()
        _ => selected = Some(record)
      }
    }
  }
  selected.map(machine_checkout_view)
}

///|
async fn accept_machine_terms(
  model : AppModel,
) -> @commercial.ClickwrapAcceptance {
  guard model.portal.self_service.terms is Some(terms) &&
    @enterprise_ui.selected_organization_header(model.portal)
    is Some(organization_id) else {
    fail("machine terms or organization scope is unavailable")
  }
  let intent = machine_terms_acceptance_intent(
    terms,
    model.endpoint,
    organization_id,
    random_identifier("machine-terms"),
  )
  @json.from_json(
    @json.parse(
      request(
        "POST",
        model.endpoint,
        "/v1/portal/self/machine-terms/accept",
        model.token,
        model.subject_ref,
        body=intent.to_json().stringify(),
      ),
    ),
  )
}

///|
fn machine_terms_acceptance_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try accept_machine_terms(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to record machine terms acceptance: \{error.to_string()}",
            "无法记录机器条款接受证据：\{error.to_string()}",
          ),
        )
    } noraise {
      _ => MachineTermsAccepted
    }
  })
}

///|
async fn load_machine_commerce(
  model : AppModel,
) -> (
  Array[@machinecommerce.MachineOfferingView],
  Array[@machinecommerce.MachineOrder],
  @commercial.AgreementTemplate?,
  Array[@commercial_integrations.ExternalRecordView],
) {
  let terms : @commercial.AgreementTemplate? = try {
    let value : @commercial.AgreementTemplate = @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/portal/self/machine-terms",
          model.token,
          model.subject_ref,
        ),
      ),
    )
    value
  } catch {
    _ => None
  } noraise {
    value => Some(value)
  }
  let offerings : Array[@machinecommerce.MachineOfferingView] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/portal/self/machine-offerings",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let orders : Array[@machinecommerce.MachineOrder] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/portal/self/machine-orders",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let provider_requests = request_provider_requests(model)
  (offerings, orders, terms, provider_requests)
}

///|
fn machine_commerce_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try load_machine_commerce(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to load machine inventory and orders: \{error.to_string()}",
            "无法加载机器库存与订单：\{error.to_string()}",
          ),
        )
    } noraise {
      value => MachineCommerceLoaded(value.0, value.1, value.2, value.3)
    }
  })
}

///|
fn machine_quote_intent(
  state : @enterprise_ui.SelfServiceState,
  quote_id : String,
  idempotency_key : String,
) -> SelfServiceMachineQuoteIntent {
  let product = state.selected_product.unwrap_or(BareGpu)
  {
    quote_id,
    idempotency_key,
    project_id: state.project_id.trim().to_owned(),
    offering_id: state.selected_offering_id,
    quantity: 1L,
    duration_seconds: state.duration_hours.to_int64() * 3600L,
    unix_username: if product == BareGpu {
      Some(state.unix_username.trim().to_owned())
    } else {
      None
    },
    requested_model_selector: if product == DedicatedMaaS {
      optional_trimmed(state.model_selector)
    } else {
      None
    },
    model_template_ref: if product == DedicatedMaaS {
      optional_trimmed(state.model_template_ref)
    } else {
      None
    },
  }
}

///|
async fn request_machine_quote(
  model : AppModel,
) -> @machinecommerce.MachineQuote {
  let intent = machine_quote_intent(
    model.portal.self_service,
    random_identifier("machine-quote"),
    random_identifier("quote-request"),
  )
  @json.from_json(
    @json.parse(
      request(
        "POST",
        model.endpoint,
        "/v1/portal/self/machine-quotes",
        model.token,
        model.subject_ref,
        body=intent.to_json().stringify(),
      ),
    ),
  )
}

///|
fn machine_quote_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try request_machine_quote(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to create the signed machine quote: \{error.to_string()}",
            "无法创建签名机器报价：\{error.to_string()}",
          ),
        )
    } noraise {
      quote => MachineQuoteLoaded(quote)
    }
  })
}

///|
async fn create_machine_order(
  model : AppModel,
) -> SelfServiceMachineOrderResponse {
  guard model.portal.self_service.quote is Some(quote) else {
    fail("machine quote is unavailable")
  }
  let intent : SelfServiceMachineOrderIntent = {
    order_id: random_identifier("machine-order"),
    idempotency_key: random_identifier("order-create"),
    quote_id: quote.quote_id,
  }
  let response : SelfServiceMachineOrderResponse = @json.from_json(
    @json.parse(
      request(
        "POST",
        model.endpoint,
        "/v1/portal/self/machine-orders",
        model.token,
        model.subject_ref,
        body=intent.to_json().stringify(),
      ),
    ),
  )
  if response.entitlement_transaction_ref !=
    "machine-order:" + response.order.order_id {
    fail("machine checkout returned an invalid entitlement binding")
  }
  response
}

///|
fn machine_order_create_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try create_machine_order(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to create the machine order: \{error.to_string()}",
            "无法创建机器订单：\{error.to_string()}",
          ),
        )
    } noraise {
      value => MachineOrderCreated(value)
    }
  })
}

///|
async fn update_machine_order(
  model : AppModel,
  order_id : String,
  generation : Int64,
  action : String,
) -> @machinecommerce.MachineOrder {
  let intent : SelfServiceMachineOrderAction = {
    idempotency_key: random_identifier("order-" + action),
    expected_generation: generation,
    reason: if action == "cancel" {
      "Customer requested cancellation from enterprise self-service"
    } else {
      "Customer requested termination from enterprise self-service"
    },
  }
  @json.from_json(
    @json.parse(
      request(
        "POST",
        model.endpoint,
        "/v1/portal/self/machine-orders/" + order_id + "/" + action,
        model.token,
        model.subject_ref,
        body=intent.to_json().stringify(),
      ),
    ),
  )
}

///|
fn machine_order_action_command(
  model : AppModel,
  order_id : String,
  generation : Int64,
  action : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try update_machine_order(model, order_id, generation, action) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to \{action} the machine order: \{error.to_string()}",
            (if action == "cancel" {
              "无法取消机器订单："
            } else {
              "无法终止机器订单："
            }) +
            "\{error.to_string()}",
          ),
        )
    } noraise {
      order => MachineOrderUpdated(order, action)
    }
  })
}

///|
async fn launch_desktop_client(model : AppModel) -> String {
  guard model.portal.desktop_client is Some(client) else {
    raise Failure("desktop workspace integration is not configured")
  }
  if !client.ready {
    raise Failure("selected WebIDE access is not ready")
  }
  guard @enterprise_ui.webide_launch_selection(model.portal)
    is Some((order_id, project_id, allowed_models)) else {
    raise Failure("the selected WebIDE model source is not active and ready")
  }
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/self/client-handoffs",
    model.token,
    model.subject_ref,
    body=desktop_handoff_payload(
      random_identifier("desktop-handoff"),
      client.client_id,
      project_id,
      order_id,
      allowed_models,
    ).stringify(),
  )
  let launch : DesktopClientHandoffLaunch = @json.from_json(
    @json.parse(response),
  )
  if !launch.one_time ||
    launch.client_id != client.client_id ||
    launch.handoff_expires_unix_ms <= current_unix_ms() {
    raise Failure("controller returned an invalid desktop handoff")
  }
  open_desktop_client(launch.launch_uri, launch.client_id, launch.handoff_code)
  launch.display_name
}

///|
fn desktop_client_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try launch_desktop_client(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to open the desktop WebIDE: \{error.to_string()}",
            "无法打开桌面 WebIDE：\{error.to_string()}",
          ),
        )
    } noraise {
      name => DesktopClientLaunched(name)
    }
  })
}

///|
fn derive_payment_checkout_quote(
  commercial : @commercial.CommercialSnapshot?,
) -> @enterprise_ui.PaymentCheckoutQuote? {
  guard commercial is Some(snapshot) && snapshot.finalized_periods.length() > 0 else {
    return None
  }
  let mut selected : @commercial.FinalizedPeriod? = None
  for period in snapshot.finalized_periods {
    if period.total.minor_units > 0L &&
      (match selected {
        Some(current) => period.finalized_unix_ms > current.finalized_unix_ms
        None => true
      }) {
      selected = Some(period)
    }
  }
  guard selected is Some(period) &&
    period.total.scale >= 0 &&
    period.total.scale <= 9 else {
    return None
  }
  let total = period.total
  let entitlement_digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode("billing-period:\{period.period_id}")),
  )
  Some({
    period_id: period.period_id,
    expected_amount_minor: total.minor_units,
    currency: total.currency,
    money_scale: total.scale,
    display_amount: if total.currency == "CNY" && total.scale == 2 {
      "CNY \{@contractdoc.format_cny_minor_units(total.minor_units)}"
    } else {
      "\{total.currency} \{total.minor_units} minor units · scale \{total.scale}"
    },
    idempotency_key: "checkout-\{entitlement_digest}",
    entitlement_transaction_ref_sha256: "sha256:\{entitlement_digest}",
    ledger_entry_count: period.entry_ids.length(),
    ledger_revision_unix_ms: period.finalized_unix_ms,
  })
}

///|
async fn request_provider_requests(
  model : AppModel,
) -> Array[@commercial_integrations.ExternalRecordView] {
  let snapshot : @commercial_integrations.IntegrationSnapshot = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/portal/self/provider-requests",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  snapshot.records
}

///|
async fn load_self(
  model : AppModel,
) -> (
  @portal.EnterpriseSelfView,
  @enterprise_ui.AccountView?,
  @enterprise_ui.TrialEntitlementView?,
  Array[@enterprise_ui.BrowserSessionView],
  Array[@enterprise_ui.EnterpriseCostCenterRow],
  String,
  Array[@portal.EnterpriseModelSummary],
  Array[@notifications.NotificationRecord],
  Array[@notifications.NotificationPreferenceView],
  Array[@nodelease.CustomerExclusiveMachineView],
  Array[@offline.CommercialOrder],
  Array[@offline_commerce.OfflineArtifactSummary],
  Array[@contractdoc.ContractTemplateManifest],
  Array[@contractdoc.ContractPacket],
  Array[@contractdoc.ContractPacketEvent],
  ContractSelfGovernance,
  Array[@enterprise_ui.EnterpriseDesktopClient],
  Array[@enterprise_ui.ApiCredentialView],
  Array[@commercial_integrations.ExternalRecordView],
  @enterprise_ui.PaymentCheckoutQuote?,
) {
  let body = request(
    "GET",
    model.endpoint,
    "/v1/portal/self",
    model.token,
    model.subject_ref,
  )
  let view : @portal.EnterpriseSelfView = @json.from_json(@json.parse(body))
  let account : @enterprise_ui.AccountView? = if model.token.has_prefix("lnxs_") {
    Some(
      @json.from_json(
        @json.parse(
          request(
            "GET",
            model.endpoint,
            "/v1/auth/self",
            model.token,
            model.subject_ref,
          ),
        ),
      ),
    )
  } else {
    None
  }
  let trial : @enterprise_ui.TrialEntitlementView? = if model.token.has_prefix(
      "lnxs_",
    ) {
    @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/auth/trial",
          model.token,
          model.subject_ref,
        ),
      ),
    )
  } else {
    None
  }
  let browser_sessions : Array[@enterprise_ui.BrowserSessionView] = if model.token.has_prefix(
      "lnxs_",
    ) {
    @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/auth/sessions",
          model.token,
          model.subject_ref,
        ),
      ),
    )
  } else {
    []
  }
  // API keys are authority-bearing account state. A failed fetch must fail the
  // connection instead of presenting a misleading empty list.
  let api_keys : Array[@enterprise_ui.ApiCredentialView] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/portal/self/api-keys",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let commercial : @commercial.CommercialSnapshot? = try
    Some(
      @json.from_json(
        @json.parse(
          request(
            "GET",
            model.endpoint,
            "/v1/portal/self/commercial",
            model.token,
            model.subject_ref,
          ),
        ),
      ),
    )
  catch {
    _ => None
  } noraise {
    value => value
  }
  let provider_requests = request_provider_requests(model)
  let payment_checkout_quote = derive_payment_checkout_quote(commercial)
  let models : Array[@portal.EnterpriseModelSummary] = try
    @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/portal/self/models",
          model.token,
          model.subject_ref,
        ),
      ),
    )
  catch {
    _ => []
  } noraise {
    value => value
  }
  let notifications : Array[@notifications.NotificationRecord] = try
    @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/notifications/self",
          model.token,
          model.subject_ref,
        ),
      ),
    )
  catch {
    _ => []
  } noraise {
    value => value
  }
  let notification_preferences : Array[
    @notifications.NotificationPreferenceView,
  ] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/notifications/self/preferences",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let machines : Array[@nodelease.CustomerExclusiveMachineView] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/machine-access/self",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  // Orders and referenced evidence are authority-bearing. A partial response
  // must remain an error instead of looking like an empty commercial record.
  let orders : Array[@offline.CommercialOrder] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/offline-commerce/self/orders",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let artifacts : Array[@offline_commerce.OfflineArtifactSummary] = []
  for order in orders {
    for artifact_id in order.artifact_ids {
      let value : OfflineArtifactView = @json.from_json(
        @json.parse(
          request(
            "GET",
            model.endpoint,
            "/v1/offline-commerce/self/artifacts/\{artifact_id}",
            model.token,
            model.subject_ref,
          ),
        ),
      )
      ignore(value.locale)
      ignore(value.generation_state)
      artifacts.push({
        artifact_id: value.artifact_id,
        order_id: value.order_id,
        kind: value.kind,
        revision: value.revision,
        media_type: value.media_type,
        byte_count: value.byte_count,
        sha256: value.sha256,
        scan_state: value.scan_state,
        review_state: value.review_state,
        submitted_by: "customer-evidence",
        created_unix_ms: value.created_unix_ms,
      })
    }
  }
  let contract_manifest : Array[@contractdoc.ContractTemplateManifest] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/contract-documents/manifest/catalog",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let contract_packets : Array[@contractdoc.ContractPacket] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/contract-documents/self",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let contract_events : Array[@contractdoc.ContractPacketEvent] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/contract-documents/self/events",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let contract_governance : ContractSelfGovernance = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/contract-documents/self/governance",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let desktop_client : Array[@enterprise_ui.EnterpriseDesktopClient] = try {
    let responses : Array[DesktopClientResponse] = @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/portal/self/clients",
          model.token,
          model.subject_ref,
        ),
      ),
    )
    responses.map(response => {
      (
        {
          client_id: response.client_id,
          display_name: response.display_name,
          launch_uri: response.launch_uri,
          handoff_lifetime_ms: response.handoff_lifetime_ms,
          connected_handoffs: response.handoffs.length(),
          contract_ready: response.contract_ready,
          workspace_ready: response.workspace_ready,
          models_ready: response.models_ready,
          ready: response.ready,
          blocker_codes: response.blocker_codes,
          approved_model_aliases: response.approved_model_aliases,
        } : @enterprise_ui.EnterpriseDesktopClient)
    })
  } catch {
    _ => []
  } noraise {
    value => value
  }
  let cost_centers : Array[@enterprise_ui.EnterpriseCostCenterRow] = match
    commercial {
    Some(snapshot) =>
      [
        for center in snapshot.cost_centers => {
          let projects = snapshot.projects.filter(project => {
            project.cost_center_id == center.cost_center_id
          })
          let entries = snapshot.ledger_entries.filter(entry => {
            entry.cost_center_id == center.cost_center_id
          })
          let mut minor_units = 0L
          let mut currency = ""
          let mut scale = 0
          for entry in entries {
            minor_units = minor_units + entry.amount.minor_units
            currency = entry.amount.currency
            scale = entry.amount.scale
          }
          {
            cost_center_id: center.cost_center_id,
            display_name: center.display_name,
            project_count: projects.length(),
            provisional_spend: if entries.length() == 0 {
              "—"
            } else {
              "\{currency} \{minor_units} minor units · scale \{scale}"
            },
            budget_posture: "\{snapshot.budgets.length()} budget policies",
          }
        }
      ]
    None => []
  }
  let provisional_spend = match commercial {
    Some(snapshot) if snapshot.ledger_entries.length() > 0 => {
      let first = snapshot.ledger_entries[0].amount
      let mut minor_units = 0L
      for entry in snapshot.ledger_entries {
        minor_units = minor_units + entry.amount.minor_units
      }
      "\{first.currency} \{minor_units} minor units · scale \{first.scale}"
    }
    _ => "—"
  }
  (
    view, account, trial, browser_sessions, cost_centers, provisional_spend, models,
    notifications, notification_preferences, machines, orders, artifacts, contract_manifest,
    contract_packets, contract_events, contract_governance, desktop_client, api_keys,
    provider_requests, payment_checkout_quote,
  )
}

///|
async fn request_signature(
  model : AppModel,
  agreement_id : String,
) -> (
  @portal.PortalAgreement,
  Array[@commercial_integrations.ExternalRecordView],
) {
  let mut selected : @portal.PortalAgreement? = None
  for value in model.portal.agreements {
    if value.agreement_id == agreement_id {
      selected = Some(value)
    }
  }
  guard selected is Some(agreement) else { fail("agreement is unavailable") }
  let body = @portal.SignatureRequest::{
      agreement_id,
      expected_generation: agreement.generation,
      idempotency_key: random_identifier("sign"),
    }
    .to_json()
    .stringify()
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/signature-requests",
    model.token,
    model.subject_ref,
    body~,
  )
  let agreement : @portal.PortalAgreement = @json.from_json(
    @json.parse(response),
  )
  (agreement, request_provider_requests(model))
}

///|
async fn request_payment_checkout(
  model : AppModel,
) -> @commercial_integrations.ExternalRecordView {
  guard model.portal.payment_checkout_quote is Some(quote) else {
    fail("payment checkout quote is unavailable")
  }
  let body = PaymentCheckoutIntent::{
      idempotency_key: quote.idempotency_key,
      period_id: quote.period_id,
    }
    .to_json()
    .stringify()
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/payment-checkouts",
    model.token,
    model.subject_ref,
    body~,
  )
  @json.from_json(@json.parse(response))
}

///|
fn requested_models(value : String) -> Array[String] {
  value
  .split(",")
  .map(part => part.trim().to_owned())
  .filter(part => part != "")
  .to_array()
}

///|
async fn submit_lease(model : AppModel) -> @portal.EnterpriseLeaseRequest {
  guard model.portal.membership is Some(membership) else {
    fail("enterprise membership is unavailable")
  }
  let identifier = random_identifier("lease-request")
  let body = @portal.LeaseRequestSubmission::{
      request_id: identifier,
      idempotency_key: random_identifier("submit"),
      tenant_ref: membership.tenant_ref,
      organization_id: membership.organization_id,
      project_id: model.portal.project_id.trim().to_owned(),
      unix_username: model.portal.unix_username.trim().to_owned(),
      starts_unix_ms: model.portal.starts_unix_ms,
      expires_unix_ms: model.portal.expires_unix_ms,
      requested_model_ids: requested_models(model.portal.model_ids),
      justification: model.portal.justification.trim().to_owned(),
    }
    .to_json()
    .stringify()
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/lease-requests",
    model.token,
    model.subject_ref,
    body~,
  )
  @json.from_json(@json.parse(response))
}

///|
async fn mark_notification_read(
  model : AppModel,
  notification_id : String,
  generation : Int64,
) -> @notifications.NotificationRecord {
  let body = "{\"expected_generation\":\"\{generation}\"}"
  let response = request(
    "POST",
    model.endpoint,
    "/v1/notifications/self/\{notification_id}:read",
    model.token,
    model.subject_ref,
    body~,
  )
  @json.from_json(@json.parse(response))
}

///|
async fn update_notification_preference(
  model : AppModel,
  topic : @notifications.NotificationTopic,
  email_enabled : Bool,
) -> @notifications.NotificationPreferenceView {
  let body = {
      "topic": topic.to_json(),
      "channels": if email_enabled {
        let channels : Array[@notifications.NotificationChannel] = [
          InApp,
          Email,
        ]
        channels.to_json()
      } else {
        let channels : Array[@notifications.NotificationChannel] = [InApp]
        channels.to_json()
      },
      "minimum_severity": @notifications.NotificationSeverity::Information.to_json(),
    }
    .to_json()
    .stringify()
  let response = request(
    "PUT",
    model.endpoint,
    "/v1/notifications/self/preferences",
    model.token,
    model.subject_ref,
    body~,
  )
  @json.from_json(@json.parse(response))
}

///|
async fn terminate_machine_access(
  model : AppModel,
  lease_ref : String,
  generation : Int64,
  confirmation : String,
) -> @nodelease.CustomerExclusiveMachineView {
  let body = @nodelease.CustomerExclusiveLeaseTerminationRequest::{
      expected_generation: generation,
      confirmation,
      reason: "customer-requested",
    }
    .to_json()
    .stringify()
  let response = request(
    "POST",
    model.endpoint,
    "/v1/machine-access/self/\{lease_ref}:terminate",
    model.token,
    model.subject_ref,
    body~,
  )
  @json.from_json(@json.parse(response))
}

///|
async fn redeem_machine_credential(
  model : AppModel,
  lease_ref : String,
  generation : Int64,
) -> @credential.CredentialHandoffRedemption {
  let response = request(
    "POST",
    model.endpoint,
    "/v1/machine-access/self/\{lease_ref}/credential:redeem",
    model.token,
    model.subject_ref,
    body=({ "expected_generation": generation } : Json).stringify(),
  )
  @json.from_json(@json.parse(response))
}

///|
async fn create_offline_order(model : AppModel) -> @offline.CommercialOrder {
  let commerce = model.portal.offline_commerce
  let requested_term = commerce.undertaking_term.trim().to_owned()
  let intent : OfflineOrderIntent = {
    order_id: random_identifier("offline-order"),
    idempotency_key: random_identifier("offline-order-create"),
    project_id: commerce.project_id.trim().to_owned(),
    selected_service_code: commerce.service_code.trim().to_owned(),
    selected_sla_code: commerce.sla_code.trim().to_owned(),
    expires_unix_ms: current_unix_ms() + 2592000000L,
    requested_undertaking_term: match
      @offline.undertaking_term_tier(requested_term) {
      Some(_) => Some(requested_term)
      None => None
    },
  }
  let response = request(
    "POST",
    model.endpoint,
    "/v1/offline-commerce/self/orders",
    model.token,
    model.subject_ref,
    body=intent.to_json().stringify(),
  )
  @json.from_json(@json.parse(response))
}

///|
fn next_artifact_revision(
  state : @offline_commerce.OfflineCommerceState,
  order_id : String,
  kind : @offline.DocumentArtifactKind,
) -> Int {
  let mut revision = 1
  for artifact in state.artifacts {
    if artifact.order_id == order_id &&
      artifact.kind == kind &&
      artifact.revision >= revision {
      revision = artifact.revision + 1
    }
  }
  revision
}

///|
async fn request_offline_upload_grant(
  model : AppModel,
  order_id : String,
  kind : @offline.DocumentArtifactKind,
) -> OfflineUploadTransferView {
  let artifact_id = random_identifier("offline-artifact")
  let intent : SelfUploadIntent = {
    grant_id: random_identifier("offline-upload-grant"),
    idempotency_key: random_identifier("offline-upload"),
    order_id,
    artifact_id,
    kind,
    revision: next_artifact_revision(
      model.portal.offline_commerce,
      order_id,
      kind,
    ),
    allowed_media_types: @offline.expected_media_type(kind),
    maximum_byte_count: 26214400L,
    expires_unix_ms: current_unix_ms() + 3600000L,
  }
  let response = request(
    "POST",
    model.endpoint,
    "/v1/offline-commerce/self/upload-grants",
    model.token,
    model.subject_ref,
    body=intent.to_json().stringify(),
  )
  let grant : OfflineUploadTransferView = @json.from_json(@json.parse(response))
  if grant.transfer.session_id != "transfer-\{grant.evidence.grant_id}" ||
    grant.transfer.direction != UploadTransfer {
    raise Failure("upload transfer grant is not bound to its evidence grant")
  }
  grant
}

///|
async fn upload_offline_evidence(
  transfer : @offline.OfflineTransferGrant,
) -> String {
  let value = upload_file_promise(
    transfer.transfer_path,
    transfer.session_token,
    transfer.media_types.join(","),
    transfer.maximum_byte_count,
  ).wait()
  value.cast()
}

///|
async fn request_and_download_offline_artifact(
  model : AppModel,
  artifact_id : String,
) -> String {
  let intent : SelfDownloadIntent = {
    session_id: random_identifier("offline-download"),
    idempotency_key: random_identifier("offline-download-idempotency"),
  }
  let response = request(
    "POST",
    model.endpoint,
    "/v1/offline-commerce/self/artifacts/\{artifact_id}:download",
    model.token,
    model.subject_ref,
    body=intent.to_json().stringify(),
  )
  let transfer : @offline.OfflineTransferGrant = @json.from_json(
    @json.parse(response),
  )
  guard transfer.expected_sha256 is Some(expected_sha256) else {
    raise Failure("download grant is not bound to an artifact digest")
  }
  let value = download_file_promise(
    transfer.transfer_path,
    transfer.session_token,
    transfer.maximum_byte_count,
    expected_sha256,
    artifact_id,
    offline_download_digest,
  ).wait()
  value.cast()
}

///|
async fn issue_api_key(model : AppModel) -> @enterprise_ui.IssuedApiKeyView {
  let draft = model.portal.api_key_issue_draft
  let requested_expiry = current_unix_ms() +
    draft.lifetime_days.to_int64() * 86400000L
  let expires_unix_ms = match model.portal.trial {
    Some(trial) if trial.revoked_unix_ms is None &&
      trial.expires_unix_ms < requested_expiry => trial.expires_unix_ms
    _ => requested_expiry
  }
  let intent : PortalApiKeyIssueIntent = {
    key_id: random_identifier("api-key"),
    project_id: model.portal.project_id.trim().to_owned(),
    display_name: draft.display_name.trim().to_owned(),
    scopes: @enterprise_ui.api_key_scopes(model.portal),
    allowed_models: @enterprise_ui.api_key_allowed_models(model.portal),
    expires_unix_ms,
    maximum_requests: draft.maximum_requests,
  }
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/self/api-keys",
    model.token,
    model.subject_ref,
    body=intent.to_json().stringify(),
  )
  @json.from_json(@json.parse(response))
}

///|
fn api_key_issue_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try issue_api_key(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to create the API key: \{error.to_string()}",
            "无法创建 API 密钥：\{error.to_string()}",
          ),
        )
    } noraise {
      value => ApiKeyIssued(model.session_generation, value)
    }
  })
}

///|
async fn revoke_api_key(
  model : AppModel,
  key_id : String,
) -> PortalApiKeyRevokeView {
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/self/api-keys/\{key_id}:revoke",
    model.token,
    model.subject_ref,
    body="{}",
  )
  @json.from_json(@json.parse(response))
}

///|
fn api_key_revoke_command(
  model : AppModel,
  key_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try revoke_api_key(model, key_id) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to revoke the API key: \{error.to_string()}",
            "无法撤销 API 密钥：\{error.to_string()}",
          ),
        )
    } noraise {
      value =>
        ApiKeyRevoked(
          model.session_generation,
          value.key_id,
          value.revoked_unix_ms,
        )
    }
  })
}

///|
fn copy_api_key_secret_command(
  model : AppModel,
  secret : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try copy_text_promise(secret).wait() catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Clipboard access failed. Select and copy the secret manually: \{error.to_string()}",
            "无法访问剪贴板。请手动选择并复制密钥：\{error.to_string()}",
          ),
        )
    } noraise {
      _ => ApiKeySecretCopied(model.session_generation)
    }
  })
}

///|
fn bootstrap_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let generation = model.session_generation
  @rabbita.perform(result => emit(result), async fn() noraise {
    try {
      let body : String = gateway_session_promise().wait().cast()
      let session : GatewayBrowserBootstrap = @json.from_json(@json.parse(body))
      if !session.session_token.has_prefix("lnxs_") ||
        session.csrf_token == "" ||
        session.expires_unix_ms <= current_unix_ms() {
        raise Failure("gateway returned an invalid or expired browser session")
      }
      BootstrapReady(generation, session)
    } catch {
      _ => BootstrapUnavailable(generation)
    }
  })
}

///|
fn gateway_auth_error_code(body : String) -> String {
  (@json.from_json(@json.parse(body)) : GatewayAuthError).error catch {
    _ => ""
  }
}

///|
/// Map the gateway's refusal onto customer-facing copy. The gateway collapses
/// its own failures into a small set of codes precisely so the browser never
/// learns more than the class of refusal.
fn gateway_auth_refusal(
  locale : @i18n.Locale,
  outcome : GatewayAuthOutcome,
  registering : Bool,
) -> String {
  match gateway_auth_error_code(outcome.body) {
    "email-taken" =>
      portal_copy(
        locale, "That address already has an account. Sign in instead, or use another address.",
        "该邮箱已注册。请直接登录，或改用其他邮箱。",
      )
    "password-rejected" =>
      portal_copy(
        locale, "The identity provider rejected this password. It must be at least 12 characters and contain an uppercase letter, a lowercase letter, a digit and a symbol, and must not contain your address or username.",
        "身份提供商拒绝了该密码。密码至少 12 位，且需包含大写字母、小写字母、数字和符号，并且不能包含邮箱或用户名。",
      )
    "registration-unavailable" =>
      portal_copy(
        locale, "Self-registration is not available on this deployment yet. Ask a platform administrator to create the account.",
        "当前部署尚未开放自助注册。请联系平台管理员创建账户。",
      )
    "invalid-registration-request" =>
      portal_copy(
        locale, "The registration form was incomplete. A valid email address, a display name and a password are all required.",
        "注册信息不完整。邮箱、名称和密码都必须填写。",
      )
    "invalid-credentials" =>
      portal_copy(
        locale, "The address or password was not accepted. Check both and try again.",
        "邮箱或密码不正确，请检查后重试。",
      )
    "identity-rejected" =>
      portal_copy(
        locale, "Signed in, but this identity cannot be used yet. Ask a platform administrator to enable the account.",
        "登录成功，但该身份暂时不可用。请联系平台管理员启用账户。",
      )
    "identity-provider-unavailable" =>
      portal_copy(
        locale, "The identity provider is unavailable. Try again shortly.", "身份提供商当前不可用，请稍后重试。",
      )
    "too-many-attempts" =>
      portal_copy(
        locale, "Too many failed attempts from this address. Wait five minutes and try again.",
        "此地址的失败尝试过多，请等待五分钟后再试。",
      )
    _ =>
      if registering {
        portal_copy(
          locale, "The gateway refused the registration.", "网关拒绝了本次注册。",
        )
      } else {
        portal_copy(
          locale, "The gateway refused the sign-in.", "网关拒绝了本次登录。",
        )
      }
  }
}

///|
/// A refusal the gateway named, carried to the update loop as the copy the
/// customer reads. Every other failure of the same call is a transport or
/// decoding failure and reads as an unreachable gateway instead.
priv suberror GatewayAuthFailure {
  GatewayRefused(String)
}

///|
/// Exchange the customer's address and password, or a new account, for a
/// gateway session. The gateway is the only party that sees the identity
/// provider's client secret; what comes back is the same session document the
/// OIDC callback produces, so everything below the gate is unchanged.
fn gateway_auth_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let generation = model.session_generation
  let locale = model.portal.locale
  let registering = model.registering
  let email = model.login_email
  let password = model.login_password
  let display_name = model.register_display_name
  @rabbita.perform(result => emit(result), async fn() noraise {
    try {
      let text : String = if registering {
        registration_promise(email, display_name, password).wait().cast()
      } else {
        password_login_promise(email, password).wait().cast()
      }
      let outcome : GatewayAuthOutcome = @json.from_json(@json.parse(text))
      guard outcome.status == 200 || outcome.status == 201 else {
        raise GatewayRefused(gateway_auth_refusal(locale, outcome, registering))
      }
      let session : GatewayBrowserBootstrap = @json.from_json(
        @json.parse(outcome.body),
      )
      if !session.session_token.has_prefix("lnxs_") ||
        session.csrf_token == "" ||
        session.expires_unix_ms <= current_unix_ms() {
        raise Failure("gateway returned an invalid or expired browser session")
      }
      BootstrapReady(generation, session)
    } catch {
      GatewayRefused(message) => EnterpriseAuthRefused(locale, message)
      _ =>
        EnterpriseAuthRefused(
          locale,
          portal_copy(
            locale, "The identity gateway could not be reached.", "无法连接身份网关。",
          ),
        )
    }
  })
}

///|
fn logout_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let generation = model.session_generation + 1L
  @rabbita.perform(value => emit(LogoutCompleted(value)), async fn() noraise {
    try {
      ignore(
        request(
          "POST",
          model.endpoint,
          "/v1/auth/logout",
          model.token,
          model.subject_ref,
          body="{}",
        ),
      )
      if model.csrf_token != "" {
        ignore(gateway_logout_promise(model.csrf_token).wait())
      }
      generation
    } catch {
      // Local secret erasure is immediate even if remote revocation cannot be
      // confirmed. The gateway's short expiry remains the fail-safe.
      _ => {
        try {
          if model.csrf_token != "" {
            ignore(gateway_logout_promise(model.csrf_token).wait())
          }
        } catch {
          _ => ()
        }
        generation
      }
    }
  })
}

///|
fn load_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try load_self(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to load enterprise access: \{error.to_string()}",
            "无法加载企业访问权限：\{error.to_string()}",
          ),
        )
    } noraise {
      (
        view,
        account,
        trial,
        browser_sessions,
        cost_centers,
        provisional_spend,
        models,
        notifications,
        notification_preferences,
        machines,
        orders,
        artifacts,
        contract_manifest,
        contract_packets,
        contract_events,
        contract_governance,
        desktop_client,
        api_keys,
        provider_requests,
        payment_checkout_quote,
      ) =>
        Loaded(
          model.session_generation,
          view,
          account,
          trial,
          browser_sessions,
          cost_centers,
          provisional_spend,
          models,
          notifications,
          notification_preferences,
          machines,
          orders,
          artifacts,
          contract_manifest,
          contract_packets,
          contract_events,
          contract_governance,
          desktop_client,
          api_keys,
          provider_requests,
          payment_checkout_quote,
        )
    }
  })
}

///|
fn offline_order_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try create_offline_order(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to create the offline order: \{error.to_string()}",
            "无法创建线上线下协同订单：\{error.to_string()}",
          ),
        )
    } noraise {
      value => OfflineOrderCreated(value)
    }
  })
}

///|
fn offline_order_cancellation_command(
  model : AppModel,
  order_id : String,
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try {
      let body : SelfOfflineOrderAction = {
        order_id,
        expected_generation: generation,
      }
      let response = request(
        "POST",
        model.endpoint,
        "/v1/offline-commerce/self/orders/\{order_id}:cancel",
        model.token,
        model.subject_ref,
        body=body.to_json().stringify(),
      )
      let order : @offline.CommercialOrder = @json.from_json(
        @json.parse(response),
      )
      OfflineOrderCancelled(order)
    } catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to cancel the order or end access: \{error.to_string()}",
            "无法取消订单或结束访问：\{error.to_string()}",
          ),
        )
    }
  })
}

///|
fn offline_upload_grant_command(
  model : AppModel,
  order_id : String,
  kind : @offline.DocumentArtifactKind,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try {
      let grant = request_offline_upload_grant(model, order_id, kind)
      upload_offline_evidence(grant.transfer)
    } catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to create the evidence upload grant: \{error.to_string()}",
            "无法创建凭证上传授权：\{error.to_string()}",
          ),
        )
    } noraise {
      filename => EvidenceUploaded(filename)
    }
  })
}

///|
fn offline_artifact_download_command(
  model : AppModel,
  artifact_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try request_and_download_offline_artifact(model, artifact_id) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to download the verified artifact: \{error.to_string()}",
            "无法下载已验证文件：\{error.to_string()}",
          ),
        )
    } noraise {
      filename => ArtifactDownloaded(filename)
    }
  })
}

///|
fn notification_read_command(
  model : AppModel,
  notification_id : String,
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try mark_notification_read(model, notification_id, generation) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to update notification: \{error.to_string()}",
            "无法更新通知：\{error.to_string()}",
          ),
        )
    } noraise {
      value => NotificationRead(value)
    }
  })
}

///|
fn notification_preference_command(
  model : AppModel,
  topic : @notifications.NotificationTopic,
  email_enabled : Bool,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try update_notification_preference(model, topic, email_enabled) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to update delivery preferences: \{error.to_string()}",
            "无法更新投递偏好：\{error.to_string()}",
          ),
        )
    } noraise {
      value => NotificationPreferenceUpdated(value)
    }
  })
}

///|
fn machine_termination_command(
  model : AppModel,
  lease_ref : String,
  generation : Int64,
  confirmation : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try
      terminate_machine_access(model, lease_ref, generation, confirmation)
    catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to terminate machine access: \{error.to_string()}",
            "无法终止机器访问：\{error.to_string()}",
          ),
        )
    } noraise {
      value => MachineTerminated(value)
    }
  })
}

///|
fn credential_redemption_command(
  model : AppModel,
  lease_ref : String,
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try redeem_machine_credential(model, lease_ref, generation) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to redeem machine access: \{error.to_string()}",
            "无法领取机器访问凭据：\{error.to_string()}",
          ),
        )
    } noraise {
      value => CredentialRedeemed(value)
    }
  })
}

///|
fn machine_clock_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let now = model.portal.machine_access.now_unix_ms
  let expiries = [
    for machine in model.portal.machine_access.machines if machine.expires_unix_ms >
    now &&
    machine.state != Completed &&
    machine.state != Cancelled => machine.expires_unix_ms
  ]
  match model.session_expires_unix_ms {
    Some(expires_unix_ms) if expires_unix_ms > now =>
      expiries.push(expires_unix_ms)
    _ => ()
  }
  guard expiries.length() > 0 else { return @rabbita.none }
  expiries.sort()
  let next_expiry = expiries[0]
  let generation = model.machine_clock_generation
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try machine_clock_promise(next_expiry).wait() catch {
      _ => MachineClockAdvanced(current_unix_ms(), generation)
    } noraise {
      value => MachineClockAdvanced(value.cast(), generation)
    }
  })
}

///|
fn replace_machine(
  values : Array[@nodelease.CustomerExclusiveMachineView],
  updated : @nodelease.CustomerExclusiveMachineView,
) -> Array[@nodelease.CustomerExclusiveMachineView] {
  [
    for value in values => {
      if value.lease_ref == updated.lease_ref {
        updated
      } else {
        value
      }
    }
  ]
}

///|
fn replace_notification(
  values : Array[@notifications.NotificationRecord],
  updated : @notifications.NotificationRecord,
) -> Array[@notifications.NotificationRecord] {
  [
    for value in values => {
      if value.event.notification_id == updated.event.notification_id {
        updated
      } else {
        value
      }
    }
  ]
}

///|
fn replace_notification_preference(
  values : Array[@notifications.NotificationPreferenceView],
  updated : @notifications.NotificationPreferenceView,
) -> Array[@notifications.NotificationPreferenceView] {
  let mut found = false
  let result = [
    for value in values => {
      if value.topic == updated.topic {
        found = true
        updated
      } else {
        value
      }
    }
  ]
  if !found {
    result.push(updated)
  }
  result
}

///|
fn signature_command(
  model : AppModel,
  agreement_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try request_signature(model, agreement_id) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Signature request was rejected: \{error.to_string()}",
            "签署请求被拒绝：\{error.to_string()}",
          ),
        )
    } noraise {
      (agreement, provider_requests) =>
        AgreementUpdated(agreement, provider_requests)
    }
  })
}

///|
fn provider_requests_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try request_provider_requests(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Provider status could not be refreshed: \{error.to_string()}",
            "无法刷新服务商状态：\{error.to_string()}",
          ),
        )
    } noraise {
      records => ProviderRequestsLoaded(records)
    }
  })
}

///|
fn payment_checkout_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try request_payment_checkout(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Checkout request was rejected: \{error.to_string()}",
            "支付请求被拒绝：\{error.to_string()}",
          ),
        )
    } noraise {
      record => PaymentCheckoutCreated(record)
    }
  })
}

///|
fn lease_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try submit_lease(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Lease request was rejected: \{error.to_string()}",
            "租用申请被拒绝：\{error.to_string()}",
          ),
        )
    } noraise {
      value => LeaseCreated(value)
    }
  })
}

///|
fn replace_contract_packet(
  values : Array[@contractdoc.ContractPacket],
  updated : @contractdoc.ContractPacket,
) -> Array[@contractdoc.ContractPacket] {
  let mut found = false
  let next = [
    for value in values => {
      if value.packet_id == updated.packet_id {
        found = true
        updated
      } else {
        value
      }
    }
  ]
  if !found {
    next.push(updated)
  }
  next
}

///|
fn merge_contract_draft(
  draft : Array[@contractdoc.ContractFieldValue],
  updated : @contractdoc.ContractPacket,
) -> Array[@contractdoc.ContractFieldValue] {
  let values : Map[String, String] = Map([])
  for item in draft {
    values[item.field_id] = item.value
  }
  for item in updated.values {
    values[item.field_id] = item.value
  }
  let merged = values
    .to_array()
    .map(pair => @contractdoc.ContractFieldValue::{
      field_id: pair.0,
      value: pair.1,
    })
  merged.sort_by((left, right) => left.field_id.compare(right.field_id))
  merged
}

///|
async fn update_contract_information(
  model : AppModel,
  packet_id : String,
  expected_revision : Int64,
  changes : Array[@contractdoc.ContractFieldValue],
) -> @contractdoc.ContractPacket {
  let response = request(
    "PUT",
    model.endpoint,
    "/v1/contract-documents/self/\{packet_id}:information",
    model.token,
    model.subject_ref,
    body=ContractInformationUpdate::{ expected_revision, changes, }
      .to_json()
      .stringify(),
  )
  @json.from_json(@json.parse(response))
}

///|
async fn contract_revision_action(
  model : AppModel,
  packet_id : String,
  expected_revision : Int64,
  expected_values_sha256 : String?,
  suffix : String,
) -> @contractdoc.ContractPacket {
  let response = request(
    "POST",
    model.endpoint,
    "/v1/contract-documents/self/\{packet_id}:\{suffix}",
    model.token,
    model.subject_ref,
    body=ContractRevisionAction::{ expected_revision, expected_values_sha256, }
      .to_json()
      .stringify(),
  )
  @json.from_json(@json.parse(response))
}

///|
async fn renew_contract_packet(
  model : AppModel,
  source_packet_id : String,
) -> @contractdoc.ContractPacket {
  let response = request(
    "POST",
    model.endpoint,
    "/v1/contract-documents/self/\{source_packet_id}:renew",
    model.token,
    model.subject_ref,
    body=ContractRenewalIntent::{
        packet_id: random_identifier("contract-renewal"),
        idempotency_key: random_identifier("contract-renewal-idempotency"),
      }
      .to_json()
      .stringify(),
  )
  @json.from_json(@json.parse(response))
}

///|
async fn contract_preview(
  model : AppModel,
  packet_id : String,
  expected_revision : Int64,
  form : @contractdoc.ContractFormKind,
  changes : Array[@contractdoc.ContractFieldValue],
) -> @contractdoc.ContractPreviewDocument {
  let response = request(
    "POST",
    model.endpoint,
    "/v1/contract-documents/self/\{packet_id}:preview",
    model.token,
    model.subject_ref,
    body=ContractPreviewIntent::{ expected_revision, form, changes, }
      .to_json()
      .stringify(),
  )
  @json.from_json(@json.parse(response))
}

///|
async fn demo_contract_preview(
  model : AppModel,
  packet_id : String,
  form : @contractdoc.ContractFormKind,
  changes : Array[@contractdoc.ContractFieldValue],
) -> @contractdoc.ContractPreviewDocument {
  guard model.portal.contract_documents.current_manifest() is Some(manifest) else {
    fail("contract manifest unavailable")
  }
  let text : String = demo_contract_preview_promise(manifest.template_id)
    .wait()
    .cast()
  let template : @contractdoc.ContractPreviewTemplate = @json.from_json(
    @json.parse(text),
  )
  guard model.portal.contract_documents.packets.search_by(packet => {
      packet.packet_id == packet_id
    })
    is Some(index) else {
    fail("contract packet unavailable")
  }
  @contractdoc.materialize_preview_template(
    template,
    manifest,
    model.portal.contract_documents.packets[index],
    model.portal.contract_documents.actor_owner,
    form,
    changes,
  )
}

///|
/// Demo confirmation digests are placeholders with the documented digest
/// shape: no controller hashes the packet in demo mode, but the lifecycle
/// rules and the generation request round-trip still carry the value.
let demo_values_digest : String = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

///|
/// Applies one demo contract action to the seeded packet with the real
/// lifecycle rules. Generation completes immediately with illustrative
/// artifact records; the placeholder digests only need the documented shape.
fn demo_contract_transition(
  packet : @contractdoc.ContractPacket,
  manifest : @contractdoc.ContractTemplateManifest,
  message : @contract_documents.ContractDocumentsMessage,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket raise @contractdoc.ContractDocumentError {
  match message {
    SaveInformation(_, expected_revision, changes) =>
      packet.update_information(
        manifest,
        expected_revision,
        changes,
        CustomerMessenger,
        packet.subject_ref,
        "portal-contract-form:demo",
        now_unix_ms,
      )
    ConfirmAction(ConfirmInformation(_, expected_revision)) =>
      packet.confirm_information(
        manifest,
        expected_revision,
        demo_values_digest,
        packet.subject_ref,
        now_unix_ms,
      )
    ConfirmAction(RequestGeneration(_, expected_revision, digest)) => {
      let requested = packet.request_generation(
        expected_revision, digest, now_unix_ms,
      )
      let evidence = "sha256:2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"
      let docx : @contractdoc.ContractGeneratedArtifact = {
        artifact_id: "\{packet.packet_id}-docx-demo",
        media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        sha256: "sha256:fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9",
        byte_count: 419200L,
        page_count: manifest.page_count,
        render_evidence_sha256: evidence,
        generated_unix_ms: now_unix_ms,
      }
      let pdf : @contractdoc.ContractGeneratedArtifact = {
        artifact_id: "\{packet.packet_id}-pdf-demo",
        media_type: "application/pdf",
        sha256: "sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c",
        byte_count: 722000L,
        page_count: manifest.page_count,
        render_evidence_sha256: evidence,
        generated_unix_ms: now_unix_ms,
      }
      requested.complete_generation(requested.revision, docx, pdf, now_unix_ms)
    }
    ConfirmAction(RequestRenewal(_)) =>
      packet.renewal_draft(
        manifest,
        random_identifier("contract-renewal"),
        random_identifier("contract-renewal-idempotency"),
        now_unix_ms,
      )
    _ => packet
  }
}

///|
/// Demo mode runs without a controller, so contract actions transition the
/// seeded packet locally with the same lifecycle rules the `:information`,
/// `:confirm`, and `:generate` routes enforce. Generation lands immediately
/// with illustrative artifact records rather than rendered files.
fn demo_contract_action(
  documents : @contract_documents.ContractDocumentsState,
  message : @contract_documents.ContractDocumentsMessage,
) -> @contract_documents.ContractDocumentsState {
  let packet_id = match message {
    SaveInformation(packet_id, _, _) => packet_id
    ConfirmAction(ConfirmInformation(packet_id, _)) => packet_id
    ConfirmAction(RequestGeneration(packet_id, _, _)) => packet_id
    ConfirmAction(RequestRenewal(packet_id)) => packet_id
    _ => return { ..documents, loading: false, }
  }
  guard documents.current_manifest() is Some(manifest) &&
    documents.packets.search_by(packet => packet.packet_id == packet_id)
    is Some(index) else {
    return {
      ..documents,
      loading: false,
      error_message: Some(
        portal_copy(
          documents.locale,
          "Demo contract packet is unavailable.",
          "演示合同资料包不可用。",
        ),
      ),
    }
  }
  let packet = documents.packets[index]
  let now = current_unix_ms()
  let updated = try
    demo_contract_transition(packet, manifest, message, now)
  catch {
    error =>
      return {
        ..documents,
        loading: false,
        error_message: Some(
          portal_copy(
            documents.locale,
            "Demo contract action failed: \{Repr(error)}",
            "演示模式合同操作失败：\{Repr(error)}",
          ),
        ),
      }
  } noraise {
    value => value
  }
  let notice = match message {
    SaveInformation(_, _, _) =>
      portal_copy(
        documents.locale,
        "Demo information saved locally; no controller was contacted.",
        "演示模式：信息已在本地保存，未连接控制平面。",
      )
    ConfirmAction(ConfirmInformation(_, _)) =>
      portal_copy(
        documents.locale,
        "Demo information confirmed; generation can now be requested.",
        "演示模式：信息已确认，现在可以请求生成合同。",
      )
    ConfirmAction(RequestRenewal(_)) =>
      portal_copy(
        documents.locale,
        "Demo renewal draft created locally; no controller was contacted.",
        "演示模式：续约草稿已在本地创建，未连接控制平面。",
      )
    _ =>
      portal_copy(
        documents.locale,
        "Demo generation completed with illustrative artifacts.",
        "演示模式：合同已生成示例文件记录。",
      )
  }
  {
    ..documents,
    packets: replace_contract_packet(documents.packets, updated),
    selected_packet_id: Some(updated.packet_id),
    draft_values: merge_contract_draft(documents.draft_values, updated),
    loading: false,
    success_message: Some(notice),
    error_message: None,
  }
}

///|
fn contract_packet_command(
  model : AppModel,
  generation : Int64,
  message : @contract_documents.ContractDocumentsMessage,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try {
      match message {
        CreatePacket(template_id, order_ref) => {
          let intent : Json = {
            "packet_id": random_identifier("contract"),
            "idempotency_key": random_identifier("contract-create"),
            "template_id": template_id,
            "order_ref": order_ref,
            "active_forms": ["MasterLease"],
          }
          @json.from_json(
            @json.parse(
              request(
                "POST",
                model.endpoint,
                "/v1/contract-documents/self",
                model.token,
                model.subject_ref,
                body=intent.stringify(),
              ),
            ),
          )
          |> ContractPacketUpdated
        }
        ConfirmAction(
          SubmitUndertaking(packet_id, revision, artifact_id, signed_on)
        ) => {
          let intent : Json = {
            "expected_revision": revision.to_json(),
            "evidence_artifact_id": artifact_id,
            "signed_on": signed_on,
          }
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/contract-documents/self/\{packet_id}:undertaking-submit",
              model.token,
              model.subject_ref,
              body=intent.stringify(),
            ),
          )
          ContractActionNeedsRefresh
        }
        ConfirmAction(ReviseUndertaking(packet_id, revision)) => {
          ignore(
            contract_revision_action(model, packet_id, revision, None, "revise"),
          )
          ContractActionNeedsRefresh
        }
        ConfirmAction(WithdrawUndertaking(approval_id, reason)) => {
          let intent : Json = { "reason": reason }
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/contract-documents/self/approvals/\{approval_id}:withdraw",
              model.token,
              model.subject_ref,
              body=intent.stringify(),
            ),
          )
          ContractActionNeedsRefresh
        }
        RequestPreview(packet_id, revision, form, changes) =>
          ContractPreviewLoaded(
            generation,
            contract_preview(model, packet_id, revision, form, changes),
          )
        SaveInformation(packet_id, revision, changes) =>
          update_contract_information(model, packet_id, revision, changes)
          |> ContractPacketUpdated
        ConfirmAction(ConfirmInformation(packet_id, revision)) =>
          contract_revision_action(model, packet_id, revision, None, "confirm")
          |> ContractPacketUpdated
        ConfirmAction(RequestGeneration(packet_id, revision, digest)) =>
          contract_revision_action(
            model,
            packet_id,
            revision,
            Some(digest),
            "generate",
          )
          |> ContractPacketUpdated
        ConfirmAction(RequestRenewal(packet_id)) =>
          renew_contract_packet(model, packet_id) |> ContractPacketUpdated
        _ => fail("unsupported contract document operation")
      }
    } catch {
      error => {
        let failure = portal_copy(
          model.portal.locale,
          "Contract document operation failed: \{error.to_string()}",
          "合同文件操作失败：\{error.to_string()}",
        )
        if message is RequestPreview(_, _, _, _) {
          ContractPreviewFailed(generation, model.portal.locale, failure)
        } else {
          Failed(model.portal.locale, failure)
        }
      }
    }
  })
}

///|
fn contract_approval_nudge_command(
  model : AppModel,
  approval_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try {
      ignore(
        request(
          "POST",
          model.endpoint,
          "/v1/contract-documents/self/approvals/\{approval_id}:nudge",
          model.token,
          model.subject_ref,
          body="{}",
        ),
      )
      ContractApprovalNudged
    } catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to send the approval reminder: \{error.to_string()}",
            "无法发送审批催办：\{error.to_string()}",
          ),
        )
    }
  })
}

///|
fn schedule_contract_preview_only(
  model : AppModel,
  documents : @contract_documents.ContractDocumentsState,
  delay_ms : Int,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  guard documents.preview_request() is Some(request) else {
    return (
      { ..model, portal: { ..model.portal, contract_documents: documents, }, },
      @rabbita.none,
    )
  }
  let generation = model.contract_preview_generation + 1L
  let pending = documents.update(request)
  let next = {
    ..model,
    contract_preview_generation: generation,
    portal: { ..model.portal, contract_documents: pending, },
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
fn replace_agreement(
  values : Array[@portal.PortalAgreement],
  updated : @portal.PortalAgreement,
) -> Array[@portal.PortalAgreement] {
  [
    for value in values => {
      if value.agreement_id == updated.agreement_id {
        updated
      } else {
        value
      }
    }
  ]
}

///|
fn upsert_provider_request(
  values : Array[@commercial_integrations.ExternalRecordView],
  updated : @commercial_integrations.ExternalRecordView,
) -> Array[@commercial_integrations.ExternalRecordView] {
  let mut found = false
  let next = values.map(value => {
    if value.record_id == updated.record_id {
      found = true
      updated
    } else {
      value
    }
  })
  if !found {
    next.push(updated)
  }
  next
}

///|
fn signed_out_model(model : AppModel) -> AppModel {
  commit_enterprise_organization("")
  let locale = model.portal.locale
  {
    ..model,
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    session_generation: model.session_generation + 1L,
    session_expires_unix_ms: None,
    machine_clock_generation: model.machine_clock_generation + 1L,
    contract_preview_generation: model.contract_preview_generation + 1L,
    contract_poll_generation: model.contract_poll_generation + 1L,
    portal: {
      ..@enterprise_ui.default_state(current_unix_ms()),
      locale,
      machine_access: {
        ..@enterprise_ui.default_state(current_unix_ms()).machine_access,
        locale,
      },
      offline_commerce: {
        ..@enterprise_ui.default_state(current_unix_ms()).offline_commerce,
        locale,
      },
      contract_documents: {
        ..@enterprise_ui.default_state(current_unix_ms()).contract_documents,
        locale,
      },
    },
  }
}

///|
fn update(
  model : AppModel,
  message : AppMessage,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  match message {
    ContractPollDue(generation, packet_id, remaining) =>
      if contract_poll_active(model, generation, packet_id) && remaining > 0 {
        (
          model,
          contract_poll_request(model, generation, packet_id, remaining, emit),
        )
      } else {
        (model, @rabbita.none)
      }
    ContractPollResult(generation, packet_id, remaining, result) =>
      apply_contract_poll(model, generation, packet_id, remaining, result, emit)
    EndpointChanged(value) => ({ ..model, endpoint: value, }, @rabbita.none)
    TokenChanged(value) => ({ ..model, token: value, }, @rabbita.none)
    SubjectChanged(value) => ({ ..model, subject_ref: value, }, @rabbita.none)
    LoginEmailChanged(value) =>
      ({ ..model, login_email: value, }, @rabbita.none)
    LoginPasswordChanged(value) =>
      ({ ..model, login_password: value, }, @rabbita.none)
    RegisterDisplayNameChanged(value) =>
      ({ ..model, register_display_name: value, }, @rabbita.none)
    ToggleRegistration => {
      // Switching forms must not carry a half-typed password across, and it
      // must clear whatever the previous form reported.
      let next = {
        ..model,
        registering: !model.registering,
        login_password: "",
        portal: { ..model.portal, error_message: None, success_message: None, },
      }
      (next, @rabbita.none)
    }
    EnterpriseSignInSubmitted =>
      if model.login_email.trim() == "" || model.login_password == "" {
        (model, @rabbita.none)
      } else {
        let next = {
          ..model,
          connecting: true,
          portal: {
            ..model.portal,
            error_message: None,
            success_message: None,
          },
        }
        (next, gateway_auth_command(next, emit))
      }
    EnterpriseRegistrationSubmitted =>
      if model.login_email.trim() == "" ||
        model.register_display_name.trim() == "" ||
        model.login_password == "" {
        (model, @rabbita.none)
      } else {
        let next = {
          ..model,
          connecting: true,
          portal: {
            ..model.portal,
            error_message: None,
            success_message: None,
          },
        }
        (next, gateway_auth_command(next, emit))
      }
    EnterpriseAuthRefused(dispatched_locale, message) =>
      (
        {
          ..model,
          connecting: false,
          // The draft keeps the address the customer typed, but not the
          // password: it is dropped as soon as it has been used.
          login_password: "",
          portal: {
            ..model.portal,
            error_message: Some(
              if dispatched_locale == model.portal.locale {
                message
              } else {
                portal_copy(
                  model.portal.locale,
                  "The identity gateway refused the request. Retry it.",
                  "身份网关拒绝了该请求。请重试。",
                )
              },
            ),
          },
        },
        @rabbita.none,
      )
    Connect =>
      if model.token == "" || model.endpoint == "" {
        (
          {
            ..model,
            portal: {
              ..model.portal,
              error_message: Some(
                portal_copy(
                  model.portal.locale,
                  "A scoped token and controller endpoint are required.",
                  "需要限定范围的令牌和控制器端点。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        let next = {
          ..model,
          connecting: true,
          csrf_token: "",
          session_expires_unix_ms: None,
          session_generation: model.session_generation + 1L,
        }
        (next, organization_bootstrap_command(next, emit))
      }
    Bootstrap =>
      if model.demo_mode || model.bootstrap_started {
        (model, @rabbita.none)
      } else {
        let next = { ..model, bootstrap_started: true, connecting: true, }
        (next, bootstrap_command(next, emit))
      }
    BootstrapReady(generation, browser_session) =>
      if generation != model.session_generation ||
        browser_session.expires_unix_ms <= current_unix_ms() {
        (model, @rabbita.none)
      } else {
        let next = {
          ..model,
          token: browser_session.session_token,
          csrf_token: browser_session.csrf_token,
          subject_ref: "",
          connecting: true,
          session_generation: model.session_generation + 1L,
          session_expires_unix_ms: Some(browser_session.expires_unix_ms),
        }
        (next, organization_bootstrap_command(next, emit))
      }
    BootstrapUnavailable(generation) =>
      if generation == model.session_generation {
        ({ ..model, connecting: false, }, @rabbita.none)
      } else {
        (model, @rabbita.none)
      }
    Logout => {
      let command = if model.token.has_prefix("lnxs_") {
        logout_command(model, emit)
      } else {
        @rabbita.none
      }
      (signed_out_model(model), command)
    }
    LogoutCompleted(generation) => {
      ignore(generation == model.session_generation)
      (model, @rabbita.none)
    }
    Portal(LocaleChanged(locale)) => {
      apply_enterprise_locale(locale)
      (
        { ..model, portal: model.portal.update(LocaleChanged(locale)), },
        @rabbita.none,
      )
    }
    DeliveryPollDue(generation, organization, poll_generation) => {
      if generation != model.session_generation ||
        organization != model.portal.selected_organization_id ||
        poll_generation != model.portal.deliveries.poll_generation ||
        model.portal.route != DesktopIde ||
        model.portal.deliveries.loading {
        return (model, @rabbita.none)
      }
      let next = { ..model, portal: model.portal.update(Delivery(Refresh)), }
      (next, delivery_command(next, None, emit))
    }
    DeliveriesLoaded(generation, organization, poll_generation, result) => {
      if generation != model.session_generation ||
        organization != model.portal.selected_organization_id ||
        poll_generation != model.portal.deliveries.poll_generation {
        return (model, @rabbita.none)
      }
      let panel = model.portal.deliveries
      let deliveries = match result {
        Ok((options, operations, error)) =>
          {
            ..panel,
            options,
            operations,
            loaded: true,
            loading: false,
            error,
            stop_confirmation: None,
          }
        Err(error) => { ..panel, loading: false, error: Some(error), }
      }
      let next = { ..model, portal: { ..model.portal, deliveries, }, }
      (next, delivery_poll_command(next, emit))
    }
    DeliveryAccessIssued(generation, organization, poll_generation, result) => {
      if generation != model.session_generation ||
        organization != model.portal.selected_organization_id ||
        poll_generation != model.portal.deliveries.poll_generation ||
        model.portal.route != DesktopIde {
        return (model, @rabbita.none)
      }
      let panel = model.portal.deliveries
      let deliveries = match result {
        Ok(access) =>
          { ..panel, loading: false, api_access: Some(access), error: None, }
        Err(error) =>
          { ..panel, loading: false, api_access: None, error: Some(error), }
      }
      ({ ..model, portal: { ..model.portal, deliveries, }, }, @rabbita.none)
    }
    Portal(Delivery(message)) => {
      if model.portal.deliveries.loading {
        return (model, @rabbita.none)
      }
      let next = { ..model, portal: model.portal.update(Delivery(message)), }
      match message {
        OpenWorkspace(id) if !model.demo_mode =>
          (next, delivery_workspace_command(next, id, emit))
        IssueApiAccess(id) if !model.demo_mode =>
          (next, delivery_api_access_command(next, id, emit))
        SelectReservation(_)
        | SelectTemplate(_)
        | RequestStop(_)
        | DismissApiAccess
        | CancelStop => (next, @rabbita.none)
        _ if model.demo_mode => (model, @rabbita.none)
        Start if !@enterprise_ui.delivery_start_available(
            model.portal.deliveries,
          ) => (model, @rabbita.none)
        _ => {
          let panel = next.portal.deliveries
          let next = if message == Start && panel.idempotency_key == "" {
            {
              ..next,
              portal: {
                ..next.portal,
                deliveries: {
                  ..panel,
                  idempotency_key: random_identifier("delivery"),
                },
              },
            }
          } else {
            next
          }
          (next, delivery_command(next, Some(message), emit))
        }
      }
    }
    Portal(Navigate(route)) => {
      let portal = model.portal.update(Navigate(route))
      let portal = {
        ..portal,
        deliveries: {
          ..portal.deliveries,
          api_access: None,
          loading: false,
          poll_generation: portal.deliveries.poll_generation + 1L,
        },
      }
      let next = {
        ..model,
        portal,
        contract_poll_generation: model.contract_poll_generation + 1L,
      }
      match route {
        DesktopIde if !model.demo_mode => {
          let next = { ..next, portal: next.portal.update(Delivery(Refresh)), }
          (next, delivery_command(next, None, emit))
        }
        ContractDocuments =>
          schedule_contract_preview(next, portal.contract_documents, 0, emit)
        SelfService if !model.demo_mode &&
          @enterprise_ui.selected_organization_header(portal) is Some(_) => {
          let loading = {
            ..next,
            portal: {
              ..portal,
              self_service: {
                ..portal.self_service,
                offerings_loading: true,
                offerings_error: None,
              },
            },
          }
          (loading, machine_commerce_command(loading, emit))
        }
        _ => (next, @rabbita.none)
      }
    }
    Portal(SelfService(SelectOrganization(organization_id))) => {
      let portal = model.portal.update(
        SelfService(SelectOrganization(organization_id)),
      )
      let next = {
        ..model,
        portal: {
          ..portal,
          deliveries: @enterprise_ui.default_delivery_panel(),
        },
        contract_poll_generation: model.contract_poll_generation + 1L,
      }
      match @enterprise_ui.selected_organization_header(portal) {
        Some(selected) if !model.demo_mode => {
          commit_enterprise_organization(selected)
          let loading = { ..next, connecting: true, }
          (loading, load_command(loading, emit))
        }
        Some(selected) => {
          commit_enterprise_organization(selected)
          (next, @rabbita.none)
        }
        None => {
          commit_enterprise_organization("")
          (next, @rabbita.none)
        }
      }
    }
    Portal(SelfService(SubmitCreateCompany)) => {
      if !@enterprise_ui.company_creation_valid(model.portal.self_service) ||
        !model.token.has_prefix("lnxs_") {
        return (model, @rabbita.none)
      }
      let next = {
        ..model,
        portal: model.portal.update(SelfService(SubmitCreateCompany)),
      }
      if model.demo_mode {
        (
          {
            ..next,
            portal: {
              ..next.portal,
              self_service: {
                ..next.portal.self_service,
                action_loading: false,
              },
              success_message: Some(
                portal_copy(
                  next.portal.locale,
                  "Demo preview only; no company was created.",
                  "仅为演示预览；未创建公司。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        (next, organization_create_command(next, emit))
      }
    }
    Portal(SelfService(SubmitJoinCompany)) => {
      if !@enterprise_ui.company_join_valid(model.portal.self_service) ||
        !model.token.has_prefix("lnxs_") {
        return (model, @rabbita.none)
      }
      let next = {
        ..model,
        portal: model.portal.update(SelfService(SubmitJoinCompany)),
      }
      if model.demo_mode {
        (
          {
            ..next,
            portal: {
              ..next.portal,
              self_service: {
                ..next.portal.self_service,
                action_loading: false,
              },
              success_message: Some(
                portal_copy(
                  next.portal.locale,
                  "Demo preview only; no invitation was consumed.",
                  "仅为演示预览；未使用邀请码。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        (next, organization_join_command(next, emit))
      }
    }
    Portal(SelfService(RefreshOrganizations)) => {
      let portal = model.portal.update(SelfService(RefreshOrganizations))
      let next = { ..model, portal, connecting: true, }
      if model.demo_mode {
        (
          {
            ..next,
            connecting: false,
            portal: {
              ..portal,
              self_service: { ..portal.self_service, action_loading: false, },
            },
          },
          @rabbita.none,
        )
      } else {
        (next, organization_bootstrap_command(next, emit))
      }
    }
    Portal(SelfService(RefreshOfferings))
    | Portal(SelfService(RefreshMachineOrders)) => {
      if model.demo_mode {
        let portal = model.portal.update(SelfService(RefreshMachineOrders))
        return (
          {
            ..model,
            portal: {
              ..portal,
              self_service: {
                ..portal.self_service,
                offerings_loading: false,
                action_loading: false,
              },
            },
          },
          @rabbita.none,
        )
      }
      guard @enterprise_ui.selected_organization_header(model.portal) is Some(_) else {
        return (model, @rabbita.none)
      }
      let portal = model.portal.update(SelfService(RefreshOfferings))
      let next = { ..model, portal, }
      (next, machine_commerce_command(next, emit))
    }
    Portal(SelfService(RequestQuote)) => {
      if !@enterprise_ui.self_service_configuration_valid(
          model.portal.self_service,
        ) {
        return (model, @rabbita.none)
      }
      let portal = model.portal.update(SelfService(RequestQuote))
      let next = { ..model, portal, }
      if model.demo_mode {
        (
          {
            ..next,
            portal: {
              ..portal,
              self_service: { ..portal.self_service, action_loading: false, },
            },
          },
          @rabbita.none,
        )
      } else {
        (next, machine_quote_command(next, emit))
      }
    }
    Portal(SelfService(AcceptMachineTerms)) => {
      if !model.portal.self_service.terms_reviewed {
        return (model, @rabbita.none)
      }
      let portal = model.portal.update(SelfService(AcceptMachineTerms))
      let next = { ..model, portal, }
      if model.demo_mode {
        (
          {
            ..next,
            portal: {
              ..portal,
              self_service: {
                ..portal.self_service,
                terms_accepted: true,
                action_loading: false,
              },
            },
          },
          @rabbita.none,
        )
      } else {
        (next, machine_terms_acceptance_command(next, emit))
      }
    }
    Portal(SelfService(CreateMachineOrder)) => {
      guard model.portal.self_service.quote is Some(quote) &&
        quote.valid_until_unix_ms > current_unix_ms() &&
        (
          model.portal.self_service.terms_accepted ||
          model.portal.agreements.any(value => value.state == Executed)
        ) else {
        return (model, @rabbita.none)
      }
      let portal = model.portal.update(SelfService(CreateMachineOrder))
      let next = { ..model, portal, }
      if model.demo_mode {
        (
          {
            ..next,
            portal: {
              ..portal,
              self_service: { ..portal.self_service, action_loading: false, },
            },
          },
          @rabbita.none,
        )
      } else {
        (next, machine_order_create_command(next, emit))
      }
    }
    Portal(SelfService(CancelMachineOrder(order_id, generation))) => {
      let portal = model.portal.update(
        SelfService(CancelMachineOrder(order_id, generation)),
      )
      let next = { ..model, portal, }
      if model.demo_mode {
        let order = portal.self_service.order.map(value => {
          if value.order_id == order_id && value.generation == generation {
            { ..value, status: CancelledOrder, generation: generation + 1L, }
          } else {
            value
          }
        })
        (
          {
            ..next,
            portal: {
              ..portal,
              self_service: {
                ..portal.self_service,
                order,
                action_loading: false,
              },
            },
          },
          @rabbita.none,
        )
      } else {
        (
          next,
          machine_order_action_command(
            next, order_id, generation, "cancel", emit,
          ),
        )
      }
    }
    Portal(SelfService(TerminateMachineOrder(order_id, generation))) => {
      let portal = model.portal.update(
        SelfService(TerminateMachineOrder(order_id, generation)),
      )
      let next = { ..model, portal, }
      if model.demo_mode {
        let order = portal.self_service.order.map(value => {
          if value.order_id == order_id && value.generation == generation {
            {
              ..value,
              status: TerminationPending,
              generation: generation + 1L,
            }
          } else {
            value
          }
        })
        (
          {
            ..next,
            portal: {
              ..portal,
              self_service: {
                ..portal.self_service,
                order,
                action_loading: false,
              },
            },
          },
          @rabbita.none,
        )
      } else {
        (
          next,
          machine_order_action_command(
            next, order_id, generation, "terminate", emit,
          ),
        )
      }
    }
    Portal(SubmitApiKeyIssue) => {
      let next = model.portal.update(SubmitApiKeyIssue)
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..next,
              loading: false,
              api_key_issue_open: false,
              one_time_api_key_secret: Some({
                key_id: "demo-preview-only",
                display_name: "DEMO — no credential issued",
                secret: "DEMO-NOT-A-CREDENTIAL",
                allowed_models: ["text.default"],
                api_base_url: Some("https://api.example.invalid"),
                tenant_ref: "demo-tenant",
                memory_ceiling_mib: Some(8192),
              }),
              success_message: Some(
                portal_copy(
                  next.locale,
                  "Demo preview only; no API key was issued.",
                  "仅为演示预览；未签发 API 密钥。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else if !@enterprise_ui.api_key_issue_valid(model.portal) {
        (model, @rabbita.none)
      } else {
        ({ ..model, portal: next, }, api_key_issue_command(model, emit))
      }
    }
    Portal(ConfirmRevokeApiKey(key_id)) => {
      let next = model.portal.update(ConfirmRevokeApiKey(key_id))
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..next,
              loading: false,
              api_key_revoke_id: None,
              success_message: Some(
                portal_copy(
                  next.locale,
                  "Demo preview only; no API key was revoked.",
                  "仅为演示预览；未撤销 API 密钥。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        (
          { ..model, portal: next, },
          api_key_revoke_command(model, key_id, emit),
        )
      }
    }
    Portal(CopyOneTimeApiKeySecret) =>
      match model.portal.one_time_api_key_secret {
        Some(value) =>
          (model, copy_api_key_secret_command(model, value.secret, emit))
        _ => (model, @rabbita.none)
      }
    Portal(CopyFirstCallExample) =>
      match model.portal.one_time_api_key_secret {
        Some(value) =>
          (
            model,
            copy_api_key_secret_command(
              model,
              @enterprise_ui.first_call_example(value),
              emit,
            ),
          )
        None => (model, @rabbita.none)
      }
    Portal(CopyDetail(value))
    | Portal(MachineAccess(CopyAccessDetail(value)))
    | Portal(ContractDocuments(CopyPublicIdentifier(value))) =>
      (model, copy_api_key_secret_command(model, value, emit))
    Portal(ExportCosts) => {
      let started = download_costs_csv(@enterprise_ui.costs_csv(model.portal))
      (
        {
          ..model,
          portal: {
            ..model.portal,
            success_message: if started {
              Some(
                portal_copy(
                  model.portal.locale,
                  "CSV download started. Check your browser downloads.",
                  "CSV 下载已发起，请查看浏览器下载列表。",
                ),
              )
            } else {
              None
            },
            error_message: if started {
              None
            } else {
              Some(
                portal_copy(
                  model.portal.locale,
                  "The download could not start. Check browser download permissions and retry.",
                  "无法发起下载，请检查浏览器下载权限后重试。",
                ),
              )
            },
          },
        },
        @rabbita.none,
      )
    }
    ContractPreviewDue(generation, request) =>
      if generation != model.contract_preview_generation {
        (model, @rabbita.none)
      } else if model.demo_mode {
        match request {
          RequestPreview(packet_id, _, form, changes) =>
            (
              model,
              @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
                try
                  demo_contract_preview(model, packet_id, form, changes)
                catch {
                  error =>
                    ContractPreviewFailed(
                      generation,
                      model.portal.locale,
                      "MoonLeaf preview failed: \{error.to_string()}",
                    )
                } noraise {
                  preview => ContractPreviewLoaded(generation, preview)
                }
              }),
            )
          _ => (model, @rabbita.none)
        }
      } else {
        (model, contract_packet_command(model, generation, request, emit))
      }
    Portal(SignAgreement(agreement_id)) => {
      let next = model.portal.update(SignAgreement(agreement_id))
      if model.demo_mode {
        let agreements = [
          for agreement in next.agreements => {
            if agreement.agreement_id == agreement_id {
              {
                ..agreement,
                state: SignatureRequested,
                generation: agreement.generation + 1L,
                signer_subject_ref: Some("subject-demo"),
                signature_request_receipt: Some("portal-signature:demo"),
              }
            } else {
              agreement
            }
          }
        ]
        (
          {
            ..model,
            portal: {
              ..next,
              agreements,
              loading: false,
              success_message: Some(
                portal_copy(
                  next.locale,
                  "Signature ceremony requested. Execution waits for verified provider evidence.",
                  "已发起签署流程。协议将在验证提供商证据后执行。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        (
          { ..model, portal: next, },
          signature_command(model, agreement_id, emit),
        )
      }
    }
    Portal(RefreshProviderRequests) => {
      let next = model.portal.update(RefreshProviderRequests)
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..next,
              provider_requests_loading: false,
              success_message: Some(
                portal_copy(
                  next.locale,
                  "Provider status refreshed.",
                  "服务商状态已刷新。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        ({ ..model, portal: next, }, provider_requests_command(model, emit))
      }
    }
    Portal(SubmitPaymentCheckout) => {
      let next = model.portal.update(SubmitPaymentCheckout)
      if model.demo_mode {
        guard next.payment_checkout_quote is Some(quote) else {
          return (
            {
              ..model,
              portal: {
                ..next,
                payment_checkout_loading: false,
                error_message: Some(
                  portal_copy(
                    next.locale,
                    "No payable ledger balance is available.",
                    "当前没有可支付的台账余额。",
                  ),
                ),
              },
            },
            @rabbita.none,
          )
        }
        let record : @commercial_integrations.ExternalRecordView = {
          record_id: "payment-demo-checkout",
          organization_id: next.membership
          .map(value => value.organization_id)
          .unwrap_or("org-demo"),
          kind: Payment,
          provider: "qualified-services-demo",
          environment: "test",
          external_ref_sha256: "sha256:payment-demo-checkout",
          state: Submitted,
          expected_amount_minor: Some(quote.expected_amount_minor),
          currency: Some(quote.currency),
          money_scale: Some(quote.money_scale),
          expected_document_hash: None,
          entitlement_transaction_ref_sha256: Some(
            quote.entitlement_transaction_ref_sha256,
          ),
          action_url: Some("https://pay.example.invalid/checkout/demo"),
          action_expires_unix_ms: Some(
            next.machine_access.now_unix_ms + 900000L,
          ),
          updated_unix_ms: next.machine_access.now_unix_ms,
        }
        (
          {
            ..model,
            portal: {
              ..next,
              provider_requests: upsert_provider_request(
                next.provider_requests,
                record,
              ),
              payment_checkout_loading: false,
              success_message: Some(
                portal_copy(
                  next.locale,
                  "Secure checkout is ready. Open it explicitly when you are ready to pay.",
                  "安全支付链接已就绪。准备付款时请手动打开。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        ({ ..model, portal: next, }, payment_checkout_command(model, emit))
      }
    }
    Portal(SubmitLease) => {
      let next = model.portal.update(SubmitLease)
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..next,
              loading: false,
              success_message: Some(
                portal_copy(
                  next.locale,
                  "Demo preview only; no lease request was submitted to the operator queue.",
                  "仅为演示预览；未向运维审核队列提交租用申请。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        ({ ..model, portal: next, }, lease_command(model, emit))
      }
    }
    Portal(LaunchDesktopClient) => {
      let next = model.portal.update(LaunchDesktopClient)
      if model.demo_mode {
        open_desktop_client(
          "/workbench/?demo=1",
          "demo-client",
          "lnxc_" + "d".repeat(64),
        )
        (
          {
            ..model,
            portal: {
              ..next,
              loading: false,
              success_message: Some(
                portal_copy(
                  next.locale,
                  "Demo WebIDE opened with a simulated one-time handoff.",
                  "演示 WebIDE 已通过模拟单次交接打开。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        ({ ..model, portal: next, }, desktop_client_command(model, emit))
      }
    }
    Portal(MarkNotificationRead(notification_id, generation)) =>
      if model.demo_mode {
        let notifications = [
          for value in model.portal.notifications => {
            if value.event.notification_id == notification_id {
              {
                ..value,
                lifecycle: Read,
                generation: value.generation + 1L,
                updated_unix_ms: current_unix_ms(),
              }
            } else {
              value
            }
          }
        ]
        (
          { ..model, portal: { ..model.portal, notifications, }, },
          @rabbita.none,
        )
      } else {
        (
          model,
          notification_read_command(model, notification_id, generation, emit),
        )
      }
    Portal(SetNotificationEmail(topic, enabled)) =>
      if model.demo_mode {
        let updated : @notifications.NotificationPreferenceView = {
          topic,
          channels: if enabled {
            [InApp, Email]
          } else {
            [InApp]
          },
          minimum_severity: Information,
          updated_unix_ms: current_unix_ms(),
        }
        (
          {
            ..model,
            portal: {
              ..model.portal,
              notification_preferences: replace_notification_preference(
                model.portal.notification_preferences,
                updated,
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        (model, notification_preference_command(model, topic, enabled, emit))
      }
    Portal(
      MachineAccess(ConfirmTermination(lease_ref, generation, confirmation))
    ) => {
      let portal = model.portal.update(
        MachineAccess(ConfirmTermination(lease_ref, generation, confirmation)),
      )
      if model.demo_mode {
        let now = current_unix_ms()
        let machines = portal.machine_access.machines.map(machine => {
          if machine.lease_ref == lease_ref && machine.generation == generation {
            {
              ..machine,
              state: Expiring,
              generation: machine.generation + 1L,
              updated_unix_ms: now,
              credential_handoff: {
                ..machine.credential_handoff,
                state: Closed,
                handoff_ref: None,
              },
              can_terminate: false,
              termination_confirmation: None,
            }
          } else {
            machine
          }
        })
        (
          {
            ..model,
            portal: {
              ..portal,
              machine_access: {
                ..portal.machine_access,
                machines,
                confirmation_lease_ref: None,
                confirmation_text: "",
                loading: false,
              },
              success_message: Some(
                portal_copy(
                  portal.locale,
                  "Demo access termination entered verified cleanup; no controller was contacted.",
                  "演示模式：访问终止已进入验证清理流程，未连接控制平面。",
                ),
              ),
              error_message: None,
            },
          },
          @rabbita.none,
        )
      } else {
        (
          { ..model, portal, },
          machine_termination_command(
            model, lease_ref, generation, confirmation, emit,
          ),
        )
      }
    }
    Portal(MachineAccess(RedeemCredential(lease_ref, generation))) => {
      let portal = model.portal.update(
        MachineAccess(RedeemCredential(lease_ref, generation)),
      )
      if model.demo_mode {
        let credential : @credential.CredentialHandoffRedemption = {
          version: @credential.contract_version,
          handoff_ref: "handoff-demo-recoverable",
          lease_ref,
          generation,
          issuer_redirect_url: "https://issuer.demo.invalid/redeem",
          host_alias: "machine.demo.invalid",
          ssh_port: 22,
          host_key_fingerprint: "SHA256:demo-host-key-fingerprint",
          connection_command: "ssh -p 22 alice@machine.demo.invalid",
          valid_until_unix_ms: current_unix_ms() + 900000L,
          redemption_receipt: "demo:credential-redemption",
          one_time: true,
          raw_secret_included: false,
        }
        (
          {
            ..model,
            portal: {
              ..portal,
              machine_access: portal.machine_access.with_redeemed_credential(
                credential,
              ),
              success_message: Some(
                portal_copy(
                  portal.locale,
                  "Demo access metadata redeemed; no credential was issued and no controller was contacted.",
                  "演示模式：已显示访问元数据；未签发凭据，也未连接控制平面。",
                ),
              ),
              error_message: None,
            },
          },
          @rabbita.none,
        )
      } else {
        (
          { ..model, portal, },
          credential_redemption_command(model, lease_ref, generation, emit),
        )
      }
    }
    Portal(OfflineCommerce(CreateOrder)) => {
      let next = model.portal.update(OfflineCommerce(CreateOrder))
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..next,
              offline_commerce: {
                ..next.offline_commerce,
                loading: false,
                success_message: Some(
                  portal_copy(
                    next.locale,
                    "Draft order preview created. Connect to submit it.",
                    "已创建订单草稿预览。连接控制平面后即可提交。",
                  ),
                ),
              },
            },
          },
          @rabbita.none,
        )
      } else {
        ({ ..model, portal: next, }, offline_order_command(model, emit))
      }
    }
    Portal(OfflineCommerce(RequestEvidenceUpload(order_id, kind))) => {
      let next = model.portal.update(
        OfflineCommerce(RequestEvidenceUpload(order_id, kind)),
      )
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..next,
              offline_commerce: {
                ..next.offline_commerce,
                loading: false,
                success_message: Some(
                  portal_copy(
                    next.locale,
                    "Upload authorization preview created; no file was transferred.",
                    "已创建上传授权预览；尚未传输任何文件。",
                  ),
                ),
              },
            },
          },
          @rabbita.none,
        )
      } else {
        (
          { ..model, portal: next, },
          offline_upload_grant_command(model, order_id, kind, emit),
        )
      }
    }
    Portal(OfflineCommerce(RequestArtifactDownload(artifact_id))) => {
      let next = model.portal.update(
        OfflineCommerce(RequestArtifactDownload(artifact_id)),
      )
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..next,
              offline_commerce: {
                ..next.offline_commerce,
                loading: false,
                success_message: Some(
                  portal_copy(
                    next.locale,
                    "Verified download preview; no file was transferred.",
                    "已预览验证下载；未传输任何文件。",
                  ),
                ),
              },
            },
          },
          @rabbita.none,
        )
      } else {
        (
          { ..model, portal: next, },
          offline_artifact_download_command(model, artifact_id, emit),
        )
      }
    }
    Portal(OfflineCommerce(Refresh)) =>
      if model.demo_mode {
        (model, @rabbita.none)
      } else {
        (
          {
            ..model,
            portal: {
              ..model.portal,
              offline_commerce: {
                ..model.portal.offline_commerce,
                loading: true,
              },
            },
          },
          load_command(model, emit),
        )
      }
    Portal(OfflineCommerce(ConfirmAction(CancelOrder(order_id, generation)))) => {
      let next = model.portal.update(
        OfflineCommerce(ConfirmAction(CancelOrder(order_id, generation))),
      )
      if model.demo_mode {
        ({ ..model, portal: next, }, @rabbita.none)
      } else {
        (
          { ..model, portal: next, },
          offline_order_cancellation_command(model, order_id, generation, emit),
        )
      }
    }
    Portal(OfflineCommerce(ConfirmAction(_))) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            offline_commerce: {
              ..model.portal.offline_commerce,
              loading: false,
              error_message: Some(
                portal_copy(
                  model.portal.locale,
                  "Operator-only commercial action is unavailable in the customer portal.",
                  "客户门户不可执行仅限运营人员的商务操作。",
                ),
              ),
            },
          },
        },
        @rabbita.none,
      )
    Portal(ContractDocuments(Refresh)) =>
      if model.demo_mode {
        (model, @rabbita.none)
      } else {
        (
          {
            ..model,
            portal: {
              ..model.portal,
              contract_documents: {
                ..model.portal.contract_documents,
                loading: true,
              },
            },
          },
          load_command(model, emit),
        )
      }
    Portal(ContractDocuments(SelectPacket(packet_id))) => {
      let documents = model.portal.contract_documents.update(
        SelectPacket(packet_id),
      )
      schedule_contract_preview(model, documents, 0, emit)
    }
    Portal(ContractDocuments(SelectTenant(tenant_ref))) => {
      let documents = model.portal.contract_documents.update(
        SelectTenant(tenant_ref),
      )
      schedule_contract_preview(model, documents, 0, emit)
    }
    Portal(ContractDocuments(SearchChanged(query))) => {
      let documents = model.portal.contract_documents.update(
        SearchChanged(query),
      )
      schedule_contract_preview(model, documents, 0, emit)
    }
    Portal(ContractDocuments(SelectForm(form))) => {
      let documents = model.portal.contract_documents.update(SelectForm(form))
      schedule_contract_preview(model, documents, 0, emit)
    }
    Portal(ContractDocuments(FieldChanged(field_id, value))) => {
      let documents = model.portal.contract_documents.update(
        FieldChanged(field_id, value),
      )
      schedule_contract_preview(model, documents, 250, emit)
    }
    Portal(ContractDocuments(NudgeApproval(approval_id))) => {
      let documents = model.portal.contract_documents.update(
        NudgeApproval(approval_id),
      )
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..model.portal,
              contract_documents: {
                ..documents,
                loading: false,
                success_message: Some(
                  portal_copy(
                    model.portal.locale,
                    "Demo reminder recorded locally.",
                    "演示催办已在本地记录。",
                  ),
                ),
              },
            },
          },
          @rabbita.none,
        )
      } else {
        (
          {
            ..model,
            portal: { ..model.portal, contract_documents: documents, },
          },
          contract_approval_nudge_command(model, approval_id, emit),
        )
      }
    }
    Portal(ContractDocuments(RequestPreview(_, _, _, _) as request)) => {
      let documents = model.portal.contract_documents.update(request)
      schedule_contract_preview(model, documents, 0, emit)
    }
    Portal(ContractDocuments(DownloadDocument(artifact_id))) =>
      if model.demo_mode {
        (model, @rabbita.none)
      } else {
        (model, offline_artifact_download_command(model, artifact_id, emit))
      }
    Portal(ContractDocuments(UploadUndertakingEvidence(order_id))) =>
      if model.demo_mode {
        (model, @rabbita.none)
      } else {
        (
          {
            ..model,
            portal: {
              ..model.portal,
              contract_documents: {
                ..model.portal.contract_documents,
                confirmation: None,
                loading: true,
              },
            },
          },
          offline_upload_grant_command(
            model,
            order_id,
            ExecutedContractScan,
            emit,
          ),
        )
      }
    Portal(ContractDocuments(message)) if message is SaveInformation(_, _, _) ||
      message is CreatePacket(_, _) ||
      message is ConfirmAction(_) => {
      if model.portal.contract_documents.loading {
        return (model, @rabbita.none)
      }
      if message is ConfirmAction(RequestGeneration(packet_id, _, _)) &&
        model.portal.contract_documents.packets.any(packet => {
          packet.packet_id == packet_id && packet.state == GenerationRequested
        }) {
        return (model, @rabbita.none)
      }
      let next = model.portal.update(ContractDocuments(message))
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..next,
              contract_documents: demo_contract_action(
                next.contract_documents,
                message,
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        (
          { ..model, portal: next, },
          contract_packet_command(
            model,
            model.contract_preview_generation,
            message,
            emit,
          ),
        )
      }
    }
    Outcome(ContractPreviewLoaded(generation, preview)) =>
      if generation != model.contract_preview_generation {
        (model, @rabbita.none)
      } else {
        (
          {
            ..model,
            portal: model.portal.update(
              ContractDocuments(PreviewLoaded(preview)),
            ),
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
            portal: {
              ..model.portal,
              contract_documents: model.portal.contract_documents.update(
                PreviewFailed(
                  if dispatched_locale == model.portal.locale {
                    message
                  } else {
                    portal_copy(
                      model.portal.locale,
                      "MoonLeaf preview failed. It will retry after the next edit.",
                      "MoonLeaf 预览失败；下次编辑后将自动重试。",
                    )
                  },
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
    Portal(portal_message) =>
      ({ ..model, portal: model.portal.update(portal_message), }, @rabbita.none)
    Outcome(ApiKeyIssued(generation, issued)) =>
      if generation != model.session_generation {
        (model, @rabbita.none)
      } else {
        let api_keys = [
          issued.credential,
          ..model.portal.api_keys.filter(key => {
            key.key_id != issued.credential.key_id
          }),
        ]
        (
          {
            ..model,
            portal: {
              ..model.portal,
              api_keys,
              api_key_issue_open: false,
              api_key_revoke_id: None,
              api_key_issue_draft: {
                display_name: "",
                model_list_scope: true,
                inference_scope: true,
                allowed_models: "",
                lifetime_days: 30,
                maximum_requests: 10000L,
              },
              one_time_api_key_secret: Some({
                key_id: issued.credential.key_id,
                display_name: issued.credential.display_name,
                secret: issued.secret,
                allowed_models: issued.credential.allowed_models,
                api_base_url: issued.api_base_url,
                tenant_ref: issued.credential.tenant_ref,
                memory_ceiling_mib: match
                  issued.credential.allowed_models.get(0) {
                  Some(model_alias) =>
                    model.portal.model_catalog
                    .iter()
                    .find_first(item => {
                      item.alias_name == Some(model_alias) &&
                      item.minimum_memory_mib > 0
                    })
                    .map(item => item.minimum_memory_mib)
                  None => None
                },
              }),
              loading: false,
              success_message: None,
              error_message: None,
            },
          },
          @rabbita.none,
        )
      }
    Outcome(ApiKeyRevoked(generation, key_id, revoked_unix_ms)) =>
      if generation != model.session_generation {
        (model, @rabbita.none)
      } else {
        let revoked_at = revoked_unix_ms.unwrap_or(current_unix_ms())
        let api_keys = model.portal.api_keys.map(key => {
          if key.key_id == key_id {
            { ..key, revoked_unix_ms: Some(revoked_at), }
          } else {
            key
          }
        })
        (
          {
            ..model,
            portal: {
              ..model.portal,
              api_keys,
              api_key_revoke_id: None,
              loading: false,
              success_message: Some(
                portal_copy(
                  model.portal.locale,
                  "API key revoked. Requests using it now fail.",
                  "API 密钥已撤销，使用该密钥的请求现将失败。",
                ),
              ),
              error_message: None,
            },
          },
          @rabbita.none,
        )
      }
    Outcome(ApiKeySecretCopied(generation)) =>
      if generation != model.session_generation {
        (model, @rabbita.none)
      } else {
        (
          {
            ..model,
            portal: {
              ..model.portal,
              success_message: Some(
                portal_copy(
                  model.portal.locale,
                  "Copied. Keep any credentials private.",
                  "已复制。请妥善保管所有凭据。",
                ),
              ),
              error_message: None,
            },
          },
          @rabbita.none,
        )
      }
    Outcome(OrganizationsLoaded(generation, organizations, preferred_id)) => {
      if generation != model.session_generation {
        return (model, @rabbita.none)
      }
      let requested_id = preferred_id.unwrap_or("")
      match preferred_organization(organizations, requested_id) {
        Some(selection) => {
          let organization_id = selection.organization.organization_id
          commit_enterprise_organization(organization_id)
          let base = {
            ..model.portal,
            organizations,
            selected_organization_id: Some(organization_id),
          }
          let portal = base.update(
            SelfService(SelectOrganization(organization_id)),
          )
          let next = { ..model, connecting: true, portal, }
          (next, load_command(next, emit))
        }
        None => {
          commit_enterprise_organization("")
          let empty = organizations.length() == 0
          (
            {
              ..model,
              connecting: false,
              portal: {
                ..model.portal,
                route: SelfService,
                organizations,
                selected_organization_id: None,
                membership: None,
                self_service: {
                  ..model.portal.self_service,
                  step: Organization,
                  action_loading: false,
                  action_error: None,
                },
                success_message: None,
                error_message: Some(
                  if empty {
                    portal_copy(
                      model.portal.locale,
                      "Create a company or accept an invitation to continue.",
                      "请创建公司或接受邀请后继续。",
                    )
                  } else {
                    portal_copy(
                      model.portal.locale,
                      "Choose the organization for this session. Scoped requests remain blocked until you do.",
                      "请选择本次会话使用的组织；选择前，限定组织范围的请求保持关闭。",
                    )
                  },
                ),
              },
            },
            @rabbita.none,
          )
        }
      }
    }
    Outcome(OrganizationCreated(created)) => {
      let organization_id = created.organization.organization_id
      let organizations = [
        created,
        ..model.portal.organizations.filter(value => {
          value.organization.organization_id != organization_id
        }),
      ]
      commit_enterprise_organization(organization_id)
      let base = {
        ..model.portal,
        organizations,
        selected_organization_id: Some(organization_id),
        self_service: {
          ..model.portal.self_service,
          step: Organization,
          action_loading: false,
          action_error: None,
        },
      }
      let portal = base.update(SelfService(SelectOrganization(organization_id)))
      let next = {
        ..model,
        connecting: true,
        portal: {
          ..portal,
          success_message: Some(
            portal_copy(
              model.portal.locale,
              "Company created. Machine ordering remains blocked until verification succeeds.",
              "公司已创建；完成验证前，机器下单保持关闭。",
            ),
          ),
          error_message: None,
        },
      }
      (next, load_command(next, emit))
    }
    Outcome(OrganizationJoined) => {
      let next = {
        ..model,
        connecting: true,
        portal: {
          ..model.portal,
          self_service: {
            ..model.portal.self_service,
            action_loading: false,
            action_error: None,
          },
        },
      }
      (next, organization_bootstrap_command(next, emit))
    }
    Outcome(
      MachineCommerceLoaded(
        raw_offerings,
        raw_orders,
        raw_terms,
        provider_requests
      )
    ) => {
      let offerings = raw_offerings.map(machine_offering_view)
      let orders = raw_orders.map(order => machine_order_view(order, offerings))
      let preferred_id = model.portal.self_service.order.map(value => {
        value.order_id
      })
      let mut current = match preferred_id {
        Some(order_id) =>
          orders.iter().find_first(order => order.order_id == order_id)
        None => None
      }
      if current is None {
        for order in orders {
          match current {
            Some(selected) if selected.updated_unix_ms >= order.updated_unix_ms =>
              ()
            _ => current = Some(order)
          }
        }
      }
      (
        {
          ..model,
          portal: {
            ..model.portal,
            self_service: {
              ..model.portal.self_service,
              offerings,
              offerings_loading: false,
              offerings_loaded: true,
              offerings_error: None,
              terms: match raw_terms {
                Some(value) => machine_terms_view(value)
                None => None
              },
              orders,
              order: current,
              checkout: checkout_for_order(current, provider_requests),
              action_loading: false,
              action_error: None,
            },
            provider_requests,
          },
        },
        @rabbita.none,
      )
    }
    Outcome(MachineQuoteLoaded(quote)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            self_service: {
              ..model.portal.self_service,
              quote: Some(machine_quote_view(quote)),
              step: Quote,
              action_loading: false,
              action_error: None,
            },
          },
        },
        @rabbita.none,
      )
    Outcome(MachineTermsAccepted) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            self_service: {
              ..model.portal.self_service,
              terms_accepted: true,
              action_loading: false,
              action_error: None,
            },
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Machine terms accepted. You can now create the order.",
                "机器条款已接受，现在可以创建订单。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(MachineOrderCreated(response)) => {
      let order = machine_order_view(
        response.order,
        model.portal.self_service.offerings,
      )
      let orders = [
        order,
        ..model.portal.self_service.orders.filter(value => {
          value.order_id != order.order_id
        }),
      ]
      (
        {
          ..model,
          portal: {
            ..model.portal,
            self_service: {
              ..model.portal.self_service,
              order: Some(order),
              orders,
              checkout: Some(machine_checkout_view(response.checkout)),
              step: ContractPayment,
              action_loading: false,
              action_error: None,
            },
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Machine order created. Payment remains untrusted until provider settlement is verified.",
                "机器订单已创建；支付服务商结算验证完成前，付款状态保持不可信。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    }
    Outcome(MachineOrderUpdated(raw_order, action)) => {
      let order = machine_order_view(
        raw_order,
        model.portal.self_service.offerings,
      )
      let orders = [
        order,
        ..model.portal.self_service.orders.filter(value => {
          value.order_id != order.order_id
        }),
      ]
      (
        {
          ..model,
          portal: {
            ..model.portal,
            self_service: {
              ..model.portal.self_service,
              order: Some(order),
              orders,
              step: Provisioning,
              action_loading: false,
              action_error: None,
            },
            success_message: Some(
              portal_copy(
                model.portal.locale,
                if action == "cancel" {
                  "Cancellation request recorded. Cleanup continues asynchronously."
                } else {
                  "Termination request recorded. Cleanup continues asynchronously."
                },
                if action == "cancel" {
                  "取消请求已记录；清理将在后台继续。"
                } else {
                  "终止请求已记录；清理将在后台继续。"
                },
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    }
    Outcome(
      Loaded(
        dispatched_session_generation,
        view,
        account,
        trial,
        browser_sessions,
        cost_centers,
        provisional_spend,
        models,
        notifications,
        notification_preferences,
        machines,
        orders,
        artifacts,
        contract_manifest,
        contract_packets,
        contract_events,
        contract_governance,
        desktop_client,
        api_keys,
        provider_requests,
        payment_checkout_quote
      )
    ) => {
      if dispatched_session_generation != model.session_generation {
        return (model, @rabbita.none)
      }
      let active_trial = match trial {
        Some(value) if value.revoked_unix_ms is None &&
          value.expires_unix_ms > current_unix_ms() => Some(value)
        _ => None
      }
      let selected_contract = match
        model.portal.contract_documents.selected_packet_id {
        Some(id) =>
          match
            contract_packets.filter(packet => packet.packet_id == id).get(0) {
            Some(packet) => Some(packet)
            None => contract_packets.get(0)
          }
        None => contract_packets.get(0)
      }
      let next = {
        ..model,
        connecting: false,
        machine_clock_generation: model.machine_clock_generation + 1L,
        portal: {
          ..model.portal,
          membership: Some(view.membership),
          account,
          trial,
          browser_sessions,
          api_keys,
          api_key_issue_draft: match active_trial {
            Some(value) =>
              {
                ..model.portal.api_key_issue_draft,
                allowed_models: value.allowed_models.join(", "),
                lifetime_days: 1,
                maximum_requests: value.maximum_requests,
              }
            None => model.portal.api_key_issue_draft
          },
          agreements: view.agreements,
          lease_requests: view.lease_requests,
          cost_centers,
          provisional_spend,
          payment_checkout_quote,
          provider_requests,
          provider_requests_loading: false,
          payment_checkout_loading: false,
          model_catalog: models,
          desktop_clients: desktop_client,
          desktop_client: match model.portal.desktop_client {
            Some(selected) =>
              match
                desktop_client
                .filter(client => client.client_id == selected.client_id)
                .get(0) {
                Some(client) => Some(client)
                None => desktop_client.get(0)
              }
            None => desktop_client.get(0)
          },
          project_id: match active_trial {
            Some(value) if @enterprise_ui.selected_organization_header(
                model.portal,
              ) ==
              Some(value.organization_id) => value.project_id
            _ => model.portal.project_id
          },
          notifications,
          notification_preferences,
          machine_access: {
            ..model.portal.machine_access,
            machines,
            now_unix_ms: current_unix_ms(),
            loading: false,
          },
          offline_commerce: {
            ..model.portal.offline_commerce,
            orders,
            artifacts,
            selected_order_id: match
              model.portal.offline_commerce.selected_order_id {
              Some(value) => Some(value)
              None =>
                if orders.length() > 0 {
                  Some(orders[0].order_id)
                } else {
                  None
                }
            },
            loading: false,
            error_message: None,
          },
          contract_documents: {
            ..model.portal.contract_documents,
            manifest: contract_manifest.get(0),
            available_manifests: contract_manifest,
            creation_template_id: if model.portal.contract_documents.creation_template_id ==
              "" &&
              contract_manifest.any(item => {
                item.template_id ==
                @contractdoc.undertaking_ofl_manifest().template_id
              }) {
              @contractdoc.undertaking_ofl_manifest().template_id
            } else {
              model.portal.contract_documents.creation_template_id
            },
            available_orders: orders.map(order => {
              (
                order.order_id,
                "\{order.selected_service_code} · \{order.order_id}",
              )
            }),
            undertaking_order_refs: orders
            .filter(order => @offline.undertaking_quote_term(order) is Some(_))
            .map(order => order.order_id),
            signed_artifacts: artifacts
            .filter(artifact => {
              artifact.kind == ExecutedContractScan &&
              artifact.scan_state == ScanPassed &&
              artifact.review_state != ReviewRejected
            })
            .map(artifact => {
              (
                artifact.order_id,
                artifact.artifact_id,
                "v\{artifact.revision} · \{@contractdoc.format_unix_ms_utc(artifact.created_unix_ms)}",
                artifact.created_unix_ms,
              )
            }),
            packets: contract_packets,
            events: contract_events,
            approvals: contract_governance.approvals,
            amendments: contract_governance.amendments,
            obligations: contract_governance.obligations,
            closure_proposals: contract_governance.closure_proposals,
            contract_numbers: contract_governance.numbers,
            now_unix_ms: current_unix_ms(),
            selected_packet_id: selected_contract.map(packet => packet.packet_id),
            selected_form: match selected_contract {
              Some(packet) => packet.active_forms.get(0)
              None => None
            },
            draft_values: selected_contract.map_or([], packet => {
              packet.values.copy()
            }),
            loading: false,
            error_message: None,
          },
          loading: false,
          success_message: Some(
            portal_copy(
              model.portal.locale,
              "Enterprise access loaded.",
              "企业访问权限已加载。",
            ),
          ),
          error_message: None,
        },
      }
      let (next, poll) = match selected_contract {
        Some(packet) => start_contract_poll(next, packet, emit)
        None => (next, @rabbita.none)
      }
      (
        next,
        @rabbita.batch([
          machine_clock_command(next, emit),
          machine_commerce_command(next, emit),
          poll,
        ]),
      )
    }
    Outcome(DesktopClientLaunched(name)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "\{name} received a one-time setup request.",
                "\{name} 已收到单次设置请求。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(OfflineOrderCreated(order)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            offline_commerce: {
              ..model.portal.offline_commerce,
              orders: [order, ..model.portal.offline_commerce.orders],
              selected_order_id: Some(order.order_id),
              loading: false,
              success_message: Some(
                portal_copy(
                  model.portal.locale,
                  "Draft order created. Pricing and offline controls remain pending.",
                  "订单草稿已创建。报价及线下控制仍待办理。",
                ),
              ),
              error_message: None,
            },
          },
        },
        @rabbita.none,
      )
    Outcome(OfflineOrderCancelled(order)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            offline_commerce: {
              ..model.portal.offline_commerce,
              orders: model.portal.offline_commerce.orders.map(existing => {
                if existing.order_id == order.order_id {
                  order
                } else {
                  existing
                }
              }),
              selected_order_id: Some(order.order_id),
              loading: false,
              success_message: Some(
                portal_copy(
                  model.portal.locale,
                  "Cancellation accepted. Active access remains tracked until entitlement authority confirmation.",
                  "已接受取消请求；有效访问将继续跟踪，直至权益授权方确认。",
                ),
              ),
              error_message: None,
            },
          },
        },
        @rabbita.none,
      )
    Outcome(EvidenceUploaded(filename)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            contract_documents: {
              ..model.portal.contract_documents,
              loading: false,
              success_message: Some(
                portal_copy(
                  model.portal.locale,
                  "Signed scan uploaded. Refresh after the safety scan to select it for approval.",
                  "扫描件已上传。安全检查通过后刷新，即可选择并提交审批。",
                ),
              ),
            },
            offline_commerce: {
              ..model.portal.offline_commerce,
              loading: false,
              success_message: Some(
                portal_copy(
                  model.portal.locale,
                  "Evidence uploaded: \{filename}. Safety scanning and reconciliation will continue asynchronously.",
                  "凭证已上传：\{filename}。安全扫描与核验将异步继续。",
                ),
              ),
              error_message: None,
            },
          },
        },
        @rabbita.none,
      )
    Outcome(ArtifactDownloaded(filename)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            contract_documents: {
              ..model.portal.contract_documents,
              loading: false,
              success_message: Some(
                portal_copy(
                  model.portal.locale,
                  "Verified document downloaded: \{filename}.",
                  "已下载并校验文档：\{filename}。",
                ),
              ),
            },
            offline_commerce: {
              ..model.portal.offline_commerce,
              loading: false,
              success_message: Some(
                portal_copy(
                  model.portal.locale,
                  "Verified artifact downloaded: \{filename}.",
                  "已下载并校验文件：\{filename}。",
                ),
              ),
              error_message: None,
            },
          },
        },
        @rabbita.none,
      )
    Outcome(ContractActionNeedsRefresh) => (model, load_command(model, emit))
    Outcome(ContractPacketUpdated(packet)) => {
      let packets = replace_contract_packet(
        model.portal.contract_documents.packets,
        packet,
      )
      let next = {
        ..model,
        portal: {
          ..model.portal,
          contract_documents: {
            ..model.portal.contract_documents,
            packets,
            selected_packet_id: Some(packet.packet_id),
            selected_form: packet.active_forms.get(0),
            draft_values: if model.portal.contract_documents.selected_packet_id ==
              Some(packet.packet_id) {
              merge_contract_draft(
                model.portal.contract_documents.draft_values,
                packet,
              )
            } else {
              packet.values.copy()
            },
            loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Contract packet updated.",
                "合同资料包已更新。",
              ),
            ),
            error_message: None,
          },
        },
      }
      start_contract_poll(next, packet, emit)
    }
    Outcome(ContractApprovalNudged) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            contract_documents: {
              ..model.portal.contract_documents,
              loading: false,
              success_message: Some(
                portal_copy(
                  model.portal.locale,
                  "Approval reminder sent to the operator team.",
                  "已向运营团队发送审批催办。",
                ),
              ),
              error_message: None,
            },
          },
        },
        @rabbita.none,
      )
    Outcome(AgreementUpdated(agreement, provider_requests)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            agreements: replace_agreement(model.portal.agreements, agreement),
            provider_requests,
            provider_requests_loading: false,
            loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Signature ceremony requested. Execution waits for verified provider evidence.",
                "已发起签署流程。协议将在验证提供商证据后执行。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(ProviderRequestsLoaded(provider_requests)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            provider_requests,
            provider_requests_loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Provider status refreshed.",
                "服务商状态已刷新。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(PaymentCheckoutCreated(record)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            provider_requests: upsert_provider_request(
              model.portal.provider_requests,
              record,
            ),
            payment_checkout_loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Checkout request created. Open the provider link only when it appears below.",
                "支付请求已创建。服务商链接在下方出现后，请手动打开。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(LeaseCreated(request)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            lease_requests: [request, ..model.portal.lease_requests],
            loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Lease request submitted to the operator queue.",
                "租用申请已提交至运维审核队列。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(NotificationRead(notification)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            notifications: replace_notification(
              model.portal.notifications,
              notification,
            ),
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Notification marked as read.",
                "通知已标记为已读。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(NotificationPreferenceUpdated(preference)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            notification_preferences: replace_notification_preference(
              model.portal.notification_preferences,
              preference,
            ),
            loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Delivery preferences updated.",
                "投递偏好已更新。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(MachineTerminated(machine)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            machine_access: {
              ..model.portal.machine_access,
              machines: replace_machine(
                model.portal.machine_access.machines,
                machine,
              ),
              confirmation_lease_ref: None,
              confirmation_text: "",
              loading: false,
            },
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Machine access termination started.",
                "机器访问终止流程已开始。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(CredentialRedeemed(credential)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            machine_access: model.portal.machine_access.with_redeemed_credential(
              credential,
            ),
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "SSH access details redeemed. Verify the host key before connecting.",
                "SSH 访问详情已领取。连接前请核对主机密钥。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(MachineClockAdvanced(now_unix_ms, generation)) =>
      if generation != model.machine_clock_generation {
        (model, @rabbita.none)
      } else {
        let session_expired = match model.session_expires_unix_ms {
          Some(expires_unix_ms) => now_unix_ms >= expires_unix_ms
          None => false
        }
        if session_expired {
          return (signed_out_model(model), @rabbita.none)
        }
        let expired = model.portal.machine_access.machines.any(machine => {
          model.portal.machine_access.now_unix_ms < machine.expires_unix_ms &&
          now_unix_ms >= machine.expires_unix_ms
        })
        let next = {
          ..model,
          portal: {
            ..model.portal,
            machine_access: { ..model.portal.machine_access, now_unix_ms, },
          },
        }
        if expired && !model.demo_mode {
          (
            {
              ..next,
              connecting: true,
              machine_clock_generation: generation + 1L,
            },
            load_command(next, emit),
          )
        } else {
          (next, machine_clock_command(next, emit))
        }
      }
    Outcome(Failed(dispatched_locale, message)) => {
      let message = portal_failure_message(model.portal.locale, message)
      (
        {
          ..model,
          connecting: false,
          portal: {
            ..model.portal,
            contract_documents: {
              ..model.portal.contract_documents,
              loading: false,
              success_message: None,
              error_message: Some(message),
            },
            offline_commerce: {
              ..model.portal.offline_commerce,
              loading: false,
              success_message: None,
              error_message: Some(
                if dispatched_locale == model.portal.locale {
                  message
                } else {
                  portal_copy(
                    model.portal.locale,
                    "The commercial operation failed. Retry after refreshing.",
                    "商务操作失败。请刷新后重试。",
                  )
                },
              ),
            },
            loading: false,
            provider_requests_loading: false,
            payment_checkout_loading: false,
            self_service: {
              ..model.portal.self_service,
              offerings_loading: false,
              action_loading: false,
              action_error: Some(
                if dispatched_locale == model.portal.locale {
                  message
                } else {
                  portal_copy(
                    model.portal.locale,
                    "The self-service operation failed. Retry the operation.",
                    "自助操作失败。请重试。",
                  )
                },
              ),
            },
            success_message: None,
            error_message: Some(
              if dispatched_locale == model.portal.locale {
                message
              } else {
                portal_copy(
                  model.portal.locale,
                  "The enterprise operation failed. Retry the operation.",
                  "企业操作失败。请重试。",
                )
              },
            ),
          },
        },
        @rabbita.none,
      )
    }
  }
}

///|
/// Loopback-only, for the development credential fallback. The login and
/// registration forms use the shared transport policy instead: they hand their
/// credential to the gateway, so they may run wherever the deployment has
/// opted public HTTP in. The development tokens are different -- they go
/// straight to the controller as a bearer -- so they stay localhost-only.
extern "js" fn development_transport_allowed(endpoint : String) -> Bool =
  #| (endpoint) => {
  #|   try {
  #|     const url = new URL(endpoint, globalThis.location?.href || "http://localhost/");
  #|     return url.hostname === "localhost" || url.hostname === "127.0.0.1" ||
  #|       url.hostname === "::1" || url.hostname === "[::1]";
  #|   } catch (_) { return false; }
  #| }

///|
fn app_view(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Html {
  let locale = model.portal.locale
  // The login and registration forms post to the same-origin gateway, so they
  // follow the deployment's public-HTTP opt-in exactly as the operator console
  // does. Development tokens keep their own loopback check.
  let transport_allowed = @browser_transport.endpoint_allowed(model.endpoint)
  let development_allowed = development_transport_allowed(model.endpoint)
  let shell_styles =
    #|:root{color-scheme:dark}body{margin:0;background:#071016;color:#ecf5f2;font:14px/1.5 Inter,"PingFang SC","Noto Sans SC",system-ui,sans-serif}.login-gate{min-height:100vh;padding:clamp(1rem,5vw,4rem);display:grid;place-items:center;background:radial-gradient(circle at 80% 0,rgba(53,189,141,.14),transparent 34rem),#071016}.login-card{box-sizing:border-box;width:min(38rem,100%);padding:clamp(1.25rem,4vw,2.5rem);border:1px solid #29424f;border-radius:1rem;background:#0d1820;box-shadow:0 2rem 6rem rgba(0,0,0,.35)}.login-mark{width:2.6rem;height:2.6rem;display:grid;place-items:center;border-radius:.7rem;background:#7ee0bd;color:#06251a;font-weight:900}.login-card h1{margin:1rem 0 .4rem;font-size:clamp(1.8rem,5vw,2.7rem);line-height:1.1}.login-card>p{color:#9db0b6}.login-sso-note{padding:.9rem;border-left:3px solid #7ee0bd;background:rgba(126,224,189,.06)}.sso-start{min-height:48px;margin:.9rem 0;display:flex;align-items:center;justify-content:center;padding:.65rem 1rem;border:1px solid #35bd8d;border-radius:.55rem;background:#7ee0bd;color:#06251a;text-decoration:none;font-weight:900}.bootstrap-status{color:#9db0b6;text-align:center}.development-fallback{margin-top:1.2rem;border:1px solid #29424f;border-radius:.7rem}.development-fallback summary{min-height:44px;padding:.8rem 1rem;cursor:pointer;font-weight:800}.development-form{display:grid;gap:.8rem;padding:0 1rem 1rem}.development-form label{display:block;margin-bottom:.3rem;font-weight:750}.development-form input{width:100%;min-height:44px;box-sizing:border-box;padding:.6rem .7rem;border:1px solid #35505f;border-radius:.5rem;background:#071218;color:#ecf5f2;font:inherit}.development-form button,.session-strip button{min-height:44px;padding:.6rem .9rem;border:1px solid #35bd8d;border-radius:.5rem;background:#7ee0bd;color:#06251a;font:inherit;font-weight:850;cursor:pointer}.development-form button:disabled{opacity:.45;cursor:not-allowed}.development-warning,.login-error{margin:0;padding:.7rem;border-radius:.5rem}.development-warning{color:#f1c66c;background:rgba(241,198,108,.08)}.login-error{color:#ffadad;background:rgba(241,111,111,.1)}.session-strip{position:relative;z-index:45;display:flex;align-items:center;justify-content:space-between;gap:1rem;padding:.65rem 1rem;border-bottom:1px solid #223743;background:#09151c;color:#9db0b6}.session-strip strong{color:#ecf5f2}.session-strip p{margin:0}.session-strip button{background:transparent;color:#ecf5f2;border-color:#35505f}.demo-flag{position:fixed;z-index:45;right:1rem;top:1rem;padding:.45rem .65rem;border:1px solid rgba(126,224,189,.3);border-radius:999px;background:#0b1720;color:#7ee0bd;font:800 .65rem/1 system-ui}.login-card form{margin:.95rem 0 0}.login-actions{display:flex;flex-wrap:wrap;gap:.6rem}.login-actions button{flex:1 1 auto}.login-actions button[type=button]{background:transparent;color:#ecf5f2;border-color:#35505f}.login-divider{display:flex;align-items:center;gap:.6rem;margin:1.1rem 0 .6rem;color:#9db0b6;font-size:.75rem}.login-divider::before,.login-divider::after{height:1px;flex:1;background:#29424f;content:""}@media(max-width:38rem){.demo-flag{position:absolute}.session-strip{align-items:stretch;flex-direction:column}.session-strip button{width:100%}.login-gate{place-items:start center}}@media(prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
  if model.demo_mode {
    return @html.div([
      @html.style_tag(shell_styles),
      @html.div(
        class="demo-flag",
        portal_copy(
          locale, "DEMO · enterprise portal", "演示 · 企业门户",
        ),
      ),
      @enterprise_ui.interactive_view(
        {
          ..model.portal,
          docs_base_url: if configured_docs_url() == "" {
            None
          } else {
            Some(configured_docs_url())
          },
        },
        emit.map(message => Portal(message)),
      ),
    ])
  }
  if model.token == "" {
    return @html.main_(class="login-gate", [
      @html.style_tag(shell_styles),
      @html.section(
        class="login-card",
        attrs=@html.Attrs::build().aria_labelledby("enterprise-sign-in-title"),
        [
          @html.div(class="login-mark", "NX"),
          @html.h1(
            id="enterprise-sign-in-title",
            portal_copy(
              locale, "LunaNexa enterprise access", "LunaNexa 企业访问",
            ),
          ),
          @html.p(
            portal_copy(
              locale, "Sign in with an existing identity or register a new account through the trusted identity ingress.",
              "使用现有身份登录，或通过受信任的身份入口注册新账户。",
            ),
          ),
          @html.p(
            portal_copy(
              locale, "This is the customer portal for workspaces, model APIs and machine orders. The operator console has a separate application session, even when you use the same identity.",
              "这里是用于工作空间、模型 API 和机器订单的用户门户。运维控制台使用独立的应用会话，即使登录的是同一身份。",
            ),
          ),
          @html.p(
            class="login-sso-note",
            if model.registering {
              portal_copy(
                locale, "A new account needs an email address, the name you want shown, and a password of at least 12 characters with an uppercase letter, a lowercase letter, a digit and a symbol. An eligible first sign-in also creates a bounded trial when trials are enabled.",
                "新账户需要邮箱、希望显示的名称，以及至少 12 位且包含大写字母、小写字母、数字和符号的密码。开启体验时，符合条件的首次登录还会获得受限体验额度。",
              )
            } else {
              portal_copy(
                locale, "Sign in with the address and password you registered. The gateway checks them and hands this page a short-lived session; LunaNexa never stores your password.",
                "请使用注册时的邮箱和密码登录。网关校验后向前端签发短期会话；LunaNexa 不保存您的密码。",
              )
            },
          ),
          @html.form(
            class="development-form",
            on_submit=emit(
              if model.registering {
                EnterpriseRegistrationSubmitted
              } else {
                EnterpriseSignInSubmitted
              },
            ),
            [
              @html.div([
                @html.label(
                  for_="portal-login-email",
                  portal_copy(locale, "Email address", "邮箱"),
                ),
                @html.input(
                  id="portal-login-email",
                  value=model.login_email,
                  auto_complete=On,
                  maxlength=320,
                  attrs=@html.Attrs::build().disabled(
                    !transport_allowed || model.connecting,
                  ),
                  on_input=emit.map(value => LoginEmailChanged(value)),
                ),
              ]),
              if model.registering {
                @html.div([
                  @html.label(
                    for_="portal-register-name",
                    portal_copy(locale, "Display name", "显示名称"),
                  ),
                  @html.input(
                    id="portal-register-name",
                    value=model.register_display_name,
                    auto_complete=On,
                    maxlength=128,
                    attrs=@html.Attrs::build().disabled(
                      !transport_allowed || model.connecting,
                    ),
                    on_input=emit.map(value => RegisterDisplayNameChanged(value)),
                  ),
                ])
              } else {
                @html.nothing
              },
              @html.div([
                @html.label(
                  for_="portal-login-password",
                  portal_copy(locale, "Password", "密码"),
                ),
                @html.input(
                  id="portal-login-password",
                  input_type=Password,
                  value=model.login_password,
                  auto_complete=On,
                  maxlength=256,
                  attrs=@html.Attrs::build().disabled(
                    !transport_allowed || model.connecting,
                  ),
                  on_input=emit.map(value => LoginPasswordChanged(value)),
                ),
              ]),
              @html.div(class="login-actions", [
                @html.button(
                  type_="submit",
                  disabled=!transport_allowed ||
                    model.connecting ||
                    model.login_email.trim() == "" ||
                    model.login_password == "" ||
                    (
                      model.registering &&
                      model.register_display_name.trim() == ""
                    ),
                  if model.connecting {
                    portal_copy(locale, "Connecting…", "正在连接…")
                  } else if model.registering {
                    portal_copy(locale, "Create account", "创建账户")
                  } else {
                    portal_copy(locale, "Sign in", "登录")
                  },
                ),
                @html.button(
                  type_="button",
                  disabled=model.connecting,
                  on_click=emit(ToggleRegistration),
                  if model.registering {
                    portal_copy(
                      locale, "I already have an account", "我已有账户，去登录",
                    )
                  } else {
                    portal_copy(
                      locale, "Register a new account", "注册新账户",
                    )
                  },
                ),
              ]),
            ],
          ),
          @html.div(
            class="login-divider",
            portal_copy(
              locale, "or use organization sign-in", "或使用组织账户登录",
            ),
          ),
          @html.a(
            class="sso-start",
            href="/auth/oidc/start?audience=enterprise",
            portal_copy(
              locale, "Sign in with the organization identity provider", "使用组织身份提供商登录",
            ),
          ),
          if model.connecting {
            @html.p(
              class="bootstrap-status",
              attrs=@html.Attrs::build().role("status").aria_live("polite"),
              portal_copy(
                locale, "Checking for an existing browser session…", "正在检查现有浏览器会话…",
              ),
            )
          } else {
            @html.nothing
          },
          match model.portal.error_message {
            Some(message) =>
              @html.p(
                class="login-error",
                attrs=@html.Attrs::build().role("alert"),
                message,
              )
            None => @html.nothing
          },
          if !transport_allowed {
            @html.p(
              class="login-error",
              attrs=@html.Attrs::build().role("alert"),
              portal_copy(
                locale, "Account login is blocked on public plain HTTP. Use the protected localhost URL or install TLS first.",
                "公共明文 HTTP 已禁止账户登录。请使用受保护的本机地址，或先部署 TLS。",
              ),
            )
          } else if model.endpoint.has_prefix("http://") && !development_allowed {
            @html.p(
              class="development-warning",
              portal_copy(
                locale, "Temporary HTTP mode is enabled by this deployment. Browser traffic is not encrypted; use only on a trusted network.",
                "此部署已开启临时 HTTP 模式。浏览器流量未加密，请仅在可信网络中使用。",
              ),
            )
          } else {
            @html.nothing
          },
          if development_allowed {
            @html.details(class="development-fallback", [
              @html.summary(
                portal_copy(
                  locale, "Development credential fallback", "开发凭据后备方式",
                ),
              ),
              @html.div(class="development-form", [
                @html.p(
                  class="development-warning",
                  portal_copy(
                    locale, "Local acceptance only. Enter a short-lived scoped token and opaque test subject. Public plain HTTP is blocked.",
                    "仅用于本地验收。请输入短期限定范围令牌和不透明测试主体。公共明文 HTTP 已被阻止。",
                  ),
                ),
                @html.div([
                  @html.label(
                    for_="portal-token",
                    portal_copy(
                      locale, "Scoped development token", "限定范围开发令牌",
                    ),
                  ),
                  @html.input(
                    id="portal-token",
                    input_type=Password,
                    value=model.token,
                    auto_complete=Off,
                    on_input=emit.map(value => TokenChanged(value)),
                  ),
                ]),
                @html.div([
                  @html.label(
                    for_="portal-subject",
                    portal_copy(
                      locale, "Opaque test subject", "不透明测试主体",
                    ),
                  ),
                  @html.input(
                    id="portal-subject",
                    value=model.subject_ref,
                    maxlength=256,
                    auto_complete=Off,
                    on_input=emit.map(value => SubjectChanged(value)),
                  ),
                ]),
                @html.div([
                  @html.label(
                    for_="portal-endpoint",
                    portal_copy(
                      locale, "Controller endpoint", "控制器端点",
                    ),
                  ),
                  @html.input(
                    id="portal-endpoint",
                    value=model.endpoint,
                    on_input=emit.map(value => EndpointChanged(value)),
                  ),
                ]),
                @html.button(
                  type_="button",
                  disabled=model.connecting ||
                    model.token == "" ||
                    model.subject_ref == "" ||
                    !development_allowed,
                  on_click=emit(Connect),
                  if model.connecting {
                    portal_copy(locale, "Connecting…", "正在连接…")
                  } else {
                    portal_copy(
                      locale, "Connect development identity", "连接开发身份",
                    )
                  },
                ),
                if development_allowed {
                  @html.nothing
                } else {
                  @html.p(
                    class="login-error",
                    attrs=@html.Attrs::build().role("alert"),
                    portal_copy(
                      locale, "Development credentials are restricted to localhost or loopback.",
                      "开发凭据仅限 localhost 或环回地址。",
                    ),
                  )
                },
              ]),
            ])
          } else {
            @html.nothing
          },
        ],
      ),
    ])
  }
  let session_scope = match model.portal.membership {
    Some(membership) =>
      "\{membership.subject_ref} · \{membership.organization_id}"
    None => portal_copy(locale, "Organization setup", "组织设置")
  }
  let session_transport_copy = if model.endpoint.has_prefix("http://") &&
    !development_allowed {
    portal_copy(
      locale, "HTTP browser session (unencrypted); ends on logout or expiry", "HTTP 浏览器会话（未加密）；退出或到期时结束",
    )
  } else {
    portal_copy(
      locale, "browser session; ends on logout or expiry", "浏览器会话；退出或到期时结束",
    )
  }
  @html.div([
    @html.style_tag(shell_styles),
    @html.header(class="session-strip", [
      @html.p([
        @html.strong(session_scope),
        @html.span(" · " + session_transport_copy),
      ]),
      @html.button(
        type_="button",
        on_click=emit(Logout),
        portal_copy(locale, "Log out", "退出登录"),
      ),
    ]),
    @enterprise_ui.interactive_view(
      {
        ..model.portal,
        docs_base_url: if configured_docs_url() == "" {
          None
        } else {
          Some(configured_docs_url())
        },
      },
      emit.map(message => Portal(message)),
    ),
  ])
}

///|
fn subscriptions(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @sub.Sub {
  if !model.demo_mode && !model.bootstrap_started {
    @sub.every(1, emit(Bootstrap))
  } else {
    @sub.none
  }
}

///|
fn main {
  install_dialog_focus()
  let is_demo = demo_mode()
  let initial_locale = @i18n.parse_locale(stored_locale_preference())
  commit_enterprise_organization(stored_organization_preference())
  apply_enterprise_locale(initial_locale)
  @rabbita.elmish(
    model={
      endpoint: configured_endpoint(),
      token: "",
      csrf_token: "",
      subject_ref: "",
      connecting: false,
      bootstrap_started: is_demo,
      demo_mode: is_demo,
      session_generation: 0L,
      session_expires_unix_ms: None,
      machine_clock_generation: 0L,
      contract_preview_generation: 0L,
      contract_poll_generation: 0L,
      portal: if is_demo {
        {
          ..@enterprise_ui.demo_state(),
          docs_base_url: if configured_docs_url() == "" {
            None
          } else {
            Some(configured_docs_url())
          },
          locale: initial_locale,
          machine_access: {
            ..@enterprise_ui.demo_state().machine_access,
            locale: initial_locale,
          },
          offline_commerce: {
            ..@enterprise_ui.demo_state().offline_commerce,
            locale: initial_locale,
          },
          contract_documents: {
            ..@enterprise_ui.demo_state().contract_documents,
            locale: initial_locale,
          },
        }
      } else {
        {
          ..@enterprise_ui.default_state(current_unix_ms()),
          docs_base_url: if configured_docs_url() == "" {
            None
          } else {
            Some(configured_docs_url())
          },
          locale: initial_locale,
          machine_access: {
            ..@enterprise_ui.default_state(current_unix_ms()).machine_access,
            locale: initial_locale,
          },
          offline_commerce: {
            ..@enterprise_ui.default_state(current_unix_ms()).offline_commerce,
            locale: initial_locale,
          },
          contract_documents: {
            ..@enterprise_ui.default_state(current_unix_ms()).contract_documents,
            locale: initial_locale,
          },
        }
      },
      login_email: "",
      login_password: "",
      register_display_name: "",
      registering: false,
    },
    view=app_view,
    update~,
    subscriptions~,
  ).mount("app")
}
