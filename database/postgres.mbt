///|
pub(all) suberror DatabaseError {
  ConnectionUnavailable(String)
  MigrationFailed(String)
  QueryFailed(String)
  UnsupportedSnapshot(String)
} derive(Debug, Eq)

///|
pub struct PostgresDatabase {
  connection : @postgres.Connection
  mutex : @async.Mutex
}

///|
fn run(
  connection : @postgres.Connection,
  sql : String,
  parameters? : Array[String?] = [],
) -> @postgres.QueryResult raise DatabaseError {
  connection.execute(sql, parameters~) catch {
    error => raise QueryFailed("\{Repr(error)}")
  }
}

///|
fn rollback(connection : @postgres.Connection) -> Unit {
  ignore(connection.execute("ROLLBACK")) catch {
    _ => ()
  }
}

///|
pub fn PostgresDatabase::open(
  connection_url : String,
) -> PostgresDatabase raise DatabaseError {
  let connection = @postgres.connect(connection_url) catch {
    error => raise ConnectionUnavailable("\{Repr(error)}")
  }
  ignore(run(connection, schema_sql)) catch {
    error => {
      connection.close()
      raise MigrationFailed("\{Repr(error)}")
    }
  }
  { connection, mutex: Mutex() }
}

///|
pub fn PostgresDatabase::close(self : PostgresDatabase) -> Unit {
  self.connection.close()
}

///|
pub fn PostgresDatabase::ping(self : PostgresDatabase) -> Bool {
  try {
    let result = run(self.connection, "SELECT 1")
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
  let result = run(
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
  domain == "enterprise_portal" ||
  domain == "workspace_directory" ||
  domain == "workspace_admissions" ||
  domain == "access_keys" ||
  domain == "commercial" ||
  domain == "commercial_integrations" ||
  domain == "notifications" ||
  domain == "observability" ||
  domain == "technical_operations"
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
  self.mutex.acquire()
  try {
    let result = run(
      self.connection,
      "SELECT schema_version, payload::text FROM lunanexa.snapshots WHERE domain = $1",
      parameters=[Some(domain)],
    )
    if result.row_count() == 0 {
      self.mutex.release()
      return None
    }
    guard result.value(0, 0) is Some(schema) &&
      result.value(0, 1) is Some(payload) else {
      raise QueryFailed("snapshot row is incomplete")
    }
    if schema != expected_schema_version {
      raise UnsupportedSnapshot(schema)
    }
    self.mutex.release()
    Some(payload)
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
}

///|
fn write_snapshot_row(
  connection : @postgres.Connection,
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
  self.mutex.acquire()
  try {
    ignore(run(self.connection, "BEGIN"))
    write_snapshot_row(self.connection, domain, version, payload)
    ignore(run(self.connection, "COMMIT"))
    self.mutex.release()
  } catch {
    error => {
      rollback(self.connection)
      self.mutex.release()
      raise error
    }
  }
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
  self.mutex.acquire()
  try {
    ignore(run(self.connection, "BEGIN"))
    for snapshot in snapshots {
      let (domain, version, payload) = snapshot
      write_snapshot_row(self.connection, domain, version, payload)
    }
    ignore(run(self.connection, "COMMIT"))
    self.mutex.release()
  } catch {
    error => {
      rollback(self.connection)
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn PostgresDatabase::save_portal_snapshot(
  self : PostgresDatabase,
  snapshot : @portal.PortalSnapshot,
) -> Unit {
  if snapshot.schema_version != @portal.snapshot_schema_version {
    raise UnsupportedSnapshot(snapshot.schema_version)
  }
  self.mutex.acquire()
  try {
    ignore(run(self.connection, "BEGIN"))
    write_snapshot_row(
      self.connection,
      "enterprise_portal",
      snapshot.schema_version,
      snapshot.to_json().stringify(),
    )
    ignore(run(self.connection, "DELETE FROM lunanexa.portal_lease_requests"))
    ignore(run(self.connection, "DELETE FROM lunanexa.portal_agreements"))
    ignore(run(self.connection, "DELETE FROM lunanexa.enterprise_memberships"))
    for membership in snapshot.memberships {
      ignore(
        run(
          self.connection,
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
          self.connection,
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
          self.connection,
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
    ignore(run(self.connection, "COMMIT"))
    self.mutex.release()
  } catch {
    error => {
      rollback(self.connection)
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn PostgresDatabase::save_workspace_snapshot(
  self : PostgresDatabase,
  snapshot : @workspace.WorkspaceDirectorySnapshot,
) -> Unit {
  if snapshot.schema_version != @workspace.directory_schema_version {
    raise UnsupportedSnapshot(snapshot.schema_version)
  }
  self.mutex.acquire()
  try {
    ignore(run(self.connection, "BEGIN"))
    write_snapshot_row(
      self.connection,
      "workspace_directory",
      snapshot.schema_version,
      snapshot.to_json().stringify(),
    )
    ignore(run(self.connection, "DELETE FROM lunanexa.workspace_access_grants"))
    ignore(run(self.connection, "DELETE FROM lunanexa.workspace_leases"))
    ignore(run(self.connection, "DELETE FROM lunanexa.workspace_users"))
    for user in snapshot.users {
      ignore(
        run(
          self.connection,
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
          self.connection,
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
          self.connection,
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
    ignore(run(self.connection, "COMMIT"))
    self.mutex.release()
  } catch {
    error => {
      rollback(self.connection)
      self.mutex.release()
      raise error
    }
  }
}
