///|
fn valid_governance_text(value : String, maximum : Int) -> Bool {
  let trimmed = value.trim()
  trimmed != "" &&
  trimmed.length() <= maximum &&
  trimmed.all(character => character != '\u{0000}')
}

///|
fn valid_digest(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].all(character => character.is_ascii_hexdigit())
}

///|
/// Returns the proleptic-Gregorian UTC year without depending on a host clock
/// or locale. Contract numbers must not drift by using a fixed 365-day year.
fn utc_year(now_unix_ms : Int64) -> Int {
  if now_unix_ms <= 0L {
    return 0
  }
  let days = now_unix_ms / 86400000L
  let z = days + 719468L
  let era = if z >= 0L { z / 146097L } else { (z - 146096L) / 146097L }
  let day_of_era = z - era * 146097L
  let year_of_era = (
      day_of_era -
      day_of_era / 1460L +
      day_of_era / 36524L -
      day_of_era / 146096L
    ) /
    365L
  let year = year_of_era + era * 400L
  let day_of_year = day_of_era -
    (365L * year_of_era + year_of_era / 4L - year_of_era / 100L)
  let month_part = (5L * day_of_year + 2L) / 153L
  let month_offset : Int64 = if month_part < 10L { 3L } else { -9L }
  let month = month_part + month_offset
  let year_offset : Int64 = if month <= 2L { 1L } else { 0L }
  (year + year_offset).to_int()
}

///|
/// The access authority is deliberately derived from the same durable packet
/// store that owns the contract. A packet that is merely generated, suspended
/// in a future version, or expired cannot authorize a credential.
pub async fn ContractDocumentStore::has_effective_master_lease(
  self : ContractDocumentStore,
  tenant_ref : String,
  subject_ref : String,
  now_unix_ms : Int64,
) -> Bool {
  self.mutex.acquire()
  let allowed = self.packets
    .values()
    .to_array()
    .any(packet => {
      packet.tenant_ref == tenant_ref &&
      packet.subject_ref == subject_ref &&
      packet.state == Effective &&
      packet.active_forms.contains(MasterLease) &&
      (match packet.value("lease.end_date") {
        Some(end_date) =>
          @contractdoc.days_until(end_date, now_unix_ms) is Some(days) &&
          days >= 0L
        None => true
      })
    })
  self.mutex.release()
  allowed
}

///|
pub async fn ContractDocumentStore::create_amendment(
  self : ContractDocumentStore,
  amendment : @contractdoc.ContractAmendment,
) -> @contractdoc.ContractAmendment {
  guard valid_governance_text(amendment.amendment_id, 128) &&
    valid_governance_text(amendment.packet_id, 128) &&
    valid_governance_text(amendment.preceding_packet_ref, 128) &&
    valid_governance_text(amendment.reason, 2000) &&
    amendment.packet_id == amendment.preceding_packet_ref &&
    amendment.changes.length() > 0 &&
    amendment.changes.length() <= 256 else {
    raise @contractdoc.ContractDocumentError::InvalidInput("invalid amendment")
  }
  self.mutex.acquire()
  let before = self.amendments.copy()
  try {
    guard !self.amendments.contains(amendment.amendment_id) else {
      raise @contractdoc.ContractDocumentError::AlreadyExists(
        amendment.amendment_id,
      )
    }
    guard self.packets.get(amendment.preceding_packet_ref) is Some(packet) &&
      packet.tenant_ref == amendment.tenant_ref &&
      packet.state == Effective &&
      packet.revision == amendment.base_revision else {
      raise @contractdoc.ContractDocumentError::InvalidTransition(
        "amendment must reference the current effective packet revision",
      )
    }
    self.amendments[amendment.amendment_id] = amendment
    self.persist()
    self.mutex.release()
    amendment
  } catch {
    error => {
      self.amendments = before
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::amendments_for_packet(
  self : ContractDocumentStore,
  packet_id : String,
) -> Array[@contractdoc.ContractAmendment] {
  self.mutex.acquire()
  let values = sorted_amendments(self.amendments).filter(value => {
    value.packet_id == packet_id
  })
  self.mutex.release()
  values
}

///|
pub async fn ContractDocumentStore::amendment(
  self : ContractDocumentStore,
  amendment_id : String,
) -> @contractdoc.ContractAmendment? {
  self.mutex.acquire()
  let value = self.amendments.get(amendment_id)
  self.mutex.release()
  value
}

///|
pub async fn ContractDocumentStore::obligation(
  self : ContractDocumentStore,
  obligation_id : String,
) -> @contractdoc.ContractObligation? {
  self.mutex.acquire()
  let value = self.obligations.get(obligation_id)
  self.mutex.release()
  value
}

///|
pub async fn ContractDocumentStore::settlement_draft(
  self : ContractDocumentStore,
  draft_id : String,
) -> @contractdoc.ContractSettlementDraft? {
  self.mutex.acquire()
  let value = self.settlement_drafts.get(draft_id)
  self.mutex.release()
  value
}

///|
pub async fn ContractDocumentStore::closure_proposal(
  self : ContractDocumentStore,
  proposal_id : String,
) -> @contractdoc.ContractClosureProposal? {
  self.mutex.acquire()
  let value = self.closure_proposals.get(proposal_id)
  self.mutex.release()
  value
}

///|
/// Approving an amendment changes only the amendment projection; the source
/// packet is never mutated. A later packet creation can consume the effective
/// amendment as its immutable predecessor.
pub async fn ContractDocumentStore::decide_amendment(
  self : ContractDocumentStore,
  amendment_id : String,
  approved : Bool,
  decided_by : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractAmendment {
  self.mutex.acquire()
  let before = self.amendments.copy()
  try {
    guard self.amendments.get(amendment_id) is Some(amendment) else {
      raise @contractdoc.ContractDocumentError::NotFound(amendment_id)
    }
    guard amendment.state == PendingApproval || amendment.state == Draft else {
      raise @contractdoc.ContractDocumentError::InvalidTransition(
        "amendment is no longer decidable",
      )
    }
    guard self.packets.get(amendment.preceding_packet_ref) is Some(packet) &&
      packet.tenant_ref == amendment.tenant_ref &&
      packet.state == Effective &&
      packet.revision == amendment.base_revision else {
      raise @contractdoc.ContractDocumentError::StaleRevision
    }
    if approved && decided_by == amendment.created_by {
      raise @contractdoc.ContractDocumentError::ContractApprovalSelfDecision(
        amendment_id,
      )
    }
    let next : @contractdoc.ContractAmendment = {
      ..amendment,
      state: if approved {
        Effective
      } else {
        Rejected
      },
      effective_unix_ms: if approved {
        Some(now_unix_ms)
      } else {
        None
      },
      updated_unix_ms: now_unix_ms,
      revision: amendment.revision + 1L,
    }
    self.amendments[amendment_id] = next
    self.persist()
    self.mutex.release()
    next
  } catch {
    error => {
      self.amendments = before
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Materializes one effective amendment into exactly one successor draft under
/// the store mutex. The predecessor lookup, successor uniqueness check,
/// idempotency reservation, field application, event append, and snapshot
/// write form one atomic mutation; concurrent requests cannot create siblings.
pub async fn ContractDocumentStore::materialize_amendment(
  self : ContractDocumentStore,
  amendment_id : String,
  packet_id : String,
  idempotency_key : String,
  actor_ref : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_keys = self.idempotency_keys.copy()
  let before_events = self.events.copy()
  try {
    guard self.amendments.get(amendment_id) is Some(amendment) &&
      amendment.state == Effective else {
      raise @contractdoc.ContractDocumentError::InvalidTransition(
        "amendment must be effective before materialization",
      )
    }
    let mut existing_successor : @contractdoc.ContractPacket? = None
    for existing in self.packets.values() {
      if existing.preceding_packet_ref == Some(amendment.preceding_packet_ref) &&
        existing.state != Superseded {
        existing_successor = Some(existing)
        break
      }
    }
    match existing_successor {
      Some(existing) if existing.packet_id == packet_id => {
        self.mutex.release()
        return existing
      }
      Some(_) =>
        raise @contractdoc.ContractDocumentError::AlreadyExists(
          "contract successor",
        )
      None => ()
    }
    if self.packets.contains(packet_id) ||
      self.idempotency_keys.contains(idempotency_key) {
      raise @contractdoc.ContractDocumentError::IdempotencyConflict(
        idempotency_key,
      )
    }
    guard self.packets.get(amendment.preceding_packet_ref) is Some(source) &&
      source.state == Effective &&
      source.revision == amendment.base_revision else {
      raise @contractdoc.ContractDocumentError::StaleRevision
    }
    let manifest = @contractdoc.manifest_for_template_id(source.template_id)
    let draft = source.renewal_draft(
      manifest, packet_id, idempotency_key, now_unix_ms,
    )
    let successor = draft.update_information(
      manifest,
      draft.revision,
      amendment.changes,
      ManagerOperator,
      actor_ref,
      "contract-amendment",
      now_unix_ms,
    )
    self.packets[successor.packet_id] = successor
    self.idempotency_keys[successor.idempotency_key] = successor.packet_id
    self.events.push(
      event_for(successor, PacketCreated, actor_ref, [], None, now_unix_ms),
    )
    self.events.push(
      event_for(
        successor,
        InformationUpdated,
        actor_ref,
        amendment.changes.map(change => change.field_id),
        None,
        now_unix_ms,
      ),
    )
    self.persist()
    self.mutex.release()
    successor
  } catch {
    error => {
      self.packets = before_packets
      self.idempotency_keys = before_keys
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::create_obligation(
  self : ContractDocumentStore,
  obligation : @contractdoc.ContractObligation,
) -> @contractdoc.ContractObligation {
  guard valid_governance_text(obligation.obligation_id, 128) &&
    valid_governance_text(obligation.packet_id, 128) &&
    valid_governance_text(obligation.owner_ref, 128) &&
    valid_governance_text(obligation.title, 500) &&
    obligation.due_unix_ms > 0L &&
    obligation.amount_minor_units.map_or(true, value => value >= 0L) else {
    raise @contractdoc.ContractDocumentError::InvalidInput("invalid obligation")
  }
  self.mutex.acquire()
  let before = self.obligations.copy()
  try {
    guard !self.obligations.contains(obligation.obligation_id) else {
      raise @contractdoc.ContractDocumentError::AlreadyExists(
        obligation.obligation_id,
      )
    }
    guard self.packets.get(obligation.packet_id) is Some(packet) &&
      packet.tenant_ref == obligation.tenant_ref &&
      packet.state == Effective else {
      raise @contractdoc.ContractDocumentError::ContractNotEffective(
        obligation.packet_id,
      )
    }
    self.obligations[obligation.obligation_id] = obligation
    self.persist()
    self.mutex.release()
    obligation
  } catch {
    error => {
      self.obligations = before
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::complete_obligation(
  self : ContractDocumentStore,
  obligation_id : String,
  expected_revision : Int64,
  completed_by : String,
  evidence_ref : String?,
  now_unix_ms : Int64,
) -> @contractdoc.ContractObligation {
  self.mutex.acquire()
  let before = self.obligations.copy()
  try {
    guard self.obligations.get(obligation_id) is Some(obligation) else {
      raise @contractdoc.ContractDocumentError::NotFound(obligation_id)
    }
    guard obligation.revision == expected_revision else {
      raise @contractdoc.ContractDocumentError::StaleRevision
    }
    guard obligation.state == Open || obligation.state == Overdue else {
      raise @contractdoc.ContractDocumentError::InvalidTransition(
        "obligation is not open",
      )
    }
    let next = {
      ..obligation,
      state: Completed,
      evidence_ref,
      completed_by: Some(completed_by),
      completed_unix_ms: Some(now_unix_ms),
      updated_unix_ms: now_unix_ms,
      revision: obligation.revision + 1L,
    }
    self.obligations[obligation_id] = next
    self.persist()
    self.mutex.release()
    next
  } catch {
    error => {
      self.obligations = before
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Waives an open or overdue obligation with an explicit operator decision.
pub async fn ContractDocumentStore::waive_obligation(
  self : ContractDocumentStore,
  obligation_id : String,
  expected_revision : Int64,
  waived_by : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractObligation {
  self.mutex.acquire()
  let before = self.obligations.copy()
  try {
    guard self.obligations.get(obligation_id) is Some(obligation) else {
      raise @contractdoc.ContractDocumentError::NotFound(obligation_id)
    }
    guard obligation.revision == expected_revision else {
      raise @contractdoc.ContractDocumentError::StaleRevision
    }
    guard obligation.state == Open || obligation.state == Overdue else {
      raise @contractdoc.ContractDocumentError::InvalidTransition(
        "obligation is not waivable",
      )
    }
    let next = {
      ..obligation,
      state: Waived,
      evidence_ref: Some("waived-by:\{waived_by}"),
      completed_by: Some(waived_by),
      completed_unix_ms: Some(now_unix_ms),
      updated_unix_ms: now_unix_ms,
      revision: obligation.revision + 1L,
    }
    self.obligations[obligation_id] = next
    self.persist()
    self.mutex.release()
    next
  } catch {
    error => {
      self.obligations = before
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Marks missed obligations overdue and returns the changed records.
pub async fn ContractDocumentStore::reconcile_obligations(
  self : ContractDocumentStore,
  now_unix_ms : Int64,
) -> Array[@contractdoc.ContractObligation] {
  self.mutex.acquire()
  let before = self.obligations.copy()
  let changed : Array[@contractdoc.ContractObligation] = []
  try {
    for obligation in sorted_obligations(self.obligations) {
      if obligation.state == Open && obligation.due_unix_ms < now_unix_ms {
        let next = {
          ..obligation,
          state: Overdue,
          updated_unix_ms: now_unix_ms,
          revision: obligation.revision + 1L,
        }
        self.obligations[obligation.obligation_id] = next
        changed.push(next)
      }
    }
    if changed.length() > 0 {
      self.persist()
    }
    self.mutex.release()
    changed
  } catch {
    error => {
      self.obligations = before
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::create_settlement_draft(
  self : ContractDocumentStore,
  draft : @contractdoc.ContractSettlementDraft,
) -> @contractdoc.ContractSettlementDraft {
  guard valid_governance_text(draft.draft_id, 128) &&
    valid_governance_text(draft.packet_id, 128) &&
    valid_digest(draft.ledger_snapshot_sha256) &&
    draft.amount_minor_units >= 0L else {
    raise @contractdoc.ContractDocumentError::InvalidInput(
      "invalid settlement draft",
    )
  }
  self.mutex.acquire()
  let before = self.settlement_drafts.copy()
  try {
    guard !self.settlement_drafts.contains(draft.draft_id) else {
      raise @contractdoc.ContractDocumentError::AlreadyExists(draft.draft_id)
    }
    guard self.packets.get(draft.packet_id) is Some(packet) &&
      packet.tenant_ref == draft.tenant_ref &&
      (packet.state == Effective || packet.state == Closed) else {
      raise @contractdoc.ContractDocumentError::NotFound(draft.packet_id)
    }
    self.settlement_drafts[draft.draft_id] = draft
    self.persist()
    self.mutex.release()
    draft
  } catch {
    error => {
      self.settlement_drafts = before
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::create_closure_proposal(
  self : ContractDocumentStore,
  proposal : @contractdoc.ContractClosureProposal,
) -> @contractdoc.ContractClosureProposal {
  guard valid_governance_text(proposal.proposal_id, 128) &&
    valid_governance_text(proposal.packet_id, 128) &&
    valid_governance_text(proposal.violation_packet_ref, 128) &&
    valid_governance_text(proposal.reason, 2000) else {
    raise @contractdoc.ContractDocumentError::InvalidInput(
      "invalid closure proposal",
    )
  }
  self.mutex.acquire()
  let before = self.closure_proposals.copy()
  try {
    guard !self.closure_proposals.contains(proposal.proposal_id) else {
      raise @contractdoc.ContractDocumentError::AlreadyExists(
        proposal.proposal_id,
      )
    }
    guard self.packets.get(proposal.packet_id) is Some(packet) &&
      self.packets.get(proposal.violation_packet_ref) is Some(violation) &&
      packet.tenant_ref == proposal.tenant_ref &&
      violation.tenant_ref == proposal.tenant_ref &&
      violation.active_forms.contains(ViolationNotice) else {
      raise @contractdoc.ContractDocumentError::NotFound(proposal.packet_id)
    }
    self.closure_proposals[proposal.proposal_id] = proposal
    self.persist()
    self.mutex.release()
    proposal
  } catch {
    error => {
      self.closure_proposals = before
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Approves or rejects a pending settlement draft.
pub async fn ContractDocumentStore::decide_settlement_draft(
  self : ContractDocumentStore,
  draft_id : String,
  approved : Bool,
  now_unix_ms : Int64,
) -> @contractdoc.ContractSettlementDraft {
  self.mutex.acquire()
  let before = self.settlement_drafts.copy()
  try {
    guard self.settlement_drafts.get(draft_id) is Some(draft) else {
      raise @contractdoc.ContractDocumentError::NotFound(draft_id)
    }
    guard draft.state == PendingApproval else {
      raise @contractdoc.ContractDocumentError::InvalidTransition(
        "settlement draft is no longer pending",
      )
    }
    let next = {
      ..draft,
      state: if approved {
        Approved
      } else {
        Rejected
      },
      created_by: draft.created_by,
      updated_unix_ms: now_unix_ms,
    }
    self.settlement_drafts[draft_id] = next
    self.persist()
    self.mutex.release()
    next
  } catch {
    error => {
      self.settlement_drafts = before
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Applies an approved settlement draft, leaving an auditable terminal state.
pub async fn ContractDocumentStore::apply_settlement_draft(
  self : ContractDocumentStore,
  draft_id : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractSettlementDraft {
  self.mutex.acquire()
  let before = self.settlement_drafts.copy()
  try {
    guard self.settlement_drafts.get(draft_id) is Some(draft) else {
      raise @contractdoc.ContractDocumentError::NotFound(draft_id)
    }
    guard draft.state == Approved else {
      raise @contractdoc.ContractDocumentError::InvalidTransition(
        "settlement draft must be approved before apply",
      )
    }
    let next = { ..draft, state: Applied, updated_unix_ms: now_unix_ms }
    self.settlement_drafts[draft_id] = next
    self.persist()
    self.mutex.release()
    next
  } catch {
    error => {
      self.settlement_drafts = before
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Approves or rejects a pending closure proposal.
pub async fn ContractDocumentStore::decide_closure_proposal(
  self : ContractDocumentStore,
  proposal_id : String,
  approved : Bool,
  now_unix_ms : Int64,
) -> @contractdoc.ContractClosureProposal {
  self.mutex.acquire()
  let before = self.closure_proposals.copy()
  try {
    guard self.closure_proposals.get(proposal_id) is Some(proposal) else {
      raise @contractdoc.ContractDocumentError::NotFound(proposal_id)
    }
    guard proposal.state == PendingApproval else {
      raise @contractdoc.ContractDocumentError::InvalidTransition(
        "closure proposal is no longer pending",
      )
    }
    let next = {
      ..proposal,
      state: if approved {
        Approved
      } else {
        Rejected
      },
      updated_unix_ms: now_unix_ms,
    }
    self.closure_proposals[proposal_id] = next
    self.persist()
    self.mutex.release()
    next
  } catch {
    error => {
      self.closure_proposals = before
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Applies an approved closure proposal after the operator has executed the
/// separate packet-close action.
pub async fn ContractDocumentStore::apply_closure_proposal(
  self : ContractDocumentStore,
  proposal_id : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractClosureProposal {
  self.mutex.acquire()
  let before = self.closure_proposals.copy()
  try {
    guard self.closure_proposals.get(proposal_id) is Some(proposal) else {
      raise @contractdoc.ContractDocumentError::NotFound(proposal_id)
    }
    guard proposal.state == Approved else {
      raise @contractdoc.ContractDocumentError::InvalidTransition(
        "closure proposal must be approved before apply",
      )
    }
    let next = { ..proposal, state: Applied, updated_unix_ms: now_unix_ms }
    self.closure_proposals[proposal_id] = next
    self.persist()
    self.mutex.release()
    next
  } catch {
    error => {
      self.closure_proposals = before
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::allocate_contract_number(
  self : ContractDocumentStore,
  tenant_ref : String,
  packet_id : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractNumber {
  guard valid_governance_text(tenant_ref, 128) &&
    valid_governance_text(packet_id, 128) else {
    raise @contractdoc.ContractDocumentError::InvalidInput(
      "invalid contract number scope",
    )
  }
  self.mutex.acquire()
  let before_numbers = self.numbers.copy()
  let before_sequences = self.number_sequences.copy()
  try {
    guard self.packets.get(packet_id) is Some(packet) &&
      packet.tenant_ref == tenant_ref else {
      raise @contractdoc.ContractDocumentError::NotFound(packet_id)
    }
    let existing_numbers = self.numbers.values().to_array()
    match existing_numbers.search_by(value => value.packet_id == packet_id) {
      Some(index) => {
        let existing = existing_numbers[index]
        self.mutex.release()
        return existing
      }
      None => ()
    }
    let sequence = self.number_sequences.get(tenant_ref).unwrap_or(0L) + 1L
    let year = utc_year(now_unix_ms).to_string()
    let number = "LN-\{year}-\{tenant_ref}-\{sequence}"
    let allocated : @contractdoc.ContractNumber = {
      number,
      tenant_ref,
      packet_id,
      sequence,
      issued_unix_ms: now_unix_ms,
    }
    self.numbers[number] = allocated
    self.number_sequences[tenant_ref] = sequence
    self.persist()
    self.mutex.release()
    allocated
  } catch {
    error => {
      self.numbers = before_numbers
      self.number_sequences = before_sequences
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::governance_dashboard(
  self : ContractDocumentStore,
  tenant_ref : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractGovernanceDashboard {
  self.mutex.acquire()
  let packets = self.packets
    .values()
    .to_array()
    .filter(packet => packet.tenant_ref == tenant_ref)
  let approvals = self.approvals
    .values()
    .to_array()
    .filter(approval => {
      approval.status == Pending &&
      packets.any(packet => packet.packet_id == approval.packet_id)
    })
  let obligations = self.obligations
    .values()
    .to_array()
    .filter(obligation => obligation.tenant_ref == tenant_ref)
  let proposals = self.closure_proposals
    .values()
    .to_array()
    .filter(proposal => {
      proposal.tenant_ref == tenant_ref &&
      (proposal.state == Draft || proposal.state == PendingApproval)
    })
  let effective = packets.filter(packet => packet.state == Effective)
  let mut total = 0L
  for obligation in obligations {
    total += obligation.amount_minor_units.unwrap_or(0L)
  }
  let mut next_expiry : Int64? = None
  for packet in effective {
    match packet.value("lease.end_date") {
      Some(value) =>
        match @contractdoc.calendar_date_days(value) {
          Some(days) => {
            let candidate = days * 86400000L
            if candidate >= now_unix_ms &&
              (
                next_expiry is None ||
                candidate < next_expiry.unwrap_or(candidate)
              ) {
              next_expiry = Some(candidate)
            }
          }
          None => ()
        }
      None => ()
    }
  }
  let dashboard : @contractdoc.ContractGovernanceDashboard = {
    tenant_ref,
    effective_packets: effective.length(),
    pending_approvals: approvals.length(),
    overdue_obligations: obligations
    .filter(value => value.state == Overdue)
    .length(),
    open_closure_proposals: proposals.length(),
    total_amount_minor_units: total,
    next_expiry_unix_ms: next_expiry,
    generated_unix_ms: now_unix_ms,
  }
  self.mutex.release()
  dashboard
}

///|
/// Returns the authoritative settlement confirmation for a tenant. Callers
/// use this before applying any ledger reconciliation, while the store uses
/// the same selector for its final close gate.
pub async fn ContractDocumentStore::latest_settlement_confirmation(
  self : ContractDocumentStore,
  tenant_ref : String,
  excluded_packet_id : String,
) -> @contractdoc.ContractPacket? {
  self.mutex.acquire()
  let selected = latest_settlement_confirmation_locked(
    self.packets,
    tenant_ref,
    excluded_packet_id,
  )
  self.mutex.release()
  selected
}
