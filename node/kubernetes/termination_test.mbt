///|
test "termination requires an explicit exit of the original container" {
  let value = pod(phase="Failed", ready=false)
  guard value is Object(root) else { fail("fixture") }
  root["status"] = {
    "phase": "Failed",
    "containerStatuses": [
      {
        "name": "runtime",
        "imageID": identity().image_ref.to_json(),
        "containerID": "containerd://original",
        "ready": false,
        "state": {
          "terminated": {
            "containerID": "containerd://original",
            "exitCode": 137,
            "finishedAt": "2026-09-15T15:00:00Z",
          },
        },
      },
    ],
  }
  assert_true(
    @kubernetes.observe_container_termination(
      identity(),
      "containerd://original",
      value,
    ),
  )
  for
    expected in [
      { ..identity(), uid: "replacement", },
      { ..identity(), node_name: "other-node", },
      { ..identity(), generation: 2L, },
    ] {
    try
      @kubernetes.observe_container_termination(
        expected, "containerd://original", value,
      )
    catch {
      @kubernetes.IdentityMismatch => ()
      error => raise error
    } noraise {
      _ => fail("foreign termination accepted")
    }
  }
  assert_false(
    @kubernetes.observe_container_termination(
      identity(),
      "containerd://original",
      pod(phase="Failed", ready=false),
    ),
  )
  assert_false(
    @kubernetes.observe_container_termination(
      identity(),
      "containerd://original",
      pod(),
    ),
  )
  guard value is { "status": { "containerStatuses": [Object(status)], .. }, .. } else {
    fail("fixture")
  }
  let invalid_states : Array[Json] = [
    { "running": {} },
    { "waiting": {} },
    {
      "terminated": {
        "containerID": "containerd://old",
        "exitCode": 0,
        "finishedAt": "2026-09-15T15:00:00Z",
      },
    },
    {
      "terminated": {
        "containerID": "containerd://original",
        "exitCode": 0,
        "finishedAt": "",
      },
    },
    {
      "terminated": {
        "containerID": "containerd://original",
        "exitCode": 0,
        "finishedAt": "2026-09-15T15:00:00Z",
      },
      "running": {},
    },
  ]
  for state in invalid_states {
    status["state"] = state
    assert_false(
      @kubernetes.observe_container_termination(
        identity(),
        "containerd://original",
        value,
      ),
    )
  }
  // A terminating Pod still has to belong to the original node.
  guard value is { "metadata": Object(metadata), .. } else { fail("fixture") }
  metadata["deletionTimestamp"] = "2026-09-15T15:00:00Z"
  try
    @kubernetes.observe_container_termination(
      { ..identity(), node_name: "other-node", },
      "containerd://original",
      value,
    )
  catch {
    @kubernetes.IdentityMismatch => ()
    error => raise error
  } noraise {
    _ => fail("deletion bypassed node identity")
  }
}
