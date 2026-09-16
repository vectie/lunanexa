///|
async test "restored completed job consumes accepted exit without provider calls or rebilling" {
  for pending_cleanup in [false, true] {
    let jobs = store()
    let context : @jobs.ExecutionContext = {
      deployment_id: "deployment",
      generation: 1L,
      node_id: "node",
      instance_id: Some("a".repeat(64)),
    }
    let job = jobs.reserve(
        owner(),
        "late-exit",
        request().digest(),
        "video.h3",
        "old-binding",
        1000L,
        5000L,
        10000L,
        execution_context=context,
      ).0
    ignore(jobs.begin_submission(job.job_id, owner(), 1001L))
    ignore(jobs.attach_provider(job.job_id, owner(), "provider-job", 1002L))
    ignore(jobs.observe(job.job_id, owner(), Completed, Some(100), 1003L))
    ignore(jobs.record_usage(job.job_id, owner(), "existing-receipt"))
    if pending_cleanup {
      ignore(jobs.cancel(job.job_id, owner(), false, 1004L))
    }
    jobs.accept_termination({
      node_id: "node",
      evidence: {
        assignment_id: "assignment",
        deployment_id: "deployment",
        generation: 1L,
        controller_epoch: 1L,
        instance_id: "a".repeat(64),
        artifact_digest: "sha256:" + "b".repeat(64),
        image_digest: "sha256:" + "c".repeat(64),
        observed_unix_ms: 1005L,
        original_assignment: None,
      },
    })
    let restored = @jobs.JobStore::restore(jobs.snapshot(), _ => ())
    let runtime = VideoRuntime::new(
      restored,
      _ => raise Failure("must not contact a dead provider or replacement"),
      (_, _, _) => true,
      _ => raise Failure("must not bill an already settled job"),
      now=() => 1010L,
    )
    assert_eq(runtime.reconcile(), (1, 0))
    let ended = restored.get(job.job_id, owner())
    assert_eq(ended.state, if pending_cleanup { Cancelled } else { Completed })
    assert_eq(ended.terminal_unix_ms, Some(1003L))
    assert_eq(ended.usage_receipt, Some("existing-receipt"))
    assert_true(ended.termination_evidence_ref is Some(_))
    try
      runtime.content(job.job_id, owner(), 100L, _ => fail("unexpected content"))
    catch {
      ContentUnavailable => ()
      error => raise error
    } noraise {
      _ => fail("dead provider artifact advertised as readable")
    }
    for _ in 0..<2 {
      assert_eq(runtime.cancel(job.job_id, owner()).state, Cancelled)
    }
  }
}

///|
async test "verified lost-instance termination retries settlement without contacting replacement" {
  let jobs = store()
  let context : @jobs.ExecutionContext = {
    deployment_id: "deployment",
    generation: 1L,
    node_id: "node",
    instance_id: Some("a".repeat(64)),
  }
  let job = jobs.reserve(
      owner(),
      "lost-instance",
      request().digest(),
      "video.h3",
      "old-binding",
      1000L,
      5000L,
      10000L,
      execution_context=context,
    ).0
  ignore(jobs.begin_submission(job.job_id, owner(), 1001L))
  ignore(jobs.attach_provider(job.job_id, owner(), "old-upstream-job", 1002L))
  let calls = Ref(0)
  let settle : async (@jobs.StoredJob) -> String = terminal => {
    assert_eq(terminal.state, Failed)
    assert_eq(terminal.termination_evidence_ref, Some("termination-proof"))
    calls.val += 1
    if calls.val == 1 {
      raise Failure("ledger unavailable")
    }
    "durable-usage-receipt"
  }
  let runtime = VideoRuntime::new(
    jobs,
    _ => raise Failure("must not contact replacement"),
    (_, _, _) => {
      raise Failure(
        "trusted recovery must not depend on current tenant authority",
      )
    },
    settle,
    now=() => 1010L,
  )
  try
    runtime.reconcile_verified_termination(
      job.job_id,
      owner(),
      "old-binding",
      context,
      "termination-proof",
      1005L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected first settlement failure")
  }
  let persisted = jobs.get(job.job_id, owner())
  assert_true(persisted.execution_terminal)
  assert_eq(persisted.usage_receipt, None)
  let restored = @jobs.JobStore::restore(
    @json.from_json(ToJson::to_json(jobs.snapshot())),
    _ => (),
  )
  let resumed = VideoRuntime::new(
    restored,
    _ => raise Failure("must not resolve old route"),
    (_, _, _) => true,
    settle,
    now=() => 1020L,
  )
  let completed = resumed.reconcile_verified_termination(
    job.job_id,
    owner(),
    "old-binding",
    context,
    "termination-proof",
    1005L,
  )
  assert_eq(completed.state, Failed)
  assert_eq(completed.usage_receipt, Some("durable-usage-receipt"))
  ignore(
    resumed.reconcile_verified_termination(
      job.job_id,
      owner(),
      "old-binding",
      context,
      "termination-proof",
      1005L,
    ),
  )
  assert_eq(calls.val, 2)
}
