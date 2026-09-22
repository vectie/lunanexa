///|
priv struct ResourceReservationSubmission {
  request : @scheduler.NodeReservationRequest
  readiness_confirmation : String
} derive(FromJson)

///|
fn resource_reservation_path(path : String) -> Bool {
  path == "/v1/resource-reservations" ||
  path.has_prefix("/v1/resource-reservations/")
}

///|
async fn ApiService::handle_resource_reservation(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if !self.operator_authorized(headers) {
    return api_error(
      401, "Unauthenticated", "operator authority is required", false,
    )
  }
  guard self.scheduler is Some(scheduler) else {
    return api_error(
      503, "ResourceAuthorityUnavailable", "resource authority is unavailable", true,
    )
  }
  if verb == Get && path == "/v1/resource-reservations" {
    return json_reply(
      200,
      scheduler.snapshot().node_reservations.unwrap_or([]).to_json(),
    )
  }
  if verb != Post || path != "/v1/resource-reservations" {
    return api_error(
      405, "MethodNotAllowed", "reservation release requires observed workload shutdown",
      false,
    )
  }
  let submission : ResourceReservationSubmission = try
    @json.from_json(@json.parse(body))
  catch {
    _ =>
      return api_error(
        400, "InvalidRequest", "invalid resource reservation", false,
      )
  } noraise {
    value => value
  }
  let request = submission.request
  if submission.readiness_confirmation !=
    "reserve-idle-nodes:\{request.reservation_id}" {
    return api_error(
      409, "NodeReadinessConfirmationRequired", "confirm that selected nodes have no unmanaged workloads before reserving",
      false,
    )
  }
  guard self.workspace_directory is Some(directory) &&
    self.portal_store is Some(portal) else {
    return api_error(
      503, "AccessAuthorityUnavailable", "workspace authority is unavailable", true,
    )
  }
  let now = @async.now()
  let workspace = directory.snapshot(now)
  guard workspace.leases
    .iter()
    .find_first(lease => lease.lease_id == request.lease_id)
    is Some(lease) &&
    lease.tenant_ref == request.tenant_ref &&
    lease.state == Active &&
    request.starts_unix_ms >= lease.starts_unix_ms &&
    request.expires_unix_ms <= lease.expires_unix_ms &&
    lease.starts_unix_ms <= now &&
    lease.expires_unix_ms > now &&
    portal.snapshot().memberships.any(membership => {
      membership.active &&
      membership.subject_ref == lease.subject_ref &&
      membership.tenant_ref == request.tenant_ref &&
      membership.organization_id == request.organization_id
    }) else {
    return api_error(
      403, "ActiveLeaseRequired", "reservation must belong to an active organization workspace lease",
      false,
    )
  }
  let authority = try
    directory.authorize_subject_for_tenant(
      lease.subject_ref,
      request.tenant_ref,
      Developer,
      now,
    )
  catch {
    _ =>
      return api_error(
        403, "ActiveGrantRequired", "active developer resource authorization is required",
        false,
      )
  } noraise {
    value => value
  }
  if authority.lease.lease_id != request.lease_id ||
    request.authority_ref != authority.access_grant.grant_id {
    return api_error(
      403, "AuthorityMismatch", "reservation must reference the active developer grant",
      false,
    )
  }
  self.resource_mutex.acquire()
  defer self.resource_mutex.release()
  let assignments = self.store.assignments()
  let legacy = match self.exclusive_lease_store {
    Some(leases) => leases.leases()
    None => []
  }
  let eligible : Array[String] = []
  for heartbeat in self.store.heartbeats() {
    if !request.node_ids.contains(heartbeat.node_id) {
      continue
    }
    guard @node.inventory_host_resources(heartbeat.inventory) is Some(host) else {
      continue
    }
    if heartbeat.state != Active ||
      heartbeat.timestamp_unix_ms +
      self.global_settings.control_timing.heartbeat_timeout_ms <
      now ||
      !heartbeat.running_deployments.is_empty() ||
      !heartbeat.inventory.taints.is_empty() ||
      !heartbeat.inventory.accelerators.any(accelerator => accelerator.healthy) ||
      host.memory_total_mib < request.memory_mib_per_node.to_int64() + 4096L ||
      request.gpu_memory_mib_per_node > request.memory_mib_per_node ||
      assignments.any(assignment => assignment.node_id == heartbeat.node_id) ||
      legacy.any(value => {
        value.intent.node_id == heartbeat.node_id &&
        @nodelease.state_blocks_managed_placement(value.state)
      }) {
      continue
    }
    eligible.push(heartbeat.node_id)
  }
  let reserved = try scheduler.reserve_nodes(request, eligible, now) catch {
    _ =>
      return api_error(
        409, "ResourceUnavailable", "complete node set is unavailable or reservation conflicts",
        true,
      )
  } noraise {
    value => value
  }
  self.operator_audit(
    "resource-reservation.reserve",
    reserved.request.reservation_id,
    reserved.request.authority_ref,
  )
  json_reply(201, reserved.to_json())
}
