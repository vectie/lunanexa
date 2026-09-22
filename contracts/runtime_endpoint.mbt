///|
/// Keep the original v1 wire representation when discovery is not advertised.

///|
pub extend NodeHeartbeat with ToJson::{to_json}

///|
pub impl ToJson for NodeHeartbeat with fn to_json(self) {
  let value : Json = {
    "node_id": self.node_id,
    "state": ToJson::to_json(self.state),
    "observed_generation": self.observed_generation.to_json(),
    "controller_epoch": self.controller_epoch.to_json(),
    "inventory": ToJson::to_json(self.inventory),
    "running_deployments": self.running_deployments.to_json(),
    "timestamp_unix_ms": self.timestamp_unix_ms.to_json(),
    "signature": self.signature,
  }
  if self.runtime_endpoints is Some(endpoints) && value is Object(fields) {
    fields["runtime_endpoints"] = endpoints.to_json()
  }
  value
}

///|
/// Node-attested location of one runtime incarnation, never a customer URL.
pub(all) struct RuntimeEndpoint {
  assignment_id : String
  deployment_id : String
  generation : Int64
  controller_epoch : Int64
  instance_id : String
  address : String
  port : Int
  artifact_digest : String
  image_digest : String
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RuntimeEndpoint with Debug::{to_repr}

///|
pub extend RuntimeEndpoint with Eq::{not_equal, equal}

///|
pub extend RuntimeEndpoint with ToJson::{to_json}

///|
pub extend RuntimeEndpoint with FromJson::{from_json}

///|
/// Administrator-owned per-node private IPv4 route boundary.
pub(all) struct RuntimeRoutePolicy {
  network : String
  prefix_length : Int
  port : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RuntimeRoutePolicy with Debug::{to_repr}

///|
pub extend RuntimeRoutePolicy with Eq::{not_equal, equal}

///|
pub extend RuntimeRoutePolicy with ToJson::{to_json}

///|
pub extend RuntimeRoutePolicy with FromJson::{from_json}

///|
fn private_ipv4_number(value : String) -> Int64? {
  let parts = value.split(".").collect()
  if parts.length() != 4 {
    return None
  }
  let octets : Array[Int] = []
  for part in parts {
    if part.length() == 0 || part.length() > 3 {
      return None
    }
    let mut number = 0
    for c in part.to_owned() {
      if c < '0' || c > '9' {
        return None
      }
      number = number * 10 + c.to_int() - '0'.to_int()
    }
    if number > 255 || number.to_string() != part.to_owned() {
      return None
    }
    octets.push(number)
  }
  if !(octets[0] == 10 ||
    (octets[0] == 192 && octets[1] == 168) ||
    (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31)) {
    return None
  }
  Some(octets.fold(init=0L, (n, octet) => n * 256L + octet.to_int64()))
}

///|
pub fn RuntimeRoutePolicy::valid(self : RuntimeRoutePolicy) -> Bool {
  guard self.prefix_length >= 8 &&
    self.prefix_length <= 32 &&
    self.port >= 1 &&
    self.port <= 65535 &&
    private_ipv4_number(self.network) is Some(network) else {
    return false
  }
  let mut block = 1L
  for _ in 0..<(32 - self.prefix_length) {
    block *= 2L
  }
  network % block == 0L
}

///|
pub fn RuntimeRoutePolicy::allows(
  self : RuntimeRoutePolicy,
  endpoint : RuntimeEndpoint,
) -> Bool {
  guard self.valid() &&
    endpoint.port == self.port &&
    private_ipv4_number(self.network) is Some(network) &&
    private_ipv4_number(endpoint.address) is Some(address) else {
    return false
  }
  let mut block = 1L
  for _ in 0..<(32 - self.prefix_length) {
    block *= 2L
  }
  address / block == network / block
}

///|
pub fn RuntimeEndpoint::matches(
  self : RuntimeEndpoint,
  assignment : DesiredAssignment,
  now_unix_ms : Int64,
) -> Bool {
  self.assignment_id == assignment.assignment_id &&
  self.deployment_id == assignment.deployment_id &&
  self.generation == assignment.generation &&
  self.controller_epoch == assignment.controller_epoch &&
  self.artifact_digest == assignment.artifact.digest &&
  self.image_digest == assignment.runtime.image_digest &&
  valid_sha256_digest("sha256:" + self.instance_id) &&
  private_ipv4_number(self.address) is Some(_) &&
  self.port >= 1 &&
  self.port <= 65535 &&
  self.observed_unix_ms >= 0L &&
  self.observed_unix_ms <= now_unix_ms &&
  now_unix_ms - self.observed_unix_ms <= 15000L &&
  assignment.signature != "" &&
  assignment.lease_expires_unix_ms > now_unix_ms
}
