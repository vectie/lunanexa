///|
pub(all) enum OperatorRoute {
  Overview
  Alerts
  Users
  Leases
  CostCenters
  Agreements
  OfflineCommerce
  ContractDocuments
  QualifiedServices
  Nodes
  Models
  Catalog
  Deployments
  Requests
  Benchmarks
  Policies
  Audit
  Blank
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OperatorRoute with Debug::{to_repr}

///|
pub extend OperatorRoute with Eq::{not_equal, equal}

///|
pub extend OperatorRoute with ToJson::{to_json}

///|
pub extend OperatorRoute with FromJson::{from_json}

///|
pub fn all_routes() -> Array[OperatorRoute] {
  [
    Overview,
    Alerts,
    Users,
    Leases,
    CostCenters,
    Agreements,
    OfflineCommerce,
    ContractDocuments,
    QualifiedServices,
    Nodes,
    Models,
    Catalog,
    Deployments,
    Requests,
    Benchmarks,
    Policies,
    Audit,
    Blank,
  ]
}
