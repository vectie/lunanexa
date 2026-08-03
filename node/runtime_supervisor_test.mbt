///|
test "runtime supervisor rejects arbitrary executables and unsafe network names" {
  try
    @node.OciRuntimeSupervisor::new(
      "/bin/sh", "lunanexa-runtime", "unix:///run/podman/podman.sock",
    )
  catch {
    @node.RuntimeSupervisorError::UnsupportedEngine(_) => ()
    error => fail("unexpected error: \{to_repr(error)}")
  } noraise {
    _ => fail("arbitrary executable was accepted")
  }
  try
    @node.OciRuntimeSupervisor::new(
      "/usr/bin/podman", "bad network", "unix:///run/podman/podman.sock",
    )
  catch {
    @node.RuntimeSupervisorError::InvalidAssignmentIdentity(_) => ()
    error => fail("unexpected error: \{to_repr(error)}")
  } noraise {
    _ => fail("unsafe network name was accepted")
  }
}

///|
test "runtime inspection requires the assigned image label and healthy state" {
  assert_eq(
    @node.classify_runtime_inspection(
      "running|healthy|runtime@sha256:5555555555555555555555555555555555555555555555555555555555555555|assignment-1",
      "runtime@sha256:5555555555555555555555555555555555555555555555555555555555555555",
      "assignment-1",
    ),
    Ready,
  )
  assert_eq(
    @node.classify_runtime_inspection(
      "running|starting|runtime@sha256:5555555555555555555555555555555555555555555555555555555555555555|assignment-1",
      "runtime@sha256:5555555555555555555555555555555555555555555555555555555555555555",
      "assignment-1",
    ),
    Starting,
  )
  assert_eq(
    @node.classify_runtime_inspection(
      "running|unhealthy|runtime@sha256:5555555555555555555555555555555555555555555555555555555555555555|assignment-1",
      "runtime@sha256:5555555555555555555555555555555555555555555555555555555555555555",
      "assignment-1",
    ),
    Degraded,
  )
  try
    @node.classify_runtime_inspection(
      "running|healthy|runtime@sha256:7777777777777777777777777777777777777777777777777777777777777777|assignment-1",
      "runtime@sha256:5555555555555555555555555555555555555555555555555555555555555555",
      "assignment-1",
    )
  catch {
    @node.RuntimeSupervisorError::InvalidAssignmentIdentity(_) => ()
    error => fail("unexpected error: \{to_repr(error)}")
  } noraise {
    _ => fail("runtime image substitution was accepted")
  }
}
