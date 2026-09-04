///|
async test "durable inference receipt is rated exactly once" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let directory = @fs.tmpdir(prefix="lunanexa-inference-billing-")
  let durable = @store.FileStore::open("\{directory}/control.json")
  durable.fence_controller(1L)
  let database = @database.PostgresDatabase::open(url)
  let commercial = @commercial.CommercialStore::new()
  commercial.add_organization({
    organization_id: "organization-inference-billing",
    display_name: "Inference billing organization",
    state: Active,
    verification_ref: Some("verification-inference-billing"),
    created_unix_ms: 1000L,
  })
  commercial.add_cost_center({
    cost_center_id: "cost-center-inference-billing",
    organization_id: "organization-inference-billing",
    parent_cost_center_id: None,
    display_name: "Inference billing cost center",
    created_unix_ms: 1000L,
  })
  commercial.add_project({
    project_id: "project-inference-billing",
    organization_id: "organization-inference-billing",
    cost_center_id: "cost-center-inference-billing",
    display_name: "Inference billing project",
    created_unix_ms: 1000L,
  })
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses", "test-runtime-token", "runtime-v1", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let rate : @commercial.RateCard = {
    rate_card_id: "inference-accelerator-second",
    version: "test-v1",
    meter: "accelerator-second",
    unit: "second",
    unit_price: @commercial.money(25L, "CNY", 2),
    effective_from_unix_ms: 1L,
    effective_until_unix_ms: 1000000L,
  }
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "test",
    )
    .with_commercial_persistence(
      commercial,
      @commercial_integrations.IntegrationStore::new(),
      database,
    )
    .with_inference_rate_card(rate)
  let request : @contracts.WorkloadEnvelope = {
    version: @contracts.contract_version,
    idempotency_key: "billing-idempotency",
    workload_id: "billing-workload",
    tenant_ref: "tenant-inference-billing",
    credential_scope: "api-key:billing-key",
    capability: TextGenerate,
    model_selector: "text-default",
    payload: { "input": "hello" },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: 100000L,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: 10,
      max_output_units: 10,
      max_runtime_ms: 10000L,
      max_accelerator_memory_mib: 1024,
    },
    stream: false,
    output_format: "text",
    trace_token: "billing-trace",
  }
  let response : @contracts.WorkloadResponse = {
    version: @contracts.contract_version,
    workload_id: request.workload_id,
    state: Succeeded,
    output: None,
    error: None,
    usage: {
      input_units: 3,
      output_units: 2,
      accelerator_ms: 1501L,
      queue_ms: 1L,
    },
    artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    runtime_version: "runtime-v1",
    execution_node_id: Some("node-billing"),
    timing: {
      accepted_unix_ms: 2000L,
      started_unix_ms: 2001L,
      first_output_unix_ms: 2100L,
      completed_unix_ms: 3502L,
    },
    retryable: false,
    audit_receipt: "billing-receipt",
  }
  let authority : @access.ApiAuthorization = {
    key_id: "billing-key",
    tenant_ref: request.tenant_ref,
    subject_ref: "subject-inference-billing",
    organization_id: "organization-inference-billing",
    project_id: "project-inference-billing",
  }
  service.record_inference_charge(request, response, authority)
  service.record_inference_charge(request, response, authority)
  let snapshot = commercial.snapshot("organization-inference-billing")
  assert_eq(snapshot.usage_observations.length(), 1)
  assert_eq(snapshot.usage_observations[0].quantity, 2L)
  assert_eq(snapshot.ledger_entries.length(), 1)
  assert_eq(snapshot.ledger_entries[0].amount.minor_units, 50L)
  database.close()
  @fs.rmdir(directory, recursive=true)
}
