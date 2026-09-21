///|
pub let contract_version : String = "lunanexa.exclusive-node-lease.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.exclusive-node-lease.snapshot.v1"

///|
pub(all) enum NodeOperatingMode {
  ManagedService
  ExclusiveLease
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NodeOperatingMode with Debug::{to_repr}

///|
pub extend NodeOperatingMode with Eq::{not_equal, equal}

///|
pub extend NodeOperatingMode with ToJson::{to_json}

///|
pub extend NodeOperatingMode with FromJson::{from_json}

///|
pub(all) enum ExclusiveLeaseState {
  Requested
  Reserved
  Provisioning
  Active
  Expiring
  Draining
  RevokingAccess
  Sanitizing
  Completed
  Cancelled
  Quarantined
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExclusiveLeaseState with Debug::{to_repr}

///|
pub extend ExclusiveLeaseState with Eq::{not_equal, equal}

///|
pub extend ExclusiveLeaseState with ToJson::{to_json}

///|
pub extend ExclusiveLeaseState with FromJson::{from_json}

///|
pub(all) struct ExclusiveNodeLeaseIntent {
  version : String
  idempotency_key : String
  lease_id : String
  node_id : String
  subject_ref : String
  unix_username : String
  access_credential_ref : String
  starts_unix_ms : Int64
  expires_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExclusiveNodeLeaseIntent with Debug::{to_repr}

///|
pub extend ExclusiveNodeLeaseIntent with Eq::{not_equal, equal}

///|
pub extend ExclusiveNodeLeaseIntent with ToJson::{to_json}

///|
pub extend ExclusiveNodeLeaseIntent with FromJson::{from_json}

///|
pub(all) struct ExclusiveNodeLease {
  intent : ExclusiveNodeLeaseIntent
  state : ExclusiveLeaseState
  generation : Int64
  created_unix_ms : Int64
  updated_unix_ms : Int64
  evidence_receipt : String
  authority_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExclusiveNodeLease with Debug::{to_repr}

///|
pub extend ExclusiveNodeLease with Eq::{not_equal, equal}

///|
pub extend ExclusiveNodeLease with ToJson::{to_json}

///|
pub extend ExclusiveNodeLease with FromJson::{from_json}

///|
pub(all) struct ExclusiveLeaseTransitionRequest {
  expected_generation : Int64
  state : ExclusiveLeaseState
  evidence_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExclusiveLeaseTransitionRequest with Debug::{to_repr}

///|
pub extend ExclusiveLeaseTransitionRequest with Eq::{not_equal, equal}

///|
pub extend ExclusiveLeaseTransitionRequest with ToJson::{to_json}

///|
pub extend ExclusiveLeaseTransitionRequest with FromJson::{from_json}

///|
pub(all) struct ExclusiveLeaseTerminationRequest {
  expected_generation : Int64
  reason : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExclusiveLeaseTerminationRequest with Debug::{to_repr}

///|
pub extend ExclusiveLeaseTerminationRequest with Eq::{not_equal, equal}

///|
pub extend ExclusiveLeaseTerminationRequest with ToJson::{to_json}

///|
pub extend ExclusiveLeaseTerminationRequest with FromJson::{from_json}

///|
pub(all) struct ExclusiveLeaseSnapshot {
  schema_version : String
  leases : Array[ExclusiveNodeLease]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExclusiveLeaseSnapshot with Debug::{to_repr}

///|
pub extend ExclusiveLeaseSnapshot with Eq::{not_equal, equal}

///|
pub extend ExclusiveLeaseSnapshot with ToJson::{to_json}

///|
pub extend ExclusiveLeaseSnapshot with FromJson::{from_json}

///|
pub(all) struct LeaseAgentObservation {
  lease_id : String
  observed_generation : Int64
  action : String
  receipt : String
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend LeaseAgentObservation with Debug::{to_repr}

///|
pub extend LeaseAgentObservation with Eq::{not_equal, equal}

///|
pub extend LeaseAgentObservation with ToJson::{to_json}

///|
pub extend LeaseAgentObservation with FromJson::{from_json}

///|
pub(all) suberror ExclusiveLeaseError {
  UnsupportedVersion(String)
  InvalidIntent(String)
  InvalidTransition(ExclusiveLeaseState, ExclusiveLeaseState)
  StaleGeneration
} derive(Debug, Eq)

///|
pub extend ExclusiveLeaseError with Debug::{to_repr}

///|
pub extend ExclusiveLeaseError with Eq::{not_equal, equal}
