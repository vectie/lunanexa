///|
/// An approved undertaking is the commercial authority for an organization
/// allocation. The browser supplies only the order and the exact node set;
/// identity, lease lifetime, price and node count come from durable records.
priv struct UndertakingAllocationRequest {
  order_id : String
  node_ids : Array[String]
  readiness_confirmation : String
} derive(FromJson)

///|
fn undertaking_allocation_path(path : String) -> Bool {
  path == "/v1/undertaking-allocations"
}

///|
fn undertaking_allocation_fingerprint(order_id : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(order_id)))
}

///|
fn undertaking_allocation_packet(
  order : @offline.CommercialOrder,
  packets : Array[@contractdoc.ContractPacket],
  snapshot : @offline.OfflineCommerceSnapshot,
  now : Int64,
) -> @contractdoc.ContractPacket? {
  let matches = packets.filter(packet => {
    packet.order_ref == order.order_id &&
    packet.tenant_ref == order.tenant_ref &&
    packet.organization_id == order.organization_id &&
    packet.subject_ref == order.purchaser_subject_ref &&
    @contractdoc.is_undertaking_template(packet.template_id) &&
    undertaking_quote_matches_template(
      order,
      @contractdoc.manifest_for_template_id(packet.template_id),
    ) &&
    packet.state == Effective &&
    packet.execution is Some(_) &&
    undertaking_quote_matches(packet, order) &&
    packet.execution.map_or(false, execution => {
      undertaking_evidence_valid(
        snapshot,
        packet,
        execution.evidence_sha256,
        true,
        now,
      )
    })
  })
  if matches.length() == 1 {
    Some(matches[0])
  } else {
    None
  }
}

///|
fn undertaking_allocation_expiry(
  order : @offline.CommercialOrder,
  packet : @contractdoc.ContractPacket,
  now : Int64,
) -> Int64? {
  guard packet.value("lease.start_date") is Some(start) &&
    packet.value("lease.end_date") is Some(end) &&
    @contractdoc.calendar_date_days(start) is Some(first_day) &&
    @contractdoc.calendar_date_days(end) is Some(last_day) &&
    first_day * 86400000L <= now &&
    last_day >= first_day else {
    return None
  }
  let expires = Int64::min(order.expires_unix_ms, (last_day + 1L) * 86400000L)
  if expires > now {
    Some(expires)
  } else {
    None
  }
}

///|
/// Host-native model processes do not necessarily appear in the controller's
/// managed-deployment list. Require fresh kernel MemAvailable evidence before
/// promising a whole Spark to a commercial undertaking.
async fn ApiService::undertaking_idle_capacity(
  self : ApiService,
  node_ids : Array[String],
  now : Int64,
) -> Int? {
  guard self.telemetry is Some(telemetry) && self.scheduler is Some(scheduler) else {
    return None
  }
  let samples = telemetry.snapshot().samples
  let heartbeats = self.store.heartbeats()
  let assignments = self.store.assignments()
  let legacy = match self.exclusive_lease_store {
    Some(leases) => leases.leases()
    None => []
  }
  let mut budget = 2147483647
  for node_id in node_ids {
    guard heartbeats
      .iter()
      .find_first(heartbeat => heartbeat.node_id == node_id)
      is Some(heartbeat) &&
      heartbeat.state == Active &&
      heartbeat.timestamp_unix_ms <= now &&
      now - heartbeat.timestamp_unix_ms <=
      self.global_settings.control_timing.heartbeat_timeout_ms &&
      heartbeat.running_deployments.is_empty() &&
      heartbeat.inventory.taints.is_empty() &&
      heartbeat.inventory.labels.get(machine_usage_pool_label) ==
      Some(machine_enterprise_pool) &&
      heartbeat.inventory.accelerators.any(accelerator => accelerator.healthy) &&
      @node.inventory_host_resources(heartbeat.inventory) is Some(host) &&
      observed_available_memory_mib(
        samples,
        node_id,
        now,
        self.global_settings.control_timing.heartbeat_timeout_ms,
      )
      is Some(available) &&
      available.to_int64() * 4L >= host.memory_total_mib * 3L &&
      !scheduler.node_is_reserved(node_id) &&
      !assignments.any(assignment => assignment.node_id == node_id) &&
      !legacy.any(lease => {
        lease.intent.node_id == node_id &&
        @nodelease.state_blocks_managed_placement(lease.state)
      }) else {
      return None
    }
    budget = Int::min(
      budget,
      Int::min((host.memory_total_mib - 16384L).to_int(), available - 4096),
    )
  }
  if budget >= 32768 {
    Some(budget)
  } else {
    None
  }
}

///|
/// An order-bound reservation loses authority when the signed undertaking,
/// prepayment review, order or term ceases to be current. Ordinary private
/// resource grants retain their existing admission rule.
async fn ApiService::undertaking_reservation_allowed(
  self : ApiService,
  reservation : @scheduler.NodeReservation,
  now : Int64,
) -> Bool {
  let prefix = "undertaking-resource-"
  if !reservation.request.reservation_id.has_prefix(prefix) {
    return true
  }
  if reservation.state != Reserved ||
    reservation.request.starts_unix_ms > now ||
    reservation.request.expires_unix_ms <= now {
    return false
  }
  guard self.offline_commerce_store is Some(commerce) &&
    self.contract_document_store is Some(documents) else {
    return false
  }
  let snapshot = commerce.snapshot()
  guard snapshot.orders
    .iter()
    .find_first(order => {
      reservation.request.reservation_id ==
      "\{prefix}\{undertaking_allocation_fingerprint(order.order_id)}"
    })
    is Some(order) &&
    order.state == Fulfilled &&
    order.entitlement_ref == Some(reservation.request.lease_id) &&
    order.tenant_ref == reservation.request.tenant_ref &&
    order.organization_id == reservation.request.organization_id &&
    undertaking_allocation_packet(
      order,
      documents.snapshot().packets,
      snapshot,
      now,
    )
    is Some(packet) &&
    undertaking_allocation_expiry(order, packet, now) is Some(expires) else {
    return false
  }
  reservation.request.expires_unix_ms == expires
}

///|
/// A signed undertaking grants machines to the organization, not to the
/// purchaser's personal desktop. Other organization members still need their
/// own live Developer workspace authority before starting an application.
async fn ApiService::delivery_reservation_authorized(
  self : ApiService,
  reservation : @scheduler.NodeReservation,
  tenant_ref : String,
  organization_id : String,
  lease_id : String,
  grant_id : String,
  now : Int64,
) -> Bool {
  if reservation.state != Reserved ||
    reservation.request.tenant_ref != tenant_ref ||
    reservation.request.organization_id != organization_id ||
    reservation.request.starts_unix_ms > now ||
    reservation.request.expires_unix_ms <= now {
    return false
  }
  if reservation.request.reservation_id.has_prefix("undertaking-resource-") {
    return self.undertaking_reservation_allowed(reservation, now)
  }
  reservation.request.lease_id == lease_id &&
  reservation.request.authority_ref == grant_id
}

///|
/// The undertaking and machine allocation belong to the company. An active
/// Developer member may use a separate personal WebIDE without signing a
/// second copy of the company's resource document.
async fn ApiService::has_active_organization_allocation(
  self : ApiService,
  tenant_ref : String,
  organization_id : String,
  subject_ref : String,
  now : Int64,
) -> Bool {
  guard self.portal_store is Some(portal) &&
    self.scheduler is Some(scheduler) &&
    portal.snapshot().memberships.any(membership => {
      membership.active &&
      membership.tenant_ref == tenant_ref &&
      membership.organization_id == organization_id &&
      membership.subject_ref == subject_ref &&
      @portal.role_allows(membership.roles, Developer)
    }) else {
    return false
  }
  for reservation in scheduler.snapshot().node_reservations.unwrap_or([]) {
    if reservation.state == Reserved &&
      reservation.request.tenant_ref == tenant_ref &&
      reservation.request.organization_id == organization_id &&
      reservation.request.starts_unix_ms <= now &&
      reservation.request.expires_unix_ms > now &&
      reservation.request.reservation_id.has_prefix("undertaking-resource-") &&
      self.undertaking_reservation_allowed(reservation, now) {
      return true
    }
  }
  false
}

///|
async fn ApiService::undertaking_allocation_view(
  self : ApiService,
  order : @offline.CommercialOrder,
  snapshot : @offline.OfflineCommerceSnapshot,
  now : Int64,
) -> Json? {
  guard self.contract_document_store is Some(documents) &&
    self.scheduler is Some(scheduler) &&
    @offline.undertaking_quote_term(order) is Some(_) else {
    return None
  }
  let packets = documents.snapshot().packets.filter(packet => {
    packet.order_ref == order.order_id &&
    @contractdoc.is_undertaking_template(packet.template_id)
  })
  if packets.is_empty() {
    return None
  }
  let ready_packet = undertaking_allocation_packet(
    order, packets, snapshot, now,
  )
  let fingerprint = undertaking_allocation_fingerprint(order.order_id)
  let reservation_id = "undertaking-resource-\{fingerprint}"
  let reservation = scheduler.node_reservation(reservation_id)
  let active_term = ready_packet.bind(packet => {
    undertaking_allocation_expiry(order, packet, now)
  })
  let status = match reservation {
    Some(value) if value.state == Reserved =>
      if self.undertaking_reservation_allowed(value, now) {
        "Allocated"
      } else {
        "AuthorityEnded"
      }
    Some(value) if value.state == Draining => "Releasing"
    _ =>
      if order.state == Cancelled ||
        order.state == Expired ||
        order.state == Rejected ||
        order.state == Revoked ||
        order.state == ReversalPending ||
        order.state == ReversalManualIntervention {
        "OrderClosed"
      } else if order.expires_unix_ms <= now {
        "OrderExpired"
      } else if ready_packet is None {
        "AwaitingApprovalOrEvidence"
      } else if active_term is None {
        "LeaseTermUnavailable"
      } else if order.state == FulfillmentPending {
        "ActivatingAccess"
      } else if order.state == Fulfilled {
        "ReadyForNodes"
      } else if order.state == UnderReconciliation {
        "ReadyForAllocation"
      } else {
        "OrderNotReady"
      }
  }
  Some({
    "order_id": order.order_id,
    "organization_id": order.organization_id,
    "purchaser_subject_ref": order.purchaser_subject_ref,
    "node_count": order.quote.unwrap().lines[0].quantity.to_json(),
    "expires_unix_ms": active_term.to_json(),
    "status": status,
    "node_ids": reservation
    .map_or([], value => value.request.node_ids)
    .to_json(),
  })
}

///|
async fn ApiService::handle_undertaking_allocation(
  self : ApiService,
  verb : ApiMethod,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.operator_identity(headers) is Some(operator) else {
    return api_error(
      401, "Unauthenticated", "operator authority is required", false,
    )
  }
  guard self.offline_commerce_store is Some(commerce) &&
    self.contract_document_store is Some(documents) &&
    self.access_onboarding_store is Some(journal) &&
    self.account_store is Some(accounts) &&
    self.portal_store is Some(portal) &&
    self.workspace_directory is Some(directory) &&
    self.scheduler is Some(scheduler) else {
    return api_error(
      503, "AllocationUnavailable", "commercial and resource authorities are required",
      true,
    )
  }
  let now = @async.now()
  if verb == Get {
    let snapshot = commerce.snapshot()
    let rows : Array[Json] = []
    for order in snapshot.orders {
      if self.undertaking_allocation_view(order, snapshot, now) is Some(view) {
        rows.push(view)
      }
    }
    return json_reply(200, rows.to_json())
  }
  if verb != Post {
    return api_error(
      405, "MethodNotAllowed", "unsupported allocation action", false,
    )
  }
  if self.reservation_host is None {
    return api_error(
      503, "AllocationHostUnavailable", "Kubernetes node reservation adapter is required",
      true,
    )
  }
  let request : UndertakingAllocationRequest = try
    @json.from_json(@json.parse(body))
  catch {
    _ =>
      return api_error(
        400, "InvalidRequest", "order and node selection are required", false,
      )
  } noraise {
    value => value
  }
  if !@contracts.valid_identifier(request.order_id) ||
    request.readiness_confirmation != "allocate-idle-nodes:\{request.order_id}" {
    return api_error(
      400, "InvalidRequest", "confirm the exact idle-node allocation", false,
    )
  }
  let snapshot = commerce.snapshot()
  guard snapshot.orders
    .iter()
    .find_first(order => order.order_id == request.order_id)
    is Some(order) &&
    undertaking_allocation_packet(
      order,
      documents.snapshot().packets,
      snapshot,
      now,
    )
    is Some(packet) &&
    undertaking_allocation_expiry(order, packet, now) is Some(expires) &&
    order.quote is Some(quote) &&
    request.node_ids.length() == quote.lines[0].quantity.to_int() &&
    (
      order.state == UnderReconciliation ||
      order.state == FulfillmentPending ||
      order.state == Fulfilled
    ) else {
    return api_error(
      409, "UndertakingNotReady", "signed, approved and fully prepaid undertaking with an exact node count is required",
      false,
    )
  }
  let seen : Map[String, Bool] = Map([])
  for node_id in request.node_ids {
    if !@contracts.valid_identifier(node_id) || seen.contains(node_id) {
      return api_error(
        400, "InvalidRequest", "node selection contains an invalid or duplicate node",
        false,
      )
    }
    seen[node_id] = true
  }
  let fingerprint = undertaking_allocation_fingerprint(order.order_id)
  let reservation_id = "undertaking-resource-\{fingerprint}"
  if scheduler.node_reservation(reservation_id) is Some(existing) {
    if existing.state == Reserved &&
      existing.request.node_ids == request.node_ids &&
      self.undertaking_reservation_allowed(existing, now) {
      return json_reply(200, existing.to_json())
    }
    return api_error(
      409, "AllocationConflict", "the order already has another or releasing allocation",
      false,
    )
  }
  guard self.undertaking_idle_capacity(request.node_ids, now)
    is Some(memory_mib) else {
    return api_error(
      409, "NodeUnavailable", "the complete node set needs fresh idle-memory and workload evidence",
      true,
    )
  }
  guard portal.snapshot().memberships.any(membership => {
      membership.active &&
      membership.subject_ref == order.purchaser_subject_ref &&
      membership.tenant_ref == order.tenant_ref &&
      membership.organization_id == order.organization_id &&
      @portal.role_allows(membership.roles, Developer)
    }) &&
    accounts.snapshot().accounts
    .iter()
    .find_first(account => {
      account.subject_ref == order.purchaser_subject_ref &&
      account.state == Active &&
      @account.role_allows(account.roles, EnterpriseUser)
    })
    is Some(account) else {
    return api_error(
      409, "PurchaserUnavailable", "active purchaser and company membership are required",
      false,
    )
  }
  let operation_id = "undertaking-access-\{fingerprint}"
  let record = match journal.record(operation_id) {
    Some(existing) => existing
    None => {
      let intent : @onboarding.AccessOnboardingIntent = {
        operation_id,
        fingerprint,
        requested_by: operator,
        account_id: account.account_id,
        subject_ref: account.subject_ref,
        identity_issuer: account.identity_issuer,
        identity_subject_sha256: account.identity_subject_sha256,
        display_name: account.display_name,
        email: account.email,
        organization_id: order.organization_id,
        tenant_ref: order.tenant_ref,
        membership_id: "undertaking-member-\{fingerprint}",
        user_id: "undertaking-user-\{fingerprint}",
        grant_id: "undertaking-grant-\{fingerprint}",
        lease_id: "undertaking-lease-\{fingerprint}",
        identity_receipt: account.identity_receipt,
        expires_unix_ms: expires,
        enterprise_gpu_capabilities: Some(true),
      }
      try journal.begin(intent, now) catch {
        _ =>
          return api_error(
            503, "AccessOnboardingUnavailable", "allocation access intent could not be saved",
            true,
          )
      } noraise {
        value => value
      }
    }
  }
  if record.intent.account_id != account.account_id ||
    record.intent.subject_ref != order.purchaser_subject_ref ||
    record.intent.organization_id != order.organization_id ||
    record.intent.tenant_ref != order.tenant_ref ||
    record.intent.expires_unix_ms != expires ||
    record.status == Conflicted {
    return api_error(
      409, "AllocationConflict", "prior access preparation conflicts with this order",
      false,
    )
  }
  if record.status == RecoverableFailure {
    ignore(journal.retry(operation_id, now)) catch {
      _ =>
        return api_error(
          503, "AccessOnboardingUnavailable", "access retry could not be saved",
          true,
        )
    }
  }
  let prepared = self.execute_webide_access_package(record.intent, now)
  if prepared.status >= 400 {
    return prepared
  }
  let lease_id = record.intent.lease_id
  if order.state == UnderReconciliation {
    if self.offline_readiness_gate(
        [EntitlementAuthority, FinanceLegalPolicy, MachineCallbackIdentity],
        now,
      )
      is Some(blocked) {
      return blocked
    }
    let activation_id = "undertaking-activation-\{fingerprint}"
    let activation : @offline.EntitlementActivation = {
      activation_id,
      idempotency_key: activation_id,
      order_id: order.order_id,
      organization_id: order.organization_id,
      purchaser_subject_ref: order.purchaser_subject_ref,
      kind: WorkspaceLease,
      authority_target_ref: lease_id,
      expected_order_generation: order.generation,
      state: EntitlementActivationRequested,
      entitlement_ref: None,
      authority_receipt: None,
      reason_code: None,
      requested_by: operator,
      requested_unix_ms: now,
      completed_unix_ms: None,
    }
    ignore(commerce.fulfill(order.order_id, order.generation, activation, now)) catch {
      error => return offline_error_reply(error)
    }
    self.operator_audit(
      "undertaking.allocation.access-requested",
      order.order_id,
      activation_id,
    )
    return json_reply(202, {
      "order_id": order.order_id,
      "status": "ActivatingAccess",
      "node_ids": request.node_ids.to_json(),
    })
  }
  if order.state == FulfillmentPending {
    return json_reply(202, {
      "order_id": order.order_id,
      "status": "ActivatingAccess",
      "node_ids": request.node_ids.to_json(),
    })
  }
  guard order.entitlement_ref == Some(lease_id) &&
    directory.snapshot(now).leases
    .iter()
    .find_first(lease => {
      lease.lease_id == lease_id &&
      lease.state == Active &&
      lease.subject_ref == order.purchaser_subject_ref &&
      lease.expires_unix_ms == expires
    })
    is Some(active_lease) else {
    return api_error(
      409, "AllocationAuthorityMismatch", "fulfilled order is not bound to the active workspace lease",
      false,
    )
  }
  let reservation : @scheduler.NodeReservationRequest = {
    reservation_id,
    idempotency_key: reservation_id,
    tenant_ref: order.tenant_ref,
    organization_id: order.organization_id,
    authority_ref: record.intent.grant_id,
    lease_id,
    node_ids: request.node_ids,
    starts_unix_ms: active_lease.starts_unix_ms,
    expires_unix_ms: expires,
    memory_mib_per_node: memory_mib,
    gpu_memory_mib_per_node: memory_mib,
    max_concurrency_per_node: 4,
  }
  let request_body : Json = {
    "request": reservation.to_json(),
    "readiness_confirmation": "reserve-idle-nodes:\{reservation_id}",
  }
  let result = self.handle_resource_reservation(
    Post,
    "/v1/resource-reservations",
    headers,
    request_body.stringify(),
  )
  if result.status == 201 {
    self.operator_audit(
      "undertaking.allocation.nodes-reserved",
      order.order_id,
      reservation_id,
    )
  }
  result
}
