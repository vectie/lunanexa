///|
test "termination acknowledgements cannot retire foreign or duplicated evidence" {
  let entry : @contracts.RuntimeTermination = {
    assignment_id: "a",
    deployment_id: "d",
    generation: 1L,
    controller_epoch: 1L,
    instance_id: "a".repeat(64),
    artifact_digest: "sha256:" + "b".repeat(64),
    image_digest: "sha256:" + "c".repeat(64),
    observed_unix_ms: 1000L,
    original_assignment: None,
  }
  let other = { ..entry, instance_id: "d".repeat(64), }
  let (first, cursor) = termination_batch([entry, other], 0)
  assert_eq(first, [entry])
  assert_eq(termination_batch([entry, other], cursor).0, [other])
  let huge = { ..entry, assignment_id: "x".repeat(210000), }
  assert_eq(termination_batch([huge, other], 0).0, [other])
  assert_true(acknowledgement_matches([entry, other], [entry]))
  assert_true(acknowledgement_matches([entry], []))
  assert_false(acknowledgement_matches([entry], [other]))
  assert_false(acknowledgement_matches([entry, other], [entry, entry]))
  assert_false(
    acknowledgement_matches([entry], [{ ..entry, controller_epoch: 2L, }]),
  )
}
