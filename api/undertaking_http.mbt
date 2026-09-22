///|
priv struct UndertakingSubmission {
  expected_revision : Int64
  evidence_artifact_id : String
  signed_on : String
} derive(FromJson)

///|
fn undertaking_order_live(
  order : @offline.CommercialOrder,
  now : Int64,
) -> Bool {
  (
    order.expires_unix_ms > now ||
    order.state == Fulfilled ||
    order.state == FulfillmentPending
  ) &&
  (match order.state {
    Draft
    | NeedsCorrection
    | Cancelled
    | Expired
    | Rejected
    | Revoked
    | ReversalPending
    | ReversalManualIntervention => false
    _ => true
  })
}

///|
/// The undertaking's fixed tariff is not a negotiable contract quote. One
/// quote line selects one term and its quantity is the device count.
fn undertaking_quote_matches(
  packet : @contractdoc.ContractPacket,
  order : @offline.CommercialOrder,
) -> Bool {
  guard order.quote is Some(quote) &&
    @offline.undertaking_quote_term(order) is Some(days) &&
    packet.value("lease.total_rent") is Some(amount) &&
    @contractdoc.parse_cny_minor_units(amount) == Some(quote.total.minor_units) &&
    packet.value("lease.start_date") is Some(start) &&
    packet.value("lease.end_date") is Some(end) &&
    @contractdoc.calendar_date_days(start) is Some(start_day) &&
    @contractdoc.calendar_date_days(end) is Some(end_day) else {
    return false
  }
  end_day - start_day + 1L == days
}

///|
/// Reads existing scanned and independently reviewed evidence; a browser
/// string, payment obligation or approval checkbox cannot stand in for it.
fn undertaking_evidence_valid(
  snapshot : @offline.OfflineCommerceSnapshot,
  packet : @contractdoc.ContractPacket,
  evidence_sha256 : String,
  require_review : Bool,
  now : Int64,
) -> Bool {
  guard snapshot.orders
    .filter(order => order.order_id == packet.order_ref)
    .get(0)
    is Some(order) &&
    order.tenant_ref == packet.tenant_ref &&
    order.organization_id == packet.organization_id &&
    order.purchaser_subject_ref == packet.subject_ref &&
    undertaking_order_live(order, now) &&
    undertaking_quote_matches(packet, order) else {
    return false
  }
  let rendered_at = packet.artifacts.fold(init=0L, (latest, artifact) => {
    latest.max(artifact.generated_unix_ms)
  })
  let signed = snapshot.artifacts.any(artifact => {
    artifact.order_id == order.order_id &&
    artifact.organization_id == packet.organization_id &&
    order.artifact_ids.contains(artifact.artifact_id) &&
    artifact.kind == ExecutedContractScan &&
    artifact.sha256 == evidence_sha256 &&
    artifact.submitted_by == packet.subject_ref &&
    artifact.generation_state == UserUploaded &&
    artifact.scan_state == ScanPassed &&
    artifact.created_unix_ms >= rendered_at &&
    rendered_at > 0L &&
    (!require_review || artifact.review_state == ReviewAccepted)
  })
  let paid = !require_review ||
    snapshot.artifacts.any(artifact => {
      artifact.order_id == order.order_id &&
      artifact.organization_id == packet.organization_id &&
      order.artifact_ids.contains(artifact.artifact_id) &&
      artifact.kind == PaymentReceipt &&
      artifact.scan_state == ScanPassed &&
      artifact.review_state == ReviewAccepted &&
      snapshot.reviews.any(review => {
        review.order_id == order.order_id &&
        review.artifact_id == artifact.artifact_id &&
        review.expected_artifact_sha256 == artifact.sha256 &&
        review.accepted &&
        review.reviewer_ref != artifact.submitted_by &&
        order.quote.map_or(false, quote => {
          review.reviewed_unix_ms >= quote.created_unix_ms
        }) &&
        review.reason_code == "FullPrepaymentVerified"
      })
    })
  signed && paid
}

///|
/// Preserve the legacy contract policy, but an undertaking also requires
/// its live prepaid order on every authorization, including after refunds.
async fn ApiService::has_effective_rental_authority(
  self : ApiService,
  documents : @contractdoc_store.ContractDocumentStore,
  tenant : String,
  subject : String,
  now : Int64,
  organization_id? : String,
) -> Bool {
  for packet in documents.packets_for_subject(subject) {
    if packet.tenant_ref != tenant ||
      packet.state != Effective ||
      !packet.active_forms.contains(MasterLease) {
      continue
    }
    if !@contractdoc.is_undertaking_template(packet.template_id) {
      if packet
        .value("lease.end_date")
        .map_or(true, end => {
          @contractdoc.days_until(end, now).map_or(false, days => days >= 0L)
        }) {
        return true
      }
      continue
    }
    guard organization_id == Some(packet.organization_id) &&
      self.offline_commerce_store is Some(commerce) &&
      packet.execution is Some(execution) &&
      packet.value("lease.start_date") is Some(start) &&
      packet.value("lease.end_date") is Some(end) &&
      @contractdoc.days_until(start, now).map_or(false, days => days <= 0L) &&
      @contractdoc.days_until(end, now).map_or(false, days => days >= 0L) else {
      continue
    }
    if undertaking_evidence_valid(
        commerce.snapshot(),
        packet,
        execution.evidence_sha256,
        true,
        now,
      ) {
      return true
    }
  }
  false
}

///|
async fn ApiService::undertaking_fulfillment_allowed(
  self : ApiService,
  order_id : String,
  now : Int64,
) -> Bool {
  if self.offline_commerce_store is Some(commerce) &&
    commerce.snapshot().orders.iter().find_first(o => o.order_id == order_id)
    is Some(order) &&
    order.technical_acceptance_waiver is Some(_) {
    return self.technical_documentary_waiver_allowed(order, now)
  }
  guard self.contract_document_store is Some(documents) else { return true }
  for packet in documents.snapshot().packets {
    if packet.order_ref != order_id ||
      !@contractdoc.is_undertaking_template(packet.template_id) {
      continue
    }
    guard packet.state == Effective &&
      packet.execution is Some(execution) &&
      packet.value("lease.start_date") is Some(start) &&
      packet.value("lease.end_date") is Some(end) &&
      @contractdoc.days_until(start, now).map_or(false, days => days <= 0L) &&
      @contractdoc.days_until(end, now).map_or(false, days => days >= 0L) &&
      self.offline_commerce_store is Some(commerce) else {
      return false
    }
    return undertaking_evidence_valid(
      commerce.snapshot(),
      packet,
      execution.evidence_sha256,
      true,
      now,
    )
  }
  true
}
