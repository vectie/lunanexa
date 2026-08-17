///|
fn contract_document_path(path : String) -> Bool {
  path == "/v1/contract-documents" || path.has_prefix("/v1/contract-documents/")
}

///|
priv struct ContractPacketIntent {
  packet_id : String
  idempotency_key : String
  order_ref : String
  preceding_packet_ref : String?
  active_forms : Array[@contractdoc.ContractFormKind]
} derive(FromJson)

///|
priv struct ContractRenewalIntent {
  packet_id : String
  idempotency_key : String
} derive(FromJson)

///|
priv struct ContractInformationUpdate {
  expected_revision : Int64
  changes : Array[@contractdoc.ContractFieldValue]
} derive(FromJson)

///|
priv struct ContractRevisionAction {
  expected_revision : Int64
  expected_values_sha256 : String?
} derive(FromJson)

///|
priv struct ContractPreviewIntent {
  expected_revision : Int64
  form : @contractdoc.ContractFormKind
  changes : Array[@contractdoc.ContractFieldValue]
} derive(FromJson)

///|
priv struct ContractGenerationResult {
  packet_id : String
  expected_revision : Int64
  docx : @contractdoc.ContractGeneratedArtifact
  pdf : @contractdoc.ContractGeneratedArtifact
  worker_receipt : String
} derive(FromJson)

///|
priv struct ContractGenerationFailure {
  packet_id : String
  expected_revision : Int64
  reason : String
  worker_receipt : String
} derive(FromJson)

///|
/// The operator registers evidence of the offline signed-and-stamped packet.
/// `registered_by` is fixed server-side to the operator authority; browsers
/// never supply actor identities.
priv struct ContractExecutionRegistration {
  expected_revision : Int64
  evidence_sha256 : String
  signed_on : String
} derive(FromJson)

///|
priv struct ContractClosureIntent {
  expected_revision : Int64
  kind : @contractdoc.ContractClosureKind
  reason : String
} derive(FromJson)

///|
priv struct ContractSupersessionIntent {
  expected_revision : Int64
  successor_ref : String
  reason : String
} derive(FromJson)

///|
priv struct ContractApprovalDecision {
  reason : String
} derive(FromJson)

///|
fn closure_kind_name(kind : @contractdoc.ContractClosureKind) -> String {
  match kind {
    Expired => "Expired"
    EarlyTermination => "EarlyTermination"
    Settled => "Settled"
  }
}

///|
fn closure_kind_from_name(name : String) -> @contractdoc.ContractClosureKind? {
  match name {
    "Expired" => Some(Expired)
    "EarlyTermination" => Some(EarlyTermination)
    "Settled" => Some(Settled)
    _ => None
  }
}

///|
fn contract_packet_id(path : String, suffix : String) -> String? {
  let prefix = "/v1/contract-documents/self/"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return None
  }
  let packet_id = path[prefix.length():path.length() - suffix.length()].to_owned()
  if @contracts.valid_identifier(packet_id) {
    Some(packet_id)
  } else {
    None
  }
}

///|
fn operator_contract_packet_id(path : String, suffix : String) -> String? {
  let prefix = "/v1/contract-documents/operator/packets/"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return None
  }
  let packet_id = path[prefix.length():path.length() - suffix.length()].to_owned()
  if @contracts.valid_identifier(packet_id) {
    Some(packet_id)
  } else {
    None
  }
}

///|
fn operator_approval_id(path : String, suffix : String) -> String? {
  let prefix = "/v1/contract-documents/operator/approvals/"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return None
  }
  let approval_id = path[prefix.length():path.length() - suffix.length()].to_owned()
  if @contracts.valid_identifier(approval_id) {
    Some(approval_id)
  } else {
    None
  }
}

///|
/// Whether the packet's `lease.total_rent` strictly exceeds the configured
/// four-eyes threshold. An unparseable or missing amount fails safe and
/// counts as over threshold; an unset threshold keeps the direct behavior.
fn ApiService::contract_approval_required(
  self : ApiService,
  packet : @contractdoc.ContractPacket,
) -> Bool {
  guard self.contract_approval_threshold_minor_units is Some(threshold) else {
    return false
  }
  match packet.value("lease.total_rent") {
    Some(raw) =>
      match @contractdoc.parse_cny_minor_units(raw) {
        Some(amount) => amount > threshold
        None => true
      }
    None => true
  }
}

///|
/// Records a durable pending approval instead of applying the transition and
/// answers 202. The requesting operator is audited as the initiator and the
/// platform operators are notified so a second pair of eyes decides.
async fn ApiService::request_contract_approval(
  self : ApiService,
  store : @contractdoc_store.ContractDocumentStore,
  packet : @contractdoc.ContractPacket,
  initiator : String,
  action : String,
  expected_revision : Int64,
  payload : @contractdoc.ContractApprovalPayload,
) -> HttpReply {
  let now = @async.now()
  let approval : @contractdoc.ContractApproval = {
    approval_id: "contract-approval-\{packet.packet_id}-\{now}",
    packet_id: packet.packet_id,
    action,
    expected_revision,
    payload,
    initiator,
    created_unix_ms: now,
    status: Pending,
    decided_by: None,
    decided_unix_ms: None,
    decision_reason: None,
  }
  let created = try store.create_approval(approval) catch {
    error => return contract_document_error(error)
  } noraise {
    value => value
  }
  self.operator_audit_as(
    initiator,
    "contract.approval.requested",
    packet.packet_id,
    "approval:\{created.approval_id}:action:\{action}",
  )
  self.notify_contract_approval_requested(created, now)
  json_reply(202, created.to_json())
}

///|
/// Re-runs the full original server-side path of an approved request. The
/// recorded payload and revision fence the re-execution: a packet that moved
/// on is rejected with the same errors the direct route would return, and the
/// approval stays pending so it can be withdrawn. The initiator is recorded
/// as the actor of the transition itself.
async fn ApiService::execute_approved_contract_action(
  self : ApiService,
  store : @contractdoc_store.ContractDocumentStore,
  approval : @contractdoc.ContractApproval,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket raise Error {
  if approval.action == "execute" {
    guard approval.payload.evidence_sha256 is Some(evidence_sha256) &&
      approval.payload.signed_on is Some(signed_on) else {
      raise @contractdoc.ContractDocumentError::InvalidInput(
        "contract approval payload is incomplete",
      )
    }
    let evidence : @contractdoc.ContractExecution = {
      evidence_sha256,
      signed_on,
      registered_by: approval.initiator,
      registered_unix_ms: now_unix_ms,
    }
    return store.register_execution(
      approval.packet_id,
      approval.expected_revision,
      evidence,
      now_unix_ms,
    )
  }
  guard approval.action.has_prefix("close:") &&
    closure_kind_from_name(approval.action[6:].to_owned()) is Some(kind) &&
    approval.payload.reason is Some(reason) else {
    raise @contractdoc.ContractDocumentError::InvalidInput(
      "contract approval payload is incomplete",
    )
  }
  guard store.packet(approval.packet_id) is Some(packet) else {
    raise @contractdoc.ContractDocumentError::NotFound("contract packet")
  }
  // The settlement gate and ledger reconciliation re-run at decision time:
  // the ledger may have changed since the request was filed.
  let settlement_check : SettlementLedgerCheck? = if kind == EarlyTermination {
    self.check_settlement_against_ledger(packet, now_unix_ms)
  } else {
    None
  }
  match settlement_check {
    Some(Mismatched(detail)) =>
      raise @contractdoc.ContractDocumentError::SettlementMismatch(detail)
    _ => ()
  }
  let updated = store.close_packet(
    approval.packet_id,
    approval.expected_revision,
    kind,
    reason,
    approval.initiator,
    now_unix_ms,
  )
  match settlement_check {
    Some(Matched(settlement_ref~, minor_units~)) =>
      self.operator_audit_as(
        approval.initiator,
        "contract.settlement.reconciled",
        updated.packet_id,
        "settlement:\{settlement_ref}:amount-cny:\{@contractdoc.format_cny_minor_units(minor_units)}:ledger-matched",
      )
    Some(LedgerUnused(settlement_ref~)) =>
      self.operator_audit_as(
        approval.initiator,
        "contract.settlement.ledger-unused",
        updated.packet_id,
        "settlement:\{settlement_ref}:ledger-not-in-use",
      )
    _ => ()
  }
  self.apply_master_lease_closure_effects(
    updated,
    approval.initiator,
    now_unix_ms,
  )
  updated
}

///|
fn contract_document_error(error : Error) -> HttpReply {
  match error {
    @contractdoc.ContractDocumentError::NotFound(_) =>
      api_error(
        404, "ContractPacketNotFound", "contract packet was not found", false,
      )
    @contractdoc.ContractDocumentError::StaleRevision =>
      api_error(
        409, "StaleContractRevision", "contract packet changed; refresh before retrying",
        true,
      )
    @contractdoc.ContractDocumentError::MissingRequiredFields(_) =>
      api_error(
        409, "ContractInformationIncomplete", "required source fields are incomplete",
        false,
      )
    @contractdoc.ContractDocumentError::ConfirmationMismatch =>
      api_error(
        409, "ContractConfirmationMismatch", "confirmed information changed", false,
      )
    @contractdoc.ContractDocumentError::InvalidTransition(_) =>
      api_error(
        409, "ContractTransitionRejected", "contract packet is not in the required state",
        false,
      )
    @contractdoc.ContractDocumentError::AlreadyExists(_)
    | @contractdoc.ContractDocumentError::IdempotencyConflict(_) =>
      api_error(
        409, "ContractPacketConflict", "contract packet already exists with different content",
        false,
      )
    @contractdoc.ContractDocumentError::ForbiddenSecret(_) =>
      api_error(
        400, "ContractSecretRejected", "this source field must be completed offline",
        false,
      )
    @contractdoc.ContractDocumentError::ContractNotEffective(_) =>
      api_error(
        409, "ContractPredecessorNotEffective", "the preceding contract packet is not effective",
        false,
      )
    @contractdoc.ContractDocumentError::ContractNotRenewable(_) =>
      api_error(
        409, "ContractRenewalRejected", "contract packet is not in a renewable state",
        false,
      )
    @contractdoc.ContractDocumentError::InvalidEvidence(_) =>
      api_error(
        400, "ContractEvidenceRejected", "contract execution evidence is invalid",
        false,
      )
    @contractdoc.ContractDocumentError::InvalidExecutionDate(_) =>
      api_error(
        400, "ContractExecutionDateRejected", "the signing date must be a YYYY-MM-DD calendar date",
        false,
      )
    @contractdoc.ContractDocumentError::SettlementMismatch(detail) =>
      api_error(409, "ContractSettlementMismatch", detail, false)
    @contractdoc.ContractDocumentError::ContractApprovalNotFound(_) =>
      api_error(
        404, "ContractApprovalNotFound", "contract approval was not found", false,
      )
    @contractdoc.ContractDocumentError::ContractApprovalSelfDecision(_) =>
      api_error(
        409, "ContractApprovalSelfDecision", "a second operator must decide the approval",
        false,
      )
    @contractdoc.ContractDocumentError::ContractApprovalAlreadyDecided(_) =>
      api_error(
        409, "ContractApprovalAlreadyDecided", "contract approval was already decided",
        false,
      )
    _ =>
      api_error(
        400, "ContractDocumentRejected", "contract document request was rejected",
        false,
      )
  }
}

///|
async fn moonleaf_contract_preview(
  manifest : @contractdoc.ContractTemplateManifest,
  packet : @contractdoc.ContractPacket,
  actor : @contractdoc.ContractFieldOwner,
  request : ContractPreviewIntent,
) -> HttpReply {
  if request.expected_revision != packet.revision {
    return api_error(
      409, "StaleContractRevision", "contract packet changed; refresh before previewing",
      true,
    )
  }
  let template_path = @env.get_env_var("LUNANEXA_CONTRACT_TEMPLATE_PATH").unwrap_or(
    "assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx",
  )
  let template = try
    @fs.read_file(template_path).binary().to_fixedarray()
  catch {
    _ =>
      return api_error(
        503, "ContractTemplateUnavailable", "the MoonLeaf contract template is unavailable",
        true,
      )
  } noraise {
    value => value
  }
  let preview = try
    @contract_preview.render(
      template,
      manifest,
      packet,
      actor,
      request.form,
      request.changes,
    )
  catch {
    _ =>
      return api_error(
        400, "ContractPreviewRejected", "MoonLeaf rejected the contract preview request",
        false,
      )
  } noraise {
    value => value
  }
  json_reply(200, preview.to_json())
}

///|
fn linked_order_values(
  packet : @contractdoc.ContractPacket,
) -> Array[@contractdoc.ContractFieldValue] {
  if packet.active_forms.contains(AccessConfirmation) {
    [{ field_id: "access.order_number", value: packet.order_ref }]
  } else {
    []
  }
}

///|
/// Applies platform-derived linked values on the creation write path. Reads
/// (`GET`) never mutate the store; the order reference is fixed at creation,
/// so synchronizing here and on idempotent replays keeps the value durable.
async fn synchronize_linked_contract_values(
  store : @contractdoc_store.ContractDocumentStore,
  manifest : @contractdoc.ContractTemplateManifest,
  packet : @contractdoc.ContractPacket,
) -> @contractdoc.ContractPacket {
  let changes = linked_order_values(packet).filter(item => {
    packet.value(item.field_id) != Some(item.value)
  })
  if changes.length() == 0 {
    packet
  } else {
    store.update_information(
      manifest,
      packet.packet_id,
      packet.revision,
      changes,
      PlatformDerived,
      "contract-system",
      "linked-order:\{packet.order_ref}",
      @async.now(),
    )
  }
}

///|
async fn ApiService::handle_contract_documents(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.contract_document_store is Some(store) else {
    return api_error(
      503, "ContractDocumentStoreUnavailable", "durable contract-document authority is unavailable",
      true,
    )
  }
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  if path == "/v1/contract-documents/operator/packets" ||
    path.has_prefix("/v1/contract-documents/operator/packets/") {
    guard self.operator_identity(headers) is Some(operator_id) else {
      return api_error(
        401, "Unauthenticated", "operator authority is required", false,
      )
    }
    return match (verb, path) {
      (Get, "/v1/contract-documents/operator/packets") =>
        json_reply(200, store.snapshot().packets.to_json())
      (Put, _) if operator_contract_packet_id(path, ":information")
        is Some(packet_id) => {
        let decoded : ContractInformationUpdate? = Some(
          @json.from_json(@json.parse(body)),
        ) catch {
          _ => None
        }
        guard decoded is Some(request) && store.packet(packet_id) is Some(_) else {
          return api_error(
            404, "ContractPacketNotFound", "contract packet was not found", false,
          )
        }
        let updated = try
          store.update_information(
            manifest,
            packet_id,
            request.expected_revision,
            request.changes,
            ManagerOperator,
            operator_id,
            "operator-console",
            @async.now(),
          )
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        json_reply(200, updated.to_json())
      }
      (Post, _) if operator_contract_packet_id(path, ":preview")
        is Some(packet_id) => {
        let decoded : ContractPreviewIntent? = Some(
          @json.from_json(@json.parse(body)),
        ) catch {
          _ => None
        }
        guard decoded is Some(request) &&
          store.packet(packet_id) is Some(packet) else {
          return api_error(
            404, "ContractPacketNotFound", "contract packet was not found", false,
          )
        }
        moonleaf_contract_preview(manifest, packet, ManagerOperator, request)
      }
      (Post, _) if operator_contract_packet_id(path, ":execute")
        is Some(packet_id) => {
        let decoded : ContractExecutionRegistration? = Some(
          @json.from_json(@json.parse(body)),
        ) catch {
          _ => None
        }
        guard decoded is Some(request) &&
          store.packet(packet_id) is Some(packet) else {
          return api_error(
            404, "ContractPacketNotFound", "contract packet was not found", false,
          )
        }
        if self.contract_approval_required(packet) {
          return self.request_contract_approval(store, packet, operator_id, "execute", request.expected_revision, {
            evidence_sha256: Some(request.evidence_sha256),
            signed_on: Some(request.signed_on),
            kind: None,
            reason: None,
          })
        }
        let evidence : @contractdoc.ContractExecution = {
          evidence_sha256: request.evidence_sha256,
          signed_on: request.signed_on,
          registered_by: operator_id,
          registered_unix_ms: @async.now(),
        }
        let updated = try
          store.register_execution(
            packet_id,
            request.expected_revision,
            evidence,
            @async.now(),
          )
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        json_reply(200, updated.to_json())
      }
      (Post, _) if operator_contract_packet_id(path, ":close")
        is Some(packet_id) => {
        let decoded : ContractClosureIntent? = Some(
          @json.from_json(@json.parse(body)),
        ) catch {
          _ => None
        }
        guard decoded is Some(request) &&
          store.packet(packet_id) is Some(packet) else {
          return api_error(
            404, "ContractPacketNotFound", "contract packet was not found", false,
          )
        }
        let now = @async.now()
        // Early termination is gated on the settlement ledger: the effective
        // settlement amount due must match the organization's commercial
        // ledger before the contract relationship may close.
        let settlement_check : SettlementLedgerCheck? = if request.kind ==
          EarlyTermination {
          self.check_settlement_against_ledger(packet, now)
        } else {
          None
        }
        match settlement_check {
          Some(Mismatched(detail)) =>
            return contract_document_error(
              @contractdoc.ContractDocumentError::SettlementMismatch(detail),
            )
          _ => ()
        }
        if self.contract_approval_required(packet) {
          return self.request_contract_approval(store, packet, operator_id, "close:\{closure_kind_name(request.kind)}", request.expected_revision, {
            evidence_sha256: None,
            signed_on: None,
            kind: Some(request.kind),
            reason: Some(request.reason),
          })
        }
        let updated = try
          store.close_packet(
            packet_id,
            request.expected_revision,
            request.kind,
            request.reason,
            operator_id,
            now,
          )
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        match settlement_check {
          Some(Matched(settlement_ref~, minor_units~)) =>
            self.operator_audit_as(
              operator_id,
              "contract.settlement.reconciled",
              updated.packet_id,
              "settlement:\{settlement_ref}:amount-cny:\{@contractdoc.format_cny_minor_units(minor_units)}:ledger-matched",
            )
          Some(LedgerUnused(settlement_ref~)) =>
            self.operator_audit_as(
              operator_id,
              "contract.settlement.ledger-unused",
              updated.packet_id,
              "settlement:\{settlement_ref}:ledger-not-in-use",
            )
          _ => ()
        }
        // Closing a master lease ends the access relationship; the shared
        // closure effects revoke the subject's still-active API credentials.
        // Superseded packets deliberately do NOT trigger revocation: the
        // successor packet continues the relationship, so the `:supersede`
        // branch stays untouched.
        self.apply_master_lease_closure_effects(updated, operator_id, now)
        json_reply(200, updated.to_json())
      }
      (Post, _) if operator_contract_packet_id(path, ":supersede")
        is Some(packet_id) => {
        let decoded : ContractSupersessionIntent? = Some(
          @json.from_json(@json.parse(body)),
        ) catch {
          _ => None
        }
        guard decoded is Some(request) && store.packet(packet_id) is Some(_) else {
          return api_error(
            404, "ContractPacketNotFound", "contract packet was not found", false,
          )
        }
        let updated = try
          store.supersede_packet(
            packet_id,
            request.expected_revision,
            request.successor_ref,
            request.reason,
            operator_id,
            @async.now(),
          )
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        json_reply(200, updated.to_json())
      }
      (Post, _) if operator_contract_packet_id(path, ":renew")
        is Some(source_packet_id) => {
        let decoded : ContractRenewalIntent? = Some(
          @json.from_json(@json.parse(body)),
        ) catch {
          _ => None
        }
        guard decoded is Some(intent) &&
          @contracts.valid_identifier(intent.packet_id) &&
          @contracts.valid_identifier(intent.idempotency_key) &&
          store.packet(source_packet_id) is Some(_) else {
          return api_error(
            404, "ContractPacketNotFound", "contract packet was not found", false,
          )
        }
        let renewed = try
          store.renew_packet(
            source_packet_id,
            intent.packet_id,
            intent.idempotency_key,
            operator_id,
            @async.now(),
          )
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        json_reply(201, renewed.to_json())
      }
      _ => api_error(404, "NotFound", "route was not found", false)
    }
  }
  if path == "/v1/contract-documents/operator/approvals" ||
    path.has_prefix("/v1/contract-documents/operator/approvals?") ||
    path.has_prefix("/v1/contract-documents/operator/approvals/") {
    guard self.operator_identity(headers) is Some(operator_id) else {
      return api_error(
        401, "Unauthenticated", "operator authority is required", false,
      )
    }
    return match (verb, path) {
      (Get, _) if path == "/v1/contract-documents/operator/approvals" ||
        path.has_prefix("/v1/contract-documents/operator/approvals?") => {
        let status : @contractdoc.ContractApprovalStatus? = if
          path.contains("status=pending") {
          Some(Pending)
        } else if path.contains("status=approved") {
          Some(Approved)
        } else if path.contains("status=rejected") {
          Some(Rejected)
        } else {
          None
        }
        json_reply(200, store.list_approvals(status).to_json())
      }
      (Post, _) if operator_approval_id(path, ":approve") is Some(approval_id) => {
        guard store.get_approval(approval_id) is Some(approval) else {
          return api_error(
            404, "ContractApprovalNotFound", "contract approval was not found",
            false,
          )
        }
        if approval.status != Pending {
          return api_error(
            409, "ContractApprovalAlreadyDecided", "contract approval was already decided",
            false,
          )
        }
        if operator_id == approval.initiator {
          return api_error(
            409, "ContractApprovalSelfDecision", "a second operator must approve the request",
            false,
          )
        }
        let now = @async.now()
        // The full original path re-runs here; a failure (revision fence,
        // state drift, settlement mismatch) leaves the approval pending so
        // the initiator can withdraw it.
        ignore(
          try
            self.execute_approved_contract_action(store, approval, now)
          catch {
            error => return contract_document_error(error)
          } noraise {
            value => value
          },
        )
        let decided = try
          store.decide_approval(approval_id, true, operator_id, None, now)
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        self.operator_audit_as(
          operator_id,
          "contract.approval.approved",
          approval.packet_id,
          "approval:\{approval.approval_id}:action:\{approval.action}",
        )
        json_reply(200, decided.to_json())
      }
      (Post, _) if operator_approval_id(path, ":reject") is Some(approval_id) => {
        let decoded : ContractApprovalDecision? = Some(
          @json.from_json(@json.parse(body)),
        ) catch {
          _ => None
        }
        guard decoded is Some(decision) && decision.reason.trim() != "" else {
          return api_error(
            400, "InvalidRequest", "a rejection reason is required", false,
          )
        }
        let decided = try
          store.decide_approval(
            approval_id,
            false,
            operator_id,
            Some(decision.reason),
            @async.now(),
          )
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        self.operator_audit_as(
          operator_id,
          "contract.approval.rejected",
          decided.packet_id,
          "approval:\{approval_id}:action:\{decided.action}:reason:\{decision.reason}",
        )
        json_reply(200, decided.to_json())
      }
      _ => api_error(404, "NotFound", "route was not found", false)
    }
  }
  if path == "/v1/contract-documents/worker/pending" ||
    path == "/v1/contract-documents/worker/results" ||
    path == "/v1/contract-documents/worker/failures" {
    guard self.contract_document_worker_token != "" &&
      bearer_authorized(headers, self.contract_document_worker_token) else {
      return api_error(
        401, "Unauthenticated", "contract renderer identity is required", false,
      )
    }
    return match (verb, path) {
      (Get, "/v1/contract-documents/worker/pending") =>
        json_reply(200, store.pending_generation_packets().to_json())
      (Post, "/v1/contract-documents/worker/results") => {
        let decoded : ContractGenerationResult? = Some(
          @json.from_json(@json.parse(body)),
        ) catch {
          _ => None
        }
        guard decoded is Some(result) &&
          @contracts.valid_identifier(result.worker_receipt) else {
          return api_error(
            400, "InvalidRequest", "invalid contract generation result", false,
          )
        }
        let completed = try
          store.complete_generation(
            result.packet_id,
            result.expected_revision,
            result.docx,
            result.pdf,
            "contract-renderer",
            @async.now(),
          )
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        json_reply(200, completed.to_json())
      }
      (Post, "/v1/contract-documents/worker/failures") => {
        let decoded : ContractGenerationFailure? = Some(
          @json.from_json(@json.parse(body)),
        ) catch {
          _ => None
        }
        guard decoded is Some(failure) &&
          @contracts.valid_identifier(failure.worker_receipt) else {
          return api_error(
            400, "InvalidRequest", "invalid contract generation failure", false,
          )
        }
        let failed = try
          store.fail_generation(
            failure.packet_id,
            failure.expected_revision,
            failure.reason,
            "contract-renderer",
            @async.now(),
          )
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        json_reply(200, failed.to_json())
      }
      _ => api_error(404, "NotFound", "route was not found", false)
    }
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
    (Get, "/v1/contract-documents/manifest") =>
      json_reply(200, manifest.to_json())
    (Get, "/v1/contract-documents/self") =>
      json_reply(200, store.packets_for_subject(subject_ref).to_json())
    (Post, "/v1/contract-documents/self") => {
      let decoded : ContractPacketIntent? = Some(
        @json.from_json(@json.parse(body)),
      ) catch {
        _ => None
      }
      guard decoded is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid contract packet intent", false,
        )
      }
      let now = @async.now()
      let packet = try
        @contractdoc.new_packet(
          manifest,
          intent.packet_id,
          intent.idempotency_key,
          view.membership.tenant_ref,
          view.membership.organization_id,
          subject_ref,
          intent.order_ref,
          intent.preceding_packet_ref,
          intent.active_forms,
          now,
        )
      catch {
        error => return contract_document_error(error)
      } noraise {
        value => value
      }
      let persisted = try store.create_packet(packet, subject_ref) catch {
        error => return contract_document_error(error)
      } noraise {
        value => value
      }
      let synchronized = try
        synchronize_linked_contract_values(store, manifest, persisted)
      catch {
        error => return contract_document_error(error)
      } noraise {
        value => value
      }
      json_reply(201, synchronized.to_json())
    }
    (Post, _) if contract_packet_id(path, ":renew") is Some(source_packet_id) => {
      let decoded : ContractRenewalIntent? = Some(
        @json.from_json(@json.parse(body)),
      ) catch {
        _ => None
      }
      guard decoded is Some(intent) &&
        @contracts.valid_identifier(intent.packet_id) &&
        @contracts.valid_identifier(intent.idempotency_key) &&
        store.packet(source_packet_id) is Some(source) &&
        source.subject_ref == subject_ref else {
        return api_error(
          404, "ContractPacketNotFound", "contract packet was not found", false,
        )
      }
      let renewed = try
        store.renew_packet(
          source_packet_id,
          intent.packet_id,
          intent.idempotency_key,
          subject_ref,
          @async.now(),
        )
      catch {
        error => return contract_document_error(error)
      } noraise {
        value => value
      }
      json_reply(201, renewed.to_json())
    }
    (Put, _) if contract_packet_id(path, ":information") is Some(packet_id) => {
      let decoded : ContractInformationUpdate? = Some(
        @json.from_json(@json.parse(body)),
      ) catch {
        _ => None
      }
      guard decoded is Some(request) &&
        store.packet(packet_id) is Some(packet) &&
        packet.subject_ref == subject_ref else {
        return api_error(
          404, "ContractPacketNotFound", "contract packet was not found", false,
        )
      }
      let updated = try
        store.update_information(
          manifest,
          packet_id,
          request.expected_revision,
          request.changes,
          CustomerMessenger,
          subject_ref,
          "enterprise-portal",
          @async.now(),
        )
      catch {
        error => return contract_document_error(error)
      } noraise {
        value => value
      }
      json_reply(200, updated.to_json())
    }
    (Post, _) if contract_packet_id(path, ":preview") is Some(packet_id) => {
      let decoded : ContractPreviewIntent? = Some(
        @json.from_json(@json.parse(body)),
      ) catch {
        _ => None
      }
      guard decoded is Some(request) &&
        store.packet(packet_id) is Some(packet) &&
        packet.subject_ref == subject_ref else {
        return api_error(
          404, "ContractPacketNotFound", "contract packet was not found", false,
        )
      }
      moonleaf_contract_preview(manifest, packet, CustomerMessenger, request)
    }
    (Post, _) if contract_packet_id(path, ":confirm") is Some(packet_id) => {
      let decoded : ContractRevisionAction? = Some(
        @json.from_json(@json.parse(body)),
      ) catch {
        _ => None
      }
      guard decoded is Some(request) &&
        store.packet(packet_id) is Some(packet) &&
        packet.subject_ref == subject_ref else {
        return api_error(
          404, "ContractPacketNotFound", "contract packet was not found", false,
        )
      }
      let digest = "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(packet.canonical_values_material())))}"
      let updated = try
        store.confirm_information(
          manifest,
          packet_id,
          request.expected_revision,
          digest,
          subject_ref,
          @async.now(),
        )
      catch {
        error => return contract_document_error(error)
      } noraise {
        value => value
      }
      json_reply(200, updated.to_json())
    }
    (Post, _) if contract_packet_id(path, ":generate") is Some(packet_id) => {
      let decoded : ContractRevisionAction? = Some(
        @json.from_json(@json.parse(body)),
      ) catch {
        _ => None
      }
      guard decoded is Some(request) &&
        request.expected_values_sha256 is Some(digest) &&
        store.packet(packet_id) is Some(packet) &&
        packet.subject_ref == subject_ref else {
        return api_error(
          404, "ContractPacketNotFound", "contract packet was not found", false,
        )
      }
      let updated = try
        store.request_generation(
          packet_id,
          request.expected_revision,
          digest,
          subject_ref,
          @async.now(),
        )
      catch {
        error => return contract_document_error(error)
      } noraise {
        value => value
      }
      json_reply(202, updated.to_json())
    }
    _ => api_error(404, "NotFound", "route was not found", false)
  }
}
