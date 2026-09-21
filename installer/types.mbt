///|
pub(all) struct ComputeTarget {
  node_name : String
  ssh_host : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ComputeTarget with Debug::{to_repr}

///|
pub extend ComputeTarget with Eq::{not_equal, equal}

///|
pub extend ComputeTarget with ToJson::{to_json}

///|
pub extend ComputeTarget with FromJson::{from_json}

///|
pub(all) enum DeploymentTarget {
  ManagementFoundation
  ComputeExpansion
  ManagementAndCompute
  LocalSimulation
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend DeploymentTarget with Debug::{to_repr}

///|
pub extend DeploymentTarget with Eq::{not_equal, equal}

///|
pub extend DeploymentTarget with ToJson::{to_json}

///|
pub extend DeploymentTarget with FromJson::{from_json}

///|
pub(all) struct InstallRequest {
  version : String
  deployment_target : DeploymentTarget
  apply : Bool
  confirmation : String
  ssh_user : String
  ssh_port : Int
  ssh_key_path : String
  known_hosts_path : String
  management_node : String
  management_host : String
  compute_nodes : Array[ComputeTarget]
  cluster_namespace : String
  kubeconfig_path : String
  rendered_directory : String
  management_secret_manifest : String
  secret_directory : String
  cli_path : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend InstallRequest with Debug::{to_repr}

///|
pub extend InstallRequest with Eq::{not_equal, equal}

///|
pub extend InstallRequest with ToJson::{to_json}

///|
pub extend InstallRequest with FromJson::{from_json}

///|
pub(all) suberror InstallValidationError {
  InvalidField(String)
} derive(Debug, Eq)

///|
pub extend InstallValidationError with Debug::{to_repr}

///|
pub extend InstallValidationError with Eq::{not_equal, equal}

///|
pub let request_version : String = "lunanexa.install.v4"

///|
pub let management_and_compute_confirmation : String = "DEPLOY MANAGEMENT AND COMPUTE"

///|
pub let management_confirmation : String = "DEPLOY MANAGEMENT"

///|
pub let compute_confirmation : String = "ADD COMPUTE"

///|
pub let simulation_confirmation : String = "RECONCILE SIMULATION"

///|
pub fn DeploymentTarget::confirmation(self : DeploymentTarget) -> String {
  match self {
    ManagementFoundation => management_confirmation
    ComputeExpansion => compute_confirmation
    ManagementAndCompute => management_and_compute_confirmation
    LocalSimulation => simulation_confirmation
  }
}

///|
pub fn DeploymentTarget::uses_ssh(self : DeploymentTarget) -> Bool {
  self != LocalSimulation
}

///|
pub fn DeploymentTarget::installs_management(self : DeploymentTarget) -> Bool {
  self == ManagementFoundation || self == ManagementAndCompute
}

///|
pub fn DeploymentTarget::installs_compute(self : DeploymentTarget) -> Bool {
  self == ComputeExpansion || self == ManagementAndCompute
}
