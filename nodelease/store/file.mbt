///|
pub(all) suberror ExclusiveLeaseStoreError {
  InvalidSnapshot(String)
  DuplicateLease(String)
  IdempotencyConflict(String)
  NodeUnavailable(String)
  LeaseNotFound(String)
  LeaseExpired(String)
} derive(Debug, Eq)

///|
enum ExclusiveLeasePersistence {
  LeaseFile(String)
  LeasePostgres(@database.PostgresDatabase)
}

///|
pub struct FileExclusiveLeaseStore {
  persistence : ExclusiveLeasePersistence
  signing_secret : String
  mut leases : Map[String, @nodelease.ExclusiveNodeLease]
  mutex : @async.Mutex
}

///|
fn canonical_lease(lease : @nodelease.ExclusiveNodeLease) -> String {
  { ..lease, authority_receipt: "" }.to_json().stringify()
}

///|
fn authority_receipt(
  lease : @nodelease.ExclusiveNodeLease,
  signing_secret : String,
) -> String {
  let signature = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(signing_secret).view(),
      @utf8.encode(canonical_lease(lease)).view(),
    ),
  )
  "exclusive-lease:\{lease.intent.lease_id}:\{signature}"
}

///|
fn sign_lease(
  lease : @nodelease.ExclusiveNodeLease,
  signing_secret : String,
) -> @nodelease.ExclusiveNodeLease {
  { ..lease, authority_receipt: authority_receipt(lease, signing_secret) }
}

///|
fn signature_valid(
  lease : @nodelease.ExclusiveNodeLease,
  signing_secret : String,
) -> Bool {
  lease.authority_receipt != "" &&
  lease.authority_receipt == authority_receipt(lease, signing_secret)
}

///|
fn sorted_leases(
  leases : Map[String, @nodelease.ExclusiveNodeLease],
) -> Array[@nodelease.ExclusiveNodeLease] {
  let values = [ for _, lease in leases => lease ]
  values.sort_by((left, right) => {
    left.intent.lease_id.compare(right.intent.lease_id)
  })
  values
}

///|
fn FileExclusiveLeaseStore::snapshot_unlocked(
  self : FileExclusiveLeaseStore,
) -> @nodelease.ExclusiveLeaseSnapshot {
  {
    schema_version: @nodelease.snapshot_schema_version,
    leases: sorted_leases(self.leases),
  }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : @nodelease.ExclusiveLeaseSnapshot,
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
fn FileExclusiveLeaseStore::restore(
  self : FileExclusiveLeaseStore,
  snapshot : @nodelease.ExclusiveLeaseSnapshot,
) -> Unit raise ExclusiveLeaseStoreError {
  if snapshot.schema_version != @nodelease.snapshot_schema_version {
    raise InvalidSnapshot("unsupported exclusive lease snapshot")
  }
  let idempotency_keys : Map[String, String] = Map([])
  let blocked_nodes : Map[String, String] = Map([])
  for lease in snapshot.leases {
    @nodelease.validate_intent(lease.intent) catch {
      _ => raise InvalidSnapshot("invalid exclusive lease intent")
    }
    if lease.generation <= 0L ||
      lease.updated_unix_ms < lease.created_unix_ms ||
      !signature_valid(lease, self.signing_secret) {
      raise InvalidSnapshot("invalid exclusive lease authority receipt")
    }
    if self.leases.contains(lease.intent.lease_id) {
      raise InvalidSnapshot("duplicate exclusive lease identity")
    }
    if idempotency_keys.contains(lease.intent.idempotency_key) {
      raise InvalidSnapshot("duplicate exclusive lease idempotency key")
    }
    if @nodelease.state_blocks_managed_placement(lease.state) &&
      blocked_nodes.contains(lease.intent.node_id) {
      raise InvalidSnapshot("node has multiple non-terminal exclusive leases")
    }
    self.leases[lease.intent.lease_id] = lease
    idempotency_keys[lease.intent.idempotency_key] = lease.intent.lease_id
    if @nodelease.state_blocks_managed_placement(lease.state) {
      blocked_nodes[lease.intent.node_id] = lease.intent.lease_id
    }
  }
}

///|
pub async fn FileExclusiveLeaseStore::open(
  path : String,
  signing_secret : String,
) -> FileExclusiveLeaseStore {
  if signing_secret == "" {
    raise InvalidSnapshot("exclusive lease signing authority is unavailable")
  }
  let store : FileExclusiveLeaseStore = {
    persistence: LeaseFile(path),
    signing_secret,
    leases: Map([]),
    mutex: Mutex(),
  }
  if @fs.exists(path) {
    let snapshot : @nodelease.ExclusiveLeaseSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error => raise InvalidSnapshot("\{Repr(error)}")
    }
    store.restore(snapshot)
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn FileExclusiveLeaseStore::open_postgres(
  database : @database.PostgresDatabase,
  signing_secret : String,
) -> FileExclusiveLeaseStore {
  if signing_secret == "" {
    raise InvalidSnapshot("exclusive lease signing authority is unavailable")
  }
  let store : FileExclusiveLeaseStore = {
    persistence: LeasePostgres(database),
    signing_secret,
    leases: Map([]),
    mutex: Mutex(),
  }
  match
    database.load_snapshot(
      "exclusive_node_leases", @nodelease.snapshot_schema_version,
    ) {
    Some(payload) => {
      let snapshot : @nodelease.ExclusiveLeaseSnapshot = @json.from_json(
        @json.parse(payload),
      ) catch {
        error => raise InvalidSnapshot("\{Repr(error)}")
      }
      store.restore(snapshot)
    }
    None =>
      database.save_opaque_snapshot(
        "exclusive_node_leases",
        @nodelease.snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
  }
  store
}

///|
async fn FileExclusiveLeaseStore::persist(
  self : FileExclusiveLeaseStore,
) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    LeaseFile(path) => write_snapshot(path, snapshot)
    LeasePostgres(database) =>
      database.save_opaque_snapshot(
        "exclusive_node_leases",
        @nodelease.snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
fn FileExclusiveLeaseStore::by_idempotency_unlocked(
  self : FileExclusiveLeaseStore,
  idempotency_key : String,
) -> @nodelease.ExclusiveNodeLease? {
  for _, lease in self.leases {
    if lease.intent.idempotency_key == idempotency_key {
      return Some(lease)
    }
  }
  None
}

///|
fn FileExclusiveLeaseStore::node_blocked_unlocked(
  self : FileExclusiveLeaseStore,
  node_id : String,
) -> Bool {
  self.leases
  .values()
  .any(lease => {
    lease.intent.node_id == node_id &&
    @nodelease.state_blocks_managed_placement(lease.state)
  })
}

///|
pub async fn FileExclusiveLeaseStore::issue(
  self : FileExclusiveLeaseStore,
  intent : @nodelease.ExclusiveNodeLeaseIntent,
  now_unix_ms : Int64,
) -> @nodelease.ExclusiveNodeLease {
  @nodelease.validate_intent(intent)
  if now_unix_ms >= intent.expires_unix_ms {
    raise LeaseExpired(intent.lease_id)
  }
  self.mutex.acquire()
  let previous = self.leases.copy()
  try {
    match self.by_idempotency_unlocked(intent.idempotency_key) {
      Some(existing) if existing.intent == intent => {
        self.mutex.release()
        return existing
      }
      Some(_) => raise IdempotencyConflict(intent.idempotency_key)
      None => ()
    }
    if self.leases.contains(intent.lease_id) {
      raise DuplicateLease(intent.lease_id)
    }
    if self.node_blocked_unlocked(intent.node_id) {
      raise NodeUnavailable(intent.node_id)
    }
    let lease = sign_lease(
      {
        intent,
        state: Reserved,
        generation: 1L,
        created_unix_ms: now_unix_ms,
        updated_unix_ms: now_unix_ms,
        evidence_receipt: "controller:reserved",
        authority_receipt: "",
      },
      self.signing_secret,
    )
    self.leases[intent.lease_id] = lease
    self.persist()
    self.mutex.release()
    lease
  } catch {
    error => {
      self.leases = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileExclusiveLeaseStore::transition(
  self : FileExclusiveLeaseStore,
  lease_id : String,
  request : @nodelease.ExclusiveLeaseTransitionRequest,
  now_unix_ms : Int64,
) -> @nodelease.ExclusiveNodeLease {
  self.mutex.acquire()
  let previous = self.leases.copy()
  try {
    guard self.leases.get(lease_id) is Some(lease) else {
      raise LeaseNotFound(lease_id)
    }
    let transitioned = sign_lease(
      lease.transition(
        request.state,
        request.expected_generation,
        request.evidence_receipt,
        now_unix_ms,
      ),
      self.signing_secret,
    )
    self.leases[lease_id] = transitioned
    self.persist()
    self.mutex.release()
    transitioned
  } catch {
    error => {
      self.leases = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileExclusiveLeaseStore::lease(
  self : FileExclusiveLeaseStore,
  lease_id : String,
) -> @nodelease.ExclusiveNodeLease? {
  self.mutex.acquire()
  let lease = self.leases.get(lease_id)
  self.mutex.release()
  lease
}

///|
pub async fn FileExclusiveLeaseStore::leases(
  self : FileExclusiveLeaseStore,
) -> Array[@nodelease.ExclusiveNodeLease] {
  self.mutex.acquire()
  let leases = sorted_leases(self.leases)
  self.mutex.release()
  leases
}

///|
/// Returns only leases owned by the verified subject. Callers must still bind
/// that subject to an active enterprise membership; this store method prevents
/// accidental customer-side filtering after a full authority snapshot read.
pub async fn FileExclusiveLeaseStore::leases_for_subject(
  self : FileExclusiveLeaseStore,
  subject_ref : String,
) -> Array[@nodelease.ExclusiveNodeLease] {
  if !@contracts.valid_identifier(subject_ref) {
    raise ExclusiveLeaseStoreError::InvalidSnapshot(
      "exclusive lease subject is invalid",
    )
  }
  self.mutex.acquire()
  let leases = sorted_leases(self.leases).filter(lease => {
    lease.intent.subject_ref == subject_ref
  })
  self.mutex.release()
  leases
}

///|
pub async fn FileExclusiveLeaseStore::lease_for_node(
  self : FileExclusiveLeaseStore,
  node_id : String,
) -> @nodelease.ExclusiveNodeLease? {
  self.mutex.acquire()
  let lease = self.leases
    .values()
    .find_first(value => {
      value.intent.node_id == node_id &&
      @nodelease.state_blocks_managed_placement(value.state)
    })
  self.mutex.release()
  lease
}

///|
/// Advances expired pre-access reservations to Cancelled and any possibly
/// provisioned lease to Expiring. Expiry never makes a provisioned node
/// available; revocation and sanitization must still complete.
pub async fn FileExclusiveLeaseStore::reconcile_expired(
  self : FileExclusiveLeaseStore,
  now_unix_ms : Int64,
) -> Bool {
  self.mutex.acquire()
  let previous = self.leases.copy()
  let mut changed = false
  try {
    for lease_id, lease in self.leases.copy() {
      if now_unix_ms >= lease.intent.expires_unix_ms {
        let next = match lease.state {
          Requested => Some(@nodelease.ExclusiveLeaseState::Cancelled)
          Reserved | Provisioning | Active => Some(Expiring)
          Expiring
          | Draining
          | RevokingAccess
          | Sanitizing
          | Completed
          | Cancelled
          | Quarantined => None
        }
        if next is Some(state) {
          self.leases[lease_id] = sign_lease(
            lease.transition(
              state,
              lease.generation,
              "controller:lease-expired",
              now_unix_ms,
            ),
            self.signing_secret,
          )
          changed = true
        }
      }
    }
    if changed {
      self.persist()
    }
    self.mutex.release()
    changed
  } catch {
    error => {
      self.leases = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileExclusiveLeaseStore::node_blocks_managed_placement(
  self : FileExclusiveLeaseStore,
  node_id : String,
) -> Bool {
  self.mutex.acquire()
  let blocked = self.node_blocked_unlocked(node_id)
  self.mutex.release()
  blocked
}
