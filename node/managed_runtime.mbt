///|
/// Backend selection does not change signed-assignment or artifact authority.
pub(all) enum ManagedRuntimeSupervisor {
  Oci(OciRuntimeSupervisor)
  Kubernetes(@kubernetes.RuntimeSupervisor)
}

///|
pub async fn ManagedRuntimeSupervisor::ensure_started(
  self : ManagedRuntimeSupervisor,
  assignment : @contracts.DesiredAssignment,
  materialized : MaterializedArtifact,
) -> RuntimeInstance {
  if assignment.runtime.name == "lunanexa-artifact-preparation" {
    if materialized.digest != assignment.artifact.digest ||
      materialized.size_bytes != assignment.artifact.size_bytes ||
      assignment.resources.accelerator_count != 0 ||
      !assignment.devices.is_empty() ||
      assignment.group is Some(_) {
      raise ArtifactMaterializationError::InvalidConfiguration
    }
    return {
      assignment_id: assignment.assignment_id,
      container_name: "",
      image_ref: "",
      artifact_digest: materialized.digest,
      observed_state: Ready,
      container_address: "",
      endpoint: None,
    }
  }
  match self {
    Oci(supervisor) => supervisor.ensure_started(assignment, materialized)
    Kubernetes(supervisor) => {
      let observed = supervisor.ensure_started(
        assignment,
        materialized.host_path,
        materialized.digest,
        materialized.size_bytes,
        @async.now(),
      )
      {
        assignment_id: observed.assignment_id,
        container_name: observed.pod_name,
        image_ref: assignment.runtime.name +
        "@" +
        assignment.runtime.image_digest,
        artifact_digest: assignment.artifact.digest,
        observed_state: observed.state,
        container_address: observed.address,
        endpoint: observed.endpoint,
      }
    }
  }
}

///|
pub async fn ManagedRuntimeSupervisor::stop(
  self : ManagedRuntimeSupervisor,
  assignment_id : String,
) -> Unit {
  match self {
    Oci(supervisor) => supervisor.stop(assignment_id)
    Kubernetes(supervisor) => ignore(supervisor.stop(assignment_id))
  }
}

///|
pub async fn ManagedRuntimeSupervisor::reap_expired(
  self : ManagedRuntimeSupervisor,
  now_unix_ms : Int64,
) -> Unit {
  match self {
    Oci(_) => ()
    Kubernetes(supervisor) => supervisor.reap_expired(now_unix_ms)
  }
}

///|
pub async fn ManagedRuntimeSupervisor::remove_absent(
  self : ManagedRuntimeSupervisor,
  desired_ids : Array[String],
) -> Unit {
  match self {
    Oci(_) => ()
    Kubernetes(supervisor) => supervisor.remove_absent(desired_ids)
  }
}

///|
pub fn ManagedRuntimeSupervisor::retained_artifact_digests(
  self : ManagedRuntimeSupervisor,
) -> Array[String] {
  match self {
    Oci(_) => []
    Kubernetes(supervisor) => supervisor.retained_artifact_digests()
  }
}

///|
pub fn ManagedRuntimeSupervisor::close(self : ManagedRuntimeSupervisor) -> Unit {
  match self {
    Oci(_) => ()
    Kubernetes(supervisor) => supervisor.close()
  }
}
