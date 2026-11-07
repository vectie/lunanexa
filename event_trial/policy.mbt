///|
/// Operator-owned event admission policy. Enabling registration never allocates
/// machines. All selected nodes must already serve the approved text model.
pub(all) struct Policy {
  event_id : String
  title : String
  starts_unix_ms : Int64
  // Zero means ongoing enrollment with a fixed seven-day grant per account.
  // Positive values retain the legacy fixed event deadline.
  expires_unix_ms : Int64
  // Zero means no participant / request-count cap; usage is still recorded.
  maximum_users : Int32
  maximum_requests : Int64
  // Canonical UTF-8 request payload bytes, not model tokens. Legacy events keep 8 KiB.
  max_input_bytes : Int32?
  // Absent in legacy snapshots; changed explicitly through the operator UI.
  max_output_tokens : Int32?
  allowed_models : Array[String]
  node_ids : Array[String]
  // Zero leaves concurrency to the serving runtime and infrastructure admission.
  // A positive value is an explicit operator-selected per-replica limit.
  per_node_concurrency : Int32
  registration_open : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend Policy with Debug::{to_repr}

///|
pub extend Policy with Eq::{equal, not_equal}

///|
pub extend Policy with ToJson::{to_json}

///|
pub extend Policy with FromJson::{from_json}

///|
pub fn Policy::valid(self : Policy) -> Bool {
  @contracts.valid_identifier(self.event_id) &&
  self.title.trim() != "" &&
  self.title.length() <= 128 &&
  self.title.all(c => c.is_printable()) &&
  self.starts_unix_ms > 0L &&
  (
    self.expires_unix_ms == 0L ||
    (
      self.expires_unix_ms > self.starts_unix_ms &&
      self.expires_unix_ms - self.starts_unix_ms <= 2592000000L
    )
  ) &&
  self.maximum_users >= 0 &&
  self.maximum_requests >= 0L &&
  self.maximum_requests <= 10000L &&
  self.input_budget() > 0 &&
  self.input_budget() <= 65536 &&
  self.output_budget() > 0 &&
  self.output_budget() <= 131072 &&
  self.allowed_models.length() == 1 &&
  self.allowed_models.all(v => @contracts.valid_identifier(v)) &&
  self.node_ids.length() >= 1 &&
  self.node_ids.length() <= 4 &&
  self.node_ids.all(v => {
    @contracts.valid_identifier(v) && self.node_ids.count(v) == 1
  }) &&
  self.per_node_concurrency >= 0
}

///|
pub fn Policy::input_budget(self : Policy) -> Int32 {
  self.max_input_bytes.unwrap_or(8192)
}

///|
pub fn Policy::output_budget(self : Policy) -> Int32 {
  self.max_output_tokens.unwrap_or(1024)
}

///|
pub fn Policy::accepting(self : Policy, now : Int64) -> Bool {
  self.registration_open && self.within_window(now)
}

///|
pub fn Policy::within_window(self : Policy, now : Int64) -> Bool {
  self.starts_unix_ms <= now && !self.ended(now)
}

///|
pub fn Policy::ended(self : Policy, now : Int64) -> Bool {
  self.expires_unix_ms != 0L && now >= self.expires_unix_ms
}

///|
pub fn Policy::grant_expires(self : Policy, starts : Int64) -> Int64 {
  if self.expires_unix_ms == 0L {
    starts + 604800000L
  } else {
    self.expires_unix_ms
  }
}

///|
pub fn Policy::overlaps(self : Policy, other : Policy) -> Bool {
  !self.ended(other.starts_unix_ms) && !other.ended(self.starts_unix_ms)
}

///|
/// Topology is visible to operators only, never to registration responses.
pub(all) struct View {
  policy : Policy
  registered_users : Int32
  ready_nodes : Array[String]
  blockers : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend View with Debug::{to_repr}

///|
pub extend View with Eq::{equal, not_equal}

///|
pub extend View with ToJson::{to_json}

///|
pub extend View with FromJson::{from_json}
