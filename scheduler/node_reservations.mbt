///|
pub(all) enum NodeReservationState {
  Reserved
  Draining
  Released
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeReservationRequest {
  reservation_id : String
  idempotency_key : String
  tenant_ref : String
  organization_id : String
  authority_ref : String
  lease_id : String
  node_ids : Array[String]
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  memory_mib_per_node : Int
  gpu_memory_mib_per_node : Int
  max_concurrency_per_node : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeServiceClaim {
  service_id : String
  node_id : String
  memory_mib : Int
  gpu_memory_mib : Int
  concurrency : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeReservation {
  request : NodeReservationRequest
  state : NodeReservationState
  generation : Int64
  updated_unix_ms : Int64
  services : Array[NodeServiceClaim]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NodeReservationState with Debug::{to_repr}

///|
pub extend NodeReservationState with Eq::{not_equal, equal}

///|
pub extend NodeReservationState with ToJson::{to_json}

///|
pub extend NodeReservationState with FromJson::{from_json}

///|
pub extend NodeReservationRequest with Debug::{to_repr}

///|
pub extend NodeReservationRequest with Eq::{not_equal, equal}

///|
pub extend NodeReservationRequest with ToJson::{to_json}

///|
pub extend NodeReservationRequest with FromJson::{from_json}

///|
pub extend NodeServiceClaim with Debug::{to_repr}

///|
pub extend NodeServiceClaim with Eq::{not_equal, equal}

///|
pub extend NodeServiceClaim with ToJson::{to_json}

///|
pub extend NodeServiceClaim with FromJson::{from_json}

///|
pub extend NodeReservation with Debug::{to_repr}

///|
pub extend NodeReservation with Eq::{not_equal, equal}

///|
pub extend NodeReservation with ToJson::{to_json}

///|
pub extend NodeReservation with FromJson::{from_json}

///|
fn FileScheduler::node_held_unlocked(
  self : FileScheduler,
  node_id : String,
) -> Bool {
  self.node_reservations
  .values()
  .any(value => {
    value.state != Released && value.request.node_ids.contains(node_id)
  })
}

///|
/// The caller supplies nodes verified idle against real workloads and legacy
/// bare-metal leases. The entire set commits under the scheduler's one mutex
/// and durable snapshot, before any delivery adapter may start workloads.
pub async fn FileScheduler::reserve_nodes(
  self : FileScheduler,
  request : NodeReservationRequest,
  eligible_node_ids : Array[String],
  now_unix_ms : Int64,
) -> NodeReservation {
  self.mutex.acquire()
  defer self.mutex.release()
  for _, value in self.node_reservations {
    if value.request.reservation_id == request.reservation_id ||
      (
        value.request.tenant_ref == request.tenant_ref &&
        value.request.idempotency_key == request.idempotency_key
      ) {
      if value.request != request {
        raise InvalidSchedulerState("node reservation idempotency conflict")
      }
      return value
    }
  }
  if request.reservation_id == "" ||
    request.idempotency_key == "" ||
    request.tenant_ref == "" ||
    request.organization_id == "" ||
    request.authority_ref == "" ||
    request.lease_id == "" ||
    request.node_ids.is_empty() ||
    request.starts_unix_ms >= request.expires_unix_ms ||
    request.expires_unix_ms <= now_unix_ms ||
    request.memory_mib_per_node <= 0 ||
    request.gpu_memory_mib_per_node <= 0 ||
    request.max_concurrency_per_node <= 0 {
    raise InvalidSchedulerState("invalid node reservation")
  }
  let seen : Map[String, Bool] = Map([])
  for node_id in request.node_ids {
    if node_id == "" ||
      seen.contains(node_id) ||
      !eligible_node_ids.contains(node_id) ||
      self.node_held_unlocked(node_id) {
      raise InvalidSchedulerState("requested node set is unavailable")
    }
    seen[node_id] = true
  }
  let previous = self.snapshot_unlocked()
  errdefer self.restore_unlocked(previous)
  let value : NodeReservation = {
    request: { ..request, node_ids: request.node_ids.copy(), },
    state: Reserved,
    generation: 1L,
    updated_unix_ms: now_unix_ms,
    services: [],
  }
  self.node_reservations[request.reservation_id] = value
  self.persist()
  value
}

///|
pub async fn FileScheduler::node_reservation(
  self : FileScheduler,
  reservation_id : String,
) -> NodeReservation? {
  self.mutex.acquire()
  defer self.mutex.release()
  self.node_reservations.get(reservation_id)
}

///|
pub async fn FileScheduler::node_is_reserved(
  self : FileScheduler,
  node_id : String,
) -> Bool {
  self.mutex.acquire()
  defer self.mutex.release()
  self.node_held_unlocked(node_id)
}

///|
/// Expiry denies new use but never implicitly frees a machine still running.
pub async fn FileScheduler::claim_node_service(
  self : FileScheduler,
  reservation_id : String,
  tenant_ref : String,
  claim : NodeServiceClaim,
  now_unix_ms : Int64,
) -> NodeReservation {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.node_reservations.get(reservation_id) is Some(value) else {
    raise InvalidSchedulerState("node reservation not found")
  }
  if value.request.tenant_ref != tenant_ref ||
    value.state != Reserved ||
    now_unix_ms < value.request.starts_unix_ms ||
    now_unix_ms >= value.request.expires_unix_ms ||
    !value.request.node_ids.contains(claim.node_id) ||
    claim.service_id == "" ||
    claim.memory_mib < 0 ||
    claim.gpu_memory_mib < 0 ||
    claim.concurrency <= 0 {
    raise InvalidSchedulerState("node service is outside active reservation")
  }
  let mut memory = claim.memory_mib.to_int64()
  let mut gpu_memory = claim.gpu_memory_mib.to_int64()
  let mut concurrency = claim.concurrency.to_int64()
  for service in value.services {
    if service.service_id == claim.service_id {
      if service != claim {
        raise InvalidSchedulerState("service claim conflict")
      }
      return value
    }
    if service.node_id == claim.node_id {
      memory += service.memory_mib.to_int64()
      gpu_memory += service.gpu_memory_mib.to_int64()
      concurrency += service.concurrency.to_int64()
    }
  }
  if memory > value.request.memory_mib_per_node.to_int64() ||
    gpu_memory > value.request.gpu_memory_mib_per_node.to_int64() ||
    concurrency > value.request.max_concurrency_per_node.to_int64() {
    raise InvalidSchedulerState("node service budget exhausted")
  }
  let previous = self.snapshot_unlocked()
  errdefer self.restore_unlocked(previous)
  let services = value.services.copy()
  services.push(claim)
  let updated = {
    ..value,
    services,
    generation: value.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
  self.node_reservations[reservation_id] = updated
  self.persist()
  updated
}

///|
/// Called only after observing that this exact service has stopped.
pub async fn FileScheduler::confirm_node_service_stopped(
  self : FileScheduler,
  reservation_id : String,
  service_id : String,
  now_unix_ms : Int64,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.node_reservations.get(reservation_id) is Some(value) else {
    raise InvalidSchedulerState("node reservation not found")
  }
  let previous = self.snapshot_unlocked()
  errdefer self.restore_unlocked(previous)
  self.node_reservations[reservation_id] = {
    ..value,
    services: value.services.filter(service => service.service_id != service_id),
    generation: value.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
  self.persist()
}

///|
pub async fn FileScheduler::begin_node_release(
  self : FileScheduler,
  reservation_id : String,
  now_unix_ms : Int64,
) -> NodeReservation {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.node_reservations.get(reservation_id) is Some(value) else {
    raise InvalidSchedulerState("node reservation not found")
  }
  if value.state != Reserved {
    return value
  }
  let previous = self.snapshot_unlocked()
  errdefer self.restore_unlocked(previous)
  let updated = {
    ..value,
    state: Draining,
    generation: value.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
  self.node_reservations[reservation_id] = updated
  self.persist()
  updated
}

///|
/// The reconciler must supply the complete observed-stopped node set. A timer
/// or a requested delete is not stop evidence. User volumes are not removed.
pub async fn FileScheduler::complete_node_release(
  self : FileScheduler,
  reservation_id : String,
  stopped_node_ids : Array[String],
  now_unix_ms : Int64,
) -> NodeReservation {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.node_reservations.get(reservation_id) is Some(value) else {
    raise InvalidSchedulerState("node reservation not found")
  }
  if value.state == Released {
    return value
  }
  if value.state != Draining ||
    !value.services.is_empty() ||
    !value.request.node_ids.all(node => stopped_node_ids.contains(node)) {
    raise InvalidSchedulerState(
      "reservation workloads have not finished stopping",
    )
  }
  let previous = self.snapshot_unlocked()
  errdefer self.restore_unlocked(previous)
  let updated = {
    ..value,
    state: Released,
    generation: value.generation + 1L,
    updated_unix_ms: now_unix_ms,
  }
  self.node_reservations[reservation_id] = updated
  self.persist()
  updated
}

///|
pub async fn FileScheduler::place_reserved(
  self : FileScheduler,
  nodes : Array[NodeSnapshot],
  requirements : PlacementRequirements,
  policy : ScorePolicy,
  reservation_id : String,
  tenant_ref : String,
  now_unix_ms : Int64,
) -> PlacementDecision {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.node_reservations.get(reservation_id) is Some(value) else {
    raise InvalidSchedulerState("node reservation not found")
  }
  if value.request.tenant_ref != tenant_ref ||
    value.state != Reserved ||
    now_unix_ms < value.request.starts_unix_ms ||
    now_unix_ms >= value.request.expires_unix_ms {
    raise InvalidSchedulerState("node reservation is not active for tenant")
  }
  let decision = place(
    nodes.filter(node => value.request.node_ids.contains(node.node_id)),
    requirements,
    policy,
  )
  let previous = self.snapshot_unlocked()
  errdefer self.restore_unlocked(previous)
  self.decisions.push(decision)
  while self.decisions.length() > self.decision_history_limit {
    ignore(self.decisions.remove(0))
  }
  self.persist()
  decision
}
