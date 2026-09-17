///|
/// Authenticated operator issuance, never purchaser impersonation.
pub async fn OfflineCommerceStore::issue_operator_download_session(
  self : OfflineCommerceStore,
  session : @offline.OfflineTransferSession,
  tenant_ref~ : String,
  operator_ref~ : String,
) -> @offline.OfflineTransferSession {
  @offline.validate_transfer_session(session)
  if !@contracts.valid_identifier(operator_ref, maximum_length=240) ||
    session.subject_ref != "operator:\{operator_ref}" ||
    session.direction != DownloadTransfer ||
    session.state != TransferIssued ||
    session.consumed_unix_ms is Some(_) ||
    session.expires_unix_ms > session.issued_unix_ms + 120000L {
    raise @offline.OfflineCommerceError::Unauthorized
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let order = self.require_order_unlocked(session.order_id)
  if order.tenant_ref != tenant_ref ||
    order.organization_id != session.organization_id {
    raise @offline.OfflineCommerceError::TenantMismatch
  }
  guard self.artifacts.get(session.artifact_id) is Some(artifact) &&
    artifact.order_id == order.order_id &&
    artifact.organization_id == order.organization_id &&
    artifact.scan_state == ScanPassed &&
    session.media_types == [artifact.media_type] &&
    session.maximum_byte_count == artifact.byte_count &&
    session.expected_sha256 == Some(artifact.sha256) else {
    raise @offline.OfflineCommerceError::ArtifactUnavailable(
      "review artifact is not a verified byte-bound download",
    )
  }
  match self.transfer_sessions.get(session.session_id) {
    Some(existing) if existing == session => return existing
    Some(_) =>
      raise @offline.OfflineCommerceError::IdempotencyConflict(
        session.session_id,
      )
    None => ()
  }
  let before = self.transfer_sessions.copy()
  errdefer {
    self.transfer_sessions = before
  }
  self.transfer_sessions[session.session_id] = session
  self.persist()
  session
}
