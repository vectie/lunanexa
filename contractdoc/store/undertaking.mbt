///|
/// A revision reopens drafting but never erases evidence. Pending decisions
/// are rejected in the same snapshot; old artifacts remain in the audit log,
/// while the new version must be confirmed, rendered and signed again.
pub async fn ContractDocumentStore::revise_undertaking(
  self : ContractDocumentStore,
  packet_id : String,
  expected_revision : Int64,
  subject_ref : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  defer self.mutex.release()
  let before_packets = self.packets.copy()
  let before_approvals = self.approvals.copy()
  let before_events = self.events.copy()
  errdefer {
    self.packets = before_packets
    self.approvals = before_approvals
    self.events = before_events
  }
  guard self.packets.get(packet_id) is Some(packet) &&
    packet.subject_ref == subject_ref &&
    @contractdoc.is_undertaking_template(packet.template_id) else {
    raise @contractdoc.ContractDocumentError::NotFound("undertaking")
  }
  if packet.revision != expected_revision {
    raise @contractdoc.ContractDocumentError::StaleRevision
  }
  if packet.state == Effective ||
    packet.state == Closed ||
    packet.state == Superseded ||
    packet.state == GenerationRequested {
    raise @contractdoc.ContractDocumentError::InvalidTransition(
      "undertaking cannot be revised in this state",
    )
  }
  for id, approval in self.approvals {
    if approval.packet_id == packet_id &&
      (approval.status == Pending || approval.status == Approved) {
      self.approvals[id] = {
        ..approval,
        status: Rejected,
        decided_by: Some(subject_ref),
        decided_unix_ms: Some(now_unix_ms),
        decision_reason: Some("withdrawn for undertaking revision"),
      }
    }
  }
  let updated : @contractdoc.ContractPacket = {
    ..packet,
    values_sha256: None,
    confirmed_by: None,
    confirmed_unix_ms: None,
    artifacts: [],
    execution: None,
    generation_failure: None,
    state: if @contractdoc.missing_required_fields(
        @contractdoc.manifest_for_template_id(packet.template_id),
        packet,
      ).is_empty() {
      ReadyForConfirmation
    } else {
      InformationDraft
    },
    revision: packet.revision + 1L,
    updated_unix_ms: now_unix_ms,
  }
  self.packets[packet_id] = updated
  self.events.push(
    event_for(updated, InformationUpdated, subject_ref, [], None, now_unix_ms),
  )
  self.persist()
  updated
}
