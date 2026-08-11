///|
pub(all) suberror RuntimeSupervisorError {
  UnsupportedEngine(String)
  InvalidAssignmentIdentity(String)
  RuntimeCommandFailed(String)
} derive(Debug, Eq)

///|
pub(all) struct RuntimeInstance {
  assignment_id : String
  container_name : String
  image_ref : String
  artifact_digest : String
  observed_state : @contracts.DeploymentState
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct OciRuntimeSupervisor {
  engine : String
  network : String
  engine_endpoint : String
}

///|
pub fn OciRuntimeSupervisor::new(
  engine : String,
  network : String,
  engine_endpoint : String,
) -> OciRuntimeSupervisor raise {
  if engine != "/usr/bin/podman" &&
    engine != "/usr/bin/docker" &&
    engine != "/opt/homebrew/bin/podman" &&
    engine != "/opt/homebrew/bin/docker" {
    raise RuntimeSupervisorError::UnsupportedEngine(engine)
  }
  if !safe_identity(network) || !network.has_prefix("lunanexa-") {
    raise RuntimeSupervisorError::InvalidAssignmentIdentity(network)
  }
  if !engine_endpoint.has_prefix("unix:///run/") ||
    engine_endpoint.contains("..") {
    raise RuntimeSupervisorError::InvalidAssignmentIdentity(engine_endpoint)
  }
  { engine, network, engine_endpoint }
}

///|
fn OciRuntimeSupervisor::engine_environment(
  self : OciRuntimeSupervisor,
) -> Map[String, String] {
  {
    "CONTAINER_HOST": self.engine_endpoint,
    "DOCKER_HOST": self.engine_endpoint,
  }
}

///|
fn safe_identity(value : String) -> Bool {
  value != "" &&
  value.length() <= 96 &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.'
  })
}

///|
fn container_name(assignment_id : String) -> String {
  "lunanexa-\{assignment_id}"
}

///|
fn validate_runtime_assignment(
  assignment : @contracts.DesiredAssignment,
  materialized : MaterializedArtifact,
) -> Unit raise RuntimeSupervisorError {
  if !safe_identity(assignment.assignment_id) ||
    !@contracts.valid_sha256_digest(assignment.runtime.image_digest) ||
    assignment.runtime.name == "" ||
    assignment.runtime.name.contains_char(' ') ||
    assignment.runtime.name.contains_char('@') ||
    assignment.runtime.name.contains("..") ||
    assignment.runtime.name.contains_char('\n') ||
    assignment.runtime.name.contains_char('\r') ||
    !@contracts.valid_sha256_digest(assignment.artifact.digest) ||
    assignment.artifact.signature_ref == "" ||
    !(assignment.artifact.uri.has_prefix("s3://") ||
    assignment.artifact.uri.has_prefix("oci://")) ||
    assignment.resources.accelerator_count <= 0 ||
    assignment.resources.accelerator_count != assignment.devices.length() ||
    assignment.resources.accelerator_memory_mib <= 0 ||
    assignment.resources.cpu_millis <= 0 ||
    assignment.resources.memory_mib <= 0 ||
    assignment.network.allowed_egress.length() > 0 ||
    materialized.digest != assignment.artifact.digest ||
    materialized.size_bytes != assignment.artifact.size_bytes ||
    !safe_absolute_path(materialized.host_path) ||
    !assignment.devices.all(device => safe_identity(device)) {
    raise InvalidAssignmentIdentity(assignment.assignment_id)
  }
}

///|
pub fn classify_materialized_runtime_inspection(
  inspection : String,
  expected_image : String,
  expected_assignment : String,
  expected_artifact_digest : String,
) -> @contracts.DeploymentState raise RuntimeSupervisorError {
  let fields = inspection
    .trim()
    .split("|")
    .map(value => value.to_owned())
    .collect()
  if fields.length() != 5 ||
    fields[2] != expected_image ||
    fields[3] != expected_assignment ||
    fields[4] != expected_artifact_digest {
    raise InvalidAssignmentIdentity(expected_assignment)
  }
  match (fields[0], fields[1]) {
    ("running", "healthy") => Ready
    ("running", "starting") | ("running", "none") => Starting
    ("running", "unhealthy") => Degraded
    ("created", _) | ("restarting", _) => Starting
    ("exited", _) | ("dead", _) => Failed
    _ => Failed
  }
}

///|
fn runtime_run_arguments(
  assignment : @contracts.DesiredAssignment,
  materialized : MaterializedArtifact,
  name : String,
  image_ref : String,
  network : String,
) -> Array[String] {
  let memory_bytes = assignment.resources.memory_mib.to_int64() * 1024L * 1024L
  [
    "run",
    "--detach",
    "--name",
    name,
    "--label",
    "lunanexa.assignment=\{assignment.assignment_id}",
    "--label",
    "lunanexa.artifact=\{assignment.artifact.digest}",
    "--read-only",
    "--cap-drop=ALL",
    "--security-opt=no-new-privileges",
    "--pids-limit=512",
    "--ipc=private",
    "--pull=never",
    "--memory=\{memory_bytes}",
    "--cpus=\{(assignment.resources.cpu_millis.max(1).to_double() / 1000.0)}",
    "--restart=no",
    "--network",
    network,
    "--mount",
    "type=bind,src=\{materialized.host_path},dst=/var/lib/lunanexa/model/model,readonly",
    "--env",
    "NVIDIA_VISIBLE_DEVICES=\{assignment.devices.join(",")}",
    "--env",
    "LUNANEXA_MODEL_PATH=/var/lib/lunanexa/model/model",
    "--env",
    "LUNANEXA_ARTIFACT_DIGEST=\{assignment.artifact.digest}",
    image_ref,
  ]
}

///|
pub fn classify_runtime_inspection(
  inspection : String,
  expected_image : String,
  expected_assignment : String,
) -> @contracts.DeploymentState raise RuntimeSupervisorError {
  let fields = inspection
    .trim()
    .split("|")
    .map(value => value.to_owned())
    .collect()
  if fields.length() != 4 ||
    fields[2] != expected_image ||
    fields[3] != expected_assignment {
    raise InvalidAssignmentIdentity(expected_assignment)
  }
  match (fields[0], fields[1]) {
    ("running", "healthy") => Ready
    ("running", "starting") | ("running", "none") => Starting
    ("running", "unhealthy") => Degraded
    ("created", _) | ("restarting", _) => Starting
    ("exited", _) | ("dead", _) => Failed
    _ => Failed
  }
}

///|
pub async fn OciRuntimeSupervisor::ensure_started(
  self : OciRuntimeSupervisor,
  assignment : @contracts.DesiredAssignment,
  materialized : MaterializedArtifact,
) -> RuntimeInstance {
  validate_runtime_assignment(assignment, materialized)
  let name = container_name(assignment.assignment_id)
  let image_ref = "\{assignment.runtime.name}@\{assignment.runtime.image_digest}"
  let inspection_format = "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.Config.Image}}|{{index .Config.Labels \"lunanexa.assignment\"}}|{{index .Config.Labels \"lunanexa.artifact\"}}"
  let (exists_status, exists_output, _) = @process.collect_output(
    self.engine,
    ["container", "inspect", "--format", inspection_format, name],
    extra_env=self.engine_environment(),
    inherit_env=false,
  )
  let mut needs_start = exists_status != 0
  if !needs_start {
    try
      classify_materialized_runtime_inspection(
        exists_output.text(),
        image_ref,
        assignment.assignment_id,
        assignment.artifact.digest,
      )
    catch {
      _ => {
        let (remove_status, _, _) = @process.collect_output(
          self.engine,
          ["rm", "--force", name],
          extra_env=self.engine_environment(),
          inherit_env=false,
        )
        if remove_status != 0 {
          raise RuntimeCommandFailed(assignment.assignment_id)
        }
        needs_start = true
      }
    } noraise {
      _ => ()
    }
  }
  if needs_start {
    let (pull_status, _, _) = @process.collect_output(
      self.engine,
      ["pull", image_ref],
      extra_env=self.engine_environment(),
      inherit_env=false,
    )
    if pull_status != 0 {
      raise RuntimeCommandFailed(assignment.assignment_id)
    }
    let args = runtime_run_arguments(
      assignment,
      materialized,
      name,
      image_ref,
      self.network,
    )
    let (status, _, _) = @process.collect_output(
      self.engine,
      args,
      extra_env=self.engine_environment(),
      inherit_env=false,
    )
    if status != 0 {
      raise RuntimeCommandFailed(assignment.assignment_id)
    }
  }
  let (inspect_status, inspect_output, _) = @process.collect_output(
    self.engine,
    ["container", "inspect", "--format", inspection_format, name],
    extra_env=self.engine_environment(),
    inherit_env=false,
  )
  if inspect_status != 0 {
    raise RuntimeCommandFailed(assignment.assignment_id)
  }
  let observed_state = classify_materialized_runtime_inspection(
    inspect_output.text(),
    image_ref,
    assignment.assignment_id,
    assignment.artifact.digest,
  )
  {
    assignment_id: assignment.assignment_id,
    container_name: name,
    image_ref,
    artifact_digest: assignment.artifact.digest,
    observed_state,
  }
}

///|
pub async fn OciRuntimeSupervisor::stop(
  self : OciRuntimeSupervisor,
  assignment_id : String,
) -> Unit {
  if !safe_identity(assignment_id) {
    raise RuntimeSupervisorError::InvalidAssignmentIdentity(assignment_id)
  }
  let (inspect_status, _, _) = @process.collect_output(
    self.engine,
    ["container", "inspect", container_name(assignment_id)],
    extra_env=self.engine_environment(),
    inherit_env=false,
  )
  if inspect_status != 0 {
    return
  }
  let (status, _, _) = @process.collect_output(
    self.engine,
    ["rm", "--force", container_name(assignment_id)],
    extra_env=self.engine_environment(),
    inherit_env=false,
  )
  if status != 0 {
    raise RuntimeCommandFailed(assignment_id)
  }
}
