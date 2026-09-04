///|
priv struct TestMachineTermsAcceptanceRequest {
  idempotency_key : String
  template_version : String
  rendered_document_hash : String
  document_uri : String
  presentation_context_hash : String
  network_context_hash : String
} derive(ToJson)

///|
priv struct TestMachineQuoteRequest {
  quote_id : String
  idempotency_key : String
  project_id : String
  offering_id : String
  quantity : Int64
  duration_seconds : Int64
  unix_username : String?
  requested_model_selector : String?
  model_template_ref : String?
} derive(ToJson)

///|
priv struct TestMachineOrderRequest {
  order_id : String
  idempotency_key : String
  quote_id : String
} derive(ToJson)

///|
fn machine_dedicated_template() -> @deployment.ModelServiceTemplate {
  {
    template_id: "text-small",
    version: "v1",
    display_name: "Text small",
    description: "Approved dedicated text service",
    model_selector: "text.default",
    model_id: "model.text",
    model_version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model.text/v1",
      size_bytes: 1024L,
      signature_ref: "s3://models/model.text/v1.sig",
    },
    runtime: {
      name: "text-runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "runtime-v1",
      architectures: ["nvidia-gb10"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    capability: TextGenerate,
    architecture: "nvidia-gb10",
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 1024,
      cpu_millis: 1000,
      memory_mib: 2048,
    },
    network: {
      allow_controller: true,
      allow_artifact_store: true,
      allowed_egress: [],
    },
    health: {
      readiness_path: "/health",
      interval_ms: 1000,
      failure_threshold: 3,
      termination_grace_ms: 30000,
    },
    data_policy: {
      classification: Internal,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    secret_refs: ["runtime-token"],
    rollout: {
      canary_replicas: 1,
      automatic_promotion: false,
      automatic_rollback: true,
      readiness_timeout_ms: 60000L,
    },
    approval_receipt: "",
    signature: "",
  }
}

///|
async fn machine_dedicated_registry(
  path : String,
  template : @deployment.ModelServiceTemplate,
) -> @registry.FileRegistry {
  let registry = @registry.FileRegistry::open(path)
  registry.register_runtime(template.runtime)
  registry.register_model({
    model_id: template.model_id,
    version: template.model_version,
    artifact: template.artifact,
    license_id: "license.text",
    provenance: "upstream",
    compatible_architectures: [template.architecture],
    minimum_memory_mib: 1024,
    state: Candidate,
  })
  registry.record_license({
    license_id: "license.text",
    model_id: template.model_id,
    status: Accepted,
    accepted_by: "operator",
    evidence_ref: "license-review",
    expires_unix_ms: None,
  })
  for digest in [template.artifact.digest, template.runtime.image_digest] {
    registry.record_verification({
      digest,
      signature_verified: true,
      provenance_verified: true,
      verified_unix_ms: 1L,
      verifier: "test",
    })
  }
  registry.record_evaluation({
    evaluation_id: "eval.text.v1",
    model_id: template.model_id,
    model_version: template.model_version,
    suite_version: "suite-v1",
    passed: true,
    score: 1.0,
    benchmark: {
      profile_id: "profile-v1",
      model_id: template.model_id,
      model_version: template.model_version,
      runtime_version: template.runtime.version,
      hardware_profile: template.architecture,
      workload_profile: "smoke",
      p50_ms: 1.0,
      p95_ms: 2.0,
      p99_ms: 3.0,
      throughput_per_second: 1.0,
      peak_memory_mib: 1024,
    },
    evidence_ref: "evaluation-report",
  })
  ignore(registry.approve(template.model_id, template.model_version, 2L))
  ignore(
    registry.promote(
      template.model_selector,
      template.model_id,
      template.model_version,
      Canary,
      "operator",
      3L,
    ),
  )
  registry
}

///|
async test "settled bare order provisions internally without leaking its node" {
  let directory = @fs.tmpdir(prefix="lunanexa-machine-order-reconcile-")
  let now = @async.now()
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.fence_controller(1L)
  let heartbeat : @contracts.NodeHeartbeat = {
    node_id: "physical-node-a",
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: "physical-node-a",
      agent_version: "0.1.0",
      os_release: "test",
      runtime_names: ["text-runtime"],
      accelerators: [
        {
          device_id: "gpu-private-0",
          architecture: "nvidia-rtx-5060-ti",
          memory_total_mib: 16384,
          memory_free_mib: 16384,
          healthy: true,
        },
      ],
      labels: { "lunanexa.io/region": "cn-north-1" },
      taints: [],
    },
    running_deployments: [],
    timestamp_unix_ms: now,
    signature: "test",
  }
  durable.put_heartbeat(heartbeat)
  durable.put_heartbeat({
    node_id: "aaa-wrong-region-node",
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: "aaa-wrong-region-node",
      agent_version: "0.1.0",
      os_release: "test",
      runtime_names: ["text-runtime"],
      accelerators: [
        {
          device_id: "gpu-wrong-region",
          architecture: "nvidia-rtx-5060-ti",
          memory_total_mib: 16384,
          memory_free_mib: 16384,
          healthy: true,
        },
      ],
      labels: { "lunanexa.io/region": "cn-south-1" },
      taints: [],
    },
    running_deployments: [],
    timestamp_unix_ms: now,
    signature: "test",
  })
  let machine_store = @machinecommerce_store.MachineCommerceStore::open(
    "\{directory}/machine-commerce.json",
    "machine-commerce-reconciler-test-secret-more-than-32-bytes",
  )
  ignore(
    machine_store.put_offering({
      offering_id: "bare-self-service",
      sku: "rtx-5060ti-machine",
      display_name: "RTX 5060 Ti machine",
      kind: BareMachine,
      region: "cn-north-1",
      accelerator_class: "nvidia-rtx-5060-ti",
      accelerator_count: 1L,
      memory_mib: 16384L,
      cpu_count: 16L,
      meter: "exclusive-node-second",
      unit_price: { minor_units: 2L, currency: "CNY", scale: 2 },
      billing_quantum_seconds: 60L,
      minimum_duration_seconds: 60L,
      maximum_duration_seconds: 86400L,
      capacity_total: 1L,
      allowed_model_template_refs: [],
      state: OfferingActive,
      generation: 1L,
      created_unix_ms: now - 10L,
      updated_unix_ms: now - 10L,
    }),
  )
  let (quote, _) = machine_store.create_quote(
    {
      quote_id: "bare-quote-a",
      idempotency_key: "bare-quote-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
      offering_id: "bare-self-service",
      quantity: 1L,
      duration_seconds: 3600L,
      unix_username: Some("developer"),
      requested_model_selector: None,
      model_template_ref: None,
      valid_for_ms: 60000L,
    },
    now,
  )
  let (created, _) = machine_store.create_order(
    {
      order_id: "bare-order-a",
      idempotency_key: "bare-order-a",
      quote_id: quote.quote_id,
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
    },
    now,
  )
  ignore(
    machine_store.activate_settled_payment(
      created.order_id,
      {
        provider_event_id: "provider-event-a",
        payment_ref: "provider:payment-a",
        settled_amount: quote.total,
      },
      now,
    ),
  )
  let (refund_quote, _) = machine_store.create_quote(
    {
      quote_id: "refund-quote-a",
      idempotency_key: "refund-quote-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
      offering_id: "bare-self-service",
      quantity: 1L,
      duration_seconds: 3600L,
      unix_username: Some("developer"),
      requested_model_selector: None,
      model_template_ref: None,
      valid_for_ms: 60000L,
    },
    now,
  )
  let (refund_order, _) = machine_store.create_order(
    {
      order_id: "refund-order-a",
      idempotency_key: "refund-order-a",
      quote_id: refund_quote.quote_id,
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
    },
    now,
  )
  let (compensating, _) = machine_store.activate_settled_payment(
    refund_order.order_id,
    {
      provider_event_id: "provider-event-refund-a",
      payment_ref: "provider:payment-refund-a",
      settled_amount: refund_quote.total,
    },
    now,
  )
  assert_eq(compensating.state, CompensationPending)
  let leases = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive-leases.json",
    "machine-order-exclusive-lease-test-secret",
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  ignore(
    portal.put_membership({
      membership_id: "member-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [LegalSigner, LeaseRequester],
      active: true,
      created_unix_ms: now,
    }),
  )
  let commercial = @commercial.CommercialStore::new()
  commercial.add_organization({
    organization_id: "org-a",
    display_name: "Self-service organization",
    state: Active,
    verification_ref: Some("provider:verified-org-a"),
    legal_profile: None,
    created_unix_ms: now,
  })
  commercial.add_cost_center({
    cost_center_id: "cost-a",
    organization_id: "org-a",
    parent_cost_center_id: None,
    display_name: "Default",
    created_unix_ms: now,
  })
  commercial.add_project({
    project_id: "project-a",
    organization_id: "org-a",
    cost_center_id: "cost-a",
    display_name: "Default project",
    created_unix_ms: now,
  })
  commercial.grant_role({
    grant_id: "grant-a",
    organization_id: "org-a",
    user_id: "subject-a",
    role: OrganizationOwner,
    granted_by: "subject-a",
    granted_unix_ms: now,
    expires_unix_ms: None,
  })
  let terms_hash = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  commercial.register_agreement_template({
    template_id: "machine-public-terms",
    agreement_type: "machine-self-service",
    version: "v1",
    locale: "en-US",
    effective_unix_ms: now - 1L,
    rendered_document_hash: terms_hash,
    document_uri: Some("/docs/machine-self-service/v1"),
    state: DraftTemplate,
    created_unix_ms: now - 1L,
  })
  ignore(
    commercial.set_template_state("machine-public-terms", "v1", ReadyTemplate),
  )
  let base_offering = machine_store.snapshot().offerings[0]
  ignore(
    machine_store.put_offering({
      ..base_offering,
      offering_id: "bare-self-checkout",
      sku: "rtx-5060ti-checkout",
    }),
  )
  ignore(
    machine_store.put_offering({
      ..base_offering,
      offering_id: "bare-wrong-region",
      sku: "rtx-5060ti-wrong-region",
      region: "eu-west-1",
    }),
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let configured = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_exclusive_lease_store(leases)
    .with_portal_store(portal)
    .with_machine_commerce_store(machine_store)
    .with_provider_callback_secrets({
      "provider-a|sandbox": "provider-callback-secret-more-than-32-bytes",
    })
    .with_commercial_provider_adapter(
      "provider-adapter-token-more-than-32-bytes", "provider-a", "sandbox", "https://provider.example",
    )
  let service = { ..configured, commercial_store: commercial }
  let customer_headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
    "X-LunaNexa-Organization": "org-a",
  }
  let terms = service.handle(
    Get,
    "/v1/portal/self/machine-terms",
    customer_headers,
    "",
  )
  assert_eq(terms.status, 200)
  assert_true(terms.body.contains(terms_hash))
  assert_true(terms.body.contains("/docs/machine-self-service/v1"))
  let accepted_terms = service.handle(
    Post,
    "/v1/portal/self/machine-terms/accept",
    customer_headers,
    ToJson::to_json(TestMachineTermsAcceptanceRequest::{
      idempotency_key: "accept-machine-terms-a",
      template_version: "v1",
      rendered_document_hash: terms_hash,
      document_uri: "/docs/machine-self-service/v1",
      presentation_context_hash: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      network_context_hash: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    }).stringify(),
  )
  assert_eq(accepted_terms.status, 201)
  let self_quote = service.handle(
    Post,
    "/v1/portal/self/machine-quotes",
    customer_headers,
    ToJson::to_json(TestMachineQuoteRequest::{
      quote_id: "self-quote-b",
      idempotency_key: "self-quote-b",
      project_id: "project-a",
      offering_id: "bare-self-checkout",
      quantity: 1L,
      duration_seconds: 3600L,
      unix_username: Some("developer"),
      requested_model_selector: None,
      model_template_ref: None,
    }).stringify(),
  )
  assert_eq(self_quote.status, 201)
  let unavailable_quote = service.handle(
    Post,
    "/v1/portal/self/machine-quotes",
    customer_headers,
    ToJson::to_json(TestMachineQuoteRequest::{
      quote_id: "wrong-region-quote",
      idempotency_key: "wrong-region-quote",
      project_id: "project-a",
      offering_id: "bare-wrong-region",
      quantity: 1L,
      duration_seconds: 3600L,
      unix_username: Some("developer"),
      requested_model_selector: None,
      model_template_ref: None,
    }).stringify(),
  )
  assert_eq(unavailable_quote.status, 409)
  assert_true(unavailable_quote.body.contains("CapacityUnavailable"))
  let self_order = service.handle(
    Post,
    "/v1/portal/self/machine-orders",
    customer_headers,
    ToJson::to_json(TestMachineOrderRequest::{
      order_id: "self-order-b",
      idempotency_key: "self-order-b",
      quote_id: "self-quote-b",
    }).stringify(),
  )
  assert_eq(self_order.status, 202)
  assert_true(self_order.body.contains("checkout"))
  assert_false(self_order.body.contains("physical-node-a"))
  let payment_record = service.commercial_integrations.durable_snapshot().records
    .iter()
    .find_first(record => {
      record.kind == Payment &&
      record.entitlement_transaction_ref == Some("machine-order:self-order-b")
    })
    .unwrap()
  let cross_time = @async.now()
  let cross_callback : @commercial_integrations.ExternalCallback = {
    callback_id: "machine-payment-cross-org",
    record_id: payment_record.record_id,
    organization_id: "org-b",
    provider: "provider-a",
    environment: "sandbox",
    external_ref: payment_record.external_ref,
    expected_previous_state: Pending,
    next_state: Settled,
    amount_minor: payment_record.expected_amount_minor,
    currency: payment_record.currency,
    document_hash: None,
    provider_event_unix_ms: cross_time,
    received_unix_ms: cross_time,
    signature_verified: false,
  }
  let cross_body = cross_callback.to_json().stringify()
  let cross_result = service.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    {
      "X-LunaNexa-Provider": "provider-a",
      "X-LunaNexa-Environment": "sandbox",
      "X-LunaNexa-Event-Id": "machine-payment-cross-org",
      "X-LunaNexa-Event-Timestamp": cross_time.to_string(),
      "X-LunaNexa-Signature": provider_callback_signature(
        "provider-a", "sandbox", "machine-payment-cross-org", cross_time, cross_body,
        "provider-callback-secret-more-than-32-bytes",
      ),
    },
    cross_body,
  )
  assert_eq(cross_result.status, 409)
  let underpaid_time = @async.now()
  let underpaid_callback : @commercial_integrations.ExternalCallback = {
    ..cross_callback,
    callback_id: "machine-payment-underpaid",
    organization_id: "org-a",
    amount_minor: Some(payment_record.expected_amount_minor.unwrap() - 1L),
    provider_event_unix_ms: underpaid_time,
    received_unix_ms: underpaid_time,
  }
  let underpaid_body = underpaid_callback.to_json().stringify()
  let underpaid = service.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    {
      "X-LunaNexa-Provider": "provider-a",
      "X-LunaNexa-Environment": "sandbox",
      "X-LunaNexa-Event-Id": "machine-payment-underpaid",
      "X-LunaNexa-Event-Timestamp": underpaid_time.to_string(),
      "X-LunaNexa-Signature": provider_callback_signature(
        "provider-a", "sandbox", "machine-payment-underpaid", underpaid_time, underpaid_body,
        "provider-callback-secret-more-than-32-bytes",
      ),
    },
    underpaid_body,
  )
  assert_eq(underpaid.status, 409)
  let settled_time = @async.now()
  let settled_callback : @commercial_integrations.ExternalCallback = {
    ..cross_callback,
    callback_id: "machine-payment-settled",
    organization_id: "org-a",
    provider_event_unix_ms: settled_time,
    received_unix_ms: settled_time,
  }
  let settled_body = settled_callback.to_json().stringify()
  let settled_headers = {
    "X-LunaNexa-Provider": "provider-a",
    "X-LunaNexa-Environment": "sandbox",
    "X-LunaNexa-Event-Id": "machine-payment-settled",
    "X-LunaNexa-Event-Timestamp": settled_time.to_string(),
    "X-LunaNexa-Signature": provider_callback_signature(
      "provider-a", "sandbox", "machine-payment-settled", settled_time, settled_body,
      "provider-callback-secret-more-than-32-bytes",
    ),
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/provider-callbacks/commercial",
      settled_headers,
      settled_body,
    ).status,
    200,
  )
  let callback_order = machine_store.order("self-order-b").unwrap()
  assert_eq(callback_order.state, PaymentSettled)
  let callback_replay = service.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    settled_headers,
    settled_body,
  )
  assert_eq(callback_replay.status, 200)
  assert_true(callback_replay.body.contains("Replayed"))
  service.reconcile_machine_commerce()
  let refund_record = service.commercial_integrations.durable_snapshot().records
    .iter()
    .find_first(record => {
      record.kind == PaymentRefund &&
      record.entitlement_transaction_ref == Some("machine-order:refund-order-a")
    })
    .unwrap()
  assert_eq(
    refund_record.expected_amount_minor,
    Some(refund_quote.total.minor_units),
  )
  let refund_event_time = @async.now()
  let refund_callback : @commercial_integrations.ExternalCallback = {
    callback_id: "refund-callback-a",
    record_id: refund_record.record_id,
    organization_id: "org-a",
    provider: "provider-a",
    environment: "sandbox",
    external_ref: refund_record.external_ref,
    expected_previous_state: Pending,
    next_state: Refunded,
    amount_minor: Some(refund_quote.total.minor_units),
    currency: Some(refund_quote.total.currency),
    document_hash: None,
    provider_event_unix_ms: refund_event_time,
    received_unix_ms: refund_event_time,
    signature_verified: false,
  }
  let refund_body = refund_callback.to_json().stringify()
  let refund_signature = provider_callback_signature(
    "provider-a", "sandbox", "refund-callback-a", refund_event_time, refund_body,
    "provider-callback-secret-more-than-32-bytes",
  )
  let refunded = service.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    {
      "X-LunaNexa-Provider": "provider-a",
      "X-LunaNexa-Environment": "sandbox",
      "X-LunaNexa-Event-Id": "refund-callback-a",
      "X-LunaNexa-Event-Timestamp": refund_event_time.to_string(),
      "X-LunaNexa-Signature": refund_signature,
    },
    refund_body,
  )
  assert_eq(refunded.status, 200)
  service.reconcile_machine_commerce()
  let compensated = machine_store.order(refund_order.order_id).unwrap()
  assert_eq(compensated.state, Failed)
  assert_true(compensated.compensation_ref.unwrap_or("").has_prefix("refund:"))
  let reconciled = machine_store.order(created.order_id).unwrap()
  assert_eq(reconciled.state, Provisioning)
  assert_eq(
    reconciled.target_lease_ref,
    Some("machine-order-lease-bare-order-a"),
  )
  let internal_lease = leases
    .lease(reconciled.target_lease_ref.unwrap())
    .unwrap()
  assert_eq(internal_lease.intent.node_id, "physical-node-a")
  let active_lease = leases.transition(
    internal_lease.intent.lease_id,
    {
      expected_generation: internal_lease.generation,
      state: Active,
      evidence_receipt: "agent:machine-ready",
    },
    @async.now(),
  )
  ignore(active_lease)
  service.reconcile_machine_commerce()
  let active_order = machine_store.order(created.order_id).unwrap()
  assert_eq(active_order.state, Active)
  let usage_end = active_order.active_started_unix_ms.unwrap() + 60000L
  ignore(
    machine_store.record_usage(
      active_order.order_id,
      {
        idempotency_key: "machine-usage-no-second-charge",
        expected_generation: active_order.generation,
        ended_unix_ms: usage_end,
      },
      usage_end,
    ),
  )
  service.ingest_machine_usage(machine_store.snapshot())
  let commercial_usage = service.commercial_store.snapshot("org-a")
  assert_eq(commercial_usage.usage_observations.length(), 1)
  assert_eq(commercial_usage.ledger_entries.length(), 0)
  let customer = service.handle(
    Get,
    "/v1/portal/self/machine-orders",
    customer_headers,
    "",
  )
  assert_eq(customer.status, 200)
  assert_false(customer.body.contains("physical-node-a"))
  assert_false(customer.body.contains("gpu-private-0"))
  let machine_access = service.handle(
    Get,
    "/v1/machine-access/self",
    customer_headers,
    "",
  )
  assert_eq(machine_access.status, 200)
  assert_true(
    machine_access.body.contains(active_order.target_lease_ref.unwrap()),
  )
  assert_false(machine_access.body.contains("physical-node-a"))
  let order_access = service.handle(
    Get,
    "/v1/portal/self/machine-orders/\{active_order.order_id}/access",
    customer_headers,
    "",
  )
  assert_eq(order_access.status, 200)
  assert_true(order_access.body.contains("/v1/machine-access/self"))
  assert_false(order_access.body.contains("physical-node-a"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "dedicated endpoint uses pinned managed deployment and never exclusive lease" {
  let directory = @fs.tmpdir(prefix="lunanexa-machine-dedicated-")
  let now = @async.now()
  let template = machine_dedicated_template()
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.fence_controller(1L)
  let heartbeat : @contracts.NodeHeartbeat = {
    node_id: "managed-node-a",
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: "managed-node-a",
      agent_version: "0.1.0",
      os_release: "test",
      runtime_names: ["text-runtime"],
      accelerators: [
        {
          device_id: "gpu-managed-0",
          architecture: "nvidia-gb10",
          memory_total_mib: 8192,
          memory_free_mib: 8192,
          healthy: true,
        },
      ],
      labels: {
        "lunanexa.data-classes": "Internal",
        "lunanexa.io/region": "cn-north-1",
      },
      taints: [],
    },
    running_deployments: [],
    timestamp_unix_ms: now,
    signature: "test",
  }
  durable.put_heartbeat(heartbeat)
  let registry = machine_dedicated_registry(
    "\{directory}/registry.json",
    template,
  )
  let deployments = @deployment_store.FileDeploymentStore::open(
    "\{directory}/deployments.json",
    "assignment-secret",
  )
  ignore(deployments.register_template(template))
  let leases = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive.json",
    "dedicated-exclusive-lease-secret-more-than-32-bytes",
  )
  let machine_store = @machinecommerce_store.MachineCommerceStore::open(
    "\{directory}/machine-commerce.json",
    "dedicated-machine-commerce-secret-more-than-32-bytes",
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  ignore(
    portal.put_membership({
      membership_id: "dedicated-member-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [Developer, LeaseRequester],
      active: true,
      created_unix_ms: now,
    }),
  )
  let access_store = @access.AccessStore::open(
    "\{directory}/access.json",
    "dedicated-api-key-issuer-secret-more-than-32-bytes",
  )
  ignore(
    machine_store.put_offering({
      offering_id: "dedicated-text",
      sku: "dedicated-text-gb10",
      display_name: "Dedicated text endpoint",
      kind: DedicatedEndpoint,
      region: "cn-north-1",
      accelerator_class: "nvidia-gb10",
      accelerator_count: 1L,
      memory_mib: 2048L,
      cpu_count: 1L,
      meter: "dedicated-endpoint-second",
      unit_price: { minor_units: 3L, currency: "CNY", scale: 2 },
      billing_quantum_seconds: 60L,
      minimum_duration_seconds: 60L,
      maximum_duration_seconds: 86400L,
      capacity_total: 2L,
      allowed_model_template_refs: ["text-small:v1"],
      state: OfferingActive,
      generation: 1L,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  for suffix in ["a", "b"] {
    let (quote, _) = machine_store.create_quote(
      {
        quote_id: "dedicated-quote-\{suffix}",
        idempotency_key: "dedicated-quote-\{suffix}",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        project_id: "project-a",
        purchaser_subject_ref: "subject-a",
        offering_id: "dedicated-text",
        quantity: 1L,
        duration_seconds: 3600L,
        unix_username: None,
        requested_model_selector: Some("text.default"),
        model_template_ref: Some("text-small:v1"),
        valid_for_ms: 60000L,
      },
      now,
    )
    let (order, _) = machine_store.create_order(
      {
        order_id: "dedicated-order-\{suffix}",
        idempotency_key: "dedicated-order-\{suffix}",
        quote_id: quote.quote_id,
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        project_id: "project-a",
        purchaser_subject_ref: "subject-a",
      },
      now,
    )
    ignore(
      machine_store.activate_settled_payment(
        order.order_id,
        {
          provider_event_id: "dedicated-payment-\{suffix}",
          payment_ref: "provider:dedicated-\{suffix}",
          settled_amount: quote.total,
        },
        now,
      ),
    )
  }
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    template.runtime.version,
    template.runtime.image_digest,
    template.artifact.digest,
    allow_http_loopback=true,
  )
  let service = ApiService::with_registry(
      durable, registry, runtime, "operator-token", "inference-token", "node-token",
      "0.1.0",
    )
    .with_assignment_signing_secret("assignment-secret")
    .with_deployment_store(deployments, available_secret_refs=["runtime-token"])
    .with_exclusive_lease_store(leases)
    .with_machine_commerce_store(machine_store)
    .with_portal_store(portal)
    .with_access_store(access_store)
  service.reconcile_machine_commerce()
  let first = machine_store.order("dedicated-order-a").unwrap()
  let second = machine_store.order("dedicated-order-b").unwrap()
  assert_eq(first.state, Provisioning)
  assert_eq(first.target_lease_ref, None)
  assert_eq(
    first.target_deployment_ref,
    Some("machine-order-deployment-dedicated-order-a"),
  )
  assert_eq(second.state, PaymentSettled)
  assert_eq(leases.leases().length(), 0)
  assert_eq(deployments.operations().length(), 1)
  assert_eq(durable.assignments().length(), 1)
  durable.put_heartbeat({
    ..heartbeat,
    observed_generation: 2L,
    running_deployments: [first.target_deployment_ref.unwrap()],
    timestamp_unix_ms: now + 1000L,
  })
  service.reconcile_machine_commerce()
  let active = machine_store.order(first.order_id).unwrap()
  assert_eq(active.state, Active)
  let customer_headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
    "X-LunaNexa-Organization": "org-a",
  }
  let access_view = service.handle(
    Get,
    "/v1/portal/self/machine-orders/\{active.order_id}/access",
    customer_headers,
    "",
  )
  assert_eq(access_view.status, 200)
  assert_true(access_view.body.contains("/v1/workloads"))
  assert_true(access_view.body.contains("text.default"))
  assert_false(access_view.body.contains("managed-node-a"))
  let issued = service.handle(
    Post,
    "/v1/portal/self/machine-orders/\{active.order_id}/access-key",
    customer_headers,
    "{\"key_id\":\"dedicated-key-a\",\"display_name\":\"Dedicated endpoint\",\"maximum_requests\":\"1000\"}",
  )
  assert_eq(issued.status, 201)
  assert_true(issued.body.contains("lnx_"))
  assert_true(issued.body.contains("/v1/workloads"))
  assert_false(issued.body.contains("managed-node-a"))
  assert_eq(
    machine_store.order_for_access_key("dedicated-key-a").unwrap().order_id,
    active.order_id,
  )
  let portal_key = service.handle(
    Post,
    "/v1/portal/self/api-keys",
    customer_headers,
    (
      {
        "key_id": "dedicated-key-via-account",
        "project_id": "project-a",
        "display_name": "Dedicated account key",
        "scopes": ["ModelList", "Inference"],
        "allowed_models": ["text.default"],
        "expires_unix_ms": (@async.now() + 60000L).to_json(),
        "maximum_requests": 1000L.to_json(),
      } : Json).stringify(),
  )
  assert_eq(portal_key.status, 201)
  assert_true(portal_key.body.contains("lnx_"))
  assert_eq(
    machine_store.order_for_access_key("dedicated-key-via-account").unwrap().order_id,
    active.order_id,
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "paid order without eligible capacity times out into compensation" {
  let directory = @fs.tmpdir(prefix="lunanexa-machine-timeout-")
  let current = @async.now()
  let payment_time = current - 901000L
  let machine_store = @machinecommerce_store.MachineCommerceStore::open(
    "\{directory}/machine-commerce.json",
    "machine-timeout-store-secret-more-than-32-bytes",
  )
  ignore(
    machine_store.put_offering({
      offering_id: "timeout-bare",
      sku: "timeout-bare",
      display_name: "Timeout bare machine",
      kind: BareMachine,
      region: "cn-north-1",
      accelerator_class: "nvidia-rtx-5060-ti",
      accelerator_count: 1L,
      memory_mib: 16384L,
      cpu_count: 16L,
      meter: "exclusive-node-second",
      unit_price: { minor_units: 1L, currency: "CNY", scale: 2 },
      billing_quantum_seconds: 60L,
      minimum_duration_seconds: 60L,
      maximum_duration_seconds: 3600L,
      capacity_total: 1L,
      allowed_model_template_refs: [],
      state: OfferingActive,
      generation: 1L,
      created_unix_ms: payment_time - 10L,
      updated_unix_ms: payment_time - 10L,
    }),
  )
  let (quote, _) = machine_store.create_quote(
    {
      quote_id: "timeout-quote",
      idempotency_key: "timeout-quote",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
      offering_id: "timeout-bare",
      quantity: 1L,
      duration_seconds: 3600L,
      unix_username: Some("developer"),
      requested_model_selector: None,
      model_template_ref: None,
      valid_for_ms: 60000L,
    },
    payment_time - 2L,
  )
  let (order, _) = machine_store.create_order(
    {
      order_id: "timeout-order",
      idempotency_key: "timeout-order",
      quote_id: quote.quote_id,
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
    },
    payment_time - 1L,
  )
  ignore(
    machine_store.activate_settled_payment(
      order.order_id,
      {
        provider_event_id: "timeout-payment",
        payment_ref: "provider:timeout-payment",
        settled_amount: quote.total,
      },
      payment_time,
    ),
  )
  let durable = @store.FileStore::open("\{directory}/state.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_machine_commerce_store(machine_store)
  service.reconcile_machine_commerce()
  let timed_out = machine_store.order(order.order_id).unwrap()
  assert_eq(timed_out.state, CompensationPending)
  assert_eq(timed_out.failure_code, Some("ProvisioningCapacityUnavailable"))
  @fs.rmdir(directory, recursive=true)
}
