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
fn local_operator_path(value : String) -> Bool {
  absolute_operator_path(value) ||
  (
    value.has_prefix("~/") &&
    value.length() <= 1024 &&
    !value.contains("\n") &&
    !value.contains("\r") &&
    !value.contains("\u0000") &&
    !value.split("/").any(segment => segment == "..")
  )
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
  require_field(
    simple_identifier(request.cluster_namespace),
    "cluster_namespace",
  )
  require_field(
    if request.deployment_target == LocalSimulation {
      local_operator_path(request.kubeconfig_path)
    } else {
      absolute_operator_path(request.kubeconfig_path)
    },
    "kubeconfig_path",
  )
  if request.apply {
    require_field(
      request.confirmation == request.deployment_target.confirmation(),
      "confirmation",
    )
  }
  if request.deployment_target == LocalSimulation {
    return
  }
  require_field(simple_identifier(request.ssh_user), "ssh_user")
  require_field(request.ssh_port > 0 && request.ssh_port <= 65535, "ssh_port")
  require_field(absolute_operator_path(request.ssh_key_path), "ssh_key_path")
  require_field(
    absolute_operator_path(request.known_hosts_path),
    "known_hosts_path",
  )
  if request.deployment_target.installs_management() {
    require_field(simple_identifier(request.management_node), "management_node")
    require_field(ssh_host(request.management_host), "management_host")
  }
  let compute_count = request.compute_nodes.length()
  require_field(
    match request.deployment_target {
      ManagementFoundation => compute_count == 0
      ComputeExpansion | ManagementAndCompute =>
        compute_count > 0 && compute_count <= 256
      LocalSimulation => true
    },
    "compute_nodes",
  )
  let seen : Map[String, Bool] = Map([])
  for target in request.compute_nodes {
    require_field(simple_identifier(target.node_name), "compute_node_name")
    require_field(ssh_host(target.ssh_host), "compute_ssh_host")
    require_field(!seen.contains(target.node_name), "compute_node_name")
    seen[target.node_name] = true
  }
  require_field(
    absolute_operator_path(request.rendered_directory),
    "rendered_directory",
  )
  if request.deployment_target.installs_management() {
    require_field(
      absolute_operator_path(request.management_secret_manifest),
      "management_secret_manifest",
    )
  }
  if request.deployment_target.installs_compute() {
    require_field(
      absolute_operator_path(request.secret_directory),
      "secret_directory",
    )
    require_field(absolute_operator_path(request.cli_path), "cli_path")
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
pub fn stage_names(target : DeploymentTarget) -> Array[String] {
  match target {
    ManagementFoundation =>
      [
        "Validate operator-side paths", "Inspect selected management host over pinned SSH",
        "Verify Kubernetes context and preview changes", "Label the selected management node",
        "Apply reviewed management manifests", "Verify management services",
      ]
    ComputeExpansion =>
      [
        "Validate operator-side paths", "Inspect selected compute hosts over pinned SSH",
        "Verify management-plane readiness", "Label selected compute nodes", "Install protected node material",
        "Issue one-use enrollment tokens", "Apply node agent and verify selected heartbeats",
      ]
    ManagementAndCompute =>
      [
        "Validate operator-side paths", "Inspect selected management host over pinned SSH",
        "Inspect selected compute hosts over pinned SSH", "Verify Kubernetes context and preview changes",
        "Label management and compute nodes", "Apply reviewed management manifests",
        "Verify management services", "Install protected node material", "Issue one-use enrollment tokens",
        "Apply node agent and verify heartbeats",
      ]
    LocalSimulation =>
      [
        "Verify dedicated Colima profile", "Verify Docker and kind tooling", "Inspect or create the simulation topology",
        "Apply simulation-only placement probes", "Verify simulated management and compute placements",
      ]
  }
}
