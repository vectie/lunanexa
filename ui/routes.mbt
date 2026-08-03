///|
pub(all) enum OperatorRoute {
  Overview
  Nodes
  Models
  Deployments
  Requests
  Benchmarks
  Policies
  Audit
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn all_routes() -> Array[OperatorRoute] {
  [Overview, Nodes, Models, Deployments, Requests, Benchmarks, Policies, Audit]
}
