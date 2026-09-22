///|
priv struct OfflineEntitlementExecution {
  activation : @offline.EntitlementActivation?
  reversal : @offline.CommercialReversal?
} derive(FromJson)

///|
fn offline_execution_pending() -> HttpReply {
  json_reply(202, { "code": "EntitlementExecutionPending" })
}

///|
/// Receipts identify a committed authority result, never a claimed intention.
fn offline_execution_receipt(
  kind : String,
  id : String,
  state : String,
) -> String {
  "offline-authority:" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode("\{kind}\n\{id}\n\{state}")),
  )
}

///|
/// This endpoint accepts only exact durable dispatcher work. It cannot create
/// a lease, pick a node, enlarge a quota or accept browser-supplied authority.
async fn ApiService::execute_offline_entitlement(
  self : ApiService,
  verb : ApiMethod,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.entitlement_authority_callback_token is Some(token) else {
    return api_error(
      503, "EntitlementAuthorityUnavailable", "entitlement authority is not configured",
      true,
    )
  }
  if verb != Post || !bearer_authorized(headers, token) {
    return api_error(
      401, "Unauthenticated", "valid entitlement authority is required", false,
    )
  }
  guard self.offline_commerce_store is Some(store) &&
    (decode_offline(body) : OfflineEntitlementExecution?) is Some(intent) else {
    return api_error(
      400, "InvalidRequest", "invalid entitlement execution request", false,
    )
  }
  let reply = store.with_authority_execution((snapshot, activate, reverse) => {
    match (intent.activation, intent.reversal) {
      (Some(request), None) =>
        self.execute_offline_activation(snapshot, request, activate)
      (None, Some(request)) =>
        self.execute_offline_reversal(snapshot, request, reverse)
      _ =>
        api_error(
          400, "InvalidRequest", "exactly one authority operation is required", false,
        )
    }
  }) catch {
    error => offline_error_reply(error)
  }
  if reply.status == 200 {
    self.refresh_offline_commerce_notifications(@async.now())
  }
  reply
}

///|
/// The offline mutex is already held by the executor; use its snapshot rather
/// than reentering the store through undertaking_fulfillment_allowed.
async fn ApiService::offline_execution_undertaking_allowed(
  self : ApiService,
  snapshot : @offline.OfflineCommerceSnapshot,
  order_id : String,
  now : Int64,
) -> Bool {
  if snapshot.orders.iter().find_first(o => o.order_id == order_id)
    is Some(order) &&
    order.technical_acceptance_waiver is Some(_) {
    return self.technical_documentary_waiver_allowed(order, now)
  }
  guard self.contract_document_store is Some(documents) else { return true }
  for packet in documents.snapshot().packets {
    if packet.order_ref != order_id ||
      !@contractdoc.is_undertaking_template(packet.template_id) {
      continue
    }
    guard packet.state == Effective &&
      packet.execution is Some(execution) &&
      packet.value("lease.start_date") is Some(start) &&
      packet.value("lease.end_date") is Some(end) &&
      @contractdoc.days_until(start, now).map_or(false, days => days <= 0L) &&
      @contractdoc.days_until(end, now).map_or(false, days => days >= 0L) else {
      return false
    }
    return undertaking_evidence_valid(
      snapshot,
      packet,
      execution.evidence_sha256,
      true,
      now,
    )
  }
  true
}

///|
async fn ApiService::execute_offline_activation(
  self : ApiService,
  snapshot : @offline.OfflineCommerceSnapshot,
  request : @offline.EntitlementActivation,
  complete : async (@offline.EntitlementActivation) -> @offline.CommercialOrder,
) -> HttpReply {
  guard snapshot.entitlement_activations
    .iter()
    .find_first(value => value.activation_id == request.activation_id)
    is Some(persisted) else {
    return api_error(404, "NotFound", "activation work was not found", false)
  }
  // Normalize only terminal output fields for a restart after callback success.
  if {
      ..persisted,
      state: EntitlementActivationRequested,
      entitlement_ref: None,
      authority_receipt: None,
      reason_code: None,
      completed_unix_ms: None,
    } !=
    request {
    return api_error(
      409, "IdempotencyConflict", "activation does not match durable work", false,
    )
  }
  if persisted.state != EntitlementActivationRequested {
    return json_reply(200, persisted.to_json())
  }
  if snapshot.entitlement_activations.any(other => {
      other.order_id != request.order_id &&
      other.kind == request.kind &&
      other.authority_target_ref == request.authority_target_ref &&
      other.state != EntitlementActivationRejected &&
      snapshot.orders.any(order => {
        order.order_id == other.order_id &&
        (
          order.state == FulfillmentPending ||
          order.state == Fulfilled ||
          order.state == ReversalPending ||
          order.state == ReversalManualIntervention
        )
      })
    }) {
    return api_error(
      409, "EntitlementAlreadyBound", "authority target belongs to another live commercial order",
      false,
    )
  }
  guard snapshot.orders
    .iter()
    .find_first(value => value.order_id == request.order_id)
    is Some(order) else {
    return api_error(404, "NotFound", "activation order was not found", false)
  }
  guard order.state == FulfillmentPending &&
    order.generation == request.expected_order_generation + 1L &&
    order.organization_id == request.organization_id &&
    order.purchaser_subject_ref == request.purchaser_subject_ref &&
    snapshot.work_claims.any(claim => {
      claim.work_id == "activation:\{request.activation_id}" &&
      claim.worker_kind == EntitlementDispatcher &&
      claim.attempt > 0 &&
      claim.completed_unix_ms is None &&
      claim.expected_order_generation == request.expected_order_generation
    }) else {
    return api_error(
      409, "StaleGeneration", "activation work is not currently claimed", false,
    )
  }
  let now = @async.now()
  let technical_invalid = !self.technical_activation_allowed(
    order, request, now,
  )
  if technical_invalid {
    // A crash may have activated the lease before committing completion.
    // Revoke only the exact bound authority before terminally rejecting.
    guard self.compensate_technical_target(order, request, now) else {
      return api_error(
        409, "TechnicalTargetMismatch", "technical recovery target cannot be verified",
        false,
      )
    }
  }
  if now >= order.expires_unix_ms || technical_invalid {
    // Every supported target is bounded by the order term before mutation.
    // A crash/restart after that term must close the saga rather than keep
    // retrying an activation that can no longer be admitted.
    let rejected : @offline.EntitlementActivation = {
      ..request,
      state: EntitlementActivationRejected,
      entitlement_ref: None,
      authority_receipt: Some(
        offline_execution_receipt(
          "activation",
          request.activation_id,
          if technical_invalid {
            "TechnicalAuthorizationInvalidCompensated"
          } else {
            "OrderExpired"
          },
        ),
      ),
      reason_code: Some(
        if technical_invalid {
          "TechnicalAuthorizationInvalidCompensated"
        } else {
          "OrderExpired"
        },
      ),
      completed_unix_ms: Some(now),
    }
    ignore(complete(rejected))
    return json_reply(200, rejected.to_json())
  }
  if !self.offline_execution_undertaking_allowed(snapshot, order.order_id, now) {
    return api_error(
      409, "UndertakingApprovalRequired", "current approval and an active order term are required",
      false,
    )
  }
  let receipt = match request.kind {
    WorkspaceLease => {
      guard self.workspace_directory is Some(directory) else {
        return api_error(
          503, "WorkspaceUnavailable", "workspace authority is not configured", true,
        )
      }
      guard directory.snapshot(now).leases
        .iter()
        .find_first(value => value.lease_id == request.authority_target_ref)
        is Some(lease) &&
        lease.tenant_ref == order.tenant_ref &&
        lease.subject_ref == order.purchaser_subject_ref &&
        lease.expires_unix_ms <= order.expires_unix_ms else {
        return api_error(
          409, "EntitlementTargetMismatch", "workspace target is absent or not bound to the order",
          false,
        )
      }
      if now < lease.starts_unix_ms {
        return offline_execution_pending()
      }
      let active = if lease.state == Requested {
        directory.activate_lease(lease.lease_id, now)
      } else {
        lease
      }
      if active.state != Active || now >= active.expires_unix_ms {
        return api_error(
          409, "EntitlementTargetUnavailable", "workspace lease cannot activate",
          false,
        )
      }
      // Recheck real grant/user authority, including replays of an active lease.
      ignore(
        directory.authorize_subject_for_tenant(
          order.purchaser_subject_ref,
          order.tenant_ref,
          active.access,
          now,
        ),
      )
      offline_execution_receipt("workspace", active.lease_id, "Active")
    }
    ExclusiveMachineLease => {
      guard self.exclusive_lease_store is Some(leases) else {
        return api_error(
          503, "ExclusiveLeaseUnavailable", "exclusive lease authority is not configured",
          true,
        )
      }
      guard leases.lease(request.authority_target_ref) is Some(lease) &&
        lease.intent.subject_ref == order.purchaser_subject_ref &&
        lease.intent.expires_unix_ms <= order.expires_unix_ms else {
        return api_error(
          409, "EntitlementTargetMismatch", "exclusive lease is absent or not bound to the order",
          false,
        )
      }
      // Reuse node-drain/provision reconciliation. Only a signed node helper
      // observation may advance Provisioning to Active.
      let current = self.begin_exclusive_provisioning_if_drained(lease)
      match current.state {
        Active if now >= current.intent.starts_unix_ms &&
          now < current.intent.expires_unix_ms => current.authority_receipt
        Requested | Reserved | Provisioning =>
          return offline_execution_pending()
        _ =>
          return api_error(
            409, "EntitlementTargetUnavailable", "exclusive lease cannot activate",
            false,
          )
      }
    }
    CapacityCommitment => {
      self.commercial_mutex.acquire()
      defer self.commercial_mutex.release()
      let before = self.commercial_store.durable_snapshot()
      errdefer self.commercial_store.replace_from_durable_snapshot(before)
      guard self.commercial_store.snapshot(order.organization_id).commitments
        .iter()
        .find_first(value => value.commitment_id == request.authority_target_ref)
        is Some(commitment) &&
        commitment.organization_id == order.organization_id &&
        commitment.effective_until_unix_ms <= order.expires_unix_ms else {
        return api_error(
          409, "EntitlementTargetMismatch", "capacity commitment is absent or not bound to the order",
          false,
        )
      }
      if now < commitment.effective_from_unix_ms {
        return offline_execution_pending()
      }
      let active = self.commercial_store.activate_offline_commitment(
        order.organization_id,
        request.authority_target_ref,
        request.requested_by,
        now,
      )
      self.persist_commercial_state()
      offline_execution_receipt(
        "commitment",
        active.commitment_id,
        "ActiveCommitment",
      )
    }
  }
  let completed : @offline.EntitlementActivation = {
    ..request,
    state: EntitlementActivationConfirmed,
    entitlement_ref: Some(request.authority_target_ref),
    authority_receipt: Some(receipt),
    reason_code: None,
    completed_unix_ms: Some(now),
  }
  ignore(complete(completed))
  self.operator_audit(
    "offline.entitlement.execute",
    completed.activation_id,
    receipt,
  )
  json_reply(200, completed.to_json())
}

///|
async fn ApiService::execute_offline_reversal(
  self : ApiService,
  snapshot : @offline.OfflineCommerceSnapshot,
  request : @offline.CommercialReversal,
  complete : async (@offline.CommercialReversal) -> @offline.CommercialOrder,
) -> HttpReply {
  guard snapshot.reversals
    .iter()
    .find_first(value => value.reversal_id == request.reversal_id)
    is Some(persisted) else {
    return api_error(404, "NotFound", "reversal work was not found", false)
  }
  if {
      ..persisted,
      state: ReversalRequested,
      authority_receipt: None,
      reason_code: None,
      completed_unix_ms: None,
    } !=
    request {
    return api_error(
      409, "IdempotencyConflict", "reversal does not match durable work", false,
    )
  }
  if persisted.state != ReversalRequested {
    return json_reply(200, persisted.to_json())
  }
  guard snapshot.orders
    .iter()
    .find_first(value => value.order_id == request.order_id)
    is Some(order) else {
    return api_error(404, "NotFound", "reversal order was not found", false)
  }
  guard order.state == ReversalPending &&
    order.generation == request.expected_order_generation + 1L &&
    order.organization_id == request.organization_id &&
    order.entitlement_ref == Some(request.entitlement_ref) &&
    snapshot.work_claims.any(claim => {
      claim.work_id == "reversal:\{request.reversal_id}" &&
      claim.worker_kind == EntitlementDispatcher &&
      claim.attempt > 0 &&
      claim.completed_unix_ms is None &&
      claim.expected_order_generation == request.expected_order_generation
    }) &&
    snapshot.entitlement_activations
    .iter()
    .find_first(value => {
      value.order_id == order.order_id &&
      value.state == EntitlementActivationConfirmed &&
      value.entitlement_ref == Some(request.entitlement_ref)
    })
    is Some(activation) else {
    return api_error(
      409, "StaleGeneration", "reversal is not bound to claimed fulfilled authority",
      false,
    )
  }
  let now = @async.now()
  let receipt = match activation.kind {
    WorkspaceLease => {
      guard self.workspace_directory is Some(directory) &&
        directory.snapshot(now).leases
        .iter()
        .find_first(value => value.lease_id == request.entitlement_ref)
        is Some(lease) &&
        lease.tenant_ref == order.tenant_ref &&
        lease.subject_ref == order.purchaser_subject_ref else {
        return api_error(
          409, "EntitlementTargetMismatch", "workspace reversal target is unavailable",
          false,
        )
      }
      if lease.state != Revoked && lease.state != Expired {
        ignore(directory.revoke_lease(lease.lease_id, now))
      }
      offline_execution_receipt("workspace", lease.lease_id, "Revoked")
    }
    ExclusiveMachineLease => {
      guard self.exclusive_lease_store is Some(leases) &&
        leases.lease(request.entitlement_ref) is Some(lease) &&
        lease.intent.subject_ref == order.purchaser_subject_ref else {
        return api_error(
          409, "EntitlementTargetMismatch", "exclusive reversal target is unavailable",
          false,
        )
      }
      let target : @nodelease.ExclusiveLeaseState? = match lease.state {
        Requested => Some(Cancelled)
        Reserved | Provisioning | Active => Some(Expiring)
        Quarantined => Some(RevokingAccess)
        _ => None
      }
      let current = match target {
        None => lease
        Some(state) =>
          leases.transition(
            lease.intent.lease_id,
            {
              expected_generation: lease.generation,
              state,
              evidence_receipt: offline_execution_receipt(
                "reversal",
                request.reversal_id,
                "Requested",
              ),
            },
            now,
          )
      }
      self.publish_exclusive_lease_directive(
        current,
        directive_state_for_exclusive_lease(current.state),
      )
      // Access revocation AND sanitization are observed by the existing node
      // helper path. Never report success merely because Expiring was written.
      if current.state != Completed && current.state != Cancelled {
        return offline_execution_pending()
      }
      current.authority_receipt
    }
    CapacityCommitment => {
      self.commercial_mutex.acquire()
      defer self.commercial_mutex.release()
      let before = self.commercial_store.durable_snapshot()
      errdefer self.commercial_store.replace_from_durable_snapshot(before)
      let revoked = self.commercial_store.revoke_offline_commitment(
        order.organization_id,
        request.entitlement_ref,
      )
      self.persist_commercial_state()
      offline_execution_receipt(
        "commitment",
        revoked.commitment_id,
        "CancelledCommitment",
      )
    }
  }
  let completed : @offline.CommercialReversal = {
    ..request,
    state: ReversalConfirmed,
    authority_receipt: Some(receipt),
    reason_code: None,
    completed_unix_ms: Some(now),
  }
  ignore(complete(completed))
  self.operator_audit(
    "offline.entitlement.reverse.execute",
    completed.reversal_id,
    receipt,
  )
  json_reply(200, completed.to_json())
}
