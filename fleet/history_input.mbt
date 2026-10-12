///|
/// Each path names an existing saved GET /v1/nodes response. Import is pure;
/// only the native command resolves and reads paths relative to the manifest.
pub(all) struct HistorySource {
  capture_id : String
  captured_unix_ms : Int64
  path : String
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct HistoryManifest {
  schema_version : String
  captures : Array[HistorySource]
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct HistoryCapture {
  capture_id : String
  captured_unix_ms : Int64
  nodes : Array[@contracts.NodeHeartbeat]
}

///|
pub(all) struct HistoryQuery {
  node_id : String
  scope : String
  field : String
} derive(Eq, ToJson, FromJson)

///|
fn history_fields(
  value : Json,
  allowed : Array[String],
) -> Unit raise FleetError {
  guard value is Object(fields) else {
    raise InvalidInput("history input must be an object")
  }
  for key, _ in fields {
    if !allowed.contains(key) {
      raise InvalidInput("unknown history field: \{key}")
    }
  }
}

///|
fn validate_capture_ids(
  captures : Array[(String, Int64)],
) -> Unit raise FleetError {
  if captures.length() < 2 || captures.length() > 16 {
    raise InvalidInput("history requires 2 to 16 captures")
  }
  let seen : Map[String, Bool] = Map([])
  let mut previous = -1L
  for (id, time) in captures {
    if id.trim().is_empty() || seen.contains(id) {
      raise InvalidInput("capture IDs must be nonempty and unique")
    }
    if time < 0L || time > 9007199254740991L || time <= previous {
      raise InvalidInput(
        "capture times must strictly increase within 0..9007199254740991 ms",
      )
    }
    seen[id] = true
    previous = time
  }
}

///|
pub fn import_history_manifest(text : String) -> HistoryManifest raise {
  if text.length() > 65536 {
    raise InvalidInput("history manifest exceeds 64 Ki characters")
  }
  let value = @json.parse(text)
  history_fields(value, ["schema_version", "captures"])
  guard value is { "captures": Array(captures), .. } else {
    raise InvalidInput("history manifest requires a captures array")
  }
  for capture in captures {
    history_fields(capture, ["capture_id", "captured_unix_ms", "path"])
  }
  let manifest : HistoryManifest = @json.from_json(value)
  if manifest.schema_version != "lunanexa.fleet.history-input.v1" {
    raise InvalidInput("unsupported history manifest version")
  }
  validate_capture_ids(
    manifest.captures.map(c => (c.capture_id, c.captured_unix_ms)),
  )
  for capture in manifest.captures {
    if capture.path.trim().is_empty() {
      raise InvalidInput("capture path must be nonempty")
    }
  }
  manifest
}

///|
fn validate_history_query(query : HistoryQuery) -> Unit raise FleetError {
  if !["all", "node", "device"].contains(query.scope) {
    raise InvalidInput("history scope must be all/node/device")
  }
  if ![
      "", "presence", "state", "agent_version", "runtime_names", "running_deployment_count",
      "architecture", "healthy", "observed_total_mib", "observed_free_mib",
    ].contains(query.field) {
    raise InvalidInput("unknown history field filter")
  }
}

///|
pub fn import_history_query(text : String) -> HistoryQuery raise {
  if text.length() > 16384 {
    raise InvalidInput("history query exceeds 16 Ki characters")
  }
  let value = @json.parse(text)
  history_fields(value, ["node_id", "scope", "field"])
  let query : HistoryQuery = @json.from_json(value)
  validate_history_query(query)
  query
}

///|
pub extend HistoryManifest with ToJson::{to_json}

///|
pub extend HistorySource with ToJson::{to_json}

///|
pub extend HistoryQuery with ToJson::{to_json}

///|
pub extend HistoryManifest with Eq::{equal, not_equal}

///|
pub extend HistoryManifest with FromJson::{from_json}

///|
pub extend HistorySource with Eq::{equal, not_equal}

///|
pub extend HistorySource with FromJson::{from_json}

///|
pub extend HistoryQuery with Eq::{equal, not_equal}

///|
pub extend HistoryQuery with FromJson::{from_json}
