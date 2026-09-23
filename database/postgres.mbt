///|
pub(all) suberror DatabaseError {
  ConnectionUnavailable(String)
  MigrationFailed(String)
  QueryFailed(String)
  UnsupportedSnapshot(String)
} derive(Debug, Eq)

///|
pub extend DatabaseError with Debug::{to_repr}

///|
pub extend DatabaseError with Eq::{not_equal, equal}

///|
pub struct PostgresDatabase {
  /// Used for startup work only: schema migration, close, ping, and the
  /// projection count. It is a blocking libpq connection, so nothing on a
  /// request path may go through it.
  connection : @postgres.Connection
  mutex : @async.Mutex
  url : String
  /// Pooled worker connections. Every statement issued after startup runs
  /// here, on a worker thread, awaited instead of blocked on.
  mut work : @pgclient.PgPool?
  /// A one-connection pool reserved for session-scoped authority. Leadership
  /// is bound to a backend pid, so those statements must not share a
  /// connection with anything else.
  mut leader : @pgclient.PgPool?
}

///|
/// One pooled connection borrowed for the length of a single operation. A
/// statement that fails may have left a transaction open, so the connection is
/// rolled back before it is returned to the pool.
pub struct PgOperation {
  connection : @pgclient.PgConnection
  mut failed : Bool
}

///|
async fn PgOperation::execute(
  self : PgOperation,
  sql : String,
  parameters? : Array[String?] = [],
) -> @pgclient.PgResult raise DatabaseError {
  self.connection.execute(sql, parameters~) catch {
    @pgclient.PgError::QueryRejected(message) => {
      self.failed = true
      raise QueryFailed(message)
    }
    @pgclient.PgError::InvalidArgument(message) => {
      self.failed = true
      raise QueryFailed(message)
    }
    @pgclient.PgError::ConnectionUnavailable(message) => {
      self.failed = true
      raise ConnectionUnavailable(message)
    }
    @pgclient.PgError::Timeout => {
      self.failed = true
      raise ConnectionUnavailable("database statement timed out")
    }
    @pgclient.PgError::Closed =>
      raise ConnectionUnavailable("database pool is closed")
    _ => {
      self.failed = true
      raise ConnectionUnavailable("database statement failed")
    }
  }
}

///|
fn PgOperation::release(self : PgOperation) -> Unit {
  self.connection.release()
}

///|
/// Runs `body` inside a transaction on a borrowed connection, committing when
/// the body returns and rolling back when it raises, then releases the
/// connection. The successful value of a `try` block is delivered to `noraise`,
/// so that arm must pass its value through: returning a constant there makes
/// every transaction look failed.
async fn with_transaction(
  connection : PgOperation,
  body : async (PgOperation) -> Unit,
) -> Unit {
  let mut failure : Error? = None
  let committed = try {
    ignore(run(connection, "BEGIN"))
    body(connection)
    ignore(run(connection, "COMMIT"))
    true
  } catch {
    error => {
      failure = Some(error)
      false
    }
  } noraise {
    value => value
  }
  if !committed {
    try ignore(connection.execute("ROLLBACK")) catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
  connection.release()
  match failure {
    Some(error) => raise error
    None => ()
  }
}

///|
/// Borrows a worker connection from the shared pool.
async fn PostgresDatabase::begin_operation(
  self : PostgresDatabase,
) -> PgOperation {
  let pool = self.work_pool()
  let connection = pool.acquire() catch {
    @pgclient.PgError::Closed =>
      raise ConnectionUnavailable("database pool is closed")
    @pgclient.PgError::ConnectionUnavailable(message) =>
      raise ConnectionUnavailable(message)
    _ => raise ConnectionUnavailable("database pool is unavailable")
  }
  { connection, failed: false, }
}

///|
/// Borrows the reserved connection. Statements that read or take
/// session-scoped authority must use this so `pg_backend_pid()` matches.
async fn PostgresDatabase::begin_leader_operation(
  self : PostgresDatabase,
) -> PgOperation {
  let pool = self.leader_pool()
  let connection = pool.acquire() catch {
    @pgclient.PgError::Closed =>
      raise ConnectionUnavailable("database pool is closed")
    @pgclient.PgError::ConnectionUnavailable(message) =>
      raise ConnectionUnavailable(message)
    _ => raise ConnectionUnavailable("database pool is unavailable")
  }
  { connection, failed: false, }
}

///|
async fn PostgresDatabase::work_pool(
  self : PostgresDatabase,
) -> @pgclient.PgPool {
  match self.work {
    Some(pool) => pool
    None => {
      let pool = self.make_pool(worker_count())
      self.work = Some(pool)
      pool
    }
  }
}

///|
async fn PostgresDatabase::leader_pool(
  self : PostgresDatabase,
) -> @pgclient.PgPool {
  match self.leader {
    Some(pool) => pool
    None => {
      let pool = self.make_pool(1)
      self.leader = Some(pool)
      pool
    }
  }
}

///|
/// Starts a pool, or raises if the operating system refuses its threads.
async fn PostgresDatabase::make_pool(
  self : PostgresDatabase,
  workers : Int,
) -> @pgclient.PgPool {
  try @pgclient.PgPool::connect(self.url, workers~) catch {
    @pgclient.PgError::InvalidArgument(message) => raise QueryFailed(message)
    @pgclient.PgError::ConnectionUnavailable(message) =>
      raise ConnectionUnavailable(message)
    @pgclient.PgError::QueryRejected(message) => raise QueryFailed(message)
    _ => raise ConnectionUnavailable("database pool is unavailable")
  } noraise {
    pool => pool
  }
}

///|
/// The blocking path, used only for startup work and liveness probes. Nothing
/// on a request path may call this: it holds the event loop for the round trip.
fn run_admin(
  connection : @postgres.Connection,
  sql : String,
  parameters? : Array[String?] = [],
) -> @postgres.QueryResult raise DatabaseError {
  connection.execute(sql, parameters~) catch {
    error => raise QueryFailed("\{Repr(error)}")
  }
}

///|
async fn run(
  connection : PgOperation,
  sql : String,
  parameters? : Array[String?] = [],
) -> @pgclient.PgResult raise DatabaseError {
  connection.execute(sql, parameters~)
}

///|
pub fn PostgresDatabase::open(
  connection_url : String,
) -> PostgresDatabase raise DatabaseError {
  let connection = @postgres.connect(connection_url) catch {
    error => raise ConnectionUnavailable("\{Repr(error)}")
  }
  ignore(run_admin(connection, schema_sql)) catch {
    error => {
      connection.close()
      raise MigrationFailed("\{Repr(error)}")
    }
  }
  { connection, mutex: Mutex(), url: connection_url, work: None, leader: None, }
}

///|
/// Workers to run statements on. Reads and writes wait on these instead of on
/// one shared connection, so a slow statement no longer queues every other
/// request behind it.
fn worker_count() -> Int {
  let configured = @env.get_env_var("LUNANEXA_DATABASE_WORKERS")
    .map(value => {
      try @string.parse_int(value) catch {
        _ => 0
      } noraise {
        v => v
      }
    })
    .unwrap_or(0)
  if configured > 0 && configured <= 32 {
    configured
  } else {
    4
  }
}

///|
pub fn PostgresDatabase::close(self : PostgresDatabase) -> Unit {
  // Closing the pooled connections matters as much as closing the admin one:
  // the controller's leadership is a session lock on the leader connection, so
  // until that connection goes away no other controller can take over.
  match self.work {
    Some(pool) => pool.close()
    None => ()
  }
  match self.leader {
    Some(pool) => pool.close()
    None => ()
  }
  self.connection.close()
}

///|
pub fn PostgresDatabase::ping(self : PostgresDatabase) -> Bool {
  try {
    let result = run_admin(self.connection, "SELECT 1")
    result.row_count() == 1 && result.value(0, 0) == Some("1")
  } catch {
    _ => false
  }
}

///|
pub fn PostgresDatabase::projection_count(
  self : PostgresDatabase,
  table : String,
) -> Int64 raise DatabaseError {
  if !projection_table_names.contains(table) {
    raise QueryFailed("projection table is not allowlisted")
  }
  let result = run_admin(
    self.connection,
    "SELECT count(*)::text FROM lunanexa.\{table}",
  )
  guard result.value(0, 0) is Some(value) else {
    raise QueryFailed("projection count result is empty")
  }
  @string.parse_int64(value) catch {
    _ => raise QueryFailed("projection count is invalid")
  }
}

///|
fn allowed_domain(domain : String) -> Bool {
  domain == "control" ||
  domain == "model_registry" ||
  domain == "node_enrollment" ||
  domain == "scheduler" ||
  domain == "telemetry" ||
  domain == "deployments" ||
  domain == "exclusive_deliveries" ||
  domain == "access_onboarding" ||
  domain == "accounts" ||
  domain == "client_handoffs" ||
  domain == "media_jobs" ||
  domain == "enterprise_portal" ||
  domain == "workspace_directory" ||
  domain == "workspace_admissions" ||
  domain == "access_keys" ||
  domain == "commercial" ||
  domain == "commercial_integrations" ||
  domain == "offline_commerce" ||
  domain == "machine_commerce" ||
  domain == "contract_documents" ||
  domain == "notifications" ||
  domain == "observability" ||
  domain == "technical_operations" ||
  domain == "credential_handoffs" ||
  domain == "exclusive_node_leases"
}

///|
let controller_advisory_lock_id : String = "5496452340495695181"

///|
fn valid_controller_holder(holder_id : String) -> Bool {
  let value = holder_id.trim()
  value.length() > 0 && value.length() <= 256
}

///|
/// Tries to become the sole active control-plane writer. PostgreSQL session
/// advisory locking supplies crash release; the monotonically increasing row
/// supplies a durable fencing token for assignments and readiness.
pub async fn PostgresDatabase::try_acquire_controller_leadership(
  self : PostgresDatabase,
  holder_id : String,
) -> Int64? {
  if !valid_controller_holder(holder_id) {
    raise QueryFailed("controller holder id is invalid")
  }
  let connection = self.begin_leader_operation()
  defer connection.release()
  let locked = run(
    connection,
    "SELECT pg_try_advisory_lock($1::bigint)::text",
    parameters=[Some(controller_advisory_lock_id)],
  )
  if locked.value(0, 0) != Some("true") && locked.value(0, 0) != Some("t") {
    return None
  }
  elect_controller(connection, holder_id)
}

///|
/// Runs the election, then drops the session advisory lock when any step after
/// taking it fails. The lock lives on the leader connection, so a failed
/// attempt must give it back instead of stranding it for the next controller.
async fn elect_controller(
  connection : PgOperation,
  holder_id : String,
) -> Int64? {
  let mut failure : Error? = None
  let mut elected : Int64 = 0L
  let succeeded = try {
    ignore(connection.execute("BEGIN"))
    let inserted = connection.execute(
      (
        #|INSERT INTO lunanexa.controller_leadership
        #|  (singleton, fencing_token, holder_id, backend_pid, acquired_at)
        #|VALUES (
        #|  true,
        #|  GREATEST(
        #|    1,
        #|    COALESCE((
        #|      SELECT (payload ->> 'controller_epoch')::bigint + 1
        #|      FROM lunanexa.snapshots WHERE domain = 'control'
        #|    ), 1)
        #|  ),
        #|  $1,
        #|  pg_backend_pid(),
        #|  now()
        #|)
        #|ON CONFLICT (singleton) DO UPDATE SET
        #|  fencing_token = GREATEST(
        #|    lunanexa.controller_leadership.fencing_token + 1,
        #|    COALESCE((
        #|      SELECT (payload ->> 'controller_epoch')::bigint + 1
        #|      FROM lunanexa.snapshots WHERE domain = 'control'
        #|    ), 1)
        #|  ),
        #|  holder_id = EXCLUDED.holder_id,
        #|  backend_pid = pg_backend_pid(),
        #|  acquired_at = now()
        #|RETURNING fencing_token::text
      ),
      parameters=[Some(holder_id.trim().to_owned())],
    )
    match inserted.value(0, 0) {
      Some(raw_token) =>
        elected = @string.parse_int64(raw_token) catch {
          _ => raise QueryFailed("controller leadership token is invalid")
        }
      None => raise QueryFailed("controller leadership token is missing")
    }
    ignore(connection.execute("COMMIT"))
    true
  } catch {
    error => {
      failure = Some(error)
      false
    }
  } noraise {
    value => value
  }
  if succeeded {
    Some(elected)
  } else {
    try ignore(connection.execute("ROLLBACK")) catch {
      _ => ()
    } noraise {
      _ => ()
    }
    release_controller_lock(connection)
    match failure {
      Some(error) => raise error
      None => None
    }
  }
}

///|
/// Drops the session advisory lock after a failed election attempt so another
/// controller can take over. Runs on the leader connection itself, which is
/// why it cannot be expressed as `errdefer`: it awaits.
async fn release_controller_lock(connection : PgOperation) -> Unit {
  try
    ignore(
      connection.execute("SELECT pg_advisory_unlock($1::bigint)", parameters=[
        Some(controller_advisory_lock_id),
      ]),
    )
  catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
/// Returns false after connection loss, leadership replacement, or token
/// mismatch. Callers use this on readiness and before every mutation.
pub async fn PostgresDatabase::controller_leadership_is_current(
  self : PostgresDatabase,
  holder_id : String,
  fencing_token : Int64,
) -> Bool {
  if !valid_controller_holder(holder_id) || fencing_token <= 0L {
    return false
  }
  let connection = self.begin_leader_operation()
  defer connection.release()
  let result = try {
    let checked = run(
      connection,
      (
        #|SELECT EXISTS (
        #|  SELECT 1 FROM lunanexa.controller_leadership
        #|  WHERE singleton = true
        #|    AND holder_id = $1
        #|    AND fencing_token = $2::bigint
        #|    AND backend_pid = pg_backend_pid()
        #|)::text
      ),
      parameters=[
        Some(holder_id.trim().to_owned()),
        Some(fencing_token.to_string()),
      ],
    )
    checked.value(0, 0) == Some("true") || checked.value(0, 0) == Some("t")
  } catch {
    _ => false
  }
  result
}

///|
pub async fn PostgresDatabase::load_snapshot(
  self : PostgresDatabase,
  domain : String,
  expected_schema_version : String,
) -> String? {
  if !allowed_domain(domain) || expected_schema_version.trim() == "" {
    raise UnsupportedSnapshot(domain)
  }
  let connection = self.begin_operation()
  defer connection.release()
  let result = run(
    connection,
    "SELECT schema_version, payload::text FROM lunanexa.snapshots WHERE domain = $1",
    parameters=[Some(domain)],
  )
  if result.row_count() == 0 {
    return None
  }
  guard result.value(0, 0) is Some(schema) &&
    result.value(0, 1) is Some(payload) else {
    raise QueryFailed("snapshot row is incomplete")
  }
  if schema != expected_schema_version {
    raise UnsupportedSnapshot(schema)
  }
  Some(payload)
}

///|
async fn write_snapshot_row(
  connection : PgOperation,
  domain : String,
  version : String,
  payload : String,
) -> Unit raise DatabaseError {
  ignore(
    run(
      connection,
      (
        #|INSERT INTO lunanexa.snapshots(domain, schema_version, payload)
        #|VALUES ($1, $2, $3::jsonb)
        #|ON CONFLICT (domain) DO UPDATE SET
        #|  schema_version = EXCLUDED.schema_version,
        #|  revision = lunanexa.snapshots.revision + 1,
        #|  payload = EXCLUDED.payload,
        #|  updated_at = now()
      ),
      parameters=[Some(domain), Some(version), Some(payload)],
    ),
  )
}

///|
pub async fn PostgresDatabase::save_opaque_snapshot(
  self : PostgresDatabase,
  domain : String,
  version : String,
  payload : String,
) -> Unit {
  if !allowed_domain(domain) || version.trim() == "" {
    raise UnsupportedSnapshot(domain)
  }
  ignore(@json.parse(payload) catch { _ => raise UnsupportedSnapshot(domain) })
  let connection = self.begin_operation()
  with_transaction(connection, op => {
    write_snapshot_row(op, domain, version, payload)
  })
}

///|
/// Atomically commits related opaque domain snapshots. This is used for
/// callback/business transitions that must never survive independently.
pub async fn PostgresDatabase::save_opaque_snapshots(
  self : PostgresDatabase,
  snapshots : Array[(String, String, String)],
) -> Unit {
  if snapshots.length() == 0 || snapshots.length() > 16 {
    raise UnsupportedSnapshot("snapshot batch")
  }
  let domains : Map[String, Unit] = Map([])
  for snapshot in snapshots {
    let (domain, version, payload) = snapshot
    if !allowed_domain(domain) ||
      version.trim() == "" ||
      domains.contains(domain) {
      raise UnsupportedSnapshot(domain)
    }
    ignore(
      @json.parse(payload) catch {
        _ => raise UnsupportedSnapshot(domain)
      },
    )
    domains[domain] = ()
  }
  let connection = self.begin_operation()
  with_transaction(connection, op => {
    for snapshot in snapshots {
      let (domain, version, payload) = snapshot
      write_snapshot_row(op, domain, version, payload)
    }
  })
}

///|
/// Appends one operational event to the append-only event relation. The event
/// identifier is the primary key, so replaying an already stored event is a
/// no-op instead of a duplicate row. Operational events intentionally are not
/// part of `lunanexa.snapshots`: rewriting the whole recent window on every
/// request is what made an event cost a multi-megabyte write.
pub async fn PostgresDatabase::append_operational_event(
  self : PostgresDatabase,
  event_id : String,
  timestamp_unix_ms : Int64,
  payload : String,
) -> Unit {
  if event_id.trim() == "" || event_id.length() > 256 || timestamp_unix_ms <= 0L {
    raise QueryFailed("operational event row is invalid")
  }
  ignore(
    @json.parse(payload) catch {
      _ => raise QueryFailed("operational event payload is invalid")
    },
  )
  let connection = self.begin_operation()
  defer connection.release()
  ignore(
    run(
      connection,
      (
        #|INSERT INTO lunanexa.operational_events(event_id, timestamp_unix_ms, payload)
        #|VALUES ($1, $2::bigint, $3::jsonb)
        #|ON CONFLICT (event_id) DO NOTHING
      ),
      parameters=[
        Some(event_id),
        Some(timestamp_unix_ms.to_string()),
        Some(payload),
      ],
    ),
  )
}

///|
/// Loads the newest bounded operational event window as JSON payloads,
/// oldest-first so a caller can rebuild its in-memory ordering directly. Rows
/// sharing one millisecond are ordered by event identifier; that tie-break is
/// stable across restarts but is not necessarily the original arrival order.
pub async fn PostgresDatabase::load_recent_operational_events(
  self : PostgresDatabase,
  limit : Int,
) -> Array[String] {
  if limit <= 0 || limit > 1000000 {
    raise QueryFailed("operational event window is invalid")
  }
  let connection = self.begin_operation()
  defer connection.release()
  let result = run(
    connection,
    (
      #|SELECT payload::text FROM lunanexa.operational_events
      #|ORDER BY timestamp_unix_ms DESC, event_id DESC
      #|LIMIT $1::bigint
    ),
    parameters=[Some(limit.to_string())],
  )
  let events : Array[String] = []
  for index in 0..<result.row_count() {
    guard result.value(index, 0) is Some(payload) else {
      raise QueryFailed("operational event row is incomplete")
    }
    events.push(payload)
  }
  events.rev_in_place()
  events
}

///|
/// Counts durable operational events.
pub async fn PostgresDatabase::operational_event_count(
  self : PostgresDatabase,
) -> Int64 {
  let connection = self.begin_operation()
  defer connection.release()
  let result = run(
    connection, "SELECT count(*)::text FROM lunanexa.operational_events",
  )
  guard result.value(0, 0) is Some(value) else {
    raise QueryFailed("operational event count result is empty")
  }
  @string.parse_int64(value) catch {
    _ => raise QueryFailed("operational event count is invalid")
  }
}

///|
/// Deletes operational events outside the newest `keep` window. Callers run
/// this on open and thereafter on an amortised schedule, because the durable
/// relation only has to stay bounded, not exactly trimmed on every request.
pub async fn PostgresDatabase::prune_operational_events(
  self : PostgresDatabase,
  keep : Int,
) -> Unit {
  if keep <= 0 || keep > 1000000 {
    raise QueryFailed("operational event retention window is invalid")
  }
  let connection = self.begin_operation()
  defer connection.release()
  ignore(
    run(
      connection,
      (
        #|DELETE FROM lunanexa.operational_events
        #|WHERE event_id NOT IN (
        #|  SELECT event_id FROM lunanexa.operational_events
        #|  ORDER BY timestamp_unix_ms DESC, event_id DESC
        #|  LIMIT $1::bigint
        #|)
      ),
      parameters=[Some(keep.to_string())],
    ),
  )
}

///|
pub async fn PostgresDatabase::save_portal_snapshot(
  self : PostgresDatabase,
  snapshot : @portal.PortalSnapshot,
) -> Unit {
  if snapshot.schema_version != @portal.snapshot_schema_version {
    raise UnsupportedSnapshot(snapshot.schema_version)
  }
  let connection = self.begin_operation()
  with_transaction(connection, op => {
    write_snapshot_row(
      connection,
      "enterprise_portal",
      snapshot.schema_version,
      snapshot.to_json().stringify(),
    )
    ignore(run(op, "DELETE FROM lunanexa.portal_lease_requests"))
    ignore(run(op, "DELETE FROM lunanexa.portal_agreements"))
    ignore(run(op, "DELETE FROM lunanexa.enterprise_memberships"))
    for membership in snapshot.memberships {
      ignore(
        run(
          connection,
          (
            #|INSERT INTO lunanexa.enterprise_memberships
            #|  (membership_id, tenant_ref, organization_id, subject_ref, active, created_unix_ms, payload)
            #|VALUES ($1, $2, $3, $4, $5::boolean, $6::bigint, $7::jsonb)
          ),
          parameters=[
            Some(membership.membership_id),
            Some(membership.tenant_ref),
            Some(membership.organization_id),
            Some(membership.subject_ref),
            Some(membership.active.to_string()),
            Some(membership.created_unix_ms.to_string()),
            Some(membership.to_json().stringify()),
          ],
        ),
      )
    }
    for agreement in snapshot.agreements {
      ignore(
        run(
          connection,
          (
            #|INSERT INTO lunanexa.portal_agreements
            #|  (agreement_id, tenant_ref, organization_id, state, generation, signer_subject_ref, updated_unix_ms, payload)
            #|VALUES ($1, $2, $3, $4::jsonb #>> '{}', $5::bigint, $6, $7::bigint, $8::jsonb)
          ),
          parameters=[
            Some(agreement.agreement_id),
            Some(agreement.tenant_ref),
            Some(agreement.organization_id),
            Some(agreement.state.to_json().stringify()),
            Some(agreement.generation.to_string()),
            agreement.signer_subject_ref,
            Some(agreement.updated_unix_ms.to_string()),
            Some(agreement.to_json().stringify()),
          ],
        ),
      )
    }
    for request in snapshot.lease_requests {
      ignore(
        run(
          connection,
          (
            #|INSERT INTO lunanexa.portal_lease_requests
            #|  (request_id, idempotency_key, tenant_ref, organization_id, subject_ref, state, generation, assigned_node_id, updated_unix_ms, payload)
            #|VALUES ($1, $2, $3, $4, $5, $6::jsonb #>> '{}', $7::bigint, $8, $9::bigint, $10::jsonb)
          ),
          parameters=[
            Some(request.submission.request_id),
            Some(request.submission.idempotency_key),
            Some(request.submission.tenant_ref),
            Some(request.submission.organization_id),
            Some(request.subject_ref),
            Some(request.state.to_json().stringify()),
            Some(request.generation.to_string()),
            request.assigned_node_id,
            Some(request.updated_unix_ms.to_string()),
            Some(request.to_json().stringify()),
          ],
        ),
      )
    }
  })
}

///|
pub async fn PostgresDatabase::save_workspace_snapshot(
  self : PostgresDatabase,
  snapshot : @workspace.WorkspaceDirectorySnapshot,
) -> Unit {
  if snapshot.schema_version != @workspace.directory_schema_version {
    raise UnsupportedSnapshot(snapshot.schema_version)
  }
  let connection = self.begin_operation()
  with_transaction(connection, op => {
    write_snapshot_row(
      connection,
      "workspace_directory",
      snapshot.schema_version,
      snapshot.to_json().stringify(),
    )
    ignore(run(op, "DELETE FROM lunanexa.workspace_access_grants"))
    ignore(run(op, "DELETE FROM lunanexa.workspace_leases"))
    ignore(run(op, "DELETE FROM lunanexa.workspace_users"))
    for user in snapshot.users {
      ignore(
        run(
          connection,
          (
            #|INSERT INTO lunanexa.workspace_users
            #|  (user_id, subject_ref, email, state, created_unix_ms, payload)
            #|VALUES ($1, $2, $3, $4::jsonb #>> '{}', $5::bigint, $6::jsonb)
          ),
          parameters=[
            Some(user.user_id),
            Some(user.subject_ref),
            Some(user.email),
            Some(user.state.to_json().stringify()),
            Some(user.created_unix_ms.to_string()),
            Some(user.to_json().stringify()),
          ],
        ),
      )
    }
    for grant in snapshot.access_grants {
      ignore(
        run(
          connection,
          (
            #|INSERT INTO lunanexa.workspace_access_grants
            #|  (grant_id, user_id, tenant_ref, state, expires_unix_ms, payload)
            #|VALUES ($1, $2, $3, $4::jsonb #>> '{}', $5::bigint, $6::jsonb)
          ),
          parameters=[
            Some(grant.grant_id),
            Some(grant.user_id),
            Some(grant.tenant_ref),
            Some(grant.state.to_json().stringify()),
            Some(grant.expires_unix_ms.to_string()),
            Some(grant.to_json().stringify()),
          ],
        ),
      )
    }
    for lease in snapshot.leases {
      ignore(
        run(
          connection,
          (
            #|INSERT INTO lunanexa.workspace_leases
            #|  (lease_id, tenant_ref, subject_ref, state, starts_unix_ms, expires_unix_ms, payload)
            #|VALUES ($1, $2, $3, $4::jsonb #>> '{}', $5::bigint, $6::bigint, $7::jsonb)
          ),
          parameters=[
            Some(lease.lease_id),
            Some(lease.tenant_ref),
            Some(lease.subject_ref),
            Some(lease.state.to_json().stringify()),
            Some(lease.starts_unix_ms.to_string()),
            Some(lease.expires_unix_ms.to_string()),
            Some(lease.to_json().stringify()),
          ],
        ),
      )
    }
  })
}
