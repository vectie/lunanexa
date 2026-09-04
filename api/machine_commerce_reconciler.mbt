///| Parses the catalog's stable `template_id:version` reference without ever

///|
/// accepting a physical placement from the customer.
fn machine_template_ref(value : String) -> @deployment.TemplateRef? {
  let parts : Array[String] = []
  for part in value.split(":") {
    parts.push(part.to_owned())
  }
  if parts.length() == 2 &&
    @contracts.valid_identifier(parts[0]) &&
    @contracts.valid_identifier(parts[1]) {
    Some({ template_id: parts[0], version: parts[1] })
  } else {
    None
  }
}

///| Physical nodes already pinned by an in-flight paid dedicated endpoint.

///|
/// This controller-private placement state is never returned to customers.
async fn ApiService::machine_reserved_managed_nodes(
  self : ApiService,
) -> Array[String] {
  guard self.deployment_store is Some(deployments) else { return [] }
  let reserved : Array[String] = []
  for operation in deployments.operations() {
    if operation.deployment_id.has_prefix("machine-order-deployment-") &&
      (
        operation.state == Planned ||
        operation.state == Reconciling ||
        operation.state == Ready ||
        operation.state == Degraded ||
        operation.state == RollingBack
      ) {
      for replica in operation.plan.replicas {
        if !reserved.contains(replica.node_id) {
          reserved.push(replica.node_id)
        }
      }
    }
  }
  reserved
}

///|
/// Trusted node inventory label used to honor the purchased regional SKU.
let machine_region_label : String = "lunanexa.io/region"

///| Returns controller-enrolled nodes that satisfy the purchased SKU itself.

///| Missing region labels fail closed; there is no implicit cross-region

///|
/// fallback for paid capacity.
async fn ApiService::machine_offering_nodes(
  self : ApiService,
  offering : @machinecommerce.MachineOffering,
  now_unix_ms : Int64,
) -> Array[String] {
  let candidates : Array[String] = []
  for heartbeat in self.store.heartbeats() {
    let healthy_accelerators = heartbeat.inventory.accelerators.filter(accelerator => {
      accelerator.healthy &&
      accelerator.architecture == offering.accelerator_class
    })
    let lease_blocked = match self.exclusive_lease_store {
      Some(leases) => leases.node_blocks_managed_placement(heartbeat.node_id)
      None => true
    }
    if heartbeat.state == Active &&
      heartbeat.timestamp_unix_ms +
      self.global_settings.control_timing.heartbeat_timeout_ms >=
      now_unix_ms &&
      heartbeat.inventory.labels.get(machine_region_label) ==
      Some(offering.region) &&
      healthy_accelerators.length().to_int64() >= offering.accelerator_count &&
      !lease_blocked {
      candidates.push(heartbeat.node_id)
    }
  }
  candidates.sort()
  candidates
}

///| Selects a healthy managed node internally for a bare-machine purchase.

///|
/// The chosen node is written only to the private lease authority.
async fn ApiService::machine_bare_node(
  self : ApiService,
  offering : @machinecommerce.MachineOffering,
  now_unix_ms : Int64,
) -> String? {
  let candidates = self.machine_offering_nodes(offering, now_unix_ms)
  let reserved_managed_nodes = self.machine_reserved_managed_nodes()
  candidates
  .iter()
  .find_first(node_id => !reserved_managed_nodes.contains(node_id))
}

///| Starts provisioning only after the payment callback has durably reserved

///| commercial capacity. Dedicated endpoints remain managed deployments and

///|
/// therefore never create an ExclusiveNodeLease.
async fn ApiService::start_paid_machine_order(
  self : ApiService,
  machine_store : @machinecommerce_store.MachineCommerceStore,
  order : @machinecommerce.MachineOrder,
  offering : @machinecommerce.MachineOffering,
  now_unix_ms : Int64,
) -> Unit {
  match order.offering_kind {
    BareMachine => {
      guard self.exclusive_lease_store is Some(leases) &&
        self.machine_bare_node(offering, now_unix_ms) is Some(node_id) &&
        order.unix_username is Some(unix_username) else {
        return
      }
      let lease_id = "machine-order-lease-\{order.order_id}"
      let lease = try
        leases.issue(
          {
            version: @nodelease.contract_version,
            idempotency_key: "machine-order-provision-\{order.order_id}",
            lease_id,
            node_id,
            subject_ref: order.purchaser_subject_ref,
            unix_username,
            access_credential_ref: "ssh-cert:\{lease_id}",
            starts_unix_ms: now_unix_ms,
            expires_unix_ms: now_unix_ms + order.duration_seconds * 1000L,
          },
          now_unix_ms,
        )
      catch {
        _ => return
      } noraise {
        value => value
      }
      ignore(
        machine_store.start_provisioning(
          order.order_id,
          {
            idempotency_key: "machine-order-provision-\{order.order_id}",
            expected_generation: order.generation,
            target_lease_ref: Some(lease_id),
            target_deployment_ref: None,
          },
          now_unix_ms,
        ),
      ) catch {
        _ => return
      }
      self.publish_exclusive_lease_directive(lease, Cordoned)
      self.operator_audit(
        "machine-order.bare-machine.reserve",
        order.order_id,
        lease.authority_receipt,
      )
    }
    DedicatedEndpoint => {
      guard self.deployment_store is Some(deployments) &&
        order.model_template_ref is Some(template_text) &&
        machine_template_ref(template_text) is Some(template_ref) &&
        order.requested_model_selector is Some(model_selector) else {
        return
      }
      let deployment_id = "machine-order-deployment-\{order.order_id}"
      let intent : @deployment.ModelServiceIntent = {
        version: @contracts.contract_version,
        idempotency_key: "machine-order-provision-\{order.order_id}",
        deployment_id,
        template: template_ref,
        replicas: order.quantity.to_int(),
        data_class: Internal,
        lease_duration_ms: order.duration_seconds * 1000L,
        promote_when_ready: false,
      }
      let context = try self.deployment_planning_context() catch {
        _ => return
      } noraise {
        value => value
      }
      // Forward-repair a crash after deployment persistence but before the
      // machine order link was committed.
      match deployments.deployment(deployment_id) {
        Some(operation) => {
          ignore(
            machine_store.start_provisioning(
              order.order_id,
              {
                idempotency_key: "machine-order-provision-\{order.order_id}",
                expected_generation: order.generation,
                target_lease_ref: None,
                target_deployment_ref: Some(deployment_id),
              },
              now_unix_ms,
            ),
          ) catch {
            _ => return
          }
          ignore(self.reconcile_deployment_operation(operation))
          return
        }
        None => ()
      }
      let reserved_nodes = self.machine_reserved_managed_nodes()
      let offering_nodes = self.machine_offering_nodes(offering, now_unix_ms)
      let available_context = {
        ..context,
        nodes: context.nodes.filter(node => {
          offering_nodes.contains(node.node_id) &&
          !reserved_nodes.contains(node.node_id)
        }),
      }
      let general = @deployment.preflight(
        deployments.templates(),
        intent,
        available_context,
      )
      guard general.executable && general.replicas.get(0) is Some(first_replica) else {
        return
      }
      // Pin the final plan to the controller-selected managed node. This
      // retains every ordinary registry/resource/data-policy gate and closes
      // the gap where a customer-provided placement could escape them.
      let pinned = @deployment.preflight_on_node(
        deployments.templates(),
        intent,
        available_context,
        first_replica.node_id,
      )
      guard pinned.executable &&
        pinned.template.map_or(false, template => {
          template.model_selector == model_selector
        }) else {
        return
      }
      let operation = try
        deployments.create_operation(pinned, now_unix_ms)
      catch {
        _ => return
      } noraise {
        value => value
      }
      ignore(
        machine_store.start_provisioning(
          order.order_id,
          {
            idempotency_key: "machine-order-provision-\{order.order_id}",
            expected_generation: order.generation,
            target_lease_ref: None,
            target_deployment_ref: Some(deployment_id),
          },
          now_unix_ms,
        ),
      ) catch {
        _ => return
      }
      ignore(self.reconcile_deployment_operation(operation))
      self.operator_audit(
        "machine-order.dedicated-endpoint.reserve",
        order.order_id,
        operation.audit_receipt,
      )
    }
  }
}

///|
async fn ApiService::reconcile_provisioning_machine_order(
  self : ApiService,
  machine_store : @machinecommerce_store.MachineCommerceStore,
  order : @machinecommerce.MachineOrder,
  now_unix_ms : Int64,
) -> Unit {
  match order.offering_kind {
    BareMachine => {
      guard self.exclusive_lease_store is Some(leases) &&
        order.target_lease_ref is Some(lease_id) &&
        leases.lease(lease_id) is Some(initial) else {
        return
      }
      let lease = if initial.state == Reserved {
        self.begin_exclusive_provisioning_if_drained(initial)
      } else {
        initial
      }
      if lease.state == Active {
        ignore(
          machine_store.complete_provisioning(
            order.order_id,
            "machine-order-active-\{order.order_id}",
            order.generation,
            now_unix_ms,
          ),
        ) catch {
          _ => ()
        }
      } else if lease.state == Completed ||
        lease.state == Cancelled ||
        lease.state == Quarantined {
        ignore(
          machine_store.record_failure(
            order.order_id,
            "machine-order-lease-failed-\{order.order_id}",
            order.generation,
            "ExclusiveLeaseProvisioningFailed",
            now_unix_ms,
          ),
        ) catch {
          _ => ()
        }
      }
    }
    DedicatedEndpoint => {
      guard self.deployment_store is Some(deployments) &&
        order.target_deployment_ref is Some(deployment_id) &&
        deployments.deployment(deployment_id) is Some(initial) else {
        return
      }
      let operation = if initial.state == Planned ||
        initial.state == Reconciling {
        self.reconcile_deployment_operation(initial)
      } else {
        initial
      }
      if operation.state == Ready {
        ignore(
          machine_store.complete_provisioning(
            order.order_id,
            "machine-order-active-\{order.order_id}",
            order.generation,
            now_unix_ms,
          ),
        ) catch {
          _ => ()
        }
      } else if operation.state == Failed ||
        operation.state == RolledBack ||
        operation.state == Deleted {
        ignore(
          machine_store.record_failure(
            order.order_id,
            "machine-order-deployment-failed-\{order.order_id}",
            order.generation,
            "DedicatedEndpointProvisioningFailed",
            now_unix_ms,
          ),
        ) catch {
          _ => ()
        }
      }
    }
  }
}

///| Emits durable, restart-safe wall-clock usage in bounded intervals. The

///|
/// receipt is later ingested as an accrual; it is not another payment.
async fn ApiService::meter_active_machine_order(
  self : ApiService,
  machine_store : @machinecommerce_store.MachineCommerceStore,
  order : @machinecommerce.MachineOrder,
  now_unix_ms : Int64,
) -> Unit {
  ignore(self)
  guard order.active_started_unix_ms is Some(active_started) &&
    order.last_metered_unix_ms is Some(last_metered) else {
    return
  }
  let contracted_end = active_started + order.duration_seconds * 1000L
  let interval_end = now_unix_ms.min(contracted_end)
  if interval_end > last_metered &&
    (interval_end - last_metered >= 60000L || interval_end == contracted_end) {
    ignore(
      machine_store.record_usage(
        order.order_id,
        {
          idempotency_key: "machine-meter-\{order.order_id}-\{order.generation}",
          expected_generation: order.generation,
          ended_unix_ms: interval_end,
        },
        now_unix_ms,
      ),
    ) catch {
      _ => return
    }
  }
  if now_unix_ms >= contracted_end &&
    machine_store.order(order.order_id) is Some(current) &&
    current.state == Active {
    ignore(
      machine_store.request_termination(
        current.purchaser_subject_ref,
        current.order_id,
        {
          idempotency_key: "machine-expiry-\{current.order_id}",
          expected_generation: current.generation,
          reason: "ContractDurationElapsed",
        },
        now_unix_ms,
      ),
    ) catch {
      _ => ()
    }
  }
}

///|
/// Returns authenticated provider refund evidence for this exact order.
fn ApiService::machine_order_refund_ref(
  self : ApiService,
  order : @machinecommerce.MachineOrder,
) -> String? {
  let link = machine_payment_transaction_ref(order.order_id)
  self.commercial_integrations.durable_snapshot().records
  .iter()
  .find_first(record => {
    record.organization_id == order.organization_id &&
    record.kind == PaymentRefund &&
    record.state == Refunded &&
    record.entitlement_transaction_ref == Some(link)
  })
  .map(record => "refund:\{record.record_id}")
}

///| Queues one explicit provider refund operation after cleanup. This is a

///|
/// reversal request, never a negative or second Payment charge.
async fn ApiService::queue_machine_order_refund(
  self : ApiService,
  order : @machinecommerce.MachineOrder,
  now_unix_ms : Int64,
) -> Bool {
  if !self.commercial_provider_adapter_ready() {
    return false
  }
  let entitlement_ref = machine_payment_transaction_ref(order.order_id)
  let digest = provider_request_digest(
    order.organization_id,
    "machine-order-refund:\{order.order_id}",
  )
  let record_id = "refund-\{digest}"
  let created_unix_ms = self.commercial_integrations
    .record_by_id(record_id)
    .map(record => record.created_unix_ms)
    .unwrap_or(now_unix_ms)
  try {
    ignore(
      self.queue_provider_record({
        record_id,
        organization_id: order.organization_id,
        kind: PaymentRefund,
        provider: self.commercial_provider_name.unwrap_or(""),
        environment: self.commercial_provider_environment.unwrap_or(""),
        external_ref: "refund-\{digest}",
        state: Pending,
        expected_amount_minor: Some(order.quoted_total.minor_units),
        currency: Some(order.quoted_total.currency),
        money_scale: Some(order.quoted_total.scale),
        expected_document_hash: None,
        entitlement_transaction_ref: Some(entitlement_ref),
        created_unix_ms,
        updated_unix_ms: created_unix_ms,
      }),
    )
    true
  } catch {
    _ => false
  }
}

///| Starts or observes infrastructure cleanup. It returns true only after the

///|
/// underlying exclusive lease or managed deployment is terminal.
async fn ApiService::cleanup_machine_order_resource(
  self : ApiService,
  order : @machinecommerce.MachineOrder,
  now_unix_ms : Int64,
) -> Bool {
  match order.offering_kind {
    BareMachine => {
      guard order.target_lease_ref is Some(lease_id) else { return true }
      guard self.exclusive_lease_store is Some(leases) &&
        leases.lease(lease_id) is Some(lease) else {
        return false
      }
      match lease.state {
        Completed | Cancelled => true
        Requested | Reserved | Provisioning | Active | Quarantined => {
          let target = match lease.state {
            Requested => @nodelease.ExclusiveLeaseState::Cancelled
            Quarantined => RevokingAccess
            _ => Expiring
          }
          let transitioned = try
            leases.transition(
              lease_id,
              {
                expected_generation: lease.generation,
                state: target,
                evidence_receipt: "controller:machine-order-cleanup",
              },
              now_unix_ms,
            )
          catch {
            _ => return false
          } noraise {
            value => value
          }
          self.publish_exclusive_lease_directive(
            transitioned,
            directive_state_for_exclusive_lease(transitioned.state),
          )
          transitioned.state == Completed || transitioned.state == Cancelled
        }
        Expiring | Draining | RevokingAccess | Sanitizing => false
      }
    }
    DedicatedEndpoint => {
      guard order.target_deployment_ref is Some(deployment_id) else {
        return true
      }
      guard self.deployment_store is Some(deployments) &&
        deployments.deployment(deployment_id) is Some(operation) else {
        return false
      }
      if operation.state == RolledBack || operation.state == Deleted {
        return true
      }
      ignore(self.stop_service_deployment(deployment_id, false))
      deployments
      .deployment(deployment_id)
      .map_or(false, value => {
        value.state == RolledBack || value.state == Deleted
      })
    }
  }
}

///| Cancellation and failed paid provisioning require both infrastructure

///|
/// cleanup and an authenticated provider refund before inventory is released.
async fn ApiService::reconcile_machine_compensation(
  self : ApiService,
  machine_store : @machinecommerce_store.MachineCommerceStore,
  order : @machinecommerce.MachineOrder,
  now_unix_ms : Int64,
) -> Unit {
  let cleaned = self.cleanup_machine_order_resource(order, now_unix_ms)
  if !cleaned {
    return
  }
  ignore(self.queue_machine_order_refund(order, now_unix_ms))
  guard self.machine_order_refund_ref(order) is Some(refund_ref) else { return }
  ignore(
    machine_store.complete_compensation(
      order.order_id,
      "machine-compensation-\{order.order_id}-\{order.generation}",
      order.generation,
      refund_ref,
      now_unix_ms,
    ),
  ) catch {
    _ => ()
  }
}

///| A normal termination is billable through the final verified cleanup time;

///|
/// it does not require a refund unless a separate compensation state is set.
async fn ApiService::reconcile_machine_termination(
  self : ApiService,
  machine_store : @machinecommerce_store.MachineCommerceStore,
  order : @machinecommerce.MachineOrder,
  now_unix_ms : Int64,
) -> Unit {
  guard self.cleanup_machine_order_resource(order, now_unix_ms) &&
    order.last_metered_unix_ms is Some(last_metered) &&
    now_unix_ms > last_metered else {
    return
  }
  let resource_ref = match order.offering_kind {
    BareMachine => "lease-clean:\{order.target_lease_ref.unwrap()}"
    DedicatedEndpoint =>
      "deployment-clean:\{order.target_deployment_ref.unwrap()}"
  }
  ignore(
    machine_store.complete_termination_with_usage(
      order.order_id,
      "machine-termination-complete-\{order.order_id}-\{order.generation}",
      order.generation,
      resource_ref,
      now_unix_ms,
      now_unix_ms,
    ),
  ) catch {
    _ => ()
  }
}

///| Publishes prepaid machine usage evidence without rating it into a second

///| receivable. The signed quote/payment record is the settlement authority;

///|
/// rating these same seconds again would create a duplicate checkout balance.
async fn ApiService::ingest_machine_usage(
  self : ApiService,
  snapshot : @machinecommerce.MachineCommerceSnapshot,
) -> Unit {
  self.commercial_mutex.acquire()
  defer self.commercial_mutex.release()
  let before = self.commercial_store.durable_snapshot()
  let accepted = try {
    for receipt in snapshot.usage_receipts {
      ignore(
        self.commercial_store.ingest_usage(receipt.commercial_observation()),
      )
    }
    self.persist_commercial_state()
    true
  } catch {
    _ => false
  } noraise {
    value => value
  }
  if !accepted {
    ignore(self.commercial_store.replace_from_durable_snapshot(before)) catch {
      _ => ()
    }
  }
}

///| Reconciles payment-settled machine orders into infrastructure, advances

///| readiness, meters active time, and publishes receipts to the commercial

///|
/// ledger. Every mutation has a deterministic idempotency key.
pub async fn ApiService::reconcile_machine_commerce(self : ApiService) -> Unit {
  guard self.machine_commerce_store is Some(machine_store) else { return }
  let now = @async.now()
  let snapshot = machine_store.snapshot()
  for order in snapshot.orders {
    let offering = snapshot.offerings
      .iter()
      .find_first(value => value.offering_id == order.offering_id)
    match (order.state, offering) {
      (PaymentSettled, Some(value)) => {
        self.start_paid_machine_order(machine_store, order, value, now)
        if machine_store.order(order.order_id) is Some(current) &&
          current.state == PaymentSettled &&
          now > current.updated_unix_ms + 900000L {
          ignore(
            machine_store.record_failure(
              current.order_id,
              "machine-provision-timeout-\{current.order_id}",
              current.generation,
              "ProvisioningCapacityUnavailable",
              now,
            ),
          ) catch {
            _ => ()
          }
        }
      }
      (Provisioning, _) =>
        self.reconcile_provisioning_machine_order(machine_store, order, now)
      (Active, _) => self.meter_active_machine_order(machine_store, order, now)
      (CancellationPending, _) | (CompensationPending, _) =>
        self.reconcile_machine_compensation(machine_store, order, now)
      (TerminationPending, _) =>
        self.reconcile_machine_termination(machine_store, order, now)
      _ => ()
    }
  }
  self.ingest_machine_usage(machine_store.snapshot())
}

///| Structured supervisor entry point. A thrown persistence error terminates

///| the task and therefore removes controller readiness instead of silently

///|
/// abandoning paid orders.
pub async fn ApiService::run_machine_commerce_reconciler_forever(
  self : ApiService,
  interval_ms : Int,
) -> Unit {
  if interval_ms < 1000 || interval_ms > 300000 {
    raise Failure::Failure("machine-commerce reconcile interval is invalid")
  }
  for ;; {
    self.reconcile_machine_commerce()
    @async.sleep(interval_ms)
  }
}
