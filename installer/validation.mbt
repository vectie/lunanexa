///|
fn simple_identifier(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 128 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_' ||
    character == '.'
  })
}

///|
fn ssh_host(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 253 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '.' ||
    character == ':' ||
    character == '[' ||
    character == ']'
  })
}

///|
fn absolute_operator_path(value : String) -> Bool {
  value.length() > 1 &&
  value.length() <= 1024 &&
  value.has_prefix("/") &&
  !value.contains("\n") &&
  !value.contains("\r") &&
  !value.contains("\u0000") &&
  !value.split("/").any(segment => segment == "..")
}

///|
fn require_field(
  valid : Bool,
  name : String,
) -> Unit raise InstallValidationError {
  if !valid {
    raise InvalidField(name)
  }
}

///|
pub fn validate_request(
  request : InstallRequest,
) -> Unit raise InstallValidationError {
  require_field(request.version == request_version, "version")
  require_field(simple_identifier(request.ssh_user), "ssh_user")
  require_field(absolute_operator_path(request.ssh_key_path), "ssh_key_path")
  require_field(
    absolute_operator_path(request.known_hosts_path),
    "known_hosts_path",
  )
  require_field(simple_identifier(request.management_node), "management_node")
  require_field(ssh_host(request.management_host), "management_host")
  require_field(request.compute_nodes.length() == 4, "compute_nodes")
  let seen : Map[String, Bool] = Map([])
  for target in request.compute_nodes {
    require_field(simple_identifier(target.node_name), "compute_node_name")
    require_field(ssh_host(target.ssh_host), "compute_ssh_host")
    require_field(!seen.contains(target.node_name), "compute_node_name")
    seen[target.node_name] = true
  }
  require_field(
    simple_identifier(request.cluster_namespace),
    "cluster_namespace",
  )
  require_field(
    absolute_operator_path(request.kubeconfig_path),
    "kubeconfig_path",
  )
  require_field(
    absolute_operator_path(request.rendered_directory),
    "rendered_directory",
  )
  require_field(
    absolute_operator_path(request.secret_directory),
    "secret_directory",
  )
  require_field(absolute_operator_path(request.cli_path), "cli_path")
  if request.apply {
    require_field(request.confirmation == apply_confirmation, "confirmation")
  }
}

///|
pub fn parse_compute_targets(
  value : String,
) -> Array[ComputeTarget] raise InstallValidationError {
  let targets = []
  for line in value.split("\n") {
    let trimmed = line.trim()
    if trimmed != "" {
      let pieces = trimmed.split("=").to_array()
      require_field(pieces.length() == 2, "compute_nodes")
      targets.push({
        node_name: pieces[0].trim().to_owned(),
        ssh_host: pieces[1].trim().to_owned(),
      })
    }
  }
  targets
}

///|
pub fn stage_names() -> Array[String] {
  [
    "Validate local paths", "SSH host-key preflight", "Inspect management disk and Kubernetes",
    "Inspect four DGX GPU workers", "Label management and GPU nodes", "Apply rendered management manifests",
    "Install protected node material", "Issue one-use enrollment tokens", "Apply node agent and verify heartbeats",
  ]
}
