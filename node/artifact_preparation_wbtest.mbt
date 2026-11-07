///|
async test "artifact preparation returns ready without invoking the runtime engine" {
  let original = supervisor_assignment()
  let assignment = {
    ..original,
    runtime: {
      ..original.runtime,
      name: "lunanexa-artifact-preparation",
      capabilities: [],
    },
    resources: {
      ..original.resources,
      accelerator_count: 0,
      accelerator_memory_mib: 0,
    },
    devices: [],
  }
  let supervisor = ManagedRuntimeSupervisor::Oci(
    OciRuntimeSupervisor::new("/usr/bin/podman", "lunanexa-runtime", "local://"),
  )
  let result = supervisor.ensure_started(assignment, {
    digest: assignment.artifact.digest,
    size_bytes: assignment.artifact.size_bytes,
    host_path: "/cache/verified.revision",
  })
  assert_eq(result.observed_state, Ready)
  assert_eq(result.container_name, "")
  assert_eq(result.endpoint, None)
}

///|
async test "artifact preparation cannot claim ready for a different artifact" {
  let original = supervisor_assignment()
  let assignment = {
    ..original,
    runtime: {
      ..original.runtime,
      name: "lunanexa-artifact-preparation",
      capabilities: [],
    },
    resources: {
      ..original.resources,
      accelerator_count: 0,
      accelerator_memory_mib: 0,
    },
    devices: [],
  }
  let supervisor = ManagedRuntimeSupervisor::Oci(
    OciRuntimeSupervisor::new("/usr/bin/podman", "lunanexa-runtime", "local://"),
  )
  try
    supervisor.ensure_started(assignment, {
      digest: "sha256:" + "a".repeat(64),
      size_bytes: assignment.artifact.size_bytes,
      host_path: "/cache/other.revision",
    })
  catch {
    ArtifactMaterializationError::InvalidConfiguration => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("mismatched artifact accepted")
  }
}
