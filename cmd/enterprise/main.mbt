///|
priv struct AppModel {
  endpoint : String
  token : String
  subject_ref : String
  connecting : Bool
  demo_mode : Bool
  machine_clock_generation : Int64
  portal : @enterprise_ui.EnterpriseState
} derive(Eq)

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
priv enum Outcome {
  Loaded(
    @portal.EnterpriseSelfView,
    Array[@enterprise_ui.EnterpriseCostCenterRow],
    String,
    Array[@portal.EnterpriseModelSummary],
    Array[@notifications.NotificationRecord],
    Array[@notifications.NotificationPreferenceView],
    Array[@nodelease.CustomerExclusiveMachineView],
    Array[@offline.CommercialOrder],
    Array[@offline_commerce.OfflineArtifactSummary],
    @contractdoc.ContractTemplateManifest,
    Array[@contractdoc.ContractPacket]
  )
  AgreementUpdated(@portal.PortalAgreement)
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
  ContractPreviewLoaded(@contractdoc.ContractPreviewDocument)
  ContractPreviewFailed(@i18n.Locale, String)
  Failed(@i18n.Locale, String)
}

///|
priv enum AppMessage {
  EndpointChanged(String)
  TokenChanged(String)
  SubjectChanged(String)
  Connect
  Portal(@enterprise_ui.EnterpriseMessage)
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
extern "js" fn machine_clock_promise(expires_unix_ms : Int64) -> @js.Promise =
  #| expires => new Promise(resolve => {
  #|   const remaining = expires - BigInt(Date.now());
  #|   const delay = remaining <= 0n ? 0 : Number(remaining > 60000n ? 60000n : remaining);
  #|   setTimeout(() => resolve(BigInt(Date.now())), delay);
  #| })

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
  #|     let message = `HTTP ${response.status}`;
  #|     try { message = JSON.parse(text)?.error?.message || message; } catch (_) {}
  #|     throw new Error(message);
  #|   }
  #|   return text;
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
  #|       const response = await fetch(url, {
  #|         method: "PUT",
  #|         headers: {
  #|           "Authorization": `Bearer ${sessionToken}`,
  #|           "Content-Type": file.type,
  #|         },
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
  #|   const response = await fetch(url, {
  #|     method: "GET",
  #|     headers: { "Authorization": `Bearer ${sessionToken}` },
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
async fn load_self(
  model : AppModel,
) -> (
  @portal.EnterpriseSelfView,
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
) {
  let body = request(
    "GET",
    model.endpoint,
    "/v1/portal/self",
    model.token,
    model.subject_ref,
  )
  let view : @portal.EnterpriseSelfView = @json.from_json(@json.parse(body))
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
    view, cost_centers, provisional_spend, models, notifications, notification_preferences,
    machines, orders, artifacts, contract_manifest, contract_packets,
  )
}

///|
async fn request_signature(
  model : AppModel,
  agreement_id : String,
) -> @portal.PortalAgreement {
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
      ) =>
        Loaded(
          view, cost_centers, provisional_spend, models, notifications, notification_preferences,
          machines, orders, artifacts, contract_manifest, contract_packets,
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
      value => AgreementUpdated(value)
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
fn contract_packet_command(
  model : AppModel,
  message : @contract_documents.ContractDocumentsMessage,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try {
      match message {
        RequestPreview(packet_id, revision, form, changes) =>
          contract_preview(model, packet_id, revision, form, changes)
          |> ContractPreviewLoaded
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
          ContractPreviewFailed(model.portal.locale, failure)
        } else {
          Failed(model.portal.locale, failure)
        }
      }
    }
  })
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
        ({ ..model, connecting: true }, load_command(model, emit))
      }
    Portal(LocaleChanged(locale)) => {
      apply_enterprise_locale(locale)
      (
        { ..model, portal: model.portal.update(LocaleChanged(locale)) },
        @rabbita.none,
      )
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
                  "Lease request submitted to the operator queue.",
                  "租用申请已提交至运维审核队列。",
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
        (
          {
            ..model,
            portal: {
              ..portal,
              machine_access: { ..portal.machine_access, loading: false },
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
        ({ ..model, portal, }, @rabbita.none)
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
    Portal(ContractDocuments(message)) if message is SaveInformation(_, _, _) ||
      message is RequestPreview(_, _, _, _) ||
      message is ConfirmAction(_) => {
      let next = model.portal.update(ContractDocuments(message))
      if model.demo_mode {
        match message {
          RequestPreview(packet_id, _, form, changes) =>
            (
              { ..model, portal: next },
              @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
                try
                  demo_contract_preview(model, packet_id, form, changes)
                catch {
                  error =>
                    ContractPreviewFailed(
                      model.portal.locale,
                      "MoonLeaf preview failed: \{Repr(error)}",
                    )
                } noraise {
                  preview => ContractPreviewLoaded(preview)
                }
              }),
            )
          _ => ({ ..model, portal: next }, @rabbita.none)
        }
      } else {
        (
          { ..model, portal: next },
          contract_packet_command(model, message, emit),
        )
      }
    }
    Outcome(ContractPreviewLoaded(preview)) =>
      (
        {
          ..model,
          portal: model.portal.update(ContractDocuments(PreviewLoaded(preview))),
        },
        @rabbita.none,
      )
    Outcome(ContractPreviewFailed(dispatched_locale, message)) =>
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
                    "MoonLeaf preview failed. Retry the preview.",
                    "MoonLeaf 预览失败。请重试预览。",
                  )
                },
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Portal(portal_message) =>
      ({ ..model, portal: model.portal.update(portal_message) }, @rabbita.none)
    Outcome(
      Loaded(
        view,
        cost_centers,
        provisional_spend,
        models,
        notifications,
        notification_preferences,
        machines,
        orders,
        artifacts,
        contract_manifest,
        contract_packets
      )
    ) => {
      let next = {
        ..model,
        connecting: false,
        machine_clock_generation: model.machine_clock_generation + 1L,
        portal: {
          ..model.portal,
          membership: Some(view.membership),
          agreements: view.agreements,
          lease_requests: view.lease_requests,
          cost_centers,
          provisional_spend,
          model_catalog: models,
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
      (next, machine_clock_command(next, emit))
    }
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
    Outcome(AgreementUpdated(agreement)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            agreements: replace_agreement(model.portal.agreements, agreement),
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
fn app_view(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Html {
  let ready = model.portal.membership is Some(_)
  let locale = model.portal.locale
  let connection_styles =
    #|.portal-connection{position:fixed;z-index:50;right:1rem;top:1rem;width:min(28rem,calc(100vw - 2rem));border:1px solid #2b4654;border-radius:.7rem;background:#0b1720;color:#edf7f3;box-shadow:0 20px 70px rgba(0,0,0,.45)}.portal-connection summary{min-height:44px;padding:.75rem 1rem;cursor:pointer;font-weight:800}.portal-connection-body{display:grid;gap:.65rem;padding:0 1rem 1rem}.portal-connection label{display:block;margin-bottom:.25rem;color:#9db0b6;font-size:.7rem}.portal-connection input{width:100%;min-height:44px;padding:.55rem .65rem;border:1px solid #35505f;border-radius:.45rem;background:#071218;color:#edf7f3}.portal-connection button{min-height:44px;border:1px solid #35bd8d;border-radius:.45rem;background:#7ee0bd;color:#06251a;font-weight:850}.portal-connection p{margin:0;color:#91a7ad;font-size:.7rem}.demo-flag{position:fixed;z-index:45;right:1rem;top:1rem;padding:.45rem .65rem;border:1px solid rgba(126,224,189,.3);border-radius:999px;background:#0b1720;color:#7ee0bd;font:800 .65rem/1 system-ui}@media(max-width:52rem){.portal-connection{position:relative;inset:auto;margin:1rem;width:calc(100% - 2rem);box-shadow:0 12px 36px rgba(0,0,0,.28)}.demo-flag{position:relative;inset:auto;display:inline-flex;margin:1rem 1rem 0}}
  @html.div([
    @html.style_tag(connection_styles),
    if model.demo_mode {
      @html.div(
        class="demo-flag",
        portal_copy(
          locale, "DEMO · enterprise portal", "演示 · 企业门户",
        ),
      )
    } else {
      @html.details(
        class="portal-connection",
        open=!ready,
        attrs=@html.Attrs::build().aria_label(
          portal_copy(locale, "Enterprise connection", "企业门户连接"),
        ),
        [
          @html.summary(
            if ready {
              portal_copy(
                locale, "Enterprise connection ready", "企业连接就绪",
              )
            } else {
              portal_copy(
                locale, "Connect enterprise identity", "连接企业身份",
              )
            },
          ),
          @html.div(class="portal-connection-body", [
            @html.div([
              @html.label(
                for_="portal-token",
                portal_copy(
                  locale, "Scoped inference token", "限定范围的推理令牌",
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
                  locale, "Opaque subject (loopback acceptance only)", "不透明主体引用（仅限环回验收）",
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
              disabled=model.connecting || model.token == "",
              on_click=emit(Connect),
              if model.connecting {
                portal_copy(locale, "Connecting…", "正在连接…")
              } else {
                portal_copy(locale, "Connect / refresh", "连接 / 刷新")
              },
            ),
            @html.p(
              portal_copy(
                locale, "Credentials remain in this page's browser memory and are never sent to a managed GPU node.",
                "凭据仅保留在此页面的浏览器内存中，绝不会发送到受管 GPU 节点。",
              ),
            ),
          ]),
        ],
      )
    },
    @enterprise_ui.interactive_view(
      model.portal,
      emit.map(message => Portal(message)),
    ),
  ])
}

///|
fn main {
  let is_demo = demo_mode()
  let initial_locale = @i18n.parse_locale(stored_locale_preference())
  apply_enterprise_locale(initial_locale)
  @rabbita.elmish(
    model={
      endpoint: configured_endpoint(),
      token: "",
      subject_ref: "",
      connecting: false,
      demo_mode: is_demo,
      machine_clock_generation: 0L,
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
  ).mount("app")
}
