///|
fn contract_document_path(path : String) -> Bool {
  path == "/v1/contract-documents" || path.has_prefix("/v1/contract-documents/")
}

///|
priv struct ContractPacketIntent {
  packet_id : String
  idempotency_key : String
  order_ref : String
  active_forms : Array[@contractdoc.ContractFormKind]
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
priv struct ContractGenerationResult {
  packet_id : String
  expected_revision : Int64
  docx : @contractdoc.ContractGeneratedArtifact
  pdf : @contractdoc.ContractGeneratedArtifact
  worker_receipt : String
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
    _ =>
      api_error(
        400, "ContractDocumentRejected", "contract document request was rejected",
        false,
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
  if path == "/v1/contract-documents/worker/pending" ||
    path == "/v1/contract-documents/worker/results" {
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
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
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
      json_reply(201, persisted.to_json())
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
