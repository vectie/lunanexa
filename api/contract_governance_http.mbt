///|
/// A compact governance API keeps amendments, obligations, proposals, numbers,
/// and the operator dashboard on the same durable ContractDocumentStore.
fn contract_governance_path(path : String) -> Bool {
  path == "/v1/contract-governance" ||
  path.has_prefix("/v1/contract-governance/")
}

///|
/// Request fingerprints keep server-generated governance identifiers unique
/// when two submissions arrive in the same millisecond. They are not a
/// substitute for a client idempotency key, but prevent unrelated retries or
/// records from colliding on a timestamp-only ID.
fn governance_request_fingerprint(body : String) -> String {
  digest_hex(body)[:16].to_owned()
}

///|
priv struct ContractAmendmentRequest {
  preceding_packet_ref : String
  base_revision : Int64
  reason : String
  changes : Array[@contractdoc.ContractFieldValue]
} derive(FromJson)

///|
priv struct ContractAmendmentMaterializeRequest {
  packet_id : String
  idempotency_key : String
} derive(FromJson)

///|
priv struct ContractObligationRequest {
  packet_id : String
  tenant_ref : String
  kind : @contractdoc.ContractObligationKind
  title : String
  owner_ref : String
  due_unix_ms : Int64
  amount_minor_units : Int64?
} derive(FromJson)

///|
priv struct ContractObligationCompleteRequest {
  expected_revision : Int64
  evidence_ref : String?
} derive(FromJson)

///|
priv struct ContractObligationWaiveRequest {
  expected_revision : Int64
} derive(FromJson)

///|
priv struct ContractSettlementDraftRequest {
  ledger_snapshot_sha256 : String
  amount_minor_units : Int64
} derive(FromJson)

///|
priv struct ContractClosureProposalRequest {
  violation_packet_ref : String
  reason : String
} derive(FromJson)

///|
priv struct ContractGovernanceTenantRequest {
  tenant_ref : String
} derive(FromJson)

///|
priv struct ContractAdmissionRequest {
  tenant_ref : String
  subject_ref : String
} derive(FromJson)

///|
async fn ApiService::handle_contract_governance(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.operator_identity(headers) is Some(operator_id) else {
    return api_error(
      401, "Unauthenticated", "valid operator authority is required", false,
    )
  }
  guard self.contract_document_store is Some(store) else {
    return api_error(
      503, "ContractStoreUnavailable", "durable contract governance is unavailable",
      true,
    )
  }
  let now = @async.now()
  match (verb, path) {
    (Post, "/v1/contract-governance/operator/admission") => {
      let request : ContractAdmissionRequest = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "tenant_ref and subject_ref are required", false,
          )
      }
      let effective = store.has_effective_master_lease(
        request.tenant_ref,
        request.subject_ref,
        now,
      )
      let exclusive = match self.exclusive_lease_store {
        Some(leases) =>
          leases
          .leases_for_subject(request.subject_ref)
          .any(lease => lease.state == Active || lease.state == Expiring)
        None => false
      }
      let view : @contractdoc.ContractAdmissionView = {
        tenant_ref: request.tenant_ref,
        subject_ref: request.subject_ref,
        effective_master_lease: effective,
        api_key_issuance_allowed: effective,
        workspace_admission_configured: self.require_workspace_lease,
        exclusive_lease_present: exclusive,
        evaluated_unix_ms: now,
      }
      json_reply(200, view.to_json())
    }
    (Post, "/v1/contract-governance/operator/dashboard") => {
      let request : ContractGovernanceTenantRequest = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "tenant_ref is required", false,
          )
      }
      json_reply(
        200,
        store.governance_dashboard(request.tenant_ref, now).to_json(),
      )
    }
    (Post, "/v1/contract-governance/operator/amendments") => {
      let request : ContractAmendmentRequest = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "invalid amendment request", false,
          )
      }
      let packet_id = request.preceding_packet_ref
      let packet = match store.packet(packet_id) {
        Some(value) => value
        None =>
          return api_error(
            404, "NotFound", "effective packet was not found", false,
          )
      }
      let manifest = @contractdoc.manifest_for_template_id(packet.template_id)
      guard request.changes.length() > 0 &&
        request.changes.all(change => {
          match manifest.field(change.field_id) {
            Some(definition) =>
              packet.active_forms.contains(definition.form) &&
              definition.owner == ManagerOperator
            None => false
          }
        }) else {
        return api_error(
          409, "AmendmentOwnerBoundary", "operator amendments may change only operator-owned fields",
          false,
        )
      }
      let amendment : @contractdoc.ContractAmendment = {
        amendment_id: "amendment-\{packet_id}-\{governance_request_fingerprint(body)}",
        tenant_ref: packet.tenant_ref,
        packet_id,
        preceding_packet_ref: request.preceding_packet_ref,
        base_revision: request.base_revision,
        changes: request.changes,
        reason: request.reason,
        state: PendingApproval,
        effective_unix_ms: None,
        created_by: operator_id,
        created_unix_ms: now,
        updated_unix_ms: now,
        revision: 1L,
      }
      match store.amendment(amendment.amendment_id) {
        Some(existing) => json_reply(200, existing.to_json())
        None => {
          let created = try store.create_amendment(amendment) catch {
            _ =>
              return api_error(
                409, "AmendmentRejected", "amendment was rejected", false,
              )
          } noraise {
            value => value
          }
          self.operator_audit_as(
            operator_id,
            "contract.amendment.create",
            packet_id,
            created.amendment_id,
          )
          json_reply(201, created.to_json())
        }
      }
    }
    (Post, _) if path.has_suffix(":approve") &&
      path.has_prefix("/v1/contract-governance/operator/amendments/") => {
      let amendment_id = path["/v1/contract-governance/operator/amendments/".length():path.length() -
      ":approve".length()].to_owned()
      let approved = store.decide_amendment(
        amendment_id, true, operator_id, now,
      ) catch {
        _ =>
          return api_error(
            409, "AmendmentRejected", "amendment approval was rejected", false,
          )
      }
      self.operator_audit_as(
        operator_id, "contract.amendment.approve", amendment_id, "amendment:effective",
      )
      json_reply(200, approved.to_json())
    }
    (Post, _) if path.has_suffix(":materialize") &&
      path.has_prefix("/v1/contract-governance/operator/amendments/") => {
      let amendment_id = path["/v1/contract-governance/operator/amendments/".length():path.length() -
      ":materialize".length()].to_owned()
      let request : ContractAmendmentMaterializeRequest = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "packet_id and idempotency_key are required",
            false,
          )
      }
      let amendment = match store.amendment(amendment_id) {
        Some(value) if value.state == Effective => value
        _ =>
          return api_error(
            409, "AmendmentNotEffective", "amendment must be effective before materialization",
            false,
          )
      }
      match store.successor_packet(amendment.preceding_packet_ref) {
        Some(existing) if existing.packet_id != request.packet_id =>
          return api_error(
            409, "AmendmentMaterializationRejected", "this amendment already has a successor packet",
            false,
          )
        _ => ()
      }
      let successor = store.renew_packet(
        amendment.preceding_packet_ref,
        request.packet_id,
        request.idempotency_key,
        operator_id,
        now,
      ) catch {
        _ =>
          return api_error(
            409, "AmendmentMaterializationRejected", "successor packet could not be created",
            false,
          )
      }
      let needs_changes = amendment.changes.any(change => {
        successor.value(change.field_id) != Some(change.value)
      })
      if needs_changes && successor.revision != 1L {
        return api_error(
          409, "AmendmentMaterializationRejected", "the successor draft changed after amendment materialization",
          false,
        )
      }
      let successor = if !needs_changes {
        successor
      } else {
        store.update_information(
          @contractdoc.manifest_for_template_id(successor.template_id),
          successor.packet_id,
          successor.revision,
          amendment.changes,
          ManagerOperator,
          operator_id,
          "contract-amendment",
          now,
        ) catch {
          _ =>
            return api_error(
              409, "AmendmentMaterializationRejected", "approved amendment fields could not be applied to the successor draft",
              false,
            )
        }
      }
      self.operator_audit_as(
        operator_id,
        "contract.amendment.materialize",
        amendment_id,
        successor.packet_id,
      )
      json_reply(201, {
        "amendment": amendment.to_json(),
        "successor": successor.to_json(),
      })
    }
    (Post, "/v1/contract-governance/operator/obligations") => {
      let request : ContractObligationRequest = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "invalid obligation request", false,
          )
      }
      let obligation : @contractdoc.ContractObligation = {
        obligation_id: "obligation-\{request.packet_id}-\{governance_request_fingerprint(body)}",
        tenant_ref: request.tenant_ref,
        packet_id: request.packet_id,
        kind: request.kind,
        title: request.title,
        owner_ref: request.owner_ref,
        due_unix_ms: request.due_unix_ms,
        amount_minor_units: request.amount_minor_units,
        state: Open,
        evidence_ref: None,
        completed_by: None,
        completed_unix_ms: None,
        created_unix_ms: now,
        updated_unix_ms: now,
        revision: 1L,
      }
      match store.obligation(obligation.obligation_id) {
        Some(existing) => json_reply(200, existing.to_json())
        None => {
          let created = store.create_obligation(obligation) catch {
            _ =>
              return api_error(
                409, "ObligationRejected", "obligation was rejected", false,
              )
          }
          self.operator_audit_as(
            operator_id,
            "contract.obligation.create",
            request.packet_id,
            created.obligation_id,
          )
          json_reply(201, created.to_json())
        }
      }
    }
    (Post, _) if path.has_suffix(":complete") &&
      path.has_prefix("/v1/contract-governance/operator/obligations/") => {
      let obligation_id = path["/v1/contract-governance/operator/obligations/".length():path.length() -
      ":complete".length()].to_owned()
      let request : ContractObligationCompleteRequest = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "invalid obligation completion", false,
          )
      }
      let completed = store.complete_obligation(
        obligation_id,
        request.expected_revision,
        operator_id,
        request.evidence_ref,
        now,
      ) catch {
        _ =>
          return api_error(
            409, "ObligationRejected", "obligation completion was rejected", false,
          )
      }
      self.operator_audit_as(
        operator_id, "contract.obligation.complete", obligation_id, "obligation:completed",
      )
      json_reply(200, completed.to_json())
    }
    (Post, _) if path.has_suffix(":waive") &&
      path.has_prefix("/v1/contract-governance/operator/obligations/") => {
      let obligation_id = path["/v1/contract-governance/operator/obligations/".length():path.length() -
      ":waive".length()].to_owned()
      let request : ContractObligationWaiveRequest = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "invalid obligation waiver", false,
          )
      }
      let waived = store.waive_obligation(
        obligation_id,
        request.expected_revision,
        operator_id,
        now,
      ) catch {
        _ =>
          return api_error(
            409, "ObligationRejected", "obligation waiver was rejected", false,
          )
      }
      self.operator_audit_as(
        operator_id, "contract.obligation.waive", obligation_id, "obligation:waived",
      )
      json_reply(200, waived.to_json())
    }
    (Post, _) if path.has_suffix("/settlement-drafts") &&
      path.has_prefix("/v1/contract-governance/operator/packets/") => {
      let packet_id = path["/v1/contract-governance/operator/packets/".length():path.length() -
      "/settlement-drafts".length()].to_owned()
      let request : ContractSettlementDraftRequest = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "invalid settlement draft", false,
          )
      }
      let packet = match store.packet(packet_id) {
        Some(value) => value
        None => return api_error(404, "NotFound", "packet was not found", false)
      }
      let draft : @contractdoc.ContractSettlementDraft = {
        draft_id: "settlement-draft-\{packet_id}-\{governance_request_fingerprint(body)}",
        packet_id,
        tenant_ref: packet.tenant_ref,
        ledger_snapshot_sha256: request.ledger_snapshot_sha256,
        amount_minor_units: request.amount_minor_units,
        state: PendingApproval,
        created_by: operator_id,
        created_unix_ms: now,
        updated_unix_ms: now,
      }
      match store.settlement_draft(draft.draft_id) {
        Some(existing) => json_reply(200, existing.to_json())
        None => {
          let created = store.create_settlement_draft(draft) catch {
            _ =>
              return api_error(
                409, "SettlementDraftRejected", "settlement draft was rejected",
                false,
              )
          }
          self.operator_audit_as(
            operator_id,
            "contract.settlement-draft.create",
            packet_id,
            created.draft_id,
          )
          json_reply(201, created.to_json())
        }
      }
    }
    (Post, _) if path.has_suffix(":draft-settlement") &&
      path.has_prefix("/v1/contract-governance/operator/packets/") => {
      let packet_id = path["/v1/contract-governance/operator/packets/".length():path.length() -
      ":draft-settlement".length()].to_owned()
      let packet = match store.packet(packet_id) {
        Some(value) => value
        None => return api_error(404, "NotFound", "packet was not found", false)
      }
      let summary = try
        self.commercial_store.summary(packet.organization_id, "CNY", 2, now)
      catch {
        _ =>
          return api_error(
            409, "SettlementDraftRejected", "ledger summary is unavailable or uses mixed currencies",
            false,
          )
      } noraise {
        value => value
      }
      let digest_input = summary.to_json().stringify()
      let ledger_digest = "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(digest_input)))}"
      let draft : @contractdoc.ContractSettlementDraft = {
        draft_id: "settlement-draft-\{packet_id}-\{governance_request_fingerprint(digest_input)}",
        packet_id,
        tenant_ref: packet.tenant_ref,
        ledger_snapshot_sha256: ledger_digest,
        amount_minor_units: summary.provisional_total.minor_units,
        state: PendingApproval,
        created_by: operator_id,
        created_unix_ms: now,
        updated_unix_ms: now,
      }
      match store.settlement_draft(draft.draft_id) {
        Some(existing) => json_reply(200, existing.to_json())
        None => {
          let created = store.create_settlement_draft(draft) catch {
            _ =>
              return api_error(
                409, "SettlementDraftRejected", "settlement draft was rejected",
                false,
              )
          }
          self.operator_audit_as(
            operator_id,
            "contract.settlement-draft.auto",
            packet_id,
            created.draft_id,
          )
          json_reply(201, created.to_json())
        }
      }
    }
    (Post, _) if path.has_suffix("/closure-proposals") &&
      path.has_prefix("/v1/contract-governance/operator/packets/") => {
      let packet_id = path["/v1/contract-governance/operator/packets/".length():path.length() -
      "/closure-proposals".length()].to_owned()
      let request : ContractClosureProposalRequest = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "invalid closure proposal", false,
          )
      }
      let packet = match store.packet(packet_id) {
        Some(value) => value
        None => return api_error(404, "NotFound", "packet was not found", false)
      }
      let proposal : @contractdoc.ContractClosureProposal = {
        proposal_id: "closure-proposal-\{packet_id}-\{governance_request_fingerprint(body)}",
        packet_id,
        tenant_ref: packet.tenant_ref,
        violation_packet_ref: request.violation_packet_ref,
        reason: request.reason,
        state: PendingApproval,
        created_by: operator_id,
        created_unix_ms: now,
        updated_unix_ms: now,
      }
      match store.closure_proposal(proposal.proposal_id) {
        Some(existing) => json_reply(200, existing.to_json())
        None => {
          let created = store.create_closure_proposal(proposal) catch {
            _ =>
              return api_error(
                409, "ClosureProposalRejected", "closure proposal was rejected",
                false,
              )
          }
          self.operator_audit_as(
            operator_id,
            "contract.closure-proposal.create",
            packet_id,
            created.proposal_id,
          )
          json_reply(201, created.to_json())
        }
      }
    }
    (Post, _) if path.has_suffix(":number") &&
      path.has_prefix("/v1/contract-governance/operator/packets/") => {
      let packet_id = path["/v1/contract-governance/operator/packets/".length():path.length() -
      ":number".length()].to_owned()
      let packet = match store.packet(packet_id) {
        Some(value) => value
        None => return api_error(404, "NotFound", "packet was not found", false)
      }
      let number = store.allocate_contract_number(
        packet.tenant_ref,
        packet_id,
        now,
      ) catch {
        _ =>
          return api_error(
            409, "ContractNumberRejected", "contract number allocation was rejected",
            false,
          )
      }
      self.operator_audit_as(
        operator_id,
        "contract.number.allocate",
        packet_id,
        number.number,
      )
      json_reply(201, number.to_json())
    }
    (Post, _) if path.has_prefix(
        "/v1/contract-governance/operator/settlement-drafts/",
      ) &&
      path.has_suffix(":approve") => {
      let draft_id = path["/v1/contract-governance/operator/settlement-drafts/".length():path.length() -
      ":approve".length()].to_owned()
      let decided = store.decide_settlement_draft(draft_id, true, now) catch {
        _ =>
          return api_error(
            409, "SettlementDraftRejected", "settlement draft approval was rejected",
            false,
          )
      }
      self.operator_audit_as(
        operator_id, "contract.settlement-draft.approve", draft_id, "Approved",
      )
      json_reply(200, decided.to_json())
    }
    (Post, _) if path.has_prefix(
        "/v1/contract-governance/operator/settlement-drafts/",
      ) &&
      path.has_suffix(":apply") => {
      let draft_id = path["/v1/contract-governance/operator/settlement-drafts/".length():path.length() -
      ":apply".length()].to_owned()
      let applied = store.apply_settlement_draft(draft_id, now) catch {
        _ =>
          return api_error(
            409, "SettlementDraftRejected", "settlement draft apply was rejected",
            false,
          )
      }
      self.operator_audit_as(
        operator_id, "contract.settlement-draft.apply", draft_id, "Applied",
      )
      json_reply(200, applied.to_json())
    }
    (Post, _) if path.has_prefix(
        "/v1/contract-governance/operator/closure-proposals/",
      ) &&
      path.has_suffix(":approve") => {
      let proposal_id = path["/v1/contract-governance/operator/closure-proposals/".length():path.length() -
      ":approve".length()].to_owned()
      let decided = store.decide_closure_proposal(proposal_id, true, now) catch {
        _ =>
          return api_error(
            409, "ClosureProposalRejected", "closure proposal approval was rejected",
            false,
          )
      }
      self.operator_audit_as(
        operator_id, "contract.closure-proposal.approve", proposal_id, "Approved",
      )
      json_reply(200, decided.to_json())
    }
    (Post, _) if path.has_prefix(
        "/v1/contract-governance/operator/closure-proposals/",
      ) &&
      path.has_suffix(":apply") => {
      let proposal_id = path["/v1/contract-governance/operator/closure-proposals/".length():path.length() -
      ":apply".length()].to_owned()
      let applied = store.apply_closure_proposal(proposal_id, now) catch {
        _ =>
          return api_error(
            409, "ClosureProposalRejected", "closure proposal apply was rejected",
            false,
          )
      }
      self.operator_audit_as(
        operator_id, "contract.closure-proposal.apply", proposal_id, "Applied",
      )
      json_reply(200, applied.to_json())
    }
    _ =>
      api_error(
        404, "NotFound", "contract governance route was not found", false,
      )
  }
}

///|
/// Reconciles overdue payment/acceptance obligations without relying on a
/// browser read. The store mutation is revisioned and restart durable.
pub async fn ApiService::reconcile_contract_governance(
  self : ApiService,
  now_unix_ms : Int64,
) -> Unit {
  match self.contract_document_store {
    Some(store) => {
      let overdue = store.reconcile_obligations(now_unix_ms)
      match self.notification_store {
        Some(notifications) =>
          for obligation in overdue {
            ignore(
              notifications.enqueue({
                version: @notifications.contract_version,
                notification_id: "contract-obligation-overdue-\{obligation.obligation_id}",
                deduplication_key: "contract-obligation-overdue-\{obligation.obligation_id}",
                source_receipt: "contract-governance:obligation:\{obligation.obligation_id}:overdue",
                topic: CommercialAction,
                code: "ContractObligationOverdue",
                severity: Warning,
                audience: TenantUsers(tenant_ref=obligation.tenant_ref),
                title_key: "alerts.contract_obligation_overdue.title",
                body_key: "alerts.contract_obligation_overdue.body",
                parameters: {
                  "obligation_ref": obligation.obligation_id,
                  "packet_ref": obligation.packet_id,
                  "due_unix_ms": obligation.due_unix_ms.to_string(),
                },
                created_unix_ms: now_unix_ms,
                expires_unix_ms: None,
              }),
            )
          }
        None => ()
      }
    }
    None => ()
  }
}
