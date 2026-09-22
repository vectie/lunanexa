///|
fn is_offline_domain_error(error : Error) -> Bool {
  match error {
    @offline.OfflineCommerceError::InvalidInput(_)
    | @offline.OfflineCommerceError::NotFound(_)
    | @offline.OfflineCommerceError::AlreadyExists(_)
    | @offline.OfflineCommerceError::IdempotencyConflict(_)
    | @offline.OfflineCommerceError::TenantMismatch
    | @offline.OfflineCommerceError::Unauthorized
    | @offline.OfflineCommerceError::StaleGeneration
    | @offline.OfflineCommerceError::InvalidTransition(_)
    | @offline.OfflineCommerceError::SeparationOfDuties
    | @offline.OfflineCommerceError::EvidenceMissing(_)
    | @offline.OfflineCommerceError::ArtifactUnavailable(_) => true
    _ => false
  }
}

///|
priv struct OfflineDispatcherHeartbeat {
  worker_kind : @offline.OfflineWorkerKind
} derive(FromJson)

///|
async fn ApiService::offline_dispatcher_heartbeat(
  self : ApiService,
  verb : ApiMethod,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard verb == Post else {
    return api_error(405, "MethodNotAllowed", "POST required", false)
  }
  let decoded : OfflineDispatcherHeartbeat? = decode_offline(body)
  guard decoded is Some(heartbeat) else {
    return api_error(
      400, "InvalidRequest", "invalid dispatcher heartbeat", false,
    )
  }
  let token = match heartbeat.worker_kind {
    ArtifactDispatcher => self.artifact_worker_callback_token
    EntitlementDispatcher => self.entitlement_authority_callback_token
  }
  guard token is Some(value) && bearer_authorized(headers, value) else {
    return api_error(
      401, "Unauthenticated", "matching dispatcher authority required", false,
    )
  }
  guard self.offline_commerce_store is Some(store) else {
    return api_error(
      503, "OfflineCommerceUnavailable", "durable authority unavailable", true,
    )
  }
  store.record_dispatcher_heartbeat(heartbeat.worker_kind, @async.now())
  json_reply(200, { "accepted": true })
}
