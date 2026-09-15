///|
suberror InjectedFault {
  LostResponse
  FailedCommit
}

///|
struct FakeApi {
  objects : Map[String, Json]
  calls : Array[String]
  checkpoint : Ref[String?]
  mut lose_pod_response : Bool
}

///|
fn fake_api(checkpoint : Ref[String?]) -> FakeApi {
  { objects: Map([]), calls: [], checkpoint, lose_pod_response: false, }
}

///|
fn FakeApi::transport(self : FakeApi) -> @kubernetes.Transport {
  (verb, path, body) => {
    assert_true(self.checkpoint.val is Some(_))
    self.calls.push(verb + " " + path)
    match verb {
      "GET" =>
        match self.objects.get(path) {
          Some(value) => (200, @json.parse(value.stringify()))
          None => (404, {})
        }
      "POST" => {
        let resource = @json.parse(body.unwrap().stringify())
        guard resource is Object(root) &&
          resource is { "metadata": Object(meta), .. } &&
          meta.get("name") is Some(String(name)) else {
          fail("invalid fixture resource")
        }
        let key = path + "/" + name
        if self.objects.contains(key) {
          return (409, {})
        }
        meta["uid"] = ("uid-" + self.calls.length().to_string()).to_json()
        if resource is { "kind": "Pod", "spec": Object(spec), .. } {
          spec["nodeName"] = "compute-1"
          guard resource
            is {
              "spec": { "containers": [{ "image": String(image), .. }], .. },
              ..
            } else {
            fail("missing image")
          }
          root["status"] = {
            "phase": "Running",
            "podIP": "10.42.1.99",
            "conditions": [{ "type": "Ready", "status": "True" }],
            "containerStatuses": [
              {
                "name": "runtime",
                "ready": true,
                "imageID": image.to_json(),
                "containerID": ("containerd://fixture-" +
                self.calls.length().to_string()).to_json(),
                "state": { "running": {} },
              },
            ],
          }
        }
        self.objects[key] = resource
        if path.has_suffix("/pods") && self.lose_pod_response {
          self.lose_pod_response = false
          raise InjectedFault::LostResponse
        }
        (201, @json.parse(resource.stringify()))
      }
      "DELETE" => {
        guard self.objects.get(path)
          is Some({ "metadata": { "uid": String(uid), .. }, .. }) else {
          return (404, {})
        }
        assert_true(
          body is Some({ "preconditions": { "uid": String(expected), .. }, .. }) &&
          expected == uid,
        )
        self.objects.remove(path)
        (200, {})
      }
      _ => fail("unexpected API verb")
    }
  }
}

///|
fn future_assignment() -> @contracts.DesiredAssignment {
  { ..runtime_assignment(), lease_expires_unix_ms: @async.now() + 60000L, }
}

///|
fn restore_supervisor(
  api : FakeApi,
  checkpoint : Ref[String?],
) -> @kubernetes.RuntimeSupervisor raise {
  @kubernetes.RuntimeSupervisor::restore(
    runtime_settings(),
    api.transport(),
    value => checkpoint.val = Some(value),
    checkpoint.val,
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
}

///|
async test "supervisor persists ownership before creation and resumes without duplicate resources" {
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
  assert_eq(first.state, @contracts.Ready)
  assert_eq(first.address, "10.42.1.99")
  assert_eq(api.objects.length(), 3)
  assert_eq(api.calls.filter(call => call.has_prefix("POST")).length(), 3)
  let restored = restore_supervisor(api, checkpoint)
  assert_eq(
    restored.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    ).state,
    @contracts.Ready,
  )
  assert_eq(api.calls.filter(call => call.has_prefix("POST")).length(), 3)
  assert_eq(restored.stop(assignment.assignment_id), @contracts.Draining)
  assert_eq(restored.retained_artifact_digests(), [assignment.artifact.digest])
  let deletions = api.calls.filter(call => call.has_prefix("DELETE"))
  assert_true(deletions[0].contains("/pods/"))
  assert_eq(api.objects.length(), 2)
  assert_eq(restored.stop(assignment.assignment_id), @contracts.Draining)
  assert_eq(restored.stop(assignment.assignment_id), @contracts.Draining)
  assert_eq(restored.stop(assignment.assignment_id), @contracts.Stopped)
  assert_eq(api.objects.length(), 0)
  assert_eq(restored.retained_artifact_digests(), [])
  assert_true(@json.parse(checkpoint.val.unwrap()) is { "runtimes": [], .. })
}

///|
async test "a lost Pod creation response recovers from the durable intent without adopting foreign objects" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  api.lose_pod_response = true
  let supervisor = restore_supervisor(api, checkpoint)
  let assignment = future_assignment()
  try
    supervisor.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    )
  catch {
    InjectedFault::LostResponse => ()
    _ => fail("wrong injected error")
  } noraise {
    _ => fail("response loss not injected")
  }
  assert_eq(api.objects.length(), 3)
  let restored = restore_supervisor(api, checkpoint)
  assert_eq(
    restored.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    ).state,
    @contracts.Ready,
  )
  assert_eq(api.calls.filter(call => call.has_prefix("POST")).length(), 3)
  for path, resource in api.objects {
    if path.contains("/pods/") {
      guard resource is { "metadata": Object(meta), .. } else {
        fail("missing metadata")
      }
      meta["uid"] = "foreign-replacement"
    }
  }
  try
    restored.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    )
  catch {
    @kubernetes.OwnershipConflict => ()
    _ => fail("wrong ownership error")
  } noraise {
    _ => fail("replacement Pod adopted")
  }
  assert_eq(api.calls.filter(call => call.has_prefix("POST")).length(), 3)
}

///|
async test "journal failure prevents API mutation and can retry from the same in-memory intent" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  let fail_commit = Ref(true)
  let supervisor = @kubernetes.RuntimeSupervisor::restore(
    runtime_settings(),
    api.transport(),
    value => {
      if fail_commit.val {
        raise InjectedFault::FailedCommit
      }
      checkpoint.val = Some(value)
    },
    None,
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let assignment = future_assignment()
  try
    supervisor.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    )
  catch {
    InjectedFault::FailedCommit => ()
    _ => fail("wrong commit error")
  } noraise {
    _ => fail("failed journal accepted")
  }
  assert_eq(api.calls.length(), 0)
  fail_commit.val = false
  assert_eq(
    supervisor.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    ).state,
    @contracts.Ready,
  )
}

///|
async test "an admitted Pod with a changed model mount fails closed" {
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
  for path, resource in api.objects {
    if path.contains("/pods/") {
      guard resource
        is {
          "spec": { "volumes": [{ "hostPath": Object(mount), .. }], .. },
          ..
        } else {
        fail("missing model volume")
      }
      mount["path"] = "/etc/shadow"
    }
  }
  try
    supervisor.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    )
  catch {
    @kubernetes.OwnershipConflict => ()
    _ => fail("wrong model ownership error")
  } noraise {
    _ => fail("altered model mount accepted")
  }
  for _ in 0..<4 {
    supervisor.reap_expired(@async.now())
  }
  assert_eq(api.objects.length(), 0)
}

///|
async test "expiry reaper works without fetching controller state" {
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
  for _ in 0..<4 {
    supervisor.reap_expired(assignment.lease_expires_unix_ms)
  }
  assert_eq(api.objects.length(), 0)
  assert_true(@json.parse(checkpoint.val.unwrap()) is { "runtimes": [], .. })
}

///|
async test "fresh empty controller intent cleans a restored journal without NodeAgent memory" {
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
  let restored = restore_supervisor(api, checkpoint)
  for _ in 0..<4 {
    restored.remove_absent([])
  }
  assert_eq(api.objects.length(), 0)
  assert_eq(restored.retained_artifact_digests(), [])
}

///|
async test "expiry during preparation prevents creating the runtime Pod" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  let transport = api.transport()
  let clock = Ref(1000L)
  let supervisor = @kubernetes.RuntimeSupervisor::restore(
    runtime_settings(),
    (verb, path, body) => {
      if verb == "POST" && path.has_suffix("/networkpolicies") {
        clock.val = 60000L
      }
      transport(verb, path, body)
    },
    value => checkpoint.val = Some(value),
    None,
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    clock=() => clock.val,
  )
  let assignment = runtime_assignment()
  try
    supervisor.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      1000L,
    )
  catch {
    @kubernetes.LeaseExpired => ()
    _ => fail("wrong preparation expiry error")
  } noraise {
    _ => fail("expired runtime launched")
  }
  assert_false(
    api.calls.any(call => call.has_prefix("POST") && call.has_suffix("/pods")),
  )
  for _ in 0..<4 {
    supervisor.reap_expired(@async.now())
  }
  assert_eq(api.objects.length(), 0)
}
