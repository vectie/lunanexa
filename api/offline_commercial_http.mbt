///|
fn offline_commerce_path(path : String) -> Bool {
  path == "/v1/offline-commerce" || path.has_prefix("/v1/offline-commerce/")
}

///|
priv struct OfflineOrderIntent {
  order_id : String
  idempotency_key : String
  project_id : String
  selected_service_code : String
  selected_sla_code : String
  expires_unix_ms : Int64
} derive(FromJson)

///| Conservative interim policy. Customer requests cannot weaken commercial,

///|
/// identity, finance, or internal-approval controls.
fn hybrid_offline_policy() -> @offline.FulfillmentPolicy {
  {
    require_executed_agreement: true,
    require_payment: true,
    invoice_timing: InvoiceBeforeFulfillment,
    require_identity_verification: true,
    require_internal_approval: true,
  }
}

///|
priv struct OfflineQuoteAction {
  order_id : String
  quote : @offline.ImmutableQuote
} derive(FromJson)

///|
priv struct OfflineGenerationResultAction {
  result : @offline.ArtifactGenerationResult
} derive(FromJson)

///|
priv struct OfflineOrderAction {
  order_id : String
  expected_generation : Int64
} derive(FromJson)

///|
priv struct OfflineFulfillmentAction {
  order_id : String
  expected_generation : Int64
  activation_id : String
  idempotency_key : String
  entitlement_kind : @offline.EntitlementKind
  authority_target_ref : String
} derive(FromJson)

///|
priv struct OfflineReversalAction {
  reversal_id : String
  idempotency_key : String
  order_id : String
  expected_generation : Int64
  reason : @offline.CommercialReversalReason
} derive(FromJson)

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
} derive(FromJson)

///|
priv struct OfflineReadinessGateError {
  code : String
  message : String
  blocker_codes : Array[String]
  retryable : Bool
} derive(ToJson)

///|
extend OfflineReadinessGateError with ToJson::{to_json}

///|
fn readiness_blocker(capability : @offline.OfflineCommerceCapability) -> String {
  match capability {
    ApprovedLegalTemplates => "ApprovedLegalTemplatesPending"
    ObjectStorage => "ObjectStoragePending"
    MalwareScanner => "MalwareScannerPending"
    OoxmlWorker => "OoxmlWorkerPending"
    PdfRenderer => "MoonLeafPdfRendererPending"
    SpreadsheetFormulaEngine => "SpreadsheetFormulaEnginePending"
    CjkFonts => "CjkFontsPending"
    MachineCallbackIdentity => "MachineCallbackIdentityPending"
    EntitlementAuthority => "EntitlementAuthorityPending"
    FinanceLegalPolicy => "FinanceLegalPolicyPending"
  }
}

///| Re-evaluates the signed evidence window on every projection and mutation;

///|
/// a long-running process cannot remain ready after its retained proof expires.
async fn ApiService::offline_readiness(
  self : ApiService,
  now_unix_ms : Int64,
) -> @offline.OfflineCommerceReadiness {
  let readiness = @offline.offline_commerce_readiness(
    self.offline_commerce_capabilities,
    now_unix_ms,
  )
  let blockers = readiness.blocker_codes.copy()
  if self.offline_commerce_capabilities_expires_unix_ms <= now_unix_ms {
    blockers.push("ReadinessEvidenceExpired")
  }
  if self.artifact_worker_callback_token is None {
    blockers.push("ReadinessArtifactWorkerCallbackUnavailable")
  }
  if self.artifact_scanner_callback_token is None {
    blockers.push("ReadinessArtifactScannerCallbackUnavailable")
  }
  if self.entitlement_authority_callback_token is None {
    blockers.push("ReadinessEntitlementAuthorityCallbackUnavailable")
  }
  if self.offline_transfer_adapter_endpoint is None ||
    self.offline_transfer_adapter_token is None ||
    self.offline_transfer_session_secret.length() < 32 {
    blockers.push("ReadinessTransferAdapterUnavailable")
  }
  match self.offline_commerce_store {
    Some(store) =>
      for blocker in store.worker_readiness_blockers(now_unix_ms) {
        blockers.push(blocker)
      }
    None => blockers.push("ReadinessOfflineStoreUnavailable")
  }
  {
    ..readiness,
    status: if blockers.length() == 0 {
      OfflineCommerceReady
    } else {
      OfflineCommerceAdaptersPending
    },
    blocker_codes: blockers,
  }
}

///| Returns a typed fail-closed 503 for a side effect whose externally verified

///|
/// adapters are unavailable or whose evidence set is ambiguous.
async fn ApiService::offline_readiness_gate(
  self : ApiService,
  required : Array[@offline.OfflineCommerceCapability],
  now_unix_ms : Int64,
) -> HttpReply? {
  let readiness = self.offline_readiness(now_unix_ms)
  let blockers = readiness.blocker_codes.filter(code => {
    code.has_prefix("Readiness") ||
    required.any(capability => readiness_blocker(capability) == code)
  })
  if blockers.length() == 0 {
    None
  } else {
    let error : OfflineReadinessGateError = {
      code: "OfflineCommerceNotReady",
      message: "verified offline-commerce deployment capabilities are required",
      blocker_codes: blockers,
      retryable: true,
    }
    Some(json_reply(503, error.to_json()))
  }
}

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
} derive(FromJson)

///|
priv struct SelfDownloadIntent {
  session_id : String
  idempotency_key : String
} derive(FromJson)

///| Trusted server-to-server intent. Object routing never crosses to the

///|
/// browser, and the adapter receives only the digest of the one-time token.
priv struct OfflineTransferAdapterIntent {
  session_id : String
  idempotency_key : String
  direction : @offline.OfflineTransferDirection
  object_ref : String
  session_token_sha256 : String
  media_types : Array[String]
  maximum_byte_count : Int64
  expected_sha256 : String?
  expires_unix_ms : Int64
} derive(ToJson)

///|
extend OfflineTransferAdapterIntent with ToJson::{to_json}

///|
priv struct OfflineTransferAdapterReceipt {
  session_id : String
  transfer_url : String
  expires_unix_ms : Int64
  provider_receipt : String
} derive(FromJson)

///|
priv struct OfflineTransferCompletion {
  session_id : String
  session_token : String
  media_type : String
  byte_count : Int64
  sha256 : String
  provider_receipt : String
} derive(FromJson)

///|
pub(all) struct OfflineUploadTransferView {
  evidence : @offline.OfflineUploadGrantView
  transfer : @offline.OfflineTransferGrant
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OfflineArtifactView {
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
} derive(Debug, Eq, ToJson, FromJson)

///|
fn @offline.DocumentArtifact::public_view(
  self : @offline.DocumentArtifact,
) -> OfflineArtifactView {
  {
    artifact_id: self.artifact_id,
    order_id: self.order_id,
    kind: self.kind,
    revision: self.revision,
    locale: self.locale,
    media_type: self.media_type,
    byte_count: self.byte_count,
    sha256: self.sha256,
    generation_state: self.generation_state,
    scan_state: self.scan_state,
    review_state: self.review_state,
    created_unix_ms: self.created_unix_ms,
  }
}

///|
fn @offline.EvidenceUploadGrant::public_view(
  self : @offline.EvidenceUploadGrant,
) -> @offline.OfflineUploadGrantView {
  {
    grant_id: self.grant_id,
    order_id: self.order_id,
    artifact_id: self.artifact_id,
    kind: self.kind,
    revision: self.revision,
    allowed_media_types: self.allowed_media_types,
    maximum_byte_count: self.maximum_byte_count,
    expires_unix_ms: self.expires_unix_ms,
    state: self.state,
    created_unix_ms: self.created_unix_ms,
  }
}

///|
fn[T : FromJson] decode_offline(body : String) -> T? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn offline_transfer_token(
  secret : String,
  session_id : String,
  idempotency_key : String,
  subject_ref : String,
) -> String {
  let material = @utf8.encode(
    "lunanexa.offline-transfer.v1\n\{session_id}\n\{idempotency_key}\n\{subject_ref}",
  )
  "lnxot_\{@crypto.bytes_to_hex_string(@crypto.hmac(@crypto.SHA256::new(), @utf8.encode(secret).view(), material.view()))}"
}

///|
fn offline_transfer_token_sha256(token : String) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(token)))}"
}

///| Adapter grants are accepted only under the configured adapter origin and

///| path namespace. Redirects and arbitrary provider URLs are not delegated

///|
/// to an authenticated browser.
fn safe_offline_transfer_url(endpoint : String, url : String) -> Bool {
  url.length() <= 1024 &&
  url.has_prefix("\{endpoint}/") &&
  !url.contains("?") &&
  !url.contains("#") &&
  !url.contains("\\") &&
  !url.any(character => character.is_whitespace())
}

///|
async fn request_offline_transfer_adapter(
  endpoint : String,
  adapter_token : String,
  intent : OfflineTransferAdapterIntent,
) -> OfflineTransferAdapterReceipt {
  let stream = @http.post_stream(endpoint, headers={
    "Authorization": "Bearer \{adapter_token}",
    "Content-Type": "application/json",
    "Accept": "application/json",
    "Idempotency-Key": intent.idempotency_key,
  })
  defer stream.close()
  stream.write(intent.to_json())
  let head = stream.end_request()
  if head.code >= 300 && head.code < 400 {
    raise Failure::Failure("offline transfer adapter redirect rejected")
  }
  if head.code < 200 || head.code >= 300 {
    raise Failure::Failure("offline transfer adapter rejected intent")
  }
  let content_type = head.headers
    .iter()
    .find_first(entry => entry.0.to_lower() == "content-type")
    .map(entry => entry.1.to_lower())
  if !content_type.map_or(false, value => value.has_prefix("application/json")) {
    raise Failure::Failure("offline transfer adapter response type rejected")
  }
  let buffer = @buffer.Buffer(size_hint=4096)
  for total = 0 {
    match stream.read_some(max_len=(4097 - total).min(4096)) {
      None => break
      Some(chunk) => {
        let next = total + chunk.length()
        if next > 4096 {
          raise Failure::Failure("offline transfer adapter response too large")
        }
        buffer.write_bytes(chunk)
        continue next
      }
    }
  }
  @json.from_json(@json.parse(@utf8.decode(buffer.to_bytes())))
}

///|
async fn ApiService::issue_offline_transfer(
  self : ApiService,
  store : @offline_store.OfflineCommerceStore,
  session_id : String,
  idempotency_key : String,
  organization_id : String,
  subject_ref : String,
  order_id : String,
  artifact_id : String,
  direction : @offline.OfflineTransferDirection,
  object_ref : String,
  media_types : Array[String],
  maximum_byte_count : Int64,
  expected_sha256 : String?,
  issued_unix_ms : Int64,
  expires_unix_ms : Int64,
) -> @offline.OfflineTransferGrant {
  guard self.offline_transfer_adapter_endpoint is Some(endpoint) &&
    self.offline_transfer_adapter_token is Some(adapter_token) &&
    self.offline_transfer_session_secret.length() >= 32 else {
    raise Failure::Failure("offline transfer adapter unavailable")
  }
  let existing : @offline.OfflineTransferSession? = Some(
    store.transfer_session(organization_id, subject_ref, session_id),
  ) catch {
    @offline.OfflineCommerceError::NotFound(_) => None
    error => raise error
  }
  if existing is Some(value) &&
    (
      value.idempotency_key != idempotency_key ||
      value.order_id != order_id ||
      value.artifact_id != artifact_id ||
      value.direction != direction ||
      value.media_types != media_types ||
      value.maximum_byte_count != maximum_byte_count ||
      value.expected_sha256 != expected_sha256 ||
      value.state != TransferIssued
    ) {
    raise @offline.OfflineCommerceError::IdempotencyConflict(session_id)
  }
  let effective_issued_unix_ms = existing
    .map(value => value.issued_unix_ms)
    .unwrap_or(issued_unix_ms)
  let effective_expires_unix_ms = existing
    .map(value => value.expires_unix_ms)
    .unwrap_or(expires_unix_ms)
  let token = offline_transfer_token(
    self.offline_transfer_session_secret,
    session_id,
    idempotency_key,
    subject_ref,
  )
  let session : @offline.OfflineTransferSession = {
    session_id,
    idempotency_key,
    session_token_sha256: offline_transfer_token_sha256(token),
    organization_id,
    subject_ref,
    order_id,
    artifact_id,
    direction,
    media_types,
    maximum_byte_count,
    expected_sha256,
    state: TransferIssued,
    issued_unix_ms: effective_issued_unix_ms,
    expires_unix_ms: effective_expires_unix_ms,
    consumed_unix_ms: None,
  }
  // Persist authority before asking an external adapter to accept it. An
  // adapter timeout can be retried idempotently without creating an untracked
  // browser credential.
  ignore(store.issue_transfer_session(session))
  let receipt = @async.with_timeout(5000, () => {
    request_offline_transfer_adapter(endpoint, adapter_token, {
      session_id,
      idempotency_key,
      direction,
      object_ref,
      session_token_sha256: session.session_token_sha256,
      media_types,
      maximum_byte_count,
      expected_sha256,
      expires_unix_ms: effective_expires_unix_ms,
    })
  })
  if receipt.session_id != session_id ||
    receipt.expires_unix_ms != effective_expires_unix_ms ||
    !safe_offline_transfer_url(endpoint, receipt.transfer_url) ||
    !@contracts.valid_identifier(receipt.provider_receipt, maximum_length=512) {
    raise Failure::Failure("offline transfer adapter receipt rejected")
  }
  {
    session_id,
    transfer_path: receipt.transfer_url,
    session_token: token,
    direction,
    media_types,
    maximum_byte_count,
    expected_sha256,
    expires_unix_ms: effective_expires_unix_ms,
  }
}

///|
fn offline_error_reply(error : Error) -> HttpReply {
  match error {
    @offline.OfflineCommerceError::TenantMismatch
    | @offline.OfflineCommerceError::Unauthorized =>
      api_error(
        403, "OfflineCommerceDenied", "commercial record is outside the caller authority",
        false,
      )
    @offline.OfflineCommerceError::NotFound(_) =>
      api_error(
        404, "NotFound", "offline commercial record was not found", false,
      )
    @offline.OfflineCommerceError::AlreadyExists(_)
    | @offline.OfflineCommerceError::IdempotencyConflict(_) =>
      api_error(
        409, "IdempotencyConflict", "idempotency key identifies different commercial data",
        false,
      )
    @offline.OfflineCommerceError::StaleGeneration =>
      api_error(
        409, "StaleGeneration", "commercial order changed; refresh before retrying",
        true,
      )
    @offline.OfflineCommerceError::SeparationOfDuties =>
      api_error(
        409, "SeparationOfDuties", "evidence submitter cannot review the same artifact",
        false,
      )
    @offline.OfflineCommerceError::EvidenceMissing(_) =>
      api_error(
        409, "EvidenceMissing", "fulfillment policy still has unverified prerequisites",
        false,
      )
    @offline.OfflineCommerceError::ArtifactUnavailable(_) =>
      api_error(
        409, "ArtifactUnavailable", "document artifact is not verified and releasable",
        false,
      )
    @offline.OfflineCommerceError::InvalidTransition(_) =>
      api_error(
        409, "InvalidTransition", "commercial order is not in the required state",
        false,
      )
    _ =>
      api_error(
        400, "OfflineCommerceRejected", "offline commercial request was rejected",
        false,
      )
  }
}

///|
fn offline_operator_audit_action(path : String) -> String {
  if path.contains("templates") {
    "offline.template.register"
  } else if path.contains("quotes") {
    "offline.order.quote"
  } else if path.contains("generation-results") {
    "offline.artifact.generate.complete"
  } else if path.contains("generation-requests") {
    "offline.artifact.generate.request"
  } else if path.contains("upload-callbacks") {
    "offline.artifact.upload.complete"
  } else if path.contains("reviews") {
    "offline.evidence.review"
  } else if path.contains("fulfillments") {
    "offline.order.fulfill"
  } else {
    "offline.order.transition"
  }
}

///|
fn offline_operator_actor(headers : Map[String, String]) -> String {
  trusted_workspace_subject(headers, false).unwrap_or("platform-operator")
}

///|
fn offline_state_label(state : @offline.OfflineOrderState) -> String {
  match state {
    Draft => "Draft"
    Quoted => "Quoted"
    PendingInternalApproval => "PendingInternalApproval"
    PendingOfflineExecution => "PendingOfflineExecution"
    PendingEvidenceUpload => "PendingEvidenceUpload"
    UnderReconciliation => "UnderReconciliation"
    FulfillmentPending => "FulfillmentPending"
    Fulfilled => "Fulfilled"
    ReversalPending => "ReversalPending"
    ReversalManualIntervention => "ReversalManualIntervention"
    Revoked => "Revoked"
    NeedsCorrection => "NeedsCorrection"
    Rejected => "Rejected"
    Cancelled => "Cancelled"
    Expired => "Expired"
  }
}

///| Rebuilds customer commercial notifications from durable order state. This

///| makes notification delivery restart-safe without storing an inconsistent

///|
/// second copy of commercial state.
async fn ApiService::refresh_offline_commerce_notifications(
  self : ApiService,
  now_unix_ms : Int64,
) -> Unit {
  guard self.offline_commerce_store is Some(commerce) else { return }
  for order in commerce.snapshot().orders {
    let notice = match order.state {
      Quoted =>
        Some(
          (
            "QuoteReady",
            @notifications.NotificationTopic::CommercialAction,
            @notifications.NotificationSeverity::Information,
          ),
        )
      PendingEvidenceUpload =>
        Some(("OfflinePacketReady", CommercialAction, Information))
      UnderReconciliation =>
        Some(("EvidenceUnderReconciliation", Reconciliation, Information))
      NeedsCorrection =>
        Some(("EvidenceCorrectionRequired", Reconciliation, Warning))
      Fulfilled =>
        Some(("OfflineOrderFulfilled", CommercialAction, Information))
      FulfillmentPending =>
        Some(("EntitlementActivationPending", Reconciliation, Information))
      ReversalPending =>
        Some(("EntitlementRevocationPending", Reconciliation, Warning))
      ReversalManualIntervention =>
        Some(
          ("EntitlementReversalManualIntervention", Reconciliation, Critical),
        )
      Revoked => Some(("OfflineOrderRevoked", CommercialAction, Warning))
      Cancelled => Some(("OfflineOrderCancelled", CommercialAction, Warning))
      Expired => Some(("OfflineOrderExpired", CommercialAction, Warning))
      _ => None
    }
    if notice is Some((code, topic, severity)) {
      let state = offline_state_label(order.state)
      self.enqueue_subject_notification(
        order.tenant_ref,
        order.purchaser_subject_ref,
        code,
        topic,
        severity,
        "\{order.order_id}-\{state}-\{order.generation}",
        "offline-order:\{order.order_id}:\{state}:\{order.generation}",
        { "order_ref": order.order_id, "state": state },
        now_unix_ms,
      )
    }
  }
}

///| Runs the clock-driven commerce pass without any browser request. Expiry,

///| compensation state, notices and low-cardinality operational evidence move

///|
/// together from the controller's perspective.
async fn ApiService::reconcile_offline_commerce_pass(
  self : ApiService,
  now_unix_ms : Int64,
) -> Unit {
  guard self.offline_commerce_store is Some(store) else { return }
  let started = @async.now()
  let changed = store.expire_orders(now_unix_ms)
  let expired_transfers = store.expire_transfer_sessions(now_unix_ms)
  self.refresh_offline_commerce_notifications(now_unix_ms)
  let snapshot = store.snapshot()
  let overdue = snapshot.orders.filter(order => {
    (order.state == FulfillmentPending || order.state == ReversalPending) &&
    order.updated_unix_ms + 300000L <= now_unix_ms
  })
  for order in overdue {
    self.alert_offline_callback_failure(
      if order.state == FulfillmentPending {
        "OfflineEntitlementActivationOverdue"
      } else {
        "OfflineEntitlementReversalOverdue"
      },
      order.order_id,
      now_unix_ms,
    )
  }
  self.record_component_event(
    "event-offline-commerce-reconcile-\{now_unix_ms}",
    now_unix_ms,
    if overdue.length() > 0 {
      Warning
    } else {
      Information
    },
    "controller",
    "OfflineCommerceReconciliationCompleted",
    "offline-commerce-reconcile-\{now_unix_ms}",
    "commercial",
    if overdue.length() > 0 {
      "degraded"
    } else {
      "healthy"
    },
    if overdue.length() > 0 {
      503
    } else {
      200
    },
    (@async.now() - started).max(0L),
  )
  ignore(changed)
  ignore(expired_transfers)
}

///| Durable attempt/success evidence makes scheduler failure visible to

///| readiness. A failed pass is recorded best-effort and always propagates;

///|
/// the controller must not keep serving as if expiry/compensation were live.
pub async fn ApiService::reconcile_offline_commerce(
  self : ApiService,
  now_unix_ms : Int64,
) -> Unit {
  guard self.offline_commerce_store is Some(store) else { return }
  store.record_reconciler_attempt(now_unix_ms)
  try {
    self.reconcile_offline_commerce_pass(now_unix_ms)
    store.record_reconciler_success(@async.now())
  } catch {
    error => {
      ignore(store.record_reconciler_failure("OfflineReconcileFailed")) catch {
        _ => ()
      }
      raise error
    }
  }
}

///|
async fn ApiService::alert_offline_callback_failure(
  self : ApiService,
  code : String,
  resource_ref : String,
  now_unix_ms : Int64,
) -> Unit {
  guard self.notification_store is Some(notifications) else { return }
  let safe_ref = if @contracts.valid_identifier(resource_ref) {
    resource_ref
  } else {
    "invalid-\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(resource_ref)))[:24]}"
  }
  let deduplication_key = "offline-callback-\{code}-\{safe_ref}"
  if notifications.record_by_deduplication_key(
      deduplication_key,
      PlatformOperators,
    )
    is Some(_) {
    return
  }
  ignore(
    notifications.enqueue({
      version: @notifications.contract_version,
      notification_id: "alert-\{code}-\{safe_ref}",
      deduplication_key,
      source_receipt: "offline-callback:\{code}:\{safe_ref}",
      topic: ArtifactHealth,
      code,
      severity: Critical,
      audience: PlatformOperators,
      title_key: "alerts.\{code}.title",
      body_key: "alerts.\{code}.body",
      parameters: { "resource_ref": safe_ref },
      created_unix_ms: now_unix_ms,
      expires_unix_ms: None,
    }),
  )
}

///|
async fn ApiService::handle_offline_commerce(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.offline_commerce_store is Some(store) else {
    return api_error(
      503, "OfflineCommerceUnavailable", "durable offline commercial authority is unavailable",
      true,
    )
  }
  // Clock reconciliation is controller-owned and does not trust browser time.
  // Every commerce request performs the same idempotent pass; the controller
  // also invokes this store operation from its periodic reconciler.
  let request_now = @async.now()
  ignore(store.expire_orders(request_now))
  ignore(store.expire_transfer_sessions(request_now))
  if path == "/v1/offline-commerce/operator/generation-results" {
    // Readiness gates initiation only. Results for already-issued work remain
    // reconcilable after deployment evidence expires.
    guard self.artifact_worker_callback_token is Some(token) else {
      return api_error(
        503, "ArtifactWorkerCallbackUnavailable", "artifact-worker callback authority is not configured",
        true,
      )
    }
    if verb != Post || !bearer_authorized(headers, token) {
      return api_error(
        401, "Unauthenticated", "valid artifact-worker callback authority is required",
        false,
      )
    }
    let decoded : OfflineGenerationResultAction? = decode_offline(body)
    guard decoded is Some(action) else {
      return api_error(
        400, "InvalidRequest", "invalid verified generation result", false,
      )
    }
    let reply = try
      json_reply(201, store.complete_generation(action.result).to_json())
    catch {
      error => offline_error_reply(error)
    } noraise {
      value => value
    }
    if reply.status >= 200 && reply.status < 300 {
      self.operator_audit(
        "offline.artifact.generate.complete",
        action.result.artifact_id,
        action.result.worker_receipt,
      )
      self.refresh_offline_commerce_notifications(@async.now())
    } else {
      self.alert_offline_callback_failure(
        "OfflineGenerationCallbackRejected",
        action.result.artifact_id,
        @async.now(),
      )
    }
    return reply
  }
  if path == "/v1/offline-commerce/operator/upload-callbacks" {
    guard self.artifact_scanner_callback_token is Some(token) else {
      return api_error(
        503, "ArtifactScannerCallbackUnavailable", "artifact-scanner callback authority is not configured",
        true,
      )
    }
    if verb != Post || !bearer_authorized(headers, token) {
      return api_error(
        401, "Unauthenticated", "valid artifact-scanner callback authority is required",
        false,
      )
    }
    let decoded : @offline.EvidenceUploadCallback? = decode_offline(body)
    guard decoded is Some(callback) else {
      return api_error(
        400, "InvalidRequest", "invalid verified upload callback", false,
      )
    }
    let reply = try
      json_reply(201, store.complete_upload(callback).to_json())
    catch {
      error => offline_error_reply(error)
    } noraise {
      value => value
    }
    if reply.status >= 200 && reply.status < 300 {
      self.operator_audit(
        "offline.artifact.upload.complete",
        callback.grant_id,
        callback.scanner_receipt,
      )
      self.refresh_offline_commerce_notifications(@async.now())
    } else {
      self.alert_offline_callback_failure(
        "OfflineScannerCallbackRejected",
        callback.grant_id,
        @async.now(),
      )
    }
    return reply
  }
  if path == "/v1/offline-commerce/operator/entitlement-activation-results" {
    guard self.entitlement_authority_callback_token is Some(token) else {
      return api_error(
        503, "EntitlementAuthorityUnavailable", "entitlement-authority callback identity is not configured",
        true,
      )
    }
    if verb != Post || !bearer_authorized(headers, token) {
      return api_error(
        401, "Unauthenticated", "valid entitlement-authority callback identity is required",
        false,
      )
    }
    let decoded : @offline.EntitlementActivation? = decode_offline(body)
    guard decoded is Some(result) else {
      return api_error(
        400, "InvalidRequest", "invalid entitlement activation result", false,
      )
    }
    guard result.authority_receipt is Some(receipt) &&
      (
        result.state == EntitlementActivationConfirmed ||
        result.state == EntitlementActivationRejected
      ) &&
      (
        result.state != EntitlementActivationConfirmed ||
        result.entitlement_ref is Some(_)
      ) &&
      (
        result.state != EntitlementActivationRejected ||
        result.reason_code is Some(_)
      ) else {
      return api_error(
        400, "InvalidAuthorityResult", "terminal activation state and authority evidence are required",
        false,
      )
    }
    let completed = { ..result, completed_unix_ms: Some(@async.now()) }
    let reply = try
      json_reply(200, store.complete_activation(completed).to_json())
    catch {
      error => offline_error_reply(error)
    } noraise {
      value => value
    }
    if reply.status >= 200 && reply.status < 300 {
      self.operator_audit(
        "offline.entitlement.activation.complete",
        completed.activation_id,
        receipt,
      )
      self.refresh_offline_commerce_notifications(@async.now())
    } else {
      self.alert_offline_callback_failure(
        "OfflineEntitlementActivationRejected",
        completed.activation_id,
        @async.now(),
      )
    }
    return reply
  }
  if path == "/v1/offline-commerce/operator/entitlement-reversal-results" {
    guard self.entitlement_authority_callback_token is Some(token) else {
      return api_error(
        503, "EntitlementAuthorityUnavailable", "entitlement-authority callback identity is not configured",
        true,
      )
    }
    if verb != Post || !bearer_authorized(headers, token) {
      return api_error(
        401, "Unauthenticated", "valid entitlement-authority callback identity is required",
        false,
      )
    }
    let decoded : @offline.CommercialReversal? = decode_offline(body)
    guard decoded is Some(result) else {
      return api_error(
        400, "InvalidRequest", "invalid entitlement reversal result", false,
      )
    }
    guard result.authority_receipt is Some(receipt) &&
      (result.state == ReversalConfirmed || result.state == ReversalFailed) &&
      (result.state != ReversalFailed || result.reason_code is Some(_)) else {
      return api_error(
        400, "InvalidAuthorityResult", "terminal reversal state and authority evidence are required",
        false,
      )
    }
    let completed = { ..result, completed_unix_ms: Some(@async.now()) }
    let reply = try
      json_reply(200, store.complete_reversal(completed).to_json())
    catch {
      error => offline_error_reply(error)
    } noraise {
      value => value
    }
    if reply.status >= 200 && reply.status < 300 {
      self.operator_audit(
        "offline.entitlement.reversal.complete",
        completed.reversal_id,
        receipt,
      )
      self.refresh_offline_commerce_notifications(@async.now())
    } else {
      self.alert_offline_callback_failure(
        "OfflineEntitlementReversalRejected",
        completed.reversal_id,
        @async.now(),
      )
    }
    return reply
  }
  if path == "/v1/offline-commerce/operator/transfer-results" {
    guard self.offline_transfer_adapter_token is Some(token) else {
      return api_error(
        503, "OfflineTransferAdapterUnavailable", "transfer adapter authority is not configured",
        true,
      )
    }
    if verb != Post || !bearer_authorized(headers, token) {
      return api_error(
        401, "Unauthenticated", "valid transfer adapter authority is required", false,
      )
    }
    let decoded : OfflineTransferCompletion? = decode_offline(body)
    guard decoded is Some(completion) &&
      completion.session_token.length() <= 256 else {
      return api_error(
        400, "InvalidRequest", "invalid transfer completion", false,
      )
    }
    let completed = try
      store.consume_transfer_session(
        completion.session_id,
        offline_transfer_token_sha256(completion.session_token),
        completion.media_type,
        completion.byte_count,
        completion.sha256,
        completion.provider_receipt,
        @async.now(),
      )
    catch {
      error => return offline_error_reply(error)
    } noraise {
      value => value
    }
    self.operator_audit(
      "offline.artifact.transfer.complete",
      completed.session_id,
      "offline-transfer:\{completed.session_id}",
    )
    return json_reply(200, completed.to_json())
  }
  if path == "/v1/offline-commerce/operator/generation-requests/pending" {
    guard self.artifact_worker_callback_token is Some(token) else {
      return api_error(
        503, "ArtifactPipelineUnavailable", "artifact dispatcher identity is not configured",
        true,
      )
    }
    if verb != Get || !bearer_authorized(headers, token) {
      return api_error(
        401, "Unauthenticated", "valid artifact dispatcher identity is required",
        false,
      )
    }
    return json_reply(
      200,
      store.claim_generation_requests(@async.now()).to_json(),
    )
  }
  if path == "/v1/offline-commerce/operator/entitlement-work/pending" {
    guard self.entitlement_authority_callback_token is Some(token) else {
      return api_error(
        503, "EntitlementAuthorityUnavailable", "entitlement dispatcher identity is not configured",
        true,
      )
    }
    if verb != Get || !bearer_authorized(headers, token) {
      return api_error(
        401, "Unauthenticated", "valid entitlement dispatcher identity is required",
        false,
      )
    }
    return json_reply(200, store.claim_authority_work(@async.now()).to_json())
  }
  if path.has_prefix("/v1/offline-commerce/operator/") {
    if !self.operator_authorized(headers) {
      return api_error(
        401, "Unauthenticated", "valid operator authority is required", false,
      )
    }
    let actor_ref = offline_operator_actor(headers)
    let server_now = @async.now()
    let reply = try {
      match (verb, path) {
        (Get, "/v1/offline-commerce/operator/snapshot") =>
          json_reply(200, store.snapshot().to_json())
        (Get, "/v1/offline-commerce/operator/readiness") =>
          json_reply(200, self.offline_readiness(server_now).to_json())
        (Post, "/v1/offline-commerce/operator/templates") => {
          let decoded : @offline.DocumentTemplate? = decode_offline(body)
          guard decoded is Some(template) else {
            return api_error(
              400, "InvalidRequest", "invalid immutable document template", false,
            )
          }
          json_reply(201, store.register_template(template).to_json())
        }
        (Post, "/v1/offline-commerce/operator/quotes") => {
          guard self.offline_readiness_gate(
              [ApprovedLegalTemplates, FinanceLegalPolicy],
              server_now,
            )
            is None else {
            return self
              .offline_readiness_gate(
                [ApprovedLegalTemplates, FinanceLegalPolicy],
                server_now,
              )
              .unwrap()
          }
          let decoded : OfflineQuoteAction? = decode_offline(body)
          guard decoded is Some(action) else {
            return api_error(
              400, "InvalidRequest", "invalid quote action", false,
            )
          }
          json_reply(
            200,
            store
            .quote_order(action.order_id, action.quote, actor_ref, server_now)
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/begin") => {
          guard self.offline_readiness_gate(
              [ApprovedLegalTemplates, FinanceLegalPolicy],
              server_now,
            )
            is None else {
            return self
              .offline_readiness_gate(
                [ApprovedLegalTemplates, FinanceLegalPolicy],
                server_now,
              )
              .unwrap()
          }
          let decoded : OfflineOrderAction? = decode_offline(body)
          guard decoded is Some(action) else {
            return api_error(
              400, "InvalidRequest", "invalid order transition", false,
            )
          }
          json_reply(
            200,
            store
            .begin_offline_execution(
              action.order_id,
              action.expected_generation,
              server_now,
            )
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/generation-requests") => {
          let decoded : @offline.ArtifactGenerationRequest? = decode_offline(
            body,
          )
          guard decoded is Some(request) else {
            return api_error(
              400, "InvalidRequest", "invalid document generation request", false,
            )
          }
          let required : Array[@offline.OfflineCommerceCapability] = match
            request.kind {
            EditableContractDocx => [OoxmlWorker, CjkFonts]
            QuoteScheduleXlsx =>
              [OoxmlWorker, SpreadsheetFormulaEngine, CjkFonts]
            PrintReadyContractPdf => [OoxmlWorker, PdfRenderer, CjkFonts]
            _ => [OoxmlWorker]
          }
          guard self.offline_readiness_gate(required, server_now) is None else {
            return self.offline_readiness_gate(required, server_now).unwrap()
          }
          json_reply(
            202,
            store
            .request_generation({
              ..request,
              requested_by: actor_ref,
              requested_unix_ms: server_now,
            })
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/release-packets") => {
          guard self.offline_readiness_gate(
              [OoxmlWorker, PdfRenderer, SpreadsheetFormulaEngine, CjkFonts],
              server_now,
            )
            is None else {
            return self
              .offline_readiness_gate(
                [OoxmlWorker, PdfRenderer, SpreadsheetFormulaEngine, CjkFonts],
                server_now,
              )
              .unwrap()
          }
          let decoded : OfflineOrderAction? = decode_offline(body)
          guard decoded is Some(action) else {
            return api_error(
              400, "InvalidRequest", "invalid release packet action", false,
            )
          }
          json_reply(
            200,
            store
            .release_offline_packet(
              action.order_id,
              action.expected_generation,
              server_now,
            )
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/reviews") => {
          let decoded : @offline.EvidenceReview? = decode_offline(body)
          guard decoded is Some(review) else {
            return api_error(
              400, "InvalidRequest", "invalid evidence review", false,
            )
          }
          json_reply(
            200,
            store
            .review_evidence({
              ..review,
              reviewer_ref: actor_ref,
              reviewed_unix_ms: server_now,
            })
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/fulfillments") => {
          guard self.offline_readiness_gate(
              [
                EntitlementAuthority,
                FinanceLegalPolicy,
                MachineCallbackIdentity,
              ],
              server_now,
            )
            is None else {
            return self
              .offline_readiness_gate(
                [
                  EntitlementAuthority,
                  FinanceLegalPolicy,
                  MachineCallbackIdentity,
                ],
                server_now,
              )
              .unwrap()
          }
          let decoded : OfflineFulfillmentAction? = decode_offline(body)
          guard decoded is Some(action) else {
            return api_error(
              400, "InvalidRequest", "invalid fulfillment action", false,
            )
          }
          let current = store.order_for_operator(action.order_id)
          let activation : @offline.EntitlementActivation = {
            activation_id: action.activation_id,
            idempotency_key: action.idempotency_key,
            order_id: current.order_id,
            organization_id: current.organization_id,
            purchaser_subject_ref: current.purchaser_subject_ref,
            kind: action.entitlement_kind,
            authority_target_ref: action.authority_target_ref,
            expected_order_generation: action.expected_generation,
            state: EntitlementActivationRequested,
            entitlement_ref: None,
            authority_receipt: None,
            reason_code: None,
            requested_by: actor_ref,
            requested_unix_ms: server_now,
            completed_unix_ms: None,
          }
          json_reply(
            202,
            store
            .fulfill(
              action.order_id,
              action.expected_generation,
              activation,
              server_now,
            )
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/cancellations") => {
          let decoded : OfflineOrderAction? = decode_offline(body)
          guard decoded is Some(action) else {
            return api_error(
              400, "InvalidRequest", "invalid cancellation action", false,
            )
          }
          json_reply(
            200,
            store
            .cancel_order(
              action.order_id,
              action.expected_generation,
              server_now,
            )
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/reversals") => {
          guard self.offline_readiness_gate(
              [
                EntitlementAuthority,
                FinanceLegalPolicy,
                MachineCallbackIdentity,
              ],
              server_now,
            )
            is None else {
            return self
              .offline_readiness_gate(
                [
                  EntitlementAuthority,
                  FinanceLegalPolicy,
                  MachineCallbackIdentity,
                ],
                server_now,
              )
              .unwrap()
          }
          let decoded : OfflineReversalAction? = decode_offline(body)
          guard decoded is Some(action) else {
            return api_error(
              400, "InvalidRequest", "invalid reversal action", false,
            )
          }
          let current = store.order_for_operator(action.order_id)
          guard current.entitlement_ref is Some(entitlement_ref) else {
            return api_error(
              409, "EntitlementMissing", "fulfilled entitlement is required for reversal",
              false,
            )
          }
          let reversal : @offline.CommercialReversal = {
            reversal_id: action.reversal_id,
            idempotency_key: action.idempotency_key,
            order_id: current.order_id,
            organization_id: current.organization_id,
            entitlement_ref,
            reason: action.reason,
            expected_order_generation: action.expected_generation,
            state: ReversalRequested,
            authority_receipt: None,
            reason_code: None,
            requested_by: actor_ref,
            requested_unix_ms: server_now,
            completed_unix_ms: None,
          }
          json_reply(202, store.request_reversal(reversal).to_json())
        }
        (Post, "/v1/offline-commerce/operator/reversal-recoveries") => {
          let decoded : OfflineReversalRecoveryAction? = decode_offline(body)
          guard decoded is Some(action) else {
            return api_error(
              400, "InvalidRequest", "invalid reversal recovery evidence", false,
            )
          }
          let current = store.order_for_operator(action.order_id)
          let recovery : @offline.ReversalRecovery = {
            recovery_id: action.recovery_id,
            idempotency_key: action.idempotency_key,
            order_id: current.order_id,
            organization_id: current.organization_id,
            failed_reversal_id: action.failed_reversal_id,
            expected_order_generation: action.expected_generation,
            decision: action.decision,
            replacement_reversal_id: action.replacement_reversal_id,
            authority_receipt: action.authority_receipt,
            reason_code: action.reason_code,
            recovered_by: actor_ref,
            recovered_unix_ms: server_now,
          }
          json_reply(200, store.recover_failed_reversal(recovery).to_json())
        }
        _ =>
          api_error(
            404, "NotFound", "offline commercial route was not found", false,
          )
      }
    } catch {
      error => offline_error_reply(error)
    } noraise {
      value => value
    }
    if reply.status >= 200 && reply.status < 300 && verb != Get {
      self.operator_audit(
        offline_operator_audit_action(path),
        path,
        "offline-commerce:\{@async.now()}",
      )
      self.refresh_offline_commerce_notifications(@async.now())
    }
    return reply
  }
  guard self.portal_store is Some(portal) &&
    self.portal_subject(headers, allow_asserted_subject) is Some(subject_ref) else {
    return api_error(
      401, "Unauthenticated", "verified enterprise identity is required", false,
    )
  }
  let view = try portal_view_for_request(portal, subject_ref, headers) catch {
    error => return portal_error_reply(error)
  } noraise {
    value => value
  }
  match (verb, path) {
    (Get, "/v1/offline-commerce/self/orders") => {
      self.refresh_offline_commerce_notifications(@async.now())
      json_reply(
        200,
        store
        .orders_for_organization(view.membership.organization_id)
        .filter(order => order.purchaser_subject_ref == subject_ref)
        .to_json(),
      )
    }
    (Post, "/v1/offline-commerce/self/orders") => {
      let decoded : OfflineOrderIntent? = decode_offline(body)
      guard decoded is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid commercial order intent", false,
        )
      }
      let now = @async.now()
      if intent.expires_unix_ms < now + 300000L ||
        intent.expires_unix_ms > now + 31622400000L {
        return api_error(
          400, "InvalidExpiry", "order expiry must be between five minutes and 366 days",
          false,
        )
      }
      let created = try
        store.create_order({
          order_id: intent.order_id,
          idempotency_key: intent.idempotency_key,
          tenant_ref: view.membership.tenant_ref,
          organization_id: view.membership.organization_id,
          project_id: intent.project_id,
          purchaser_subject_ref: subject_ref,
          selected_service_code: intent.selected_service_code,
          selected_sla_code: intent.selected_sla_code,
          policy: hybrid_offline_policy(),
          quote: None,
          agreement_ref: None,
          artifact_ids: [],
          entitlement_ref: None,
          state: Draft,
          generation: 1L,
          created_unix_ms: now,
          updated_unix_ms: now,
          expires_unix_ms: intent.expires_unix_ms,
        })
      catch {
        error => return offline_error_reply(error)
      } noraise {
        value => value
      }
      self.refresh_offline_commerce_notifications(now)
      json_reply(201, created.to_json())
    }
    (Post, "/v1/offline-commerce/self/upload-grants") => {
      let gate = self.offline_readiness_gate(
        [ObjectStorage, MalwareScanner, MachineCallbackIdentity],
        @async.now(),
      )
      guard gate is None else { return gate.unwrap() }
      let decoded : SelfUploadIntent? = decode_offline(body)
      guard decoded is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid evidence upload intent", false,
        )
      }
      let current = try
        store.order(view.membership.organization_id, intent.order_id)
      catch {
        error => return offline_error_reply(error)
      } noraise {
        value => value
      }
      if current.purchaser_subject_ref != subject_ref {
        return api_error(
          403, "OfflineCommerceDenied", "order belongs to a different purchaser",
          false,
        )
      }
      let now = @async.now()
      let grant = try
        store.grant_upload({
          grant_id: intent.grant_id,
          idempotency_key: intent.idempotency_key,
          order_id: intent.order_id,
          organization_id: view.membership.organization_id,
          subject_ref,
          artifact_id: intent.artifact_id,
          kind: intent.kind,
          revision: intent.revision,
          expected_object_ref: "object://offline-uploads/\{view.membership.organization_id}/\{intent.order_id}/\{intent.artifact_id}",
          allowed_media_types: intent.allowed_media_types,
          maximum_byte_count: intent.maximum_byte_count,
          expires_unix_ms: intent.expires_unix_ms,
          state: UploadGranted,
          created_unix_ms: now,
        })
      catch {
        error => return offline_error_reply(error)
      } noraise {
        value => value
      }
      let transfer = try
        self.issue_offline_transfer(
          store,
          "transfer-\{grant.grant_id}",
          "transfer-\{grant.idempotency_key}",
          grant.organization_id,
          grant.subject_ref,
          grant.order_id,
          grant.artifact_id,
          UploadTransfer,
          grant.expected_object_ref,
          grant.allowed_media_types,
          grant.maximum_byte_count,
          None,
          grant.created_unix_ms,
          grant.expires_unix_ms.min(grant.created_unix_ms + 900000L),
        )
      catch {
        _ =>
          return api_error(
            503, "OfflineTransferAdapterUnavailable", "upload transfer could not be issued",
            true,
          )
      } noraise {
        value => value
      }
      self.refresh_offline_commerce_notifications(now)
      let response : OfflineUploadTransferView = {
        evidence: grant.public_view(),
        transfer,
      }
      json_reply(201, response.to_json())
    }
    (Post, _) if path.has_prefix("/v1/offline-commerce/self/orders/") &&
      path.has_suffix(":cancel") => {
      let order_id = path["/v1/offline-commerce/self/orders/".length():path.length() -
      ":cancel".length()].to_owned()
      let decoded : OfflineOrderAction? = decode_offline(body)
      guard decoded is Some(action) && action.order_id == order_id else {
        return api_error(
          400, "InvalidRequest", "invalid order cancellation", false,
        )
      }
      let current = try
        store.order(view.membership.organization_id, order_id)
      catch {
        error => return offline_error_reply(error)
      } noraise {
        value => value
      }
      if current.purchaser_subject_ref != subject_ref {
        return api_error(
          403, "OfflineCommerceDenied", "order belongs to a different purchaser",
          false,
        )
      }
      let now = @async.now()
      let status = if current.state == Fulfilled { 202 } else { 200 }
      let cancelled = try {
        if current.state == Fulfilled {
          let gate = self.offline_readiness_gate(
            [EntitlementAuthority, FinanceLegalPolicy, MachineCallbackIdentity],
            now,
          )
          guard gate is None else { return gate.unwrap() }
          guard current.entitlement_ref is Some(entitlement_ref) else {
            return api_error(
              409, "EntitlementMissing", "fulfilled order lacks entitlement", false,
            )
          }
          let reversal_id = "customer-cancel-\{order_id}-\{action.expected_generation}"
          store.request_reversal({
            reversal_id,
            idempotency_key: reversal_id,
            order_id,
            organization_id: current.organization_id,
            entitlement_ref,
            reason: CustomerCancellation,
            expected_order_generation: action.expected_generation,
            state: ReversalRequested,
            authority_receipt: None,
            reason_code: None,
            requested_by: subject_ref,
            requested_unix_ms: now,
            completed_unix_ms: None,
          })
        } else {
          store.cancel_order(order_id, action.expected_generation, now)
        }
      } catch {
        error => return offline_error_reply(error)
      } noraise {
        value => value
      }
      self.refresh_offline_commerce_notifications(now)
      json_reply(status, cancelled.to_json())
    }
    (Post, _) if path.has_prefix("/v1/offline-commerce/self/artifacts/") &&
      path.has_suffix(":download") => {
      let artifact_id = path["/v1/offline-commerce/self/artifacts/".length():path.length() -
      ":download".length()].to_owned()
      let decoded : SelfDownloadIntent? = decode_offline(body)
      guard decoded is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid artifact download intent", false,
        )
      }
      let artifact = try
        store.artifact(view.membership.organization_id, artifact_id)
      catch {
        error => return offline_error_reply(error)
      } noraise {
        value => value
      }
      let current = try
        store.order(view.membership.organization_id, artifact.order_id)
      catch {
        error => return offline_error_reply(error)
      } noraise {
        value => value
      }
      if current.purchaser_subject_ref != subject_ref {
        return api_error(
          403, "OfflineCommerceDenied", "artifact belongs to a different purchaser",
          false,
        )
      }
      let now = @async.now()
      let transfer = try
        self.issue_offline_transfer(
          store,
          intent.session_id,
          intent.idempotency_key,
          current.organization_id,
          subject_ref,
          current.order_id,
          artifact.artifact_id,
          DownloadTransfer,
          artifact.object_ref,
          [artifact.media_type],
          artifact.byte_count,
          Some(artifact.sha256),
          now,
          now + 300000L,
        )
      catch {
        _ =>
          return api_error(
            503, "OfflineTransferAdapterUnavailable", "download transfer could not be issued",
            true,
          )
      } noraise {
        value => value
      }
      json_reply(201, transfer.to_json())
    }
    (Get, _) if path.has_prefix("/v1/offline-commerce/self/artifacts/") => {
      let artifact_id = path["/v1/offline-commerce/self/artifacts/".length():].to_owned()
      let artifact = try
        store.artifact(view.membership.organization_id, artifact_id)
      catch {
        error => return offline_error_reply(error)
      } noraise {
        value => value
      }
      let current = try
        store.order(view.membership.organization_id, artifact.order_id)
      catch {
        error => return offline_error_reply(error)
      } noraise {
        value => value
      }
      if current.purchaser_subject_ref != subject_ref {
        return api_error(
          403, "OfflineCommerceDenied", "artifact belongs to a different purchaser",
          false,
        )
      }
      json_reply(200, artifact.public_view().to_json())
    }
    _ =>
      api_error(
        404, "NotFound", "offline commercial route was not found", false,
      )
  }
}
