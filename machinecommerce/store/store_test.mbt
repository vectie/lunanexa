///|
fn persisted_test_offering(now : Int64) -> @machinecommerce.MachineOffering {
  {
    offering_id: "bare-persisted",
    sku: "rtx-5060ti-hourly",
    display_name: "RTX 5060 Ti bare machine",
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
    maximum_duration_seconds: 86400L,
    capacity_total: 1L,
    allowed_model_template_refs: [],
    state: OfferingActive,
    generation: 1L,
    created_unix_ms: now,
    updated_unix_ms: now,
  }
}

///|
async test "file store preserves payment reservation and action idempotency" {
  let directory = @fs.tmpdir(prefix="lunanexa-machine-commerce-")
  let path = "\{directory}/state.json"
  let secret = "durable-machine-commerce-signing-secret-0001"
  let now = 5000000L
  let store = MachineCommerceStore::open(path, secret)
  ignore(store.put_offering(persisted_test_offering(now)))
  let (quote, _) = store.create_quote(
    {
      quote_id: "quote-persisted",
      idempotency_key: "quote-idem-persisted",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
      offering_id: "bare-persisted",
      quantity: 1L,
      duration_seconds: 3600L,
      unix_username: Some("developer"),
      requested_model_selector: None,
      model_template_ref: None,
      valid_for_ms: 60000L,
    },
    now + 1L,
  )
  let (order, _) = store.create_order(
    {
      order_id: "order-persisted",
      idempotency_key: "order-idem-persisted",
      quote_id: quote.quote_id,
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
    },
    now + 2L,
  )
  let settlement : @machinecommerce.MachinePaymentSettlement = {
    provider_event_id: "payment-persisted",
    payment_ref: "pay-persisted",
    settled_amount: quote.total,
  }
  let (paid, _) = store.activate_settled_payment(
    order.order_id,
    settlement,
    now + 3L,
  )
  let provisioning_intent : @machinecommerce.MachineProvisioningIntent = {
    idempotency_key: "provision-persisted",
    expected_generation: paid.generation,
    target_lease_ref: Some("exclusive-persisted"),
    target_deployment_ref: None,
  }
  let (provisioning, _) = store.start_provisioning(
    order.order_id,
    provisioning_intent,
    now + 4L,
  )
  assert_eq(provisioning.state, Provisioning)

  let reopened = MachineCommerceStore::open(path, secret)
  let loaded = reopened.order(order.order_id).unwrap()
  assert_eq(loaded.state, Provisioning)
  assert_eq(
    reopened.availability("bare-persisted", now + 5L).capacity_reserved,
    1L,
  )
  let (_, payment_replay) = reopened.activate_settled_payment(
    order.order_id,
    settlement,
    now + 5L,
  )
  assert_eq(payment_replay, Replayed)
  let (_, action_replay) = reopened.start_provisioning(
    order.order_id,
    provisioning_intent,
    now + 5L,
  )
  assert_eq(action_replay, Replayed)
}
