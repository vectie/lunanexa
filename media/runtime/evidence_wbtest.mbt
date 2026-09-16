///|
async test "normal reconciliation consumes durable evidence without live authority or replacement" {
  let jobs = store()
  let context : @jobs.ExecutionContext = {
    deployment_id: "deployment",
    generation: 1L,
    node_id: "node",
    instance_id: Some("a".repeat(64)),
  }
  let job = jobs.reserve(
      owner(),
      "automatic-termination",
      request().digest(),
      "video.h3",
      "old-binding",
      1000L,
      5000L,
      10000L,
      execution_context=context,
    ).0
  ignore(jobs.begin_submission(job.job_id, owner(), 1001L))
  ignore(jobs.attach_provider(job.job_id, owner(), "upstream", 1002L))
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
  let settlements = Ref(0)
  let runtime = VideoRuntime::new(
    restored,
    _ => raise Failure("replacement must not be contacted"),
    (_, _, _) => {
      raise Failure("authority outage must not prevent terminal cleanup")
    },
    _ => {
      settlements.val += 1
      "usage-receipt"
    },
    now=() => 1010L,
  )
  assert_eq(runtime.reconcile(), (1, 0))
  let terminal = restored.get(job.job_id, owner())
  assert_eq(terminal.state, Failed)
  assert_eq(terminal.usage_receipt, Some("usage-receipt"))
  ignore(runtime.reconcile())
  assert_eq(settlements.val, 1)
  try
    restored.reserve(
      owner(),
      "new-on-dead-instance",
      request().digest(),
      "video.h3",
      "old-binding",
      1020L,
      5000L,
      10000L,
      execution_context=context,
    )
  catch {
    @jobs.InvalidTransition => ()
    error => raise error
  } noraise {
    _ => fail("dead incarnation admitted new work")
  }
}
