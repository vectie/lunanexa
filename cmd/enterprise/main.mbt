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
  portal : @enterprise_ui.EnterpriseState
} derive(Eq)

///|
priv struct GatewayBrowserBootstrap {
  session_token : String
  csrf_token : String
  expires_unix_ms : Int64
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
    @contractdoc.ContractTemplateManifest,
    Array[@contractdoc.ContractPacket],
    Array[@contractdoc.ContractPacketEvent],
    ContractSelfGovernance,
    @enterprise_ui.EnterpriseDesktopClient?,
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
  EndpointChanged(String)
  TokenChanged(String)
  SubjectChanged(String)
  Connect
  Bootstrap
  BootstrapReady(Int64, GatewayBrowserBootstrap)
  BootstrapUnavailable(Int64)
  Logout
  LogoutCompleted(Int64)
  Portal(@enterprise_ui.EnterpriseMessage)
  ContractPreviewDue(Int64, @contract_documents.ContractDocumentsMessage)
  Outcome(Outcome)
}

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
fn apply_enterprise_locale(locale : @i18n.Locale) -> Unit {
  commit_enterprise_locale(
    locale.storage_value(),
    locale.language_tag(),
    portal_copy(
      locale, "LunaNexa | Enterprise Portal", "LunaNexa | 企业门户",
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
extern "js" fn random_identifier(prefix : String) -> String =
  #| prefix => `${prefix}-${crypto.randomUUID()}`

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
  #|     let message = `HTTP ${response.status}`;
  #|     try { message = JSON.parse(text)?.error?.message || message; } catch (_) {}
  #|     throw new Error(message);
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
) -> @js.Promise =
  #| async (url, sessionToken, maximumByteCount, expectedSha256, filename) => {
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
  #|   const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  #|   const actual = `sha256:${Array.from(digest, byte => byte.toString(16).padStart(2, "0")).join("")}`;
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
            "Unable to load your organizations: \{Repr(error)}",
            "无法加载您的组织：\{Repr(error)}",
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
            "Unable to create the company: \{Repr(error)}",
            "无法创建公司：\{Repr(error)}",
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
            "Unable to accept the company invitation: \{Repr(error)}",
            "无法接受公司邀请：\{Repr(error)}",
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
            "Unable to record machine terms acceptance: \{Repr(error)}",
            "无法记录机器条款接受证据：\{Repr(error)}",
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
            "Unable to load machine inventory and orders: \{Repr(error)}",
            "无法加载机器库存与订单：\{Repr(error)}",
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
            "Unable to create the signed machine quote: \{Repr(error)}",
            "无法创建签名机器报价：\{Repr(error)}",
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
            "Unable to create the machine order: \{Repr(error)}",
            "无法创建机器订单：\{Repr(error)}",
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
            "Unable to \{action} the machine order: \{Repr(error)}",
            (if action == "cancel" {
              "无法取消机器订单："
            } else {
              "无法终止机器订单："
            }) +
            "\{Repr(error)}",
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
  let allowed_models : Array[String] = []
  for entry in model.portal.model_catalog {
    match entry.alias_name {
      Some(model_alias) if !allowed_models.contains(model_alias) =>
        allowed_models.push(model_alias)
      _ => ()
    }
  }
  if allowed_models.length() == 0 {
    raise Failure("no approved model alias is available for the desktop client")
  }
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/self/client-handoffs",
    model.token,
    model.subject_ref,
    body=(
      {
        "request_id": random_identifier("desktop-handoff"),
        "client_id": client.client_id,
        "project_id": model.portal.project_id,
        "allowed_models": allowed_models.to_json(),
      } : Json).stringify(),
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
            "Unable to open the desktop WebIDE: \{Repr(error)}",
            "无法打开桌面 WebIDE：\{Repr(error)}",
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
  @contractdoc.ContractTemplateManifest,
  Array[@contractdoc.ContractPacket],
  Array[@contractdoc.ContractPacketEvent],
  ContractSelfGovernance,
  @enterprise_ui.EnterpriseDesktopClient?,
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
  let contract_manifest : @contractdoc.ContractTemplateManifest = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/contract-documents/manifest",
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
  let desktop_client : @enterprise_ui.EnterpriseDesktopClient? = try {
    let response : DesktopClientResponse = @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/portal/self/client",
          model.token,
          model.subject_ref,
        ),
      ),
    )
    let client_view : @enterprise_ui.EnterpriseDesktopClient = {
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
    }
    Some(client_view)
  } catch {
    _ => None
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
  let intent : OfflineOrderIntent = {
    order_id: random_identifier("offline-order"),
    idempotency_key: random_identifier("offline-order-create"),
    project_id: commerce.project_id.trim().to_owned(),
    selected_service_code: commerce.service_code.trim().to_owned(),
    selected_sla_code: commerce.sla_code.trim().to_owned(),
    expires_unix_ms: current_unix_ms() + 2592000000L,
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
            "Unable to create the API key: \{Repr(error)}",
            "无法创建 API 密钥：\{Repr(error)}",
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
            "Unable to revoke the API key: \{Repr(error)}",
            "无法撤销 API 密钥：\{Repr(error)}",
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
            "Clipboard access failed. Select and copy the secret manually: \{Repr(error)}",
            "无法访问剪贴板。请手动选择并复制密钥：\{Repr(error)}",
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
            "Unable to load enterprise access: \{Repr(error)}",
            "无法加载企业访问权限：\{Repr(error)}",
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
            "Unable to create the offline order: \{Repr(error)}",
            "无法创建线上线下协同订单：\{Repr(error)}",
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
            "Unable to cancel the order or end access: \{Repr(error)}",
            "无法取消订单或结束访问：\{Repr(error)}",
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
            "Unable to create the evidence upload grant: \{Repr(error)}",
            "无法创建凭证上传授权：\{Repr(error)}",
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
            "Unable to download the verified artifact: \{Repr(error)}",
            "无法下载已验证文件：\{Repr(error)}",
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
            "Unable to update notification: \{Repr(error)}",
            "无法更新通知：\{Repr(error)}",
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
            "Unable to update delivery preferences: \{Repr(error)}",
            "无法更新投递偏好：\{Repr(error)}",
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
            "Unable to terminate machine access: \{Repr(error)}",
            "无法终止机器访问：\{Repr(error)}",
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
            "Unable to redeem machine access: \{Repr(error)}",
            "无法领取机器访问凭据：\{Repr(error)}",
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
            "Signature request was rejected: \{Repr(error)}",
            "签署请求被拒绝：\{Repr(error)}",
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
            "Provider status could not be refreshed: \{Repr(error)}",
            "无法刷新服务商状态：\{Repr(error)}",
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
            "Checkout request was rejected: \{Repr(error)}",
            "支付请求被拒绝：\{Repr(error)}",
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
            "Lease request was rejected: \{Repr(error)}",
            "租用申请被拒绝：\{Repr(error)}",
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
    body=ContractInformationUpdate::{ expected_revision, changes }
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
    body=ContractRevisionAction::{ expected_revision, expected_values_sha256 }
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
    body=ContractPreviewIntent::{ expected_revision, form, changes }
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
  let text : String = demo_contract_preview_promise().wait().cast()
  let template : @contractdoc.ContractPreviewTemplate = @json.from_json(
    @json.parse(text),
  )
  guard model.portal.contract_documents.manifest is Some(manifest) else {
    fail("contract manifest unavailable")
  }
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
    _ => return { ..documents, loading: false }
  }
  guard documents.manifest is Some(manifest) &&
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
          "Contract document operation failed: \{Repr(error)}",
          "合同文件操作失败：\{Repr(error)}",
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
            "Unable to send the approval reminder: \{Repr(error)}",
            "无法发送审批催办：\{Repr(error)}",
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
      { ..model, portal: { ..model.portal, contract_documents: documents } },
      @rabbita.none,
    )
  }
  let generation = model.contract_preview_generation + 1L
  let pending = documents.update(request)
  let next = {
    ..model,
    contract_preview_generation: generation,
    portal: { ..model.portal, contract_documents: pending },
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
    EndpointChanged(value) => ({ ..model, endpoint: value }, @rabbita.none)
    TokenChanged(value) => ({ ..model, token: value }, @rabbita.none)
    SubjectChanged(value) => ({ ..model, subject_ref: value }, @rabbita.none)
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
        let next = { ..model, bootstrap_started: true, connecting: true }
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
        ({ ..model, connecting: false }, @rabbita.none)
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
        { ..model, portal: model.portal.update(LocaleChanged(locale)) },
        @rabbita.none,
      )
    }
    Portal(Navigate(route)) => {
      let portal = model.portal.update(Navigate(route))
      let next = { ..model, portal, }
      match route {
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
      let next = { ..model, portal, }
      match @enterprise_ui.selected_organization_header(portal) {
        Some(selected) if !model.demo_mode => {
          commit_enterprise_organization(selected)
          let loading = { ..next, connecting: true }
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
      let next = { ..model, portal, connecting: true }
      if model.demo_mode {
        (
          {
            ..next,
            connecting: false,
            portal: {
              ..portal,
              self_service: { ..portal.self_service, action_loading: false },
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
              self_service: { ..portal.self_service, action_loading: false },
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
              self_service: { ..portal.self_service, action_loading: false },
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
            { ..value, status: CancelledOrder, generation: generation + 1L }
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
            { ..value, status: TerminationPending, generation: generation + 1L }
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
        ({ ..model, portal: next }, api_key_issue_command(model, emit))
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
        ({ ..model, portal: next }, api_key_revoke_command(model, key_id, emit))
      }
    }
    Portal(CopyOneTimeApiKeySecret) =>
      match model.portal.one_time_api_key_secret {
        Some(value) if !model.demo_mode =>
          (model, copy_api_key_secret_command(model, value.secret, emit))
        _ => (model, @rabbita.none)
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
                      "MoonLeaf preview failed: \{Repr(error)}",
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
          { ..model, portal: next },
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
        ({ ..model, portal: next }, provider_requests_command(model, emit))
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
        ({ ..model, portal: next }, payment_checkout_command(model, emit))
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
        ({ ..model, portal: next }, lease_command(model, emit))
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
        ({ ..model, portal: next }, desktop_client_command(model, emit))
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
        ({ ..model, portal: { ..model.portal, notifications, } }, @rabbita.none)
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
        ({ ..model, portal: next }, offline_order_command(model, emit))
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
          { ..model, portal: next },
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
          { ..model, portal: next },
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
        ({ ..model, portal: next }, @rabbita.none)
      } else {
        (
          { ..model, portal: next },
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
          { ..model, portal: { ..model.portal, contract_documents: documents } },
          contract_approval_nudge_command(model, approval_id, emit),
        )
      }
    }
    Portal(ContractDocuments(RequestPreview(_, _, _, _) as request)) => {
      let documents = model.portal.contract_documents.update(request)
      schedule_contract_preview(model, documents, 0, emit)
    }
    Portal(ContractDocuments(message)) if message is SaveInformation(_, _, _) ||
      message is ConfirmAction(_) => {
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
          { ..model, portal: next },
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
      ({ ..model, portal: model.portal.update(portal_message) }, @rabbita.none)
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
            { ..key, revoked_unix_ms: Some(revoked_at) }
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
                  "Secret copied. Save it securely, then clear this dialog.",
                  "密钥已复制。请安全保存，然后清除此对话框。",
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
          let next = { ..model, connecting: true, portal }
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
          desktop_client,
          project_id: match active_trial {
            Some(value) => value.project_id
            None => model.portal.project_id
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
            manifest: Some(contract_manifest),
            packets: contract_packets,
            events: contract_events,
            approvals: contract_governance.approvals,
            amendments: contract_governance.amendments,
            obligations: contract_governance.obligations,
            closure_proposals: contract_governance.closure_proposals,
            contract_numbers: contract_governance.numbers,
            now_unix_ms: current_unix_ms(),
            selected_packet_id: match
              model.portal.contract_documents.selected_packet_id {
              Some(value) => Some(value)
              None => contract_packets.get(0).map(packet => packet.packet_id)
            },
            draft_values: contract_packets
            .get(0)
            .map_or([], packet => packet.values.copy()),
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
      (
        next,
        @rabbita.batch([
          machine_clock_command(next, emit),
          machine_commerce_command(next, emit),
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
    Outcome(ContractPacketUpdated(packet)) => {
      let packets = replace_contract_packet(
        model.portal.contract_documents.packets,
        packet,
      )
      (
        {
          ..model,
          portal: {
            ..model.portal,
            contract_documents: {
              ..model.portal.contract_documents,
              packets,
              selected_packet_id: Some(packet.packet_id),
              draft_values: merge_contract_draft(
                model.portal.contract_documents.draft_values,
                packet,
              ),
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
        },
        @rabbita.none,
      )
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
    Outcome(Failed(dispatched_locale, message)) =>
      (
        {
          ..model,
          connecting: false,
          portal: {
            ..model.portal,
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

///|
extern "js" fn development_transport_allowed(endpoint : String) -> Bool =
  #| (endpoint) => {
  #|   try {
  #|     const url = new URL(endpoint, globalThis.location?.href || "http://localhost/");
  #|     return url.protocol === "https:" || url.hostname === "localhost" ||
  #|       url.hostname === "127.0.0.1" || url.hostname === "::1";
  #|   } catch (_) { return false; }
  #| }

///|
fn app_view(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Html {
  let locale = model.portal.locale
  let transport_allowed = development_transport_allowed(model.endpoint)
  let shell_styles =
    #|:root{color-scheme:dark}body{margin:0;background:#071016;color:#ecf5f2;font:14px/1.5 Inter,"PingFang SC","Noto Sans SC",system-ui,sans-serif}.login-gate{min-height:100vh;padding:clamp(1rem,5vw,4rem);display:grid;place-items:center;background:radial-gradient(circle at 80% 0,rgba(53,189,141,.14),transparent 34rem),#071016}.login-card{box-sizing:border-box;width:min(38rem,100%);padding:clamp(1.25rem,4vw,2.5rem);border:1px solid #29424f;border-radius:1rem;background:#0d1820;box-shadow:0 2rem 6rem rgba(0,0,0,.35)}.login-mark{width:2.6rem;height:2.6rem;display:grid;place-items:center;border-radius:.7rem;background:#7ee0bd;color:#06251a;font-weight:900}.login-card h1{margin:1rem 0 .4rem;font-size:clamp(1.8rem,5vw,2.7rem);line-height:1.1}.login-card>p{color:#9db0b6}.login-sso-note{padding:.9rem;border-left:3px solid #7ee0bd;background:rgba(126,224,189,.06)}.sso-start{min-height:48px;margin:.9rem 0;display:flex;align-items:center;justify-content:center;padding:.65rem 1rem;border:1px solid #35bd8d;border-radius:.55rem;background:#7ee0bd;color:#06251a;text-decoration:none;font-weight:900}.bootstrap-status{color:#9db0b6;text-align:center}.development-fallback{margin-top:1.2rem;border:1px solid #29424f;border-radius:.7rem}.development-fallback summary{min-height:44px;padding:.8rem 1rem;cursor:pointer;font-weight:800}.development-form{display:grid;gap:.8rem;padding:0 1rem 1rem}.development-form label{display:block;margin-bottom:.3rem;font-weight:750}.development-form input{width:100%;min-height:44px;box-sizing:border-box;padding:.6rem .7rem;border:1px solid #35505f;border-radius:.5rem;background:#071218;color:#ecf5f2;font:inherit}.development-form button,.session-strip button{min-height:44px;padding:.6rem .9rem;border:1px solid #35bd8d;border-radius:.5rem;background:#7ee0bd;color:#06251a;font:inherit;font-weight:850;cursor:pointer}.development-form button:disabled{opacity:.45;cursor:not-allowed}.development-warning,.login-error{margin:0;padding:.7rem;border-radius:.5rem}.development-warning{color:#f1c66c;background:rgba(241,198,108,.08)}.login-error{color:#ffadad;background:rgba(241,111,111,.1)}.session-strip{position:relative;z-index:45;display:flex;align-items:center;justify-content:space-between;gap:1rem;padding:.65rem 1rem;border-bottom:1px solid #223743;background:#09151c;color:#9db0b6}.session-strip strong{color:#ecf5f2}.session-strip p{margin:0}.session-strip button{background:transparent;color:#ecf5f2;border-color:#35505f}.demo-flag{position:fixed;z-index:45;right:1rem;top:1rem;padding:.45rem .65rem;border:1px solid rgba(126,224,189,.3);border-radius:999px;background:#0b1720;color:#7ee0bd;font:800 .65rem/1 system-ui}@media(max-width:38rem){.demo-flag{position:absolute}.session-strip{align-items:stretch;flex-direction:column}.session-strip button{width:100%}.login-gate{place-items:start center}}@media(prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
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
        model.portal,
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
            class="login-sso-note",
            portal_copy(
              locale, "Production access uses ingress-managed authentication and MFA. An eligible first sign-in creates the account and a bounded trial when trials are enabled. LunaNexa never accepts an account password here.",
              "生产访问使用入口管理的身份认证和多因素认证。首次登录的合格用户会创建账户；平台启用体验时还会获得受限体验。LunaNexa 不会在此接收账户密码。",
            ),
          ),
          @html.a(
            class="sso-start",
            href="/auth/oidc/start?audience=enterprise",
            portal_copy(
              locale, "Sign in or create an account", "登录或创建账户",
            ),
          ),
          if model.connecting {
            @html.p(
              class="bootstrap-status",
              attrs=@html.Attrs::build().role("status").aria_live("polite"),
              portal_copy(
                locale, "Checking for an existing secure browser session…", "正在检查现有安全浏览器会话…",
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
                  portal_copy(locale, "Controller endpoint", "控制器端点"),
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
                  !transport_allowed,
                on_click=emit(Connect),
                if model.connecting {
                  portal_copy(locale, "Connecting…", "正在连接…")
                } else {
                  portal_copy(
                    locale, "Connect development identity", "连接开发身份",
                  )
                },
              ),
              if transport_allowed {
                @html.nothing
              } else {
                @html.p(
                  class="login-error",
                  attrs=@html.Attrs::build().role("alert"),
                  portal_copy(
                    locale, "Use HTTPS, localhost, or loopback for development credentials.",
                    "开发凭据仅可通过 HTTPS、localhost 或环回地址使用。",
                  ),
                )
              },
            ]),
          ]),
        ],
      ),
    ])
  }
  let session_scope = match model.portal.membership {
    Some(membership) =>
      "\{membership.subject_ref} · \{membership.organization_id}"
    None => portal_copy(locale, "Organization setup", "组织设置")
  }
  @html.div([
    @html.style_tag(shell_styles),
    @html.header(class="session-strip", [
      @html.p([
        @html.strong(session_scope),
        @html.span(
          " · " +
          portal_copy(
            locale, "development browser session; ends on logout or reload", "开发浏览器会话；退出或重新加载时结束",
          ),
        ),
      ]),
      @html.button(
        type_="button",
        on_click=emit(Logout),
        portal_copy(locale, "Log out", "退出登录"),
      ),
    ]),
    @enterprise_ui.interactive_view(
      model.portal,
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
      portal: if is_demo {
        {
          ..@enterprise_ui.demo_state(),
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
    },
    view=app_view,
    update~,
    subscriptions~,
  ).mount("app")
}
