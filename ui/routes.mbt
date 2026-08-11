///|
pub(all) enum OperatorRoute {
  Overview
  Users
  Leases
  CostCenters
  Agreements
  QualifiedServices
  Nodes
  Models
  Catalog
  Deployments
  Requests
  Benchmarks
  Policies
  Audit
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn all_routes() -> Array[OperatorRoute] {
  [
    Overview,
    Users,
    Leases,
    CostCenters,
    Agreements,
    QualifiedServices,
    Nodes,
    Models,
    Catalog,
    Deployments,
    Requests,
    Benchmarks,
    Policies,
    Audit,
  ]
}
