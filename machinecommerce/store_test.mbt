///|
fn test_offering(
  id : String,
  kind : @machinecommerce.MachineOfferingKind,
  capacity : Int64,
  now : Int64,
) -> @machinecommerce.MachineOffering {
  {
    offering_id: id,
    sku: "sku-\{id}",
    display_name: "Test \{id}",
    kind,
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
    capacity_total: capacity,
    allowed_model_template_refs: if kind == DedicatedEndpoint {
      ["qwen-template"]
    } else {
      []
    },
    state: OfferingActive,
    generation: 1L,
    created_unix_ms: now,
    updated_unix_ms: now,
  }
}

///|
fn quote_intent(
  suffix : String,
  offering_id : String,
  dedicated : Bool,
) -> @machinecommerce.MachineQuoteIntent {
  {
    quote_id: "quote-\{suffix}",
    idempotency_key: "quote-idem-\{suffix}",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    purchaser_subject_ref: "subject-a",
    offering_id,
    quantity: 1L,
    duration_seconds: 3600L,
    unix_username: if dedicated {
      None
    } else {
      Some("developer")
    },
    requested_model_selector: if dedicated {
      Some("text.qwen")
    } else {
      None
    },
    model_template_ref: if dedicated {
      Some("qwen-template")
    } else {
      None
    },
    valid_for_ms: 60000L,
  }
}

///|
fn order_intent(
  suffix : String,
  quote_id : String,
) -> @machinecommerce.MachineOrderIntent {
  {
    order_id: "order-\{suffix}",
    idempotency_key: "order-idem-\{suffix}",
    quote_id,
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    purchaser_subject_ref: "subject-a",
  }
}

///|
test "active purchasable offerings cannot be zero-priced" {
  let now = 1000000L
  let zero = {
    ..test_offering("zero", BareMachine, 1L, now),
    unit_price: { minor_units: 0L, currency: "CNY", scale: 2 },
  }
  try @machinecommerce.validate_offering(zero) catch {
    InvalidInput(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("zero-priced active offering must be rejected")
  }
}

///|
test "v1 machine quote rejects ambiguous multi-resource quantity" {
  let now = 1000000L
  let store = @machinecommerce.MachineCommerceStore::new(
    "machine-commerce-test-signing-secret-quantity",
  )
  ignore(store.put_offering(test_offering("quantity", BareMachine, 2L, now)))
  try
    store.create_quote(
      { ..quote_intent("quantity", "quantity", false), quantity: 2L },
      now + 1L,
    )
  catch {
    InvalidInput(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("v1 must not promise multiple resources through one target ref")
  }
}

///|
test "bare machine purchase is payment-gated and meters the terminal interval" {
  let now = 1000000L
  let store = @machinecommerce.MachineCommerceStore::new(
    "machine-commerce-test-signing-secret-0001",
  )
  ignore(store.put_offering(test_offering("bare", BareMachine, 1L, now)))
  let (quote, _) = store.create_quote(
    quote_intent("bare", "bare", false),
    now + 1L,
  )
  assert_eq(quote.total.minor_units, 7200L)
  let (order, _) = store.create_order(
    order_intent("bare", quote.quote_id),
    now + 2L,
  )
  assert_eq(order.state, AwaitingPayment)
  assert_eq(store.availability("bare", now + 2L).capacity_reserved, 0L)
  try
    store.start_provisioning(
      order.order_id,
      {
        idempotency_key: "provision-before-payment",
        expected_generation: order.generation,
        target_lease_ref: Some("lease-a"),
        target_deployment_ref: None,
      },
      now + 3L,
    )
  catch {
    InvalidTransition(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("unpaid order must not provision")
  }
  try
    store.activate_settled_payment(
      order.order_id,
      {
        provider_event_id: "payment-wrong",
        payment_ref: "pay-wrong",
        settled_amount: { minor_units: 7199L, currency: "CNY", scale: 2 },
      },
      now + 4L,
    )
  catch {
    PriceMismatch => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("underpayment must be rejected")
  }
  let settlement : @machinecommerce.MachinePaymentSettlement = {
    provider_event_id: "payment-bare",
    payment_ref: "pay-bare",
    settled_amount: quote.total,
  }
  let (paid, paid_result) = store.activate_settled_payment(
    order.order_id,
    settlement,
    now + 5L,
  )
  assert_eq(paid.state, PaymentSettled)
  assert_eq(paid_result, Created)
  assert_eq(store.availability("bare", now + 5L).capacity_reserved, 1L)
  let (_, replayed) = store.activate_settled_payment(
    order.order_id,
    settlement,
    now + 6L,
  )
  assert_eq(replayed, Replayed)
  let (provisioning, _) = store.start_provisioning(
    order.order_id,
    {
      idempotency_key: "provision-bare",
      expected_generation: paid.generation,
      target_lease_ref: Some("lease-bare"),
      target_deployment_ref: None,
    },
    now + 7L,
  )
  let (active, _) = store.complete_provisioning(
    order.order_id,
    "activate-bare",
    provisioning.generation,
    now + 1000L,
  )
  let (metered, first_receipt, _) = store.record_usage(
    order.order_id,
    {
      idempotency_key: "meter-bare-1",
      expected_generation: active.generation,
      ended_unix_ms: now + 6000L,
    },
    now + 6000L,
  )
  assert_eq(first_receipt.quantity, 5L)
  assert_eq(first_receipt.resource_ref, "lease-bare")
  let (terminating, _) = store.request_termination(
    "subject-a",
    order.order_id,
    {
      idempotency_key: "terminate-bare",
      expected_generation: metered.generation,
      reason: "work completed",
    },
    now + 7000L,
  )
  let (terminated, final_receipt, _) = store.complete_termination_with_usage(
    order.order_id,
    "complete-termination-bare",
    terminating.generation,
    "cleanup-and-refund-receipt",
    now + 9000L,
    now + 9000L,
  )
  assert_eq(terminated.state, Terminated)
  assert_eq(final_receipt.quantity, 3L)
  assert_eq(store.availability("bare", now + 9000L).capacity_reserved, 0L)
  let observation = final_receipt.commercial_observation()
  assert_eq(observation.event_id, final_receipt.event_id)
  assert_eq(observation.meter, "exclusive-node-second")
}

///|
test "dedicated endpoint binds a managed deployment and never an exclusive lease" {
  let now = 2000000L
  let store = @machinecommerce.MachineCommerceStore::new(
    "machine-commerce-test-signing-secret-0002",
  )
  ignore(
    store.put_offering(test_offering("dedicated", DedicatedEndpoint, 1L, now)),
  )
  let (quote, _) = store.create_quote(
    quote_intent("dedicated", "dedicated", true),
    now + 1L,
  )
  let (order, _) = store.create_order(
    order_intent("dedicated", quote.quote_id),
    now + 2L,
  )
  let (paid, _) = store.activate_settled_payment(
    order.order_id,
    {
      provider_event_id: "payment-dedicated",
      payment_ref: "pay-dedicated",
      settled_amount: quote.total,
    },
    now + 3L,
  )
  try
    store.start_provisioning(
      order.order_id,
      {
        idempotency_key: "bad-exclusive-dedicated",
        expected_generation: paid.generation,
        target_lease_ref: Some("exclusive-lease-forbidden"),
        target_deployment_ref: Some("deployment-a"),
      },
      now + 4L,
    )
  catch {
    InvalidInput(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("dedicated endpoint must not create an exclusive lease")
  }
  let (provisioning, _) = store.start_provisioning(
    order.order_id,
    {
      idempotency_key: "managed-dedicated",
      expected_generation: paid.generation,
      target_lease_ref: None,
      target_deployment_ref: Some("deployment-a"),
    },
    now + 5L,
  )
  assert_eq(provisioning.target_lease_ref, None)
  assert_eq(provisioning.target_deployment_ref, Some("deployment-a"))
}

///|
test "paid oversell enters durable compensation instead of provisioning" {
  let now = 3000000L
  let store = @machinecommerce.MachineCommerceStore::new(
    "machine-commerce-test-signing-secret-0003",
  )
  ignore(store.put_offering(test_offering("scarce", BareMachine, 1L, now)))
  let (quote_a, _) = store.create_quote(
    quote_intent("scarce-a", "scarce", false),
    now + 1L,
  )
  let (quote_b, _) = store.create_quote(
    quote_intent("scarce-b", "scarce", false),
    now + 1L,
  )
  let (order_a, _) = store.create_order(
    order_intent("scarce-a", quote_a.quote_id),
    now + 2L,
  )
  let (order_b, _) = store.create_order(
    order_intent("scarce-b", quote_b.quote_id),
    now + 2L,
  )
  ignore(
    store.activate_settled_payment(
      order_a.order_id,
      {
        provider_event_id: "payment-scarce-a",
        payment_ref: "pay-scarce-a",
        settled_amount: quote_a.total,
      },
      now + 3L,
    ),
  )
  let (compensation, _) = store.activate_settled_payment(
    order_b.order_id,
    {
      provider_event_id: "payment-scarce-b",
      payment_ref: "pay-scarce-b",
      settled_amount: quote_b.total,
    },
    now + 4L,
  )
  assert_eq(compensation.state, CompensationPending)
  assert_false(compensation.capacity_reserved)
  let (failed, _) = store.complete_compensation(
    order_b.order_id,
    "refund-scarce-b",
    compensation.generation,
    "refund-provider-receipt",
    now + 5L,
  )
  assert_eq(failed.state, Failed)
}

///|
test "snapshot rejects quote tampering and preserves payment replay" {
  let now = 4000000L
  let secret = "machine-commerce-test-signing-secret-0004"
  let store = @machinecommerce.MachineCommerceStore::new(secret)
  ignore(store.put_offering(test_offering("restore", BareMachine, 1L, now)))
  let (quote, _) = store.create_quote(
    quote_intent("restore", "restore", false),
    now + 1L,
  )
  let (order, _) = store.create_order(
    order_intent("restore", quote.quote_id),
    now + 2L,
  )
  let settlement : @machinecommerce.MachinePaymentSettlement = {
    provider_event_id: "payment-restore",
    payment_ref: "pay-restore",
    settled_amount: quote.total,
  }
  ignore(store.activate_settled_payment(order.order_id, settlement, now + 3L))
  let restored = @machinecommerce.MachineCommerceStore::from_snapshot(
    secret,
    store.snapshot(),
  )
  let (_, replayed) = restored.activate_settled_payment(
    order.order_id,
    settlement,
    now + 4L,
  )
  assert_eq(replayed, Replayed)
  let snapshot = store.snapshot()
  let tampered_quote = {
    ..snapshot.quotes[0],
    total: { ..snapshot.quotes[0].total, minor_units: 1L },
  }
  let tampered = { ..snapshot, quotes: [tampered_quote] }
  try
    @machinecommerce.MachineCommerceStore::from_snapshot(secret, tampered)
  catch {
    InvalidInput(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("tampered quote must not restore")
  }
}

///|
test "active dedicated order durably binds access key without exposing secret" {
  let now = 5000000L
  let secret = "machine-commerce-test-signing-secret-0005"
  let store = @machinecommerce.MachineCommerceStore::new(secret)
  ignore(
    store.put_offering(
      test_offering("dedicated-access", DedicatedEndpoint, 1L, now),
    ),
  )
  let (quote, _) = store.create_quote(
    quote_intent("dedicated-access", "dedicated-access", true),
    now + 1L,
  )
  let (order, _) = store.create_order(
    order_intent("dedicated-access", quote.quote_id),
    now + 2L,
  )
  let (paid, _) = store.activate_settled_payment(
    order.order_id,
    {
      provider_event_id: "payment-dedicated-access",
      payment_ref: "pay-dedicated-access",
      settled_amount: quote.total,
    },
    now + 3L,
  )
  let (provisioning, _) = store.start_provisioning(
    order.order_id,
    {
      idempotency_key: "provision-dedicated-access",
      expected_generation: paid.generation,
      target_lease_ref: None,
      target_deployment_ref: Some("deployment-dedicated-access"),
    },
    now + 4L,
  )
  let (active, _) = store.complete_provisioning(
    order.order_id,
    "active-dedicated-access",
    provisioning.generation,
    now + 5L,
  )
  let receipt = store.bind_access_key(
    active.order_id,
    active.purchaser_subject_ref,
    "key-dedicated-access",
    now + 6L,
  )
  assert_eq(receipt.action, "access-key")
  assert_eq(
    store.order_for_access_key("key-dedicated-access").unwrap().order_id,
    active.order_id,
  )
  let restored = @machinecommerce.MachineCommerceStore::from_snapshot(
    secret,
    store.snapshot(),
  )
  assert_eq(
    restored.order_for_access_key("key-dedicated-access").unwrap().order_id,
    active.order_id,
  )
  assert_false(restored.snapshot().to_json().stringify().contains("lnx_"))
}
