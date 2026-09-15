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
