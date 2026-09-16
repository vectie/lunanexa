///|
async test "explicit container exit is checkpointed once and cannot resurrect after restart" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  let supervisor = restore_supervisor(api, checkpoint)
  let assignment = future_assignment()
  ignore(
    supervisor.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    ),
  )
  for _, object in api.objects {
    if object
      is {
        "kind": "Pod",
        "status": { "containerStatuses": [Object(container)], .. },
        ..
      } {
      container["ready"] = false
      container["state"] = {
        "terminated": {
          "containerID": container["containerID"],
          "exitCode": 137,
          "finishedAt": "2026-09-15T15:00:00Z",
        },
      }
    }
  }
  assert_true(supervisor.probe_assignments([assignment])[0].endpoint is None)
  let saved = checkpoint.val.unwrap()
  guard @json.parse(saved)
    is {
      "runtimes": [
        {
          "observed_containers": [
            { "termination_observed_unix_ms": String(_), .. },
          ],
          ..
        },
      ],
      ..
    } else {
    fail("exit evidence was not persisted")
  }
  let restored = restore_supervisor(api, checkpoint)
  assert_true(restored.probe_assignments([assignment])[0].endpoint is None)
  assert_eq(restored.snapshot(), saved)
  let evidence = restored.pending_terminations()
  assert_eq(evidence.length(), 1)
  assert_eq(evidence[0].assignment_id, assignment.assignment_id)
  assert_eq(evidence[0].controller_epoch, assignment.controller_epoch)
  for _, object in api.objects {
    if object
      is {
        "kind": "Pod",
        "status": { "containerStatuses": [Object(container)], .. },
        ..
      } {
      container["ready"] = true
      container["state"] = { "running": {} }
    }
  }
  assert_true(restored.probe_assignments([assignment])[0].endpoint is None)
  assert_eq(restored.snapshot(), saved)
  for _ in 0..<4 {
    ignore(restored.stop(assignment.assignment_id))
  }
  assert_eq(restored.stop(assignment.assignment_id), @contracts.Stopped)
  assert_eq(restored.pending_terminations(), evidence)
  let cleaned = restore_supervisor(api, checkpoint)
  assert_eq(cleaned.pending_terminations(), evidence)
  assert_true(cleaned.retained_artifact_digests().is_empty())
  cleaned.acknowledge_terminations([
    { ..evidence[0], controller_epoch: evidence[0].controller_epoch + 1L, },
  ])
  assert_eq(cleaned.pending_terminations(), evidence)
  let frozen = @kubernetes.RuntimeSupervisor::restore(
    runtime_settings(),
    api.transport(),
    _ => raise InjectedFault::FailedCommit,
    checkpoint.val,
    "a".repeat(64),
  )
  try frozen.acknowledge_terminations(evidence) catch {
    InjectedFault::FailedCommit => ()
    error => raise error
  } noraise {
    _ => fail("unpersisted acknowledgement accepted")
  }
  assert_eq(frozen.pending_terminations(), evidence)
  cleaned.acknowledge_terminations(evidence)
  cleaned.acknowledge_terminations(evidence)
  assert_true(cleaned.pending_terminations().is_empty())
  assert_true(
    restore_supervisor(api, checkpoint).pending_terminations().is_empty(),
  )
}

///|
async test "unpersisted container incarnation cannot become a route" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  let supervisor = restore_supervisor(api, checkpoint)
  let assignment = future_assignment()
  ignore(
    supervisor.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    ),
  )
  let saved = checkpoint.val.unwrap()
  let frozen = @kubernetes.RuntimeSupervisor::restore(
    runtime_settings(),
    api.transport(),
    _ => raise InjectedFault::FailedCommit,
    Some(saved),
    "a".repeat(64),
  )
  for _, object in api.objects {
    if object
      is {
        "kind": "Pod",
        "status": { "containerStatuses": [Object(container)], .. },
        ..
      } {
      container["containerID"] = "containerd://unpersisted"
    }
  }
  let observation = frozen.probe_assignments([assignment])[0]
  assert_true(observation.endpoint is None)
  assert_eq(observation.state, @contracts.Failed)
  assert_eq(frozen.snapshot(), saved)
}

///|
async test "runtime probes are read only and bind routes to container incarnations" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  let supervisor = restore_supervisor(api, checkpoint)
  let assignment = future_assignment()
  let first = supervisor.ensure_started(
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    @async.now(),
  )
  let original = first.endpoint.unwrap()
  let mutations = api.calls.filter(call => !call.has_prefix("GET")).length()
  let probed = supervisor.probe_assignments([assignment])
  assert_eq(probed.length(), 1)
  assert_eq(probed[0].state, @contracts.Ready)
  assert_eq(probed[0].endpoint.unwrap().instance_id, original.instance_id)
  assert_true(
    probed[0].endpoint.unwrap().observed_unix_ms >= original.observed_unix_ms,
  )
  for _, object in api.objects {
    if object
      is {
        "kind": "Pod",
        "status": { "containerStatuses": [Object(container)], .. },
        ..
      } {
      let old_container_id = container["containerID"]
      container["containerID"] = "containerd://replacement-container"
      container["lastState"] = {
        "terminated": {
          "containerID": old_container_id,
          "exitCode": 137,
          "finishedAt": "2026-09-15T15:00:00Z",
        },
      }
    }
  }
  let replacement = supervisor.probe_assignments([assignment])[0].endpoint.unwrap()
  assert_eq(replacement.address, original.address)
  assert_true(replacement.instance_id != original.instance_id)
  let terminated = supervisor.pending_terminations()
  assert_eq(terminated.length(), 1)
  assert_eq(terminated[0].instance_id, original.instance_id)
  guard @json.parse(checkpoint.val.unwrap())
    is { "runtimes": [{ "observed_containers": Array(known), .. }], .. } else {
    fail("container history missing from checkpoint")
  }
  assert_eq(known.length(), 2)
  let restored = restore_supervisor(api, checkpoint)
  assert_eq(
    restored.probe_assignments([assignment])[0].endpoint.unwrap().instance_id,
    replacement.instance_id,
  )
  guard @json.parse(restored.snapshot())
    is { "runtimes": [{ "observed_containers": Array(after), .. }], .. } else {
    fail("container history lost on restart")
  }
  assert_eq(after.length(), 2)
  assert_eq(
    api.calls.filter(call => !call.has_prefix("GET")).length(),
    mutations,
  )
}

///|
async test "runtime probes reject foreign ownership and absent resources without repairing them" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  let supervisor = restore_supervisor(api, checkpoint)
  let assignment = future_assignment()
  ignore(
    supervisor.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    ),
  )
  let mutations = api.calls.filter(call => !call.has_prefix("GET")).length()
  for _, object in api.objects {
    if object is { "kind": "Pod", "metadata": Object(metadata), .. } {
      metadata["uid"] = "foreign-pod-uid"
    }
  }
  let rejected = supervisor.probe_assignments([assignment])[0]
  assert_eq(rejected.state, @contracts.Failed)
  assert_true(rejected.endpoint is None)
  api.objects.clear()
  let absent = supervisor.probe_assignments([assignment])[0]
  assert_eq(absent.state, @contracts.Failed)
  assert_true(absent.endpoint is None)
  assert_eq(
    api.calls.filter(call => !call.has_prefix("GET")).length(),
    mutations,
  )
}
