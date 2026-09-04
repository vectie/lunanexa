///|
async fn ApiService::commercial_project_exists(
  self : ApiService,
  organization_id : String,
  project_id : String,
) -> Bool {
  self.commercial_mutex.acquire()
  let exists = self.commercial_store.project_for_organization(
      organization_id, project_id,
    )
    is Some(_)
  self.commercial_mutex.release()
  exists
}

///|
/// Validates commercial attribution before runtime capacity is consumed. Test
/// and development services without PostgreSQL keep the existing free/local
/// behavior; production persistence fails closed when attribution is absent.
async fn ApiService::inference_billing_preflight(
  self : ApiService,
  authority : @access.ApiAuthorization,
  now_unix_ms : Int64,
) -> HttpReply? {
  guard self.management_database is Some(_) else { return None }
  guard self.inference_rate_card is Some(rate) else {
    return Some(
      api_error(
        503, "InferenceRatingUnavailable", "the production inference rate card is not configured",
        true,
      ),
    )
  }
  if now_unix_ms < rate.effective_from_unix_ms ||
    now_unix_ms >= rate.effective_until_unix_ms {
    return Some(
      api_error(
        503, "InferenceRatingUnavailable", "the production inference rate card is not currently effective",
        true,
      ),
    )
  }
  if !self.commercial_project_exists(
      authority.organization_id,
      authority.project_id,
    ) {
    return Some(
      api_error(
        409, "CommercialAttributionRequired", "the API credential is not bound to an active commercial project",
        false,
      ),
    )
  }
  None
}

///|
/// Converts a durable workload receipt into an exactly-once usage observation
/// and rated ledger charge. The event identifiers and timestamps are derived
/// only from the durable response so a retry after PostgreSQL recovery is a
/// true replay rather than a second charge.
async fn ApiService::record_inference_charge(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
  response : @contracts.WorkloadResponse,
  authority : @access.ApiAuthorization,
) -> Unit {
  guard self.management_database is Some(_) else { return }
  guard self.inference_rate_card is Some(rate) else {
    raise Failure::Failure("production inference rate card is unavailable")
  }
  guard response.execution_node_id is Some(node_id) else {
    raise Failure::Failure("workload receipt has no execution node")
  }
  let started = response.timing.started_unix_ms
  let ended = response.timing.completed_unix_ms.max(started + 1L)
  let quantity = (response.usage.accelerator_ms.max(1L) + 999L) / 1000L
  let identity = digest_hex(
    "lunanexa.inference-charge.v1|\{request.workload_id}|\{authority.organization_id}|\{authority.project_id}",
  )
  let event_id = "usage-\{identity[:32]}"
  let entry_id = "charge-\{identity[32:]}"
  let observation : @commercial.UsageObservation = {
    event_id,
    organization_id: authority.organization_id,
    project_id: authority.project_id,
    actor_ref: authority.subject_ref,
    workload_id: request.workload_id,
    node_id,
    lease_epoch: 0L,
    meter: "accelerator-second",
    quantity,
    unit: "second",
    started_unix_ms: started,
    ended_unix_ms: ended,
    observed_unix_ms: ended,
  }
  self.commercial_mutex.acquire()
  defer self.commercial_mutex.release()
  let before = self.commercial_store.durable_snapshot()
  try {
    ignore(self.commercial_store.ingest_usage(observation))
    ignore(self.commercial_store.rate_usage(event_id, entry_id, rate, ended))
    self.persist_commercial_state()
  } catch {
    error => {
      ignore(self.commercial_store.replace_from_durable_snapshot(before))
      raise error
    }
  }
}

///|
async fn ApiService::bill_or_retry_reply(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
  response : @contracts.WorkloadResponse,
  authority : @access.ApiAuthorization,
) -> HttpReply? {
  self.record_inference_charge(request, response, authority) catch {
    _ =>
      return Some(
        api_error(
          503, "InferenceUsagePersistenceFailed", "the workload receipt is durable but its commercial charge is pending; retry with the same idempotency key",
          true,
        ),
      )
  }
  None
}
