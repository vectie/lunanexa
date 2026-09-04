///|
priv struct GatewaySessionStore {
  connection : @postgres.Connection
  mutex : @async.Mutex
}

///|
fn GatewaySessionStore::open(
  database_url : String,
) -> GatewaySessionStore raise {
  let connection = @postgres.connect(database_url)
  let create_table_sql =
    #|CREATE TABLE IF NOT EXISTS lunanexa.identity_gateway_sessions (
    #|  session_id text PRIMARY KEY,
    #|  audience text NOT NULL,
    #|  browser_host text NOT NULL,
    #|  expires_unix_ms bigint NOT NULL,
    #|  payload jsonb NOT NULL,
    #|  created_at timestamptz NOT NULL DEFAULT now()
    #|)
  ignore(connection.execute(create_table_sql))
  let create_index_sql =
    #|CREATE INDEX IF NOT EXISTS identity_gateway_sessions_expiry_idx
    #|ON lunanexa.identity_gateway_sessions (expires_unix_ms)
  ignore(connection.execute(create_index_sql))
  { connection, mutex: @async.Mutex() }
}

///|
fn GatewaySessionStore::close(self : GatewaySessionStore) -> Unit {
  self.connection.close()
}

///|
async fn GatewaySessionStore::ping(self : GatewaySessionStore) -> Bool {
  self.mutex.acquire()
  defer self.mutex.release()
  let healthy = try {
    let result = self.connection.execute("SELECT 1")
    result.row_count() == 1 && result.value(0, 0) == Some("1")
  } catch {
    _ => false
  }
  healthy
}

///|
async fn GatewaySessionStore::create(
  self : GatewaySessionStore,
  value : GatewayCookie,
) -> String {
  let id = random_token(32)
  self.mutex.acquire()
  defer self.mutex.release()
  let insert_sql =
    #|INSERT INTO lunanexa.identity_gateway_sessions
    #|  (session_id, audience, browser_host, expires_unix_ms, payload)
    #|VALUES ($1, $2, $3, $4::bigint, $5::jsonb)
  ignore(
    self.connection.execute(insert_sql, parameters=[
      Some(id),
      Some(value.audience),
      Some(value.host),
      Some(value.expires_unix_ms.to_string()),
      Some(value.to_json().stringify()),
    ]),
  )
  ignore(
    self.connection.execute(
      "DELETE FROM lunanexa.identity_gateway_sessions WHERE expires_unix_ms <= $1::bigint",
      parameters=[Some(@async.now().to_string())],
    ),
  )
  id
}

///|
async fn GatewaySessionStore::load(
  self : GatewaySessionStore,
  id : String,
) -> GatewayCookie? {
  self.mutex.acquire()
  defer self.mutex.release()
  let result = {
    let select_sql =
      #|SELECT payload::text
      #|FROM lunanexa.identity_gateway_sessions
      #|WHERE session_id = $1 AND expires_unix_ms > $2::bigint
    let queried = self.connection.execute(select_sql, parameters=[
      Some(id),
      Some(@async.now().to_string()),
    ])
    if queried.row_count() == 1 && queried.value(0, 0) is Some(payload) {
      Some(@json.from_json(@json.parse(payload)))
    } else {
      None
    }
  }
  result
}

///|
async fn GatewaySessionStore::replace(
  self : GatewaySessionStore,
  id : String,
  value : GatewayCookie,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  let update_sql =
    #|UPDATE lunanexa.identity_gateway_sessions
    #|SET audience = $2, browser_host = $3, expires_unix_ms = $4::bigint,
    #|    payload = $5::jsonb
    #|WHERE session_id = $1
  let updated = self.connection.execute(update_sql, parameters=[
    Some(id),
    Some(value.audience),
    Some(value.host),
    Some(value.expires_unix_ms.to_string()),
    Some(value.to_json().stringify()),
  ])
  guard updated.affected_rows() == 1L else {
    raise Failure("identity-gateway session disappeared")
  }
}

///|
async fn GatewaySessionStore::delete(
  self : GatewaySessionStore,
  id : String,
) -> Bool {
  self.mutex.acquire()
  defer self.mutex.release()
  let deleted = {
    let result = self.connection.execute(
      "DELETE FROM lunanexa.identity_gateway_sessions WHERE session_id = $1",
      parameters=[Some(id)],
    )
    result.affected_rows() == 1L
  }
  deleted
}
