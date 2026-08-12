///|
pub(all) struct ComputeTarget {
  node_name : String
  ssh_host : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct InstallRequest {
  version : String
  apply : Bool
  confirmation : String
  ssh_user : String
  ssh_key_path : String
  known_hosts_path : String
  management_node : String
  management_host : String
  compute_nodes : Array[ComputeTarget]
  cluster_namespace : String
  kubeconfig_path : String
  rendered_directory : String
  secret_directory : String
  cli_path : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror InstallValidationError {
  InvalidField(String)
} derive(Debug, Eq)

///|
pub let request_version : String = "lunanexa.install.v1"

///|
pub let apply_confirmation : String = "DEPLOY 4 NODES"
