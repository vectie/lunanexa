///|
fn fixture_request() -> @contracts.WorkloadEnvelope {
  {
    version: @contracts.contract_version,
    idempotency_key: "idem-001",
    workload_id: "workload-001",
    tenant_ref: "tenant-opaque-7",
    credential_scope: "inference",
    capability: TextGenerate,
    model_selector: "text.default",
    payload: { "input": "hello" },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: 1900000000000L,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: 4096,
      max_output_units: 512,
      max_runtime_ms: 30000L,
      max_accelerator_memory_mib: 120000,
    },
    stream: true,
    output_format: "text",
    trace_token: "trace-opaque-9",
  }
}

///|
test "v1 workload round-trips through canonical JSON" {
  let request = fixture_request()
  @contracts.validate_workload(request)
  let encoded = request.to_json().stringify()
  inspect(
    encoded,
    content=(
      #|{"version":"lunanexa.v1","idempotency_key":"idem-001","workload_id":"workload-001","tenant_ref":"tenant-opaque-7","credential_scope":"inference","capability":"TextGenerate","model_selector":"text.default","payload":{"input":"hello"},"data_policy":{"classification":"Confidential","retention":"Ephemeral","allow_cache":false,"allow_training_reuse":false},"deadline_unix_ms":"1900000000000","priority":"Interactive","latency_class":"Realtime","resource_ceiling":{"max_input_units":4096,"max_output_units":512,"max_runtime_ms":"30000","max_accelerator_memory_mib":120000},"stream":true,"output_format":"text","trace_token":"trace-opaque-9"}
    ),
  )
  let decoded = @contracts.decode_workload(encoded)
  assert_eq(decoded, request)
}

///|
test "training reuse requires explicit evaluation consent" {
  let request = fixture_request()
  let invalid : @contracts.WorkloadEnvelope = {
    ..request,
    data_policy: { ..request.data_policy, allow_training_reuse: true },
  }
  try @contracts.validate_workload(invalid) catch {
    InvalidPolicy(_) => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected validation failure")
  }
}

///|
test "resource ceilings and ephemeral cache policy are enforced at decode" {
  let request = fixture_request()
  let invalid : @contracts.WorkloadEnvelope = {
    ..request,
    resource_ceiling: { ..request.resource_ceiling, max_runtime_ms: 0L },
  }
  try @contracts.decode_workload(invalid.to_json().stringify()) catch {
    @contracts.ContractError::InvalidResourceCeiling("max_runtime_ms") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("zero runtime ceiling was accepted")
  }
  try
    @contracts.validate_workload({
      ..request,
      data_policy: { ..request.data_policy, allow_cache: true },
    })
  catch {
    InvalidPolicy(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("ephemeral cache was accepted")
  }
}

///|
test "public identifiers reject path and log injection characters" {
  let request = fixture_request()
  for
    invalid in [
      { ..request, workload_id: "../audit" },
      { ..request, tenant_ref: "tenant\nforged-event" },
      { ..request, model_selector: "text/default" },
    ] {
    try @contracts.validate_workload(invalid) catch {
      InvalidPolicy(message) => assert_true(message.contains("identifier"))
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("unsafe public identifier was accepted")
    }
  }
  assert_true(@contracts.valid_identifier("opaque:tenant-1"))
  assert_false(@contracts.valid_identifier("node/one"))
  assert_true(
    @contracts.valid_sha256_digest(
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
  )
  assert_false(@contracts.valid_sha256_digest("sha256:model"))
  assert_false(
    @contracts.valid_sha256_digest(
      "sha256:gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg",
    ),
  )
}

///|
test "lifecycle transitions are explicit" {
  assert_true(@contracts.workload_transition_allowed(Submitted, Admitted))
  assert_false(@contracts.workload_transition_allowed(Succeeded, Running))
  assert_true(@contracts.deployment_transition_allowed(Pending, Preparing))
  assert_false(@contracts.node_transition_allowed(Retired, Active))
  assert_true(@contracts.model_transition_allowed(Evaluated, Approved))
}
