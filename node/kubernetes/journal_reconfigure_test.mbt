///|
async test "controller routes change only after complete runtime cleanup" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  let supervisor = restore_supervisor(api, checkpoint)
  let changed = {
    ..runtime_settings(),
    controller_addresses: ["192.168.2.175", "10.42.0.0"],
  }
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
  // Both running resources and partly completed deletion retain old policy.
  for phase in 0..<5 {
    try
      @kubernetes.RuntimeSupervisor::restore(
        changed,
        api.transport(),
        value => checkpoint.val = Some(value),
        Some(supervisor.snapshot()),
        "",
      )
    catch {
      @kubernetes.InvalidResource => ()
      _ => fail("wrong policy-change rejection")
    } noraise {
      _ => fail("changed controller routes while resources remain")
    }
    let state = supervisor.stop(assignment.assignment_id)
    if phase < 4 {
      assert_eq(state, @contracts.Draining)
    } else {
      assert_eq(state, @contracts.Stopped)
    }
  }
  let restored = @kubernetes.RuntimeSupervisor::restore(
    changed,
    api.transport(),
    value => checkpoint.val = Some(value),
    Some(supervisor.snapshot()),
    "",
  )
  let before = @json.parse(supervisor.snapshot())
  let after = @json.parse(restored.snapshot())
  guard before is { "owner": String(owner), .. } &&
    after is { "owner": String(new_owner), "runtimes": [], .. } else {
    fail("journal ownership missing")
  }
  assert_eq(owner, new_owner)
  assert_eq(api.objects.length(), 0)
  ignore(
    restored.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    ),
  )
  assert_true(restored.snapshot().contains("10.42.0.0/32"))
}

///|
test "drained policy update cannot change identity or allow public routes" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  let snapshot = restore_supervisor(api, checkpoint).snapshot()
  let base = runtime_settings()
  for
    changed in [
      { ..base, namespace_name: "different", },
      { ..base, node_name: "different", },
      { ..base, node_id: "different", },
      { ..base, model_cache_root: "/var/lib/other", },
      { ..base, runtime_port: 9000, },
      { ..base, run_as_user: 2000, },
      { ..base, controller_addresses: [], },
      { ..base, controller_addresses: ["8.8.8.8"], },
      { ..base, controller_addresses: ["10.42.0.0/16"], },
    ] {
    try
      @kubernetes.RuntimeSupervisor::restore(
        changed,
        api.transport(),
        _ => (),
        Some(snapshot),
        "",
      )
    catch {
      @kubernetes.InvalidResource => ()
      _ => fail("wrong boundary rejection")
    } noraise {
      _ => fail("unsafe journal reconfiguration accepted")
    }
  }
  assert_eq(api.calls.length(), 0)
}
