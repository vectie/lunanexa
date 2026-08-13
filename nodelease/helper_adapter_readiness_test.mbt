///|
test "machine helper adapter evidence binds scope actions and expiry" {
  let secret = "machine-helper-evidence-secret-more-than-32-bytes"
  let unsigned : @nodelease.MachineHelperAdapterReadinessEvidence = {
    version: @nodelease.helper_adapter_readiness_contract_version,
    adapter_id: "systemd-root-helper",
    node_scope: "dgx-spark-fleet",
    covered_node_ids: ["dgx-spark-01", "dgx-spark-02"],
    evidence_ref: "retained-helper-drill-20260813",
    checked_unix_ms: 1000L,
    expires_unix_ms: 61000L,
    provision_verified: true,
    revoke_verified: true,
    sanitize_verified: true,
    quarantine_verified: true,
    signature: "",
  }
  let evidence = {
    ..unsigned,
    signature: @nodelease.machine_helper_adapter_signature(unsigned, secret),
  }
  assert_true(@nodelease.machine_helper_adapter_evidence_ready(evidence, 1000L))
  assert_true(
    @nodelease.valid_machine_helper_adapter_evidence_signature(evidence, secret),
  )
  assert_false(
    @nodelease.machine_helper_adapter_evidence_ready(evidence, 61000L),
  )
  assert_false(
    @nodelease.valid_machine_helper_adapter_evidence_signature(
      { ..evidence, node_scope: "other-fleet" },
      secret,
    ),
  )
  assert_false(
    @nodelease.machine_helper_adapter_evidence_ready(
      { ..evidence, sanitize_verified: false },
      1000L,
    ),
  )
  assert_false(
    @nodelease.machine_helper_adapter_evidence_ready(
      { ..evidence, covered_node_ids: ["dgx-spark-01", "dgx-spark-01"] },
      1000L,
    ),
  )
}
