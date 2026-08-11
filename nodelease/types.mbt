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
pub(all) struct ExclusiveLeaseTransitionRequest {
  expected_generation : Int64
  state : ExclusiveLeaseState
  evidence_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExclusiveLeaseSnapshot {
  schema_version : String
  leases : Array[ExclusiveNodeLease]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct LeaseAgentObservation {
  lease_id : String
  observed_generation : Int64
  action : String
  receipt : String
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror ExclusiveLeaseError {
  UnsupportedVersion(String)
  InvalidIntent(String)
  InvalidTransition(ExclusiveLeaseState, ExclusiveLeaseState)
  StaleGeneration
} derive(Debug, Eq)
