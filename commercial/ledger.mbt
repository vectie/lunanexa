///|
fn CommercialStore::overlaps_finalized_period(
  self : CommercialStore,
  organization_id : String,
  started_unix_ms : Int64,
  ended_unix_ms : Int64,
) -> String? {
  self.periods
  .values()
  .find_first(period => {
    period.organization_id == organization_id &&
    started_unix_ms < period.ended_unix_ms &&
    ended_unix_ms > period.started_unix_ms
  })
  .map(period => period.period_id)
}

///|
pub fn CommercialStore::ingest_usage(
  self : CommercialStore,
  observation : UsageObservation,
) -> IdempotencyResult raise CommercialError {
  let project = self.require_project(
    observation.organization_id,
    observation.project_id,
  )
  if !safe_identifier(observation.event_id) ||
    !safe_identifier(observation.actor_ref) ||
    !safe_identifier(observation.workload_id) ||
    !safe_identifier(observation.node_id) ||
    !safe_identifier(observation.meter) ||
    !safe_identifier(observation.unit) ||
    observation.lease_epoch < 0L ||
    observation.quantity <= 0L ||
    observation.started_unix_ms <= 0L ||
    observation.ended_unix_ms <= observation.started_unix_ms ||
    observation.observed_unix_ms < observation.ended_unix_ms {
    raise InvalidInput("invalid usage observation")
  }
  ignore(project)
  match self.observations.get(observation.event_id) {
    Some(existing) =>
      if existing == observation {
        Replayed
      } else {
        raise IdempotencyConflict("usage event payload changed")
      }
    None => {
      match
        self.overlaps_finalized_period(
          observation.organization_id,
          observation.started_unix_ms,
          observation.ended_unix_ms,
        ) {
        Some(period_id) => raise PeriodFinalized(period_id)
        None => ()
      }
      self.observations[observation.event_id] = observation
      Created
    }
  }
}

///|
fn validate_rate_card(rate : RateCard) -> Unit raise CommercialError {
  ignore(
    money(
      rate.unit_price.minor_units,
      rate.unit_price.currency,
      rate.unit_price.scale,
    ),
  )
  if !safe_identifier(rate.rate_card_id) ||
    !safe_identifier(rate.version) ||
    !safe_identifier(rate.meter) ||
    !safe_identifier(rate.unit) ||
    rate.unit_price.minor_units < 0L ||
    rate.effective_from_unix_ms <= 0L ||
    rate.effective_until_unix_ms <= rate.effective_from_unix_ms {
    raise InvalidInput("invalid rate card")
  }
}

///|
pub fn CommercialStore::rate_usage(
  self : CommercialStore,
  event_id : String,
  entry_id : String,
  rate : RateCard,
  recorded_unix_ms : Int64,
) -> (LedgerEntry, IdempotencyResult) raise CommercialError {
  validate_rate_card(rate)
  let observation = match self.observations.get(event_id) {
    Some(value) => value
    None => raise NotFound("usage observation")
  }
  if !safe_identifier(entry_id) ||
    recorded_unix_ms < observation.observed_unix_ms {
    raise InvalidInput("invalid ledger entry")
  }
  if observation.meter != rate.meter ||
    observation.unit != rate.unit ||
    observation.started_unix_ms < rate.effective_from_unix_ms ||
    observation.ended_unix_ms > rate.effective_until_unix_ms {
    raise InvalidInput("rate card does not cover the usage event")
  }
  match self.rated_events.get(event_id) {
    Some(existing_entry_id) => {
      let existing = match self.entries.get(existing_entry_id) {
        Some(value) => value
        None => raise InvalidInput("rated-event index is corrupt")
      }
      if existing.entry_id == entry_id &&
        existing.rate_card_id == rate.rate_card_id &&
        existing.rate_card_version == rate.version &&
        existing.amount == rated_amount(observation.quantity, rate.unit_price) {
        (existing, Replayed)
      } else {
        raise IdempotencyConflict("usage event was already rated")
      }
    }
    None => {
      match
        self.overlaps_finalized_period(
          observation.organization_id,
          observation.started_unix_ms,
          observation.ended_unix_ms,
        ) {
        Some(period_id) => raise PeriodFinalized(period_id)
        None => ()
      }
      if self.entries.contains(entry_id) {
        raise AlreadyExists("ledger entry")
      }
      let project = self.require_project(
        observation.organization_id,
        observation.project_id,
      )
      let organization = self.require_organization(observation.organization_id)
      let cost_center = match self.cost_centers.get(project.cost_center_id) {
        Some(value) => value
        None => raise NotFound("cost center")
      }
      let entry : LedgerEntry = {
        entry_id,
        organization_id: observation.organization_id,
        cost_center_id: cost_center.cost_center_id,
        project_id: project.project_id,
        organization_name_snapshot: organization.display_name,
        cost_center_name_snapshot: cost_center.display_name,
        project_name_snapshot: project.display_name,
        source_event_id: observation.event_id,
        linked_entry_id: None,
        kind: Charge,
        meter: observation.meter,
        quantity: observation.quantity,
        unit: observation.unit,
        amount: rated_amount(observation.quantity, rate.unit_price),
        rate_card_id: rate.rate_card_id,
        rate_card_version: rate.version,
        service_started_unix_ms: observation.started_unix_ms,
        service_ended_unix_ms: observation.ended_unix_ms,
        recorded_unix_ms,
        reason: "rated usage",
      }
      self.entries[entry_id] = entry
      self.rated_events[event_id] = entry_id
      (entry, Created)
    }
  }
}

///|
pub fn CommercialStore::finalize_period(
  self : CommercialStore,
  period_id : String,
  organization_id : String,
  started_unix_ms : Int64,
  ended_unix_ms : Int64,
  billing_timezone : String,
  currency : String,
  scale : Int,
  finalized_by : String,
  finalized_unix_ms : Int64,
) -> FinalizedPeriod raise CommercialError {
  ignore(self.require_organization(organization_id))
  let unit = money(0L, currency, scale)
  if !safe_identifier(period_id) ||
    !safe_identifier(finalized_by) ||
    billing_timezone.length() == 0 ||
    billing_timezone.length() > 80 ||
    started_unix_ms <= 0L ||
    ended_unix_ms <= started_unix_ms ||
    finalized_unix_ms < ended_unix_ms {
    raise InvalidInput("invalid finalized period")
  }
  let key = period_key(organization_id, period_id)
  if self.periods.contains(key) {
    raise PeriodFinalized(period_id)
  }
  for period in self.periods.values() {
    if period.organization_id == organization_id &&
      started_unix_ms < period.ended_unix_ms &&
      ended_unix_ms > period.started_unix_ms {
      raise PeriodFinalized(period.period_id)
    }
  }
  let entry_ids : Array[String] = []
  let mut total = unit
  for observation in self.observations.values() {
    if observation.organization_id == organization_id &&
      observation.started_unix_ms >= started_unix_ms &&
      observation.ended_unix_ms <= ended_unix_ms &&
      !self.rated_events.contains(observation.event_id) {
      raise InvalidInput("period contains unrated usage")
    }
  }
  for entry in self.entries.values() {
    if entry.organization_id == organization_id &&
      entry.service_started_unix_ms >= started_unix_ms &&
      entry.service_ended_unix_ms <= ended_unix_ms {
      total = total.add(entry.amount)
      entry_ids.push(entry.entry_id)
    } else if entry.organization_id == organization_id &&
      entry.service_started_unix_ms < ended_unix_ms &&
      entry.service_ended_unix_ms > started_unix_ms {
      raise InvalidInput("a ledger entry crosses the period boundary")
    }
  }
  entry_ids.sort()
  let period : FinalizedPeriod = {
    period_id,
    organization_id,
    started_unix_ms,
    ended_unix_ms,
    billing_timezone,
    entry_ids,
    total,
    finalized_unix_ms,
    finalized_by,
  }
  self.periods[key] = period
  period
}

///|
fn CommercialStore::finalized_period_for_entry(
  self : CommercialStore,
  entry : LedgerEntry,
) -> FinalizedPeriod? {
  self.periods
  .values()
  .find_first(period => {
    period.organization_id == entry.organization_id &&
    period.entry_ids.contains(entry.entry_id)
  })
}

///|
pub fn CommercialStore::append_adjustment(
  self : CommercialStore,
  adjustment_id : String,
  organization_id : String,
  linked_entry_id : String,
  kind : LedgerEntryKind,
  amount : FixedMoney,
  reason : String,
  recorded_unix_ms : Int64,
) -> LedgerEntry raise CommercialError {
  if kind == Charge ||
    !safe_identifier(adjustment_id) ||
    amount.minor_units == 0L ||
    !safe_display_name(reason) ||
    recorded_unix_ms <= 0L ||
    recorded_unix_ms == int64_max {
    raise InvalidInput("invalid linked adjustment")
  }
  if self.entries.contains(adjustment_id) {
    raise AlreadyExists("ledger entry")
  }
  let linked = match self.entries.get(linked_entry_id) {
    Some(value) => value
    None => raise NotFound("linked ledger entry")
  }
  if linked.organization_id != organization_id {
    raise TenantMismatch
  }
  if linked.kind != Charge || self.finalized_period_for_entry(linked) is None {
    raise InvalidInput("adjustments must link to a finalized charge")
  }
  ensure_same_money_unit(linked.amount, amount)
  let normalized_amount = match kind {
    Credit => if amount.minor_units > 0L { amount.negate() } else { amount }
    Debit | Adjustment => amount
    Charge => amount
  }
  let entry : LedgerEntry = {
    ..linked,
    entry_id: adjustment_id,
    source_event_id: "adjustment:\{adjustment_id}",
    linked_entry_id: Some(linked_entry_id),
    kind,
    quantity: 0L,
    amount: normalized_amount,
    rate_card_id: linked.rate_card_id,
    rate_card_version: linked.rate_card_version,
    service_started_unix_ms: recorded_unix_ms,
    service_ended_unix_ms: recorded_unix_ms + 1L,
    recorded_unix_ms,
    reason,
  }
  self.entries[adjustment_id] = entry
  entry
}
