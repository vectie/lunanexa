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
    guard bearer_authorized(headers, self.operator_token) else {
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
            "operator",
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
        guard decoded is Some(request) && store.packet(packet_id) is Some(_) else {
          return api_error(
            404, "ContractPacketNotFound", "contract packet was not found", false,
          )
        }
        let evidence : @contractdoc.ContractExecution = {
          evidence_sha256: request.evidence_sha256,
          signed_on: request.signed_on,
          registered_by: "operator",
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
        let updated = try
          store.close_packet(
            packet_id,
            request.expected_revision,
            request.kind,
            request.reason,
            "operator",
            now,
          )
        catch {
          error => return contract_document_error(error)
        } noraise {
          value => value
        }
        match settlement_check {
          Some(Matched(settlement_ref~, minor_units~)) =>
            self.operator_audit(
              "contract.settlement.reconciled",
              updated.packet_id,
              "settlement:\{settlement_ref}:amount-cny:\{@contractdoc.format_cny_minor_units(minor_units)}:ledger-matched",
            )
          Some(LedgerUnused(settlement_ref~)) =>
            self.operator_audit(
              "contract.settlement.ledger-unused",
              updated.packet_id,
              "settlement:\{settlement_ref}:ledger-not-in-use",
            )
          _ => ()
        }
        // Closing a master lease ends the access relationship, so every
        // still-active API credential of the subject is revoked. Superseded
        // packets deliberately do NOT trigger revocation: the successor
        // packet continues the relationship, so the `:supersede` branch
        // stays untouched.
        if updated.active_forms.contains(MasterLease) {
          match self.access_store {
            Some(access) => {
              let mut revoked_count = 0
              for
                credential in access.views_for_subject(
                  updated.tenant_ref,
                  updated.subject_ref,
                ) {
                if credential.revoked_unix_ms is None {
                  ignore(access.revoke(credential.key_id, now))
                  revoked_count += 1
                }
              }
              self.operator_audit(
                "access.api-key.revoke",
                updated.packet_id,
                "contract-close:\{updated.packet_id}:revoked-keys:\{revoked_count}",
              )
              if revoked_count > 0 {
                self.enqueue_subject_notification(
                  updated.tenant_ref,
                  updated.subject_ref,
                  "AccessCredentialsRevoked",
                  AccessCredential,
                  Warning,
                  updated.packet_id,
                  "contract-packet:\{updated.packet_id}:closed",
                  Map([
                    ("packet_id", updated.packet_id),
                    ("revoked_count", revoked_count.to_string()),
                  ]),
                  now,
                )
              }
            }
            None => ()
          }
        }
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
            "operator",
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
            "operator",
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
