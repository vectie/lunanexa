///|
/// Caller must verify live operator session, actual OIDC purchaser and the
/// existing administrator-issued grant/lease. All immutable binding and
/// single-use constraints are also enforced under the durable store lock.
pub async fn OfflineCommerceStore::authorize_technical_acceptance(
  self : OfflineCommerceStore,
  order_id : String,
  expected_generation : Int64,
  waiver : @offline.TechnicalAcceptanceWaiver,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  defer self.mutex.release()
  let order = self.require_order_unlocked(order_id)
  if order.technical_acceptance_waiver == Some(waiver) {
    return order
  }
  guard order.technical_acceptance_waiver is None &&
    order.state == Quoted &&
    order.generation == expected_generation &&
    order.agreement_ref is None &&
    order.artifact_ids.is_empty() &&
    order.entitlement_ref is None else {
    raise @offline.OfflineCommerceError::InvalidInput(
      "technical waiver requires a separate untouched quoted order",
    )
  }
  for other in self.orders.values() {
    if other.order_id != order_id &&
      other.technical_acceptance_waiver is Some(w) &&
      (
        w.waiver_id == waiver.waiver_id ||
        w.authority_target_ref == waiver.authority_target_ref
      ) {
      raise @offline.OfflineCommerceError::InvalidInput(
        "technical waiver or target already belongs to another order",
      )
    }
  }
  for activation in self.entitlement_activations.values() {
    if activation.authority_target_ref == waiver.authority_target_ref {
      raise @offline.OfflineCommerceError::InvalidInput(
        "authority target was already used by commercial fulfillment",
      )
    }
  }
  let updated = {
    ..order,
    technical_acceptance_waiver: Some(waiver),
    state: UnderReconciliation,
    generation: order.generation + 1L,
    updated_unix_ms: waiver.issued_unix_ms,
  }
  @offline.validate_order(updated)
  self.orders[order_id] = updated
  errdefer {
    self.orders[order_id] = order
  }
  self.persist()
  updated
}
