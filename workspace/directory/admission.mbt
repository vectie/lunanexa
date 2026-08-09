///|
let admission_schema_version : String = "lunanexa.workspace.admissions.v1"

///|
enum WorkloadReservationState {
  ReservationHeld
  ReservationReleased
  ReservationRecovered
} derive(Debug, Eq, ToJson, FromJson)

///|
struct WorkloadReservation {
  version : String
  workload_id : String
  request_key : String
  lease_id : String
  subject_ref : String
  tenant_ref : String
  capability : @workspace.WorkspaceCapability
  reserved_unix_ms : Int64
  expires_unix_ms : Int64
  state : WorkloadReservationState
  released_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
struct WorkspaceAdmissionSnapshot {
  schema_version : String
  reservations : Array[WorkloadReservation]
} derive(Debug, Eq, ToJson, FromJson)

///|
fn sorted_reservations(
  reservations : Map[String, WorkloadReservation],
) -> Array[WorkloadReservation] {
  let values = [ for _, reservation in reservations => reservation ]
  values.sort_by((left, right) => left.workload_id.compare(right.workload_id))
  values
}

///|
fn FileWorkspaceDirectory::admission_snapshot_unlocked(
  self : FileWorkspaceDirectory,
) -> WorkspaceAdmissionSnapshot {
  {
    schema_version: admission_schema_version,
    reservations: sorted_reservations(self.workload_reservations),
  }
}

///|
async fn write_admissions(
  path : String,
  snapshot : WorkspaceAdmissionSnapshot,
) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
fn validate_reservation(reservation : WorkloadReservation) -> Unit raise {
  if reservation.version != @workspace.contract_version ||
    !@workspace.valid_identifier(reservation.workload_id) ||
    !@workspace.valid_identifier(reservation.request_key) ||
    !@workspace.valid_identifier(reservation.lease_id) ||
    !@workspace.valid_identifier(reservation.subject_ref) ||
    !@workspace.valid_identifier(reservation.tenant_ref) ||
    reservation.reserved_unix_ms <= 0L ||
    reservation.expires_unix_ms <= reservation.reserved_unix_ms ||
    reservation.released_unix_ms < 0L {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "invalid workspace workload reservation",
    )
  }
  match reservation.state {
    ReservationHeld =>
      if reservation.released_unix_ms != 0L {
        raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
          "held workspace workload reservation has a release timestamp",
        )
      }
    ReservationReleased | ReservationRecovered =>
      if reservation.released_unix_ms < reservation.reserved_unix_ms {
        raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
          "released workspace workload reservation has an invalid timestamp",
        )
      }
  }
}

///|
fn FileWorkspaceDirectory::restore_admissions(
  self : FileWorkspaceDirectory,
  snapshot : WorkspaceAdmissionSnapshot,
) -> Unit raise {
  if snapshot.schema_version != admission_schema_version {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "unsupported workspace admission schema",
    )
  }
  for reservation in snapshot.reservations {
    validate_reservation(reservation)
    if self.workload_reservations.contains(reservation.workload_id) {
      raise @workspace.WorkspaceDirectoryError::DuplicateRecord(
        "workload:\{reservation.workload_id}",
      )
    }
    guard self.leases.get(reservation.lease_id) is Some(lease) &&
      lease.subject_ref == reservation.subject_ref &&
      lease.tenant_ref == reservation.tenant_ref &&
      @workspace.capability_limit(lease, reservation.capability) is Some(_) else {
      raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
        "workspace workload reservation references invalid authority",
      )
    }
    self.workload_reservations[reservation.workload_id] = reservation
  }
}

///|
fn FileWorkspaceDirectory::reconcile_reservations_unlocked(
  self : FileWorkspaceDirectory,
  now_unix_ms : Int64,
) -> Bool {
  let expired = [
    for workload_id, reservation in self.workload_reservations if reservation.state ==
    ReservationHeld &&
    now_unix_ms >= reservation.expires_unix_ms => workload_id
  ]
  for workload_id in expired {
    guard self.workload_reservations.get(workload_id) is Some(reservation) else {
      continue
    }
    self.workload_reservations[workload_id] = {
      ..reservation,
      state: ReservationRecovered,
      released_unix_ms: now_unix_ms,
    }
  }
  expired.length() > 0
}

///|
async fn FileWorkspaceDirectory::open_admissions(
  self : FileWorkspaceDirectory,
  now_unix_ms : Int64,
) -> Unit {
  if @fs.exists(self.admission_path) {
    let snapshot : WorkspaceAdmissionSnapshot = @json.from_json(
      @json.parse(@fs.read_file(self.admission_path).text()),
    ) catch {
      error =>
        raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
          "invalid workspace admission JSON: \{Repr(error)}",
        )
    }
    self.restore_admissions(snapshot)
    if self.reconcile_reservations_unlocked(now_unix_ms) {
      write_admissions(self.admission_path, self.admission_snapshot_unlocked())
    }
  } else {
    write_admissions(self.admission_path, self.admission_snapshot_unlocked())
  }
}

///|
async fn FileWorkspaceDirectory::persist_admissions(
  self : FileWorkspaceDirectory,
) -> Unit {
  write_admissions(self.admission_path, self.admission_snapshot_unlocked())
}

///|
fn FileWorkspaceDirectory::reservation_lease_unlocked(
  self : FileWorkspaceDirectory,
  lease_id : String,
  subject_ref : String,
  tenant_ref : String,
  capability : @workspace.WorkspaceCapability,
  now_unix_ms : Int64,
) -> (@workspace.WorkspaceLease, @workspace.CapabilityLimit) raise {
  guard self.leases.get(lease_id) is Some(lease) else {
    raise @workspace.WorkspaceDirectoryError::RecordNotFound(
      "lease:\{lease_id}",
    )
  }
  if lease.subject_ref != subject_ref || lease.tenant_ref != tenant_ref {
    raise @workspace.WorkspaceDirectoryError::AccessDenied(LeaseUnavailable)
  }
  guard user_for_subject(self.users, subject_ref) is Some(user) else {
    raise @workspace.WorkspaceDirectoryError::RecordNotFound(
      "subject:\{subject_ref}",
    )
  }
  if !self.has_grant_for_lease_unlocked(user, lease, now_unix_ms) ||
    lease.state != Active ||
    now_unix_ms < lease.starts_unix_ms ||
    now_unix_ms >= lease.expires_unix_ms {
    raise @workspace.WorkspaceDirectoryError::AccessDenied(LeaseUnavailable)
  }
  guard @workspace.capability_limit(lease, capability) is Some(limit) else {
    raise @workspace.WorkspaceDirectoryError::AccessDenied(LeaseUnavailable)
  }
  (lease, limit)
}

///|
pub async fn FileWorkspaceDirectory::reserve_workload(
  self : FileWorkspaceDirectory,
  lease_id : String,
  subject_ref : String,
  tenant_ref : String,
  capability : @workspace.WorkspaceCapability,
  workload_id : String,
  request_key : String,
  expires_unix_ms : Int64,
  now_unix_ms : Int64,
) -> Unit {
  if !@workspace.valid_identifier(workload_id) ||
    !@workspace.valid_identifier(request_key) ||
    expires_unix_ms <= now_unix_ms {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "invalid workspace workload reservation request",
    )
  }
  self.mutex.acquire()
  let previous_grants = self.access_grants.copy()
  let previous_leases = self.leases.copy()
  let previous_reservations = self.workload_reservations.copy()
  try {
    let authority_changed = self.reconcile_expiry_unlocked(now_unix_ms)
    ignore(self.reconcile_reservations_unlocked(now_unix_ms))
    if self.workload_reservations.contains(workload_id) {
      raise @workspace.WorkspaceDirectoryError::DuplicateRecord(
        "workload:\{workload_id}",
      )
    }
    let (_, limit) = self.reservation_lease_unlocked(
      lease_id, subject_ref, tenant_ref, capability, now_unix_ms,
    )
    let hourly_window_start = now_unix_ms - 3600000L
    let hourly_count = self.workload_reservations
      .values()
      .filter(reservation => {
        reservation.lease_id == lease_id &&
        reservation.capability == capability &&
        reservation.reserved_unix_ms > hourly_window_start &&
        reservation.reserved_unix_ms <= now_unix_ms
      })
      .length()
    if hourly_count >= limit.max_requests_per_hour {
      raise @workspace.WorkspaceDirectoryError::HourlyRequestLimitExceeded(
        lease_id,
      )
    }
    let concurrent_count = self.workload_reservations
      .values()
      .filter(reservation => {
        reservation.lease_id == lease_id &&
        reservation.capability == capability &&
        reservation.state == ReservationHeld &&
        reservation.expires_unix_ms > now_unix_ms
      })
      .length()
    if concurrent_count >= limit.max_concurrent_requests {
      raise @workspace.WorkspaceDirectoryError::ConcurrentRequestLimitExceeded(
        lease_id,
      )
    }
    self.workload_reservations[workload_id] = {
      version: @workspace.contract_version,
      workload_id,
      request_key,
      lease_id,
      subject_ref,
      tenant_ref,
      capability,
      reserved_unix_ms: now_unix_ms,
      expires_unix_ms,
      state: ReservationHeld,
      released_unix_ms: 0L,
    }
    if authority_changed {
      self.persist()
    }
    self.persist_admissions()
    self.mutex.release()
  } catch {
    error => {
      self.access_grants = previous_grants
      self.leases = previous_leases
      self.workload_reservations = previous_reservations
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileWorkspaceDirectory::release_workload(
  self : FileWorkspaceDirectory,
  workload_id : String,
  request_key : String,
  now_unix_ms : Int64,
) -> Unit {
  self.mutex.acquire()
  let previous = self.workload_reservations.copy()
  try {
    guard self.workload_reservations.get(workload_id) is Some(reservation) else {
      raise @workspace.WorkspaceDirectoryError::RecordNotFound(
        "workload:\{workload_id}",
      )
    }
    if reservation.request_key != request_key {
      raise @workspace.WorkspaceDirectoryError::AccessDenied(LeaseUnavailable)
    }
    if reservation.state == ReservationHeld {
      self.workload_reservations[workload_id] = {
        ..reservation,
        state: ReservationReleased,
        released_unix_ms: now_unix_ms,
      }
      self.persist_admissions()
    }
    self.mutex.release()
  } catch {
    error => {
      self.workload_reservations = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileWorkspaceDirectory::workload_owned_by(
  self : FileWorkspaceDirectory,
  workload_id : String,
  subject_ref : String,
  tenant_ref : String,
  now_unix_ms : Int64,
) -> Bool {
  self.mutex.acquire()
  let previous = self.workload_reservations.copy()
  try {
    if self.reconcile_reservations_unlocked(now_unix_ms) {
      self.persist_admissions()
    }
    let owned = self.workload_reservations
      .get(workload_id)
      .map_or(false, reservation => {
        reservation.subject_ref == subject_ref &&
        reservation.tenant_ref == tenant_ref
      })
    self.mutex.release()
    owned
  } catch {
    error => {
      self.workload_reservations = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Proves ownership for status and cancellation after admission has already
/// bound the globally unique workload ID to both a subject and tenant scope.
pub async fn FileWorkspaceDirectory::workload_owned_by_subject(
  self : FileWorkspaceDirectory,
  workload_id : String,
  subject_ref : String,
  now_unix_ms : Int64,
) -> Bool {
  self.mutex.acquire()
  let previous = self.workload_reservations.copy()
  try {
    if self.reconcile_reservations_unlocked(now_unix_ms) {
      self.persist_admissions()
    }
    let owned = self.workload_reservations
      .get(workload_id)
      .map_or(false, reservation => reservation.subject_ref == subject_ref)
    self.mutex.release()
    owned
  } catch {
    error => {
      self.workload_reservations = previous
      self.mutex.release()
      raise error
    }
  }
}
