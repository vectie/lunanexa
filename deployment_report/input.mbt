///|
fn identity(value : String) -> Unit raise ReportError {
  if value == "" || value.length() > 512 {
    raise InvalidInput("identity must contain 1..512 UTF-16 characters")
  }
}

///|
fn time(value : Int64) -> Unit raise ReportError {
  if value < 0L || value > 9007199254740991L {
    raise InvalidInput("time must be within 0..9007199254740991 ms")
  }
}

///|
fn validate_query(query : Query) -> Unit raise ReportError {
  time(query.now_unix_ms)
  time(query.maximum_age_ms)
  for value in [query.deployment_id, query.model_id, query.node_id] {
    if value.length() > 512 {
      raise InvalidInput("filter exceeds 512 characters")
    }
  }
  if ![
      "", "Submitted", "Blocked", "Planned", "Reconciling", "Ready", "Degraded",
      "RollingBack", "RolledBack", "Failed", "Deleted",
    ].contains(query.operation_state) {
    raise InvalidInput("unknown operation_state filter")
  }
}

///|
pub fn import_query(text : String) -> Query raise {
  if text.length() > 16384 {
    raise InvalidInput("query exceeds 16 Ki characters")
  }
  let value = @json.parse(text)
  guard value is Object(fields) else {
    raise InvalidInput("query must be an object")
  }
  for key, _ in fields {
    if ![
        "now_unix_ms", "maximum_age_ms", "deployment_id", "model_id", "operation_state",
        "node_id",
      ].contains(key) {
      raise InvalidInput("unknown query field: " + key)
    }
  }
  let query : Query = @json.from_json(value)
  validate_query(query)
  query
}

///|
pub fn import_operations(
  text : String,
) -> Array[@deployment.DeploymentOperation] raise {
  if text.length() > 8388608 {
    raise InvalidInput("operations exceed 8 Mi characters")
  }
  let value = @json.parse(text)
  guard value is Array(rows) && rows.length() <= 1000 else {
    raise InvalidInput("expected at most 1000 operations in an array")
  }
  @json.from_json(value)
}

///|
pub fn import_nodes(text : String) -> Array[@contracts.NodeHeartbeat] raise {
  if text.length() > 8388608 {
    raise InvalidInput("nodes exceed 8 Mi characters")
  }
  let value = @json.parse(text)
  guard value is Array(rows) && rows.length() <= 10000 else {
    raise InvalidInput("expected at most 10000 heartbeats in an array")
  }
  @json.from_json(value)
}

///|
fn state_name(state : @deployment.DeploymentOperationState) -> String {
  match state {
    Submitted => "Submitted"
    Blocked => "Blocked"
    Planned => "Planned"
    Reconciling => "Reconciling"
    Ready => "Ready"
    Degraded => "Degraded"
    RollingBack => "RollingBack"
    RolledBack => "RolledBack"
    Failed => "Failed"
    Deleted => "Deleted"
  }
}

///|
fn node_state(state : @contracts.NodeState) -> String {
  match state {
    Enrolling => "Enrolling"
    Active => "Active"
    Cordoned => "Cordoned"
    Draining => "Draining"
    Unreachable => "Unreachable"
    Retired => "Retired"
  }
}
