///|
pub fn CommercialOrder::with_quote(
  self : CommercialOrder,
  quote : ImmutableQuote,
  actor_ref : String,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  validate_order(self)
  validate_quote(quote)
  if self.state != Draft {
    raise InvalidTransition("only a draft order can be quoted")
  }
  if quote.service_code != self.selected_service_code ||
    quote.sla_code != self.selected_sla_code ||
    quote.valid_until_unix_ms > self.expires_unix_ms ||
    !valid_id(actor_ref) ||
    now_unix_ms < self.updated_unix_ms ||
    now_unix_ms >= quote.valid_until_unix_ms {
    raise InvalidInput("quote does not match order")
  }
  {
    ..self,
    quote: Some(quote),
    state: Quoted,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn CommercialOrder::begin_offline_execution(
  self : CommercialOrder,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != Quoted {
    raise InvalidTransition("order is not quoted")
  }
  guard self.quote is Some(quote) else {
    raise InvalidTransition("quote is missing")
  }
  if now_unix_ms >= quote.valid_until_unix_ms ||
    now_unix_ms >= self.expires_unix_ms {
    return {
      ..self,
      state: Expired,
      generation: self.generation + 1L,
      updated_unix_ms: now_unix_ms,
    }
  }
  {
    ..self,
    state: if self.policy.require_internal_approval {
      PendingInternalApproval
    } else {
      PendingOfflineExecution
    },
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn CommercialOrder::release_offline_packet(
  self : CommercialOrder,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != PendingOfflineExecution {
    raise InvalidTransition("order is not ready for offline execution")
  }
  {
    ..self,
    state: PendingEvidenceUpload,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn CommercialOrder::mark_reconciling(
  self : CommercialOrder,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != PendingEvidenceUpload && self.state != NeedsCorrection {
    raise InvalidTransition("order is not awaiting evidence")
  }
  {
    ..self,
    state: UnderReconciliation,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn CommercialOrder::cancel(
  self : CommercialOrder,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state == Fulfilled ||
    self.state == FulfillmentPending ||
    self.state == ReversalPending ||
    self.state == ReversalManualIntervention ||
    self.state == Revoked ||
    self.state == Rejected ||
    self.state == Cancelled ||
    self.state == Expired {
    raise InvalidTransition("terminal order cannot be cancelled")
  }
  {
    ..self,
    state: Cancelled,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn CommercialOrder::expire(
  self : CommercialOrder,
  now_unix_ms : Int64,
) -> CommercialOrder {
  if now_unix_ms < self.expires_unix_ms ||
    self.state == Fulfilled ||
    self.state == FulfillmentPending ||
    self.state == ReversalPending ||
    self.state == ReversalManualIntervention ||
    self.state == Revoked ||
    self.state == Rejected ||
    self.state == Cancelled ||
    self.state == Expired {
    self
  } else {
    {
      ..self,
      state: Expired,
      generation: self.generation + 1L,
      updated_unix_ms: now_unix_ms,
    }
  }
}

///|
pub fn CommercialOrder::request_activation(
  self : CommercialOrder,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != UnderReconciliation {
    raise InvalidTransition("order is not under reconciliation")
  }
  {
    ..self,
    state: FulfillmentPending,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn CommercialOrder::confirm_activation(
  self : CommercialOrder,
  expected_generation : Int64,
  entitlement_ref : String,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != FulfillmentPending || !valid_id(entitlement_ref) {
    raise InvalidTransition("entitlement activation is not pending")
  }
  {
    ..self,
    entitlement_ref: Some(entitlement_ref),
    state: Fulfilled,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn CommercialOrder::request_reversal(
  self : CommercialOrder,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != Fulfilled || self.entitlement_ref is None {
    raise InvalidTransition("fulfilled entitlement is required for reversal")
  }
  {
    ..self,
    state: ReversalPending,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn CommercialOrder::confirm_reversal(
  self : CommercialOrder,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != ReversalPending {
    raise InvalidTransition("commercial reversal is not pending")
  }
  {
    ..self,
    state: Revoked,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///| A terminal authority failure never recreates an unbounded reversal loop.

///|
/// Human operators must reconcile the external entitlement before retrying.
pub fn CommercialOrder::hold_failed_reversal(
  self : CommercialOrder,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != ReversalPending {
    raise InvalidTransition("commercial reversal is not pending")
  }
  {
    ..self,
    state: ReversalManualIntervention,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn CommercialOrder::recover_failed_reversal(
  self : CommercialOrder,
  expected_generation : Int64,
  decision : ReversalRecoveryDecision,
  now_unix_ms : Int64,
) -> CommercialOrder raise OfflineCommerceError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != ReversalManualIntervention || self.entitlement_ref is None {
    raise InvalidTransition("commercial reversal is not awaiting intervention")
  }
  {
    ..self,
    state: match decision {
      RetryReversal => ReversalPending
      ConfirmRevoked => Revoked
      ConfirmStillActive => Fulfilled
    },
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
}
