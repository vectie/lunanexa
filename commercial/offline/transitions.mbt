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
