///|
async test "termination rejects stale future unknown and conflicting evidence without mutation" {
  let jobs = JobStore::restore(empty_snapshot(), _ => ())
  let job = reserve(jobs, "termination-adversarial")
  let context : ExecutionContext = {
    deployment_id: "deployment-a",
    generation: 1L,
    node_id: "node-a",
    instance_id: Some("a".repeat(64)),
  }
  jobs.remember_execution(job.deployment_id, context)
  ignore(jobs.begin_submission(job.job_id, owner(), 1001L))
  ignore(jobs.attach_provider(job.job_id, owner(), "upstream-job", 1002L))
  let before = jobs.get(job.job_id, owner())
  for observed in [999L, 1005L] {
    try
      jobs.acknowledge_instance_termination(
        job.job_id,
        owner(),
        job.deployment_id,
        context,
        "evidence-a",
        observed,
        1004L,
      )
    catch {
      Conflict | InvalidInput => ()
      error => raise error
    } noraise {
      _ => fail("out-of-window termination accepted")
    }
    assert_true(jobs.get(job.job_id, owner()) == before)
  }
  try
    jobs.acknowledge_instance_termination(
      job.job_id,
      owner(),
      job.deployment_id,
      { ..context, instance_id: None, },
      "evidence-a",
      1003L,
      1004L,
    )
  catch {
    InvalidInput => ()
    error => raise error
  } noraise {
    _ => fail("unknown incarnation accepted")
  }
  assert_true(jobs.get(job.job_id, owner()) == before)
  let terminal = jobs.acknowledge_instance_termination(
    job.job_id,
    owner(),
    job.deployment_id,
    context,
    "evidence-a",
    1003L,
    1004L,
  )
  try
    jobs.acknowledge_instance_termination(
      job.job_id,
      owner(),
      job.deployment_id,
      context,
      "evidence-b",
      1003L,
      1005L,
    )
  catch {
    Conflict => ()
    error => raise error
  } noraise {
    _ => fail("conflicting terminal evidence accepted")
  }
  assert_true(jobs.get(job.job_id, owner()) == terminal)
  try
    jobs.acknowledge_instance_termination(
      job.job_id,
      owner(),
      job.deployment_id,
      context,
      "evidence-a",
      1004L,
      1005L,
    )
  catch {
    Conflict => ()
    error => raise error
  } noraise {
    _ => fail("same reference with changed observation accepted")
  }
  assert_true(jobs.get(job.job_id, owner()) == terminal)
  let saved = jobs.snapshot()
  let legacy = { ..saved, jobs: [{ ..terminal, state: Cancelling }] }
  let recovered = JobStore::restore(legacy, _ => ())
  assert_eq(recovered.get(job.job_id, owner()).state, Cancelled)
  for expired in [false, true] {
    let restored = JobStore::restore(saved, _ => ())
    let cancelled = restored.cancel(job.job_id, owner(), expired, 1006L)
    assert_eq(cancelled.state, if expired { Expired } else { Cancelled })
    assert_eq(cancelled.termination_evidence_ref, terminal.termination_evidence_ref)
    ignore(JobStore::restore(restored.snapshot(), _ => ()))
  }
  for
    invalid in [
      { ..terminal, termination_observed_unix_ms: None, },
      { ..terminal, termination_observed_unix_ms: Some(999L), },
      { ..terminal, termination_observed_unix_ms: Some(1005L), },
    ] {
    try JobStore::restore({ ..saved, jobs: [invalid], }, _ => ()) catch {
      InvalidSnapshot => ()
      error => raise error
    } noraise {
      _ => fail("invalid termination timestamp restored")
    }
  }
}

///|
async test "verified termination matches original incarnation and is durable and idempotent" {
  let jobs = JobStore::restore(empty_snapshot(), _ => ())
  let job = reserve(jobs, "termination")
  let context : ExecutionContext = {
    deployment_id: "deployment-a",
    generation: 1L,
    node_id: "node-a",
    instance_id: Some("a".repeat(64)),
  }
  jobs.remember_execution(job.deployment_id, context)
  ignore(jobs.begin_submission(job.job_id, owner(), 1001L))
  ignore(jobs.attach_provider(job.job_id, owner(), "upstream-job", 1002L))
  for
    wrong in [
      { ..context, instance_id: Some("b".repeat(64)), },
      { ..context, generation: 2L, },
      { ..context, node_id: "other-node", },
    ] {
    try
      jobs.acknowledge_instance_termination(
        job.job_id,
        owner(),
        job.deployment_id,
        wrong,
        "evidence-a",
        1003L,
        1004L,
      )
    catch {
      Conflict => ()
      error => raise error
    } noraise {
      _ => fail("foreign instance termination accepted")
    }
  }
  let terminal = jobs.acknowledge_instance_termination(
    job.job_id,
    owner(),
    job.deployment_id,
    context,
    "evidence-a",
    1003L,
    1004L,
  )
  assert_eq(terminal.state, Failed)
  assert_true(terminal.execution_terminal)
  assert_eq(terminal.usage_receipt, None)
  assert_eq(terminal.termination_evidence_ref, Some("evidence-a"))
  let restored = JobStore::restore(
    @json.from_json(ToJson::to_json(jobs.snapshot())),
    _ => (),
  )
  assert_true(
    restored.acknowledge_instance_termination(
      job.job_id,
      owner(),
      job.deployment_id,
      context,
      "evidence-a",
      1003L,
      1005L,
    ) ==
    terminal,
  )
  ignore(reserve(restored, "capacity-after-termination"))
}

///|
async test "failed termination persistence cannot release capacity" {
  let jobs = JobStore::restore(empty_snapshot(), _ => ())
  let job = reserve(jobs, "termination-failure")
  let context : ExecutionContext = {
    deployment_id: "deployment-a",
    generation: 1L,
    node_id: "node-a",
    instance_id: Some("a".repeat(64)),
  }
  jobs.remember_execution(job.deployment_id, context)
  ignore(jobs.begin_submission(job.job_id, owner(), 1001L))
  ignore(jobs.attach_provider(job.job_id, owner(), "upstream-job", 1002L))
  let frozen = JobStore::restore(jobs.snapshot(), _ => {
    raise Failure("unavailable")
  })
  try
    frozen.acknowledge_instance_termination(
      job.job_id,
      owner(),
      job.deployment_id,
      context,
      "evidence-a",
      1002L,
      1003L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("unpersisted termination accepted")
  }
  assert_false(frozen.get(job.job_id, owner()).execution_terminal)
  assert_eq(frozen.get(job.job_id, owner()).termination_evidence_ref, None)
  try reserve(frozen, "must-remain-busy") catch {
    Busy => ()
    error => raise error
  } noraise {
    _ => fail("failed persistence released capacity")
  }
}
