///|
/// Resource ownership is explicit; model names never determine tenancy.
pub(all) struct ServiceOwner {
  tenant_ref : String
  organization_id : String
  reservation_id : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ServiceOwner with Debug::{to_repr}

///|
pub extend ServiceOwner with Eq::{equal, not_equal}

///|
pub extend ServiceOwner with ToJson::{to_json}

///|
pub extend ServiceOwner with FromJson::{from_json}

///|
pub(all) enum ServiceRuntimeKind {
  NodeAssignment
  Kubernetes
  ProcessGroup
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ServiceRuntimeKind with Debug::{to_repr}

///|
pub extend ServiceRuntimeKind with Eq::{equal, not_equal}

///|
pub extend ServiceRuntimeKind with ToJson::{to_json}

///|
pub extend ServiceRuntimeKind with FromJson::{from_json}

///|
pub(all) enum ServiceRuntimeState {
  Running
  Stopped
  Partial
  Unknown
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ServiceRuntimeState with Debug::{to_repr}

///|
pub extend ServiceRuntimeState with Eq::{equal, not_equal}

///|
pub extend ServiceRuntimeState with ToJson::{to_json}

///|
pub extend ServiceRuntimeState with FromJson::{from_json}

///|
/// Public metadata only. Adapter endpoints, credentials, SSH targets and
/// container specifications remain host-owned configuration references.
pub(all) struct ModelServiceInstance {
  service_id : String
  model_alias : String
  artifact_digest : String
  owner : ServiceOwner
  node_ids : Array[String]
  runtime_kind : ServiceRuntimeKind
  binding_ref : String
  exclusive : Bool
  generation : Int64
  desired_running : Bool
  observed : ServiceRuntimeState
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelServiceInstance with Debug::{to_repr}

///|
pub extend ModelServiceInstance with Eq::{equal, not_equal}

///|
pub extend ModelServiceInstance with ToJson::{to_json}

///|
pub extend ModelServiceInstance with FromJson::{from_json}

///|
pub fn ModelServiceInstance::holds_resources(
  self : ModelServiceInstance,
) -> Bool {
  self.desired_running || self.observed != Stopped
}

///|
pub fn service_conflicts(
  candidate : ModelServiceInstance,
  current : ModelServiceInstance,
) -> Bool {
  candidate.service_id != current.service_id &&
  candidate.node_ids.any(n => current.node_ids.contains(n)) &&
  // Company ownership remains in force when a runtime is stopped. Starting
  // another tenant's service cannot consume a company's allocation.
  (
    (
      current.reserves_company_node() &&
      (
        candidate.owner.tenant_ref != current.owner.tenant_ref ||
        candidate.owner.organization_id != current.owner.organization_id
      )
    ) ||
    (
      current.holds_resources() &&
      (
        candidate.exclusive ||
        current.exclusive ||
        candidate.owner.tenant_ref != current.owner.tenant_ref ||
        candidate.owner.organization_id != current.owner.organization_id
      )
    )
  )
}

///|
/// Fixed company allocations survive stop. Delivery ownership with a reservation
/// follows that reservation's lifetime instead of permanently pinning a node.
pub fn ModelServiceInstance::reserves_company_node(
  self : ModelServiceInstance,
) -> Bool {
  self.owner.tenant_ref != "" && self.owner.reservation_id is None
}
