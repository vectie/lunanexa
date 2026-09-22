///|
priv struct ReservationHostConfig {
  kubernetes_origin : String
  token_file : String
  ca_file : String
  workload_namespace : String?
  workload_namespaces : Array[String]?
  node_names : Map[String, String]
  infrastructure : Array[@reservation_host.InfrastructurePod]
} derive(FromJson)

///|
pub fn ApiService::with_reservation_host(
  self : ApiService,
  host : @reservation_host.ReservationHost,
  node_names : Map[String, String],
) -> ApiService {
  {
    ..self,
    reservation_host: Some(host),
    reservation_node_names: node_names.copy(),
  }
}

///|
pub fn ApiService::with_reservation_host_json(
  self : ApiService,
  configuration : String?,
) -> ApiService raise {
  guard configuration is Some(raw) else { return self }
  let config : ReservationHostConfig = @json.from_json(@json.parse(raw))
  let transport = @reservation_host.authenticated_transport(
    config.kubernetes_origin,
    config.token_file,
    config.ca_file,
  )
  let host = @reservation_host.ReservationHost::new(
    transport,
    config.workload_namespace.unwrap_or(""),
    config.infrastructure,
    workload_namespaces=config.workload_namespaces.unwrap_or([
      config.workload_namespace.unwrap_or(""),
    ]),
  )
  if config.node_names.is_empty() {
    raise Failure("reservation node mapping must be nonempty and one-to-one")
  }
  let seen : Map[String, Bool] = Map([])
  for _, name in config.node_names {
    if seen.contains(name) {
      raise Failure("reservation node mapping must be one-to-one")
    }
    seen[name] = true
  }
  self.with_reservation_host(host, config.node_names)
}

///|
/// Caller holds resource_mutex when publishing. Re-observe the complete set,
/// never infer node fencing from a previous controller's in-memory status.
async fn ApiService::ensure_reservation_nodes(
  self : ApiService,
  reservation_id : String,
) -> Unit {
  guard self.reservation_host is Some(host) &&
    self.scheduler is Some(scheduler) &&
    scheduler.node_reservation(reservation_id) is Some(reservation) &&
    reservation.state == Reserved &&
    reservation.request.starts_unix_ms <= @async.now() &&
    reservation.request.expires_unix_ms > @async.now() else {
    raise Failure("active Kubernetes reservation authority is unavailable")
  }
  for node in reservation.request.node_ids {
    guard self.reservation_node_names.get(node) is Some(name) else {
      raise Failure("reservation node mapping unavailable")
    }
    ignore(host.reserve(name, reservation_id))
  }
}

///|
async fn ApiService::reservation_authorized(
  self : ApiService,
  reservation : @scheduler.NodeReservation,
  now : Int64,
) -> Bool {
  if reservation.request.expires_unix_ms <= now {
    return false
  }
  guard self.workspace_directory is Some(directory) else { return false }
  guard directory.snapshot(now).leases
    .iter()
    .find_first(value => value.lease_id == reservation.request.lease_id)
    is Some(lease) else {
    return false
  }
  try {
    let authorization = directory.authorize_subject_for_tenant(
      lease.subject_ref,
      reservation.request.tenant_ref,
      Developer,
      now,
    )
    authorization.lease.lease_id == reservation.request.lease_id &&
    authorization.access_grant.grant_id == reservation.request.authority_ref
  } catch {
    _ => false
  }
}

///|
pub async fn ApiService::reconcile_resource_reservations(
  self : ApiService,
) -> Unit {
  guard self.scheduler is Some(scheduler) && self.reservation_host is Some(host) else {
    return
  }
  for initial in scheduler.snapshot().node_reservations.unwrap_or([]) {
    if initial.state == Released {
      continue
    }
    self.resource_mutex.acquire()
    defer self.resource_mutex.release()
    let now = @async.now()
    let mut reservation = scheduler
      .node_reservation(initial.request.reservation_id)
      .unwrap()
    if reservation.state == Reserved &&
      !self.reservation_authorized(reservation, now) {
      reservation = scheduler.begin_node_release(
        reservation.request.reservation_id,
        now,
      )
    }
    if reservation.state == Reserved {
      // Retry failed/partial fencing without disrupting unrelated reservations.
      self.ensure_reservation_nodes(reservation.request.reservation_id) catch {
        _ => ()
      }
      continue
    }
    if reservation.state != Draining || !reservation.services.is_empty() {
      continue
    }
    let assignments = self.store.assignments()
    let heartbeats = self.store.heartbeats()
    if reservation.request.node_ids.any(node => {
        assignments.any(assignment => assignment.node_id == node) ||
        !heartbeats.any(heartbeat => {
          heartbeat.node_id == node &&
          heartbeat.timestamp_unix_ms >= reservation.updated_unix_ms &&
          heartbeat.timestamp_unix_ms <= now &&
          now - heartbeat.timestamp_unix_ms <=
          self.global_settings.control_timing.heartbeat_timeout_ms &&
          heartbeat.running_deployments.is_empty()
        })
      }) {
      continue
    }
    let stopped : Array[String] = []
    for node in reservation.request.node_ids {
      guard self.reservation_node_names.get(node) is Some(name) else { break }
      try host.release(name, reservation.request.reservation_id) catch {
        _ => break
      } noraise {
        _ => stopped.push(node)
      }
    }
    if stopped.length() == reservation.request.node_ids.length() {
      ignore(
        scheduler.complete_node_release(
          reservation.request.reservation_id,
          stopped,
          now,
        ),
      )
      self.operator_audit(
        "resource-reservation.released",
        reservation.request.reservation_id,
        "observed-workloads-stopped",
      )
    }
  }
}
