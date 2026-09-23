///|
/// A bound credential never falls back to shared placement when its delivery
/// becomes unavailable. All callers, including cached-result paths, can use this
/// check before accepting a key or consuming quota.
async fn ApiService::delivery_binding(
  self : ApiService,
  authority : @access.ApiAuthorization,
) -> (@delivery.Operation?, HttpReply?) {
  guard self.client_handoff_store is Some(handoffs) else { return (None, None) }
  guard handoffs.snapshot().credentials
    .iter()
    .find_first(value => value.key_id == authority.key_id)
    is Some(credential) &&
    credential.delivery_id is Some(id) else {
    return (None, None)
  }
  let denied = api_error(
    403, "DeliveryUnavailable", "the credential's delivery is not active", false,
  )
  guard self.delivery_store is Some(deliveries) &&
    self.scheduler is Some(scheduler) &&
    deliveries.operation(id) is Some(operation) &&
    (operation.stage == Ready || operation.stage == StartingWorkspace) &&
    operation.intent.tenant_id == authority.tenant_ref &&
    operation.intent.organization_id == authority.organization_id &&
    operation.intent.project_id == authority.project_id &&
    operation.intent.expires_at_ms > @async.now() &&
    operation.reservation_id is Some(reservation_id) &&
    scheduler.node_reservation(reservation_id) is Some(reservation) &&
    reservation.state == Reserved &&
    reservation.request.tenant_ref == authority.tenant_ref &&
    reservation.request.organization_id == authority.organization_id &&
    reservation.request.lease_id == operation.intent.lease_id &&
    reservation.request.authority_ref == operation.intent.authorization_ref &&
    reservation.request.starts_unix_ms <= @async.now() &&
    reservation.request.expires_unix_ms > @async.now() else {
    return (None, Some(denied))
  }
  guard self.workspace_directory is Some(directory) else {
    return (None, Some(denied))
  }
  if operation.model_service_id is Some(service_id) &&
    deliveries.model_service(service_id) is Some(service) {
    if service.runtime.stage != Ready ||
      !service.consumer_ids.contains(operation.operation_id) ||
      service.runtime.intent.expires_at_ms <= @async.now() {
      return (None, Some(denied))
    }
  }
  let active = try {
    let authorization = directory.authorize_subject_for_tenant(
      authority.subject_ref,
      authority.tenant_ref,
      Developer,
      @async.now(),
    )
    authorization.lease.lease_id == operation.intent.lease_id &&
    authorization.access_grant.grant_id == operation.intent.authorization_ref
  } catch {
    _ => false
  }
  if !active {
    return (None, Some(denied))
  }
  (Some(operation), None)
}
