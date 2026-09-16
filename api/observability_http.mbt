///| Records a typed component lifecycle event without exposing the

///| ObservabilityStore itself to workers. Callers must use stable event codes,

///|
/// bounded correlation receipts, and low-cardinality target types.
pub async fn ApiService::record_component_event(
  self : ApiService,
  event_id : String,
  timestamp_unix_ms : Int64,
  severity : @observability.OperationalSeverity,
  component : String,
  event_code : String,
  correlation_id : String,
  target_type : String,
  outcome : String,
  status_code : Int,
  duration_ms : Int64,
) -> Unit {
  match self.observability_store {
    Some(store) =>
      store.record_component_event(
        event_id, timestamp_unix_ms, severity, component, event_code, correlation_id,
        target_type, outcome, status_code, duration_ms,
      )
    None => ()
  }
}

///|
pub async fn ApiService::observability_readiness(
  self : ApiService,
  now_unix_ms? : Int64 = 0L,
) -> @observability.ObservabilityReadiness? {
  match self.observability_store {
    Some(store) =>
      Some(
        store.readiness(
          external_collector_configured=self.external_observability_collector_configured,
          now_unix_ms~,
        ),
      )
    None => None
  }
}

///| Records an authenticated deployment-owned collector proof. The HTTP route

///|
/// must require monitoring authority and reject stale/future timestamps.
pub async fn ApiService::record_external_export_proof(
  self : ApiService,
  proof : @observability.ExternalExportProof,
  now_unix_ms : Int64,
) -> @observability.OperationalEvent {
  if proof.exported_unix_ms < now_unix_ms - 300000L ||
    proof.exported_unix_ms > now_unix_ms + 5000L {
    raise @observability.ObservabilityError::InvalidEvent(
      "external export proof is outside the acceptance window",
    )
  }
  guard self.observability_store is Some(store) else {
    raise @observability.ObservabilityError::InvalidSnapshot(
      "observability authority is unavailable",
    )
  }
  store.record_external_export_proof(proof)
}

///| Resolves tenant correlation from the authenticated portal subject rather

///| than trusting a caller-supplied tenant header. Non-portal roles remain

///|
/// unscoped instead of accepting an asserted tenant identity.
pub async fn ApiService::trusted_operational_tenant_hash(
  self : ApiService,
  headers : Map[String, String],
  allow_asserted_subject : Bool,
) -> String? {
  guard self.portal_store is Some(portal) &&
    self.portal_subject(headers, allow_asserted_subject) is Some(subject_ref) else {
    return None
  }
  try portal_view_for_request(portal, subject_ref, headers) catch {
    _ => None
  } noraise {
    view => Some("sha256:\{digest_hex(view.membership.tenant_ref)}")
  }
}
