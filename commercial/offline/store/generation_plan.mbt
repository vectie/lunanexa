///|
/// Returns a detached copy: mutable JSON objects cannot rewrite retained work.
pub async fn OfflineCommerceStore::generation_plan(
  self : OfflineCommerceStore,
  request_id : String,
) -> Json? {
  self.mutex.acquire()
  let encoded = self.generation_plans.get(request_id)
  self.mutex.release()
  encoded.map(value => @json.parse(value))
}

///|
/// Freezes the actual marker/quote inputs on the first claimed execution.
/// Existing plans win over a later edit; a caller must create a new generation
/// request to intentionally produce different legal bytes.
pub async fn OfflineCommerceStore::retain_generation_plan(
  self : OfflineCommerceStore,
  request : @offline.ArtifactGenerationRequest,
  plan : Json,
) -> Json {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.generation_requests.get(request.request_id) == Some(request) &&
    self.orders.get(request.order_id) is Some(order) &&
    self.work_claims.get(artifact_work_id(request.request_id)) is Some(claim) &&
    claim.worker_kind == ArtifactDispatcher &&
    claim.attempt > 0 &&
    claim.completed_unix_ms is None &&
    order.generation == claim.expected_order_generation else {
    raise @offline.OfflineCommerceError::Unauthorized
  }
  if self.generation_plans.get(request.request_id) is Some(encoded) {
    let retained = @json.parse(encoded)
    if retained is { "job": _, .. } ||
      !(retained is { "contract_binding": _, .. }) {
      return retained
    }
    guard retained is { "contract_binding": binding, .. } &&
      plan is { "contract_binding": same, .. } &&
      binding == same else {
      raise @offline.OfflineCommerceError::IdempotencyConflict(
        request.request_id,
      )
    }
  }
  guard plan is Object(_) else {
    raise @offline.OfflineCommerceError::InvalidInput(
      "generation plan must be an object",
    )
  }
  let encoded = plan.stringify()
  if encoded.length() > 4194304 {
    raise @offline.OfflineCommerceError::InvalidInput(
      "generation plan exceeds limit",
    )
  }
  let before = self.generation_plans.copy()
  errdefer {
    self.generation_plans = before
  }
  self.generation_plans[request.request_id] = encoded
  self.persist()
  @json.parse(encoded)
}
