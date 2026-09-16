///|
async test "stopping keeps running Pods and capacity across restart until explicit exit is durable" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  api.hold_running = true
  let supervisor = restore_supervisor(api, checkpoint)
  let assignment = future_assignment()
  let first = supervisor.ensure_started(
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    @async.now(),
  )
  assert_true(first.endpoint is Some(_))
  assert_eq(supervisor.stop(assignment.assignment_id), @contracts.Draining)
  assert_eq(api.objects.length(), 3)
  assert_eq(supervisor.pending_terminations(), [])
  let restored = restore_supervisor(api, checkpoint)
  assert_eq(restored.stop(assignment.assignment_id), @contracts.Draining)
  assert_eq(api.calls.filter(call => call.has_prefix("PATCH")).length(), 1)
  assert_eq(api.calls.filter(call => call.has_prefix("DELETE")).length(), 0)
  assert_eq(restored.retained_artifact_digests(), [assignment.artifact.digest])
  for path, resource in api.objects {
    if path.contains("/pods/") {
      fixture_exit(resource)
    }
  }
  assert_eq(restored.stop(assignment.assignment_id), @contracts.Draining)
  let reports = restored.pending_terminations()
  assert_eq(reports.length(), 1)
  assert_eq(reports[0].original_assignment, Some(assignment))
  assert_eq(reports[0].instance_id, first.endpoint.unwrap().instance_id)
  let after_exit = restore_supervisor(api, checkpoint)
  for _ in 0..<3 {
    ignore(after_exit.stop(assignment.assignment_id))
  }
  assert_eq(api.objects.length(), 0)
  assert_eq(after_exit.pending_terminations(), reports)
  assert_eq(restore_supervisor(api, checkpoint).pending_terminations(), reports)
  after_exit.acknowledge_terminations(reports)
  assert_eq(restore_supervisor(api, checkpoint).pending_terminations(), [])
}

///|
async test "failed exit-report persistence never permits Pod deletion and retries exactly once" {
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
  ignore(supervisor.stop(assignment.assignment_id))
  let fail_commit = Ref(true)
  let restored = @kubernetes.RuntimeSupervisor::restore(
    runtime_settings(),
    api.transport(),
    value => {
      if fail_commit.val &&
        @json.parse(value) is { "pending_terminations": [_, ..], .. } {
        raise InjectedFault::FailedCommit
      }
      checkpoint.val = Some(value)
    },
    checkpoint.val,
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  try restored.stop(assignment.assignment_id) catch {
    InjectedFault::FailedCommit => ()
    error => raise error
  } noraise {
    _ => fail("expected exit checkpoint failure")
  }
  assert_eq(restored.pending_terminations(), [])
  assert_eq(api.calls.filter(call => call.has_prefix("DELETE")).length(), 0)
  assert_eq(api.objects.length(), 3)
  fail_commit.val = false
  assert_eq(restored.stop(assignment.assignment_id), @contracts.Draining)
  assert_eq(restored.pending_terminations().length(), 1)
  assert_eq(api.calls.filter(call => call.has_prefix("DELETE")).length(), 1)
  let recovered = restore_supervisor(api, checkpoint)
  for _ in 0..<4 {
    ignore(recovered.stop(assignment.assignment_id))
  }
  assert_eq(recovered.pending_terminations().length(), 1)
}

///|
async test "legacy signed assignment backfill restores safe stop evidence without changing instance" {
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
  let legacy = @json.parse(checkpoint.val.unwrap())
  guard legacy is { "runtimes": [Object(record)], .. } else { fail("fixture") }
  record.remove("original_assignment")
  checkpoint.val = Some(legacy.stringify())
  let restored = restore_supervisor(api, checkpoint)
  let second = restored.ensure_started(
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    @async.now(),
  )
  assert_eq(
    first.endpoint.unwrap().instance_id,
    second.endpoint.unwrap().instance_id,
  )
  ignore(restored.stop(assignment.assignment_id))
  ignore(restored.stop(assignment.assignment_id))
  assert_eq(restored.pending_terminations().length(), 1)
}

///|
async test "missing published Pod retains unresolved evidence and cache after restart" {
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
  let paths = api.objects.keys().collect()
  for path in paths {
    if path.contains("/pods/") {
      api.objects.remove(path)
    }
  }
  for _ in 0..<3 {
    assert_eq(supervisor.stop(assignment.assignment_id), @contracts.Draining)
  }
  assert_eq(supervisor.pending_terminations(), [])
  let restored = restore_supervisor(api, checkpoint)
  assert_eq(restored.stop(assignment.assignment_id), @contracts.Draining)
  assert_eq(restored.retained_artifact_digests(), [assignment.artifact.digest])
  assert_eq(api.objects.length(), 2)
  assert_eq(api.calls.filter(call => call.has_prefix("DELETE")).length(), 0)
}

///|
async test "restore rejects signed-assignment attribution changed in the journal" {
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
  let corrupt = @json.parse(checkpoint.val.unwrap())
  guard corrupt
    is { "runtimes": [{ "original_assignment": Object(original), .. }], .. } else {
    fail("fixture")
  }
  original["node_id"] = "other-node"
  checkpoint.val = Some(corrupt.stringify())
  try restore_supervisor(api, checkpoint) catch {
    @kubernetes.InvalidResource => ()
    error => raise error
  } noraise {
    _ => fail("corrupt attribution restored")
  }
}
