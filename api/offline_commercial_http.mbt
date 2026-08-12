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
  now_unix_ms : Int64
} derive(FromJson)

///|
priv struct OfflineGenerationResultAction {
  result : @offline.ArtifactGenerationResult
} derive(FromJson)

///|
priv struct OfflineOrderAction {
  order_id : String
  expected_generation : Int64
  now_unix_ms : Int64
} derive(FromJson)

///|
priv struct OfflineFulfillmentAction {
  order_id : String
  expected_generation : Int64
  entitlement_ref : String
  now_unix_ms : Int64
} derive(FromJson)

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
    Fulfilled => "Fulfilled"
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

///|
async fn ApiService::alert_offline_callback_failure(
  self : ApiService,
  code : String,
  resource_ref : String,
  now_unix_ms : Int64,
) -> Unit {
  guard self.notification_store is Some(notifications) else { return }
  let deduplication_key = "offline-callback-\{code}-\{resource_ref}"
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
      notification_id: "alert-\{code}-\{resource_ref}",
      deduplication_key,
      source_receipt: "offline-callback:\{code}:\{resource_ref}",
      topic: ArtifactHealth,
      code,
      severity: Critical,
      audience: PlatformOperators,
      title_key: "alerts.\{code}.title",
      body_key: "alerts.\{code}.body",
      parameters: { "resource_ref": resource_ref },
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
  if path == "/v1/offline-commerce/operator/generation-results" {
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
  if path.has_prefix("/v1/offline-commerce/operator/") {
    if !bearer_authorized(headers, self.operator_token) {
      return api_error(
        401, "Unauthenticated", "valid operator authority is required", false,
      )
    }
    let actor_ref = offline_operator_actor(headers)
    let reply = try {
      match (verb, path) {
        (Get, "/v1/offline-commerce/operator/snapshot") =>
          json_reply(200, store.snapshot().to_json())
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
          let decoded : OfflineQuoteAction? = decode_offline(body)
          guard decoded is Some(action) else {
            return api_error(
              400, "InvalidRequest", "invalid quote action", false,
            )
          }
          json_reply(
            200,
            store
            .quote_order(
              action.order_id,
              action.quote,
              actor_ref,
              action.now_unix_ms,
            )
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/begin") => {
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
              action.now_unix_ms,
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
          json_reply(
            202,
            store
            .request_generation({ ..request, requested_by: actor_ref })
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/release-packets") => {
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
              action.now_unix_ms,
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
            .review_evidence({ ..review, reviewer_ref: actor_ref })
            .to_json(),
          )
        }
        (Post, "/v1/offline-commerce/operator/fulfillments") => {
          let decoded : OfflineFulfillmentAction? = decode_offline(body)
          guard decoded is Some(action) else {
            return api_error(
              400, "InvalidRequest", "invalid fulfillment action", false,
            )
          }
          json_reply(
            200,
            store
            .fulfill(
              action.order_id,
              action.expected_generation,
              action.entitlement_ref,
              action.now_unix_ms,
            )
            .to_json(),
          )
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
  let view = try portal.self_view(subject_ref) catch {
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
      self.refresh_offline_commerce_notifications(now)
      json_reply(201, grant.public_view().to_json())
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
