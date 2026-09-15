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
      container["containerID"] = "containerd://replacement-container"
    }
  }
  let replacement = supervisor.probe_assignments([assignment])[0].endpoint.unwrap()
  assert_eq(replacement.address, original.address)
  assert_true(replacement.instance_id != original.instance_id)
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
