///|
/// Outcome of comparing the qualifying settlement packet against the
/// organization's commercial ledger before an early-termination close.
priv enum SettlementLedgerCheck {
  LedgerUnused(settlement_ref~ : String)
  Matched(settlement_ref~ : String, minor_units~ : Int64)
  Mismatched(String)
}

///|
/// Finds the most recently updated effective (or closed) settlement
/// confirmation for the packet's tenant — mirroring the store's own gate in
/// `ContractDocumentStore::close_packet` — and compares its
/// `settlement.amount_due` against the organization's ledger provisional
/// total. An organization without any ledger entries has no ledger in use,
/// so the comparison is skipped rather than blocking the close. `None` means
/// no qualifying settlement exists; the store's own gate then rejects the
/// close.
async fn ApiService::check_settlement_against_ledger(
  self : ApiService,
  packet : @contractdoc.ContractPacket,
  now_unix_ms : Int64,
) -> SettlementLedgerCheck? {
  guard self.contract_document_store is Some(store) else { return None }
  let mut settlement : @contractdoc.ContractPacket? = None
  for other in store.snapshot().packets {
    if other.packet_id != packet.packet_id &&
      other.tenant_ref == packet.tenant_ref &&
      other.active_forms.contains(SettlementConfirmation) &&
      (other.state == Effective || other.state == Closed) {
      match settlement {
        Some(current) if current.updated_unix_ms >= other.updated_unix_ms => ()
        _ => settlement = Some(other)
      }
    }
  }
  guard settlement is Some(confirmed) else { return None }
  let amount = match confirmed.value("settlement.amount_due") {
    Some(raw) => @contractdoc.parse_cny_minor_units(raw)
    None => None
  }
  guard amount is Some(settlement_minor) else {
    return Some(
      Mismatched(
        "settlement packet \{confirmed.packet_id} amount due is not a parseable CNY amount",
      ),
    )
  }
  let summary : @commercial.CommercialSummary? = try
    Some(
      self.commercial_store.summary(
        packet.organization_id,
        "CNY",
        2,
        now_unix_ms,
      ),
    )
  catch {
    _ => None
  } noraise {
    value => value
  }
  match summary {
    Some(ledger) if ledger.ledger_entry_count > 0 =>
      if ledger.provisional_total.minor_units == settlement_minor {
        Some(
          Matched(
            settlement_ref=confirmed.packet_id,
            minor_units=settlement_minor,
          ),
        )
      } else {
        Some(
          Mismatched(
            "settlement amount due CNY \{@contractdoc.format_cny_minor_units(settlement_minor)} does not match ledger provisional total CNY \{@contractdoc.format_cny_minor_units(ledger.provisional_total.minor_units)}",
          ),
        )
      }
    _ => Some(LedgerUnused(settlement_ref=confirmed.packet_id))
  }
}

///|
/// One bounded scan over effective contract packets. MasterLease packets
/// expire on `lease.end_date`, ReservationApplication packets on
/// `reservation.end_date`; when the remaining whole days cross into the
/// 30-day, 7-day, or 1-day window a dedup-keyed notification goes to both
/// the customer subject and the platform operators. Unparseable end dates
/// are skipped: the scan must never guess at contractual dates.
pub async fn ApiService::reconcile_expiring_contracts(
  self : ApiService,
  now_unix_ms : Int64,
) -> Unit {
  guard self.contract_document_store is Some(store) &&
    self.notification_store is Some(notifications) else {
    return
  }
  for packet in store.snapshot().packets {
    if packet.state != Effective {
      continue
    }
    let end_date = if packet.active_forms.contains(MasterLease) {
      packet.value("lease.end_date")
    } else if packet.active_forms.contains(ReservationApplication) {
      packet.value("reservation.end_date")
    } else {
      None
    }
    let remaining = match end_date {
      Some(value) => @contractdoc.days_until(value, now_unix_ms)
      None => None
    }
    guard end_date is Some(end_date_value) && remaining is Some(days_remaining) else {
      continue
    }
    let window : (String, @notifications.NotificationSeverity)? = if days_remaining <
      0L {
      None
    } else if days_remaining <= 1L {
      Some(("1d", Critical))
    } else if days_remaining <= 7L {
      Some(("7d", Warning))
    } else if days_remaining <= 30L {
      Some(("30d", Warning))
    } else {
      None
    }
    guard window is Some((tier, severity)) else { continue }
    let parameters = Map([
      ("packet_id", packet.packet_id),
      ("end_date", end_date_value),
      ("days_remaining", days_remaining.to_string()),
      ("window", tier),
    ])
    self.enqueue_subject_notification(
      packet.tenant_ref,
      packet.subject_ref,
      "ContractExpiring",
      LeaseLifecycle,
      severity,
      "\{packet.packet_id}:expiry-\{tier}",
      "contract-packet:\{packet.packet_id}:expiry-\{tier}",
      parameters,
      now_unix_ms,
    )
    let deduplication_key = "contract-packet:\{packet.packet_id}:expiry-\{tier}"
    if notifications.record_by_deduplication_key(
        deduplication_key,
        PlatformOperators,
      )
      is None {
      ignore(
        notifications.enqueue({
          version: @notifications.contract_version,
          notification_id: "alert-contract-expiring-\{packet.packet_id}-\{tier}",
          deduplication_key,
          source_receipt: deduplication_key,
          topic: LeaseLifecycle,
          code: "ContractExpiring",
          severity,
          audience: PlatformOperators,
          title_key: "notifications.ContractExpiring.title",
          body_key: "notifications.ContractExpiring.body",
          parameters,
          created_unix_ms: now_unix_ms,
          expires_unix_ms: None,
        }),
      )
    }
  }
  self.record_component_event(
    "event-contract-expiry-reconcile-\{now_unix_ms}",
    now_unix_ms,
    Information,
    "controller",
    "ContractExpiryReconciliationCompleted",
    "contract-expiry-reconcile-\{now_unix_ms}",
    "contract_document",
    "healthy",
    200,
    0L,
  )
}

///|
/// Controller-owned clock reconciliation for contract expiry reminders.
/// Failures propagate to the structured supervisor so the process cannot
/// remain Ready with a dead reminder loop.
pub async fn ApiService::run_contract_expiry_reconciler_forever(
  self : ApiService,
  interval_ms : Int,
) -> Unit {
  if interval_ms < 1000 || interval_ms > 86400000 {
    raise Failure::Failure("contract expiry reconcile interval is invalid")
  }
  for ;; {
    self.reconcile_expiring_contracts(@async.now())
    @async.sleep(interval_ms)
  }
}
