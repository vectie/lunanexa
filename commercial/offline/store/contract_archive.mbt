///|
/// Trusted renderer/storage callback, never customer input. `verified` attests
/// to durable byte/digest verification by the authenticated storage worker;
/// this store cannot itself prove remote object existence.
pub(all) struct ContractArchiveObject {
  artifact_id : String
  object_ref : String
  media_type : String
  sha256 : String
  byte_count : Int64
  storage_receipt : String
  stored_unix_ms : Int64
  verified : Bool
  active_content_detected : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractArchiveObject with Debug::{to_repr}

///|
pub extend ContractArchiveObject with Eq::{not_equal, equal}

///|
pub extend ContractArchiveObject with ToJson::{to_json}

///|
pub extend ContractArchiveObject with FromJson::{from_json}

///|
pub fn contract_archive_artifact_id(
  packet_id : String,
  revision : Int64,
  kind : @offline.DocumentArtifactKind,
) -> String raise @offline.OfflineCommerceError {
  if !@contracts.valid_identifier(packet_id) || revision <= 0L {
    raise InvalidInput("invalid contract archive identity")
  }
  let suffix = match kind {
    EditableContractDocx => "docx"
    PrintReadyContractPdf => "pdf"
    _ => raise InvalidInput("unsupported contract archive kind")
  }
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @utf8.encode("contract-archive.v1|\{packet_id}|\{revision}").to_fixedarray(),
    ),
  )
  "contract-\{digest}-\{suffix}"
}

///|
/// Opaque logical storage key, not a browser URL or a supplied filesystem path.
pub fn contract_archive_object_ref(
  organization_id : String,
  order_id : String,
  packet_id : String,
  revision : Int64,
  kind : @offline.DocumentArtifactKind,
) -> String raise @offline.OfflineCommerceError {
  if !@contracts.valid_identifier(organization_id) ||
    !@contracts.valid_identifier(order_id) {
    raise InvalidInput("invalid contract archive scope")
  }
  let scope = @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @utf8.encode("contract-scope.v1|\{organization_id}|\{order_id}").to_fixedarray(),
    ),
  )
  "object://contract-documents/\{scope}/\{contract_archive_artifact_id(packet_id, revision, kind)}"
}

///|
/// Atomically publishes BOTH already-stored artifacts into the commerce
/// authority. The API must validate the linked packet/revision and rendered
/// evidence first, then call this before completing the contract packet.
/// If the later contract-store write fails, replay this exact receipt pair;
/// immutable IDs and metadata make recovery idempotent, not a new generation.
pub async fn OfflineCommerceStore::archive_contract_generation(
  self : OfflineCommerceStore,
  tenant_ref~ : String,
  organization_id~ : String,
  subject_ref~ : String,
  order_id~ : String,
  packet_id~ : String,
  packet_revision~ : Int64,
  template_id~ : String,
  template_version~ : String,
  locale~ : String,
  now_unix_ms~ : Int64,
  docx~ : ContractArchiveObject,
  pdf~ : ContractArchiveObject,
) -> Array[@offline.DocumentArtifact] {
  if template_id != "youthpolicy-device-undertaking-v1" ||
    !@contracts.valid_identifier(template_version) ||
    !@contracts.valid_identifier(locale) {
    raise @offline.OfflineCommerceError::InvalidInput(
      "unsupported contract archive template",
    )
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let order = self.require_order_unlocked(order_id)
  if order.tenant_ref != tenant_ref ||
    order.organization_id != organization_id ||
    order.purchaser_subject_ref != subject_ref {
    raise @offline.OfflineCommerceError::TenantMismatch
  }
  let artifacts = []
  for
    item in [
      (docx, @offline.DocumentArtifactKind::EditableContractDocx),
      (pdf, PrintReadyContractPdf),
    ] {
    let (object, kind) = item
    if !object.verified ||
      object.active_content_detected ||
      object.artifact_id !=
      contract_archive_artifact_id(packet_id, packet_revision, kind) ||
      object.object_ref !=
      contract_archive_object_ref(
        organization_id, order_id, packet_id, packet_revision, kind,
      ) ||
      object.stored_unix_ms < order.created_unix_ms ||
      object.stored_unix_ms > now_unix_ms {
      raise @offline.OfflineCommerceError::ArtifactUnavailable(
        "contract archive storage verification failed",
      )
    }
    let artifact : @offline.DocumentArtifact = {
      artifact_id: object.artifact_id,
      order_id,
      organization_id,
      kind,
      revision: 1,
      template_id: Some(template_id),
      template_version: Some(template_version),
      locale,
      media_type: object.media_type,
      byte_count: object.byte_count,
      sha256: object.sha256,
      object_ref: object.object_ref,
      generation_state: ArtifactGenerated,
      scan_state: ScanPassed,
      review_state: ReviewNotRequired,
      submitted_by: subject_ref,
      creator_receipt: object.storage_receipt,
      created_unix_ms: object.stored_unix_ms,
    }
    self.validate_artifact_unlocked(artifact)
    match self.artifacts.get(artifact.artifact_id) {
      Some(existing) if existing != artifact =>
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          artifact.artifact_id,
        )
      _ => ()
    }
    artifacts.push(artifact)
  }
  if artifacts.all(artifact => {
      self.artifacts.contains(artifact.artifact_id) &&
      order.artifact_ids.contains(artifact.artifact_id)
    }) {
    return artifacts
  }
  if order.state == Cancelled ||
    order.state == Expired ||
    order.state == Rejected ||
    order.state == Revoked ||
    order.state == ReversalPending ||
    order.state == ReversalManualIntervention ||
    order.expires_unix_ms <= now_unix_ms {
    raise @offline.OfflineCommerceError::InvalidTransition(
      "contract archive order is no longer live",
    )
  }
  let before_artifacts = self.artifacts.copy()
  let before_orders = self.orders.copy()
  errdefer {
    self.artifacts = before_artifacts
    self.orders = before_orders
  }
  let mut updated = order
  for artifact in artifacts {
    self.artifacts[artifact.artifact_id] = artifact
    updated = with_artifact_id(
      updated,
      artifact.artifact_id,
      now_unix_ms.max(updated.updated_unix_ms),
    )
  }
  @offline.validate_order(updated)
  self.orders[order_id] = updated
  self.persist()
  artifacts
}
