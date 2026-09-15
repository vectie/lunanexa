///|
async test "placement metadata is durable and legacy records can be safely backfilled" {
  let saves : Array[Snapshot] = []
  let jobs = JobStore::restore(empty_snapshot(), value => saves.push(value))
  let job = reserve(jobs, "legacy-context")
  let legacy = ToJson::to_json(job)
  guard legacy is Object(fields) else { fail("expected stored job object") }
  fields.remove("execution_context")
  let decoded : StoredJob = @json.from_json(legacy)
  assert_eq(decoded.execution_context, None)
  let context : ExecutionContext = {
    deployment_id: "deployment-a",
    generation: 1L,
    node_id: "node-a",
  }
  jobs.remember_execution(job.deployment_id, context)
  assert_eq(jobs.context_for_binding(job.deployment_id), Some(context))
  let restored = JobStore::restore(saves.last().unwrap(), _ => ())
  assert_eq(restored.get(job.job_id, owner()).execution_context, Some(context))
  try
    restored.remember_execution(job.deployment_id, {
      ..context,
      node_id: "other-node",
    })
  catch {
    Conflict => ()
    error => raise error
  } noraise {
    _ => fail("placement changed for an immutable binding")
  }
  assert_eq(restored.context_for_binding(job.deployment_id), Some(context))
  assert_false(
    ToJson::to_json(restored.snapshot()).stringify().contains("http"),
  )
}

///|
async test "placement persistence failure and conflicting reservations publish no metadata" {
  let jobs = JobStore::restore(empty_snapshot(), _ => ())
  let job = reserve(jobs, "metadata-failure")
  let frozen = JobStore::restore(jobs.snapshot(), _ => {
    raise Failure("disk unavailable")
  })
  let context : ExecutionContext = {
    deployment_id: "deployment-a",
    generation: 1L,
    node_id: "node-a",
  }
  try frozen.remember_execution(job.deployment_id, context) catch {
    _ => ()
  } noraise {
    _ => fail("unpersisted metadata published")
  }
  assert_eq(frozen.context_for_binding(job.deployment_id), None)
  jobs.remember_execution(job.deployment_id, context)
  try
    jobs.reserve(
      owner(),
      "different-request",
      digest("fixture"),
      "video.h3",
      job.deployment_id,
      1000L,
      2000L,
      5000L,
      execution_context={ ..context, node_id: "other-node", },
    )
  catch {
    Conflict => ()
    error => raise error
  } noraise {
    _ => fail("conflicting binding placement accepted")
  }
  let invalid = jobs.snapshot()
  let changed = {
    ..invalid.jobs[0],
    execution_context: Some({ ..context, generation: 0L, }),
  }
  try JobStore::restore({ ..invalid, jobs: [changed], }, _ => ()) catch {
    InvalidSnapshot => ()
    error => raise error
  } noraise {
    _ => fail("invalid placement restored")
  }
}
