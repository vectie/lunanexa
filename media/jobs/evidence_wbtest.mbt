///|
async test "accepted evidence survives unrelated writes and restart and rejects changed replay" {
  let store = JobStore::restore(empty_snapshot(), _ => ())
  let value : AcceptedTermination = {
    node_id: "node-a",
    evidence: {
      assignment_id: "assignment-a",
      deployment_id: "deployment-a",
      generation: 1L,
      controller_epoch: 2L,
      instance_id: "a".repeat(64),
      artifact_digest: "sha256:" + "b".repeat(64),
      image_digest: "sha256:" + "c".repeat(64),
      observed_unix_ms: 1000L,
      original_assignment: None,
    },
  }
  store.accept_termination(value)
  for
    duplicate in [
      value,
      { ..value, evidence: { ..value.evidence, controller_epoch: 3L, }, },
    ] {
    let saved = { ..empty_snapshot(), terminations: Some([value, duplicate]), }
    try JobStore::restore(saved, _ => ()) catch {
      InvalidSnapshot => ()
      error => raise error
    } noraise {
      _ => fail("duplicate incarnation evidence restored")
    }
  }
  let different_node = { ..value, node_id: "node-b", }
  let distinct = JobStore::restore(
    { ..empty_snapshot(), terminations: Some([value, different_node]), },
    _ => (),
  )
  assert_eq(distinct.snapshot().terminations.unwrap().length(), 2)
  ignore(reserve(store, "unrelated-job"))
  let restored = JobStore::restore(store.snapshot(), _ => ())
  restored.accept_termination(value)
  assert_true(restored.snapshot().terminations == Some([value]))
  try
    restored.accept_termination({
      ..value,
      evidence: { ..value.evidence, controller_epoch: 3L, },
    })
  catch {
    Conflict => ()
    error => raise error
  } noraise {
    _ => fail("changed replay accepted")
  }
  let frozen = JobStore::restore(empty_snapshot(), _ => {
    raise Failure("disk unavailable")
  })
  try frozen.accept_termination(value) catch {
    _ => ()
  } noraise {
    _ => fail("unpersisted evidence accepted")
  }
  assert_true(frozen.snapshot().terminations == Some([]))
  let racing = JobStore::restore(empty_snapshot(), _ => ())
  let context : ExecutionContext = {
    deployment_id: "deployment-a",
    generation: 1L,
    node_id: "node-a",
    instance_id: Some("a".repeat(64)),
  }
  let reserved = racing.reserve(
      owner(),
      "reserved-before-exit",
      digest("request"),
      "video.h3",
      "binding",
      1000L,
      5000L,
      10000L,
      execution_context=context,
    ).0
  racing.accept_termination(value)
  try racing.begin_submission(reserved.job_id, owner(), 1001L) catch {
    InvalidTransition => ()
    error => raise error
  } noraise {
    _ => fail("reserved job submitted after termination acceptance")
  }
  assert_eq(racing.get(reserved.job_id, owner()).state, Intent)
}
