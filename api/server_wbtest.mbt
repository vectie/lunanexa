///|
test "public workload response removes internal execution topology" {
  let internal : @contracts.WorkloadResponse = {
    version: @contracts.contract_version,
    workload_id: "workload-redaction",
    state: Succeeded,
    output: Some({ "output_text": "ok" }),
    error: None,
    usage: { input_units: 1, output_units: 1, accelerator_ms: 1L, queue_ms: 0L },
    artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    runtime_version: "runtime-v1",
    execution_node_id: Some("private-node-1"),
    timing: {
      accepted_unix_ms: 1L,
      started_unix_ms: 2L,
      first_output_unix_ms: 3L,
      completed_unix_ms: 4L,
    },
    retryable: false,
    audit_receipt: "receipt-redaction",
  }
  let public = topology_free_workload_response(internal)
  assert_eq(public.execution_node_id, None)
  assert_eq(internal.execution_node_id, Some("private-node-1"))
}
