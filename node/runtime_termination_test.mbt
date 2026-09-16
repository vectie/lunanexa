///|
test "termination report MAC binds identity time and evidence and survives wire decoding" {
  let record : @contracts.RuntimeTermination = {
    assignment_id: "assignment-a",
    deployment_id: "deployment-a",
    generation: 1L,
    controller_epoch: 2L,
    instance_id: "a".repeat(64),
    artifact_digest: "sha256:" + "b".repeat(64),
    image_digest: "sha256:" + "c".repeat(64),
    observed_unix_ms: 1000L,
    original_assignment: None,
  }
  let report : @contracts.RuntimeTerminationReport = {
    node_id: "node-a",
    timestamp_unix_ms: 2000L,
    records: [record],
    signature: "",
  }
  let signature = @node.termination_report_signature(report, "test-only-key")
  let wire = ToJson::to_json({ ..report, signature, })
  let decoded : @contracts.RuntimeTerminationReport = @json.from_json(wire)
  assert_eq(
    @node.termination_report_signature(decoded, "test-only-key"),
    signature,
  )
  for
    changed in [
      { ..report, node_id: "node-b", },
      { ..report, timestamp_unix_ms: 2001L, },
      { ..report, records: [], },
      { ..report, records: [{ ..record, instance_id: "d".repeat(64), }], },
      { ..report, records: [{ ..record, controller_epoch: 3L, }], },
      { ..report, records: [{ ..record, observed_unix_ms: 999L, }], },
    ] {
    assert_true(
      @node.termination_report_signature(changed, "test-only-key") != signature,
    )
  }
  assert_true(
    @node.termination_report_signature(report, "wrong-key") != signature,
  )
}
