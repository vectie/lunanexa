///|
fn exclusive_lease_management_path(path : String) -> Bool {
  path == "/v1/exclusive-node-leases" ||
  path.has_prefix("/v1/exclusive-node-leases/")
}

///|
fn decode_exclusive_lease_intent(
  body : String,
) -> @nodelease.ExclusiveNodeLeaseIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_exclusive_lease_termination(
  body : String,
) -> @nodelease.ExclusiveLeaseTerminationRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_lease_agent_observation(
  body : String,
) -> @nodelease.LeaseAgentObservation? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
/// Records the billable wall-clock interval for a portal-owned exclusive
/// machine exactly once. The lease is billed while idle as dedicated capacity:
/// from its contracted start until the earlier of verified cleanup and expiry.
/// Raw operator leases have no tenant project and therefore remain outside the
/// customer ledger.
async fn ApiService::meter_completed_exclusive_lease(
  self : ApiService,
  lease : @nodelease.ExclusiveNodeLease,
) -> Bool {
  if lease.state != Completed || self.portal_store is None {
    return true
  }
  let portal = self.portal_store.unwrap()
  guard portal.snapshot().lease_requests
    .iter()
    .find_first(request => {
      request.exclusive_lease_id == Some(lease.intent.lease_id) &&
      request.state == Approved &&
      request.subject_ref == lease.intent.subject_ref
    })
    is Some(request) else {
    // Operator-created maintenance/test leases are not customer purchases.
    return true
  }
  let started_unix_ms = lease.intent.starts_unix_ms
  let ended_unix_ms = lease.updated_unix_ms.min(lease.intent.expires_unix_ms)
  if ended_unix_ms <= started_unix_ms {
    return true
  }
  let quantity = (ended_unix_ms - started_unix_ms + 999L) / 1000L
  let event_id = "exclusive-lease-usage:\{lease.intent.lease_id}"
  let entry_id = "exclusive-lease-charge:\{lease.intent.lease_id}"
  let observation : @commercial.UsageObservation = {
    event_id,
    organization_id: request.submission.organization_id,
    project_id: request.submission.project_id,
    actor_ref: lease.intent.subject_ref,
    workload_id: lease.intent.lease_id,
    node_id: lease.intent.node_id,
    lease_epoch: lease.generation,
    meter: "exclusive-node-second",
    quantity,
    unit: "second",
    started_unix_ms,
    ended_unix_ms,
    observed_unix_ms: lease.updated_unix_ms,
  }
  self.commercial_mutex.acquire()
  defer self.commercial_mutex.release()
  let before = self.commercial_store.durable_snapshot()
  let accepted = try {
    ignore(self.commercial_store.ingest_usage(observation))
    ignore(
      self.commercial_store.rate_usage(
        event_id,
        entry_id,
        {
          rate_card_id: "exclusive-node-second",
          version: "lease-v1",
          meter: "exclusive-node-second",
          unit: "second",
          unit_price: self.exclusive_lease_unit_price,
          effective_from_unix_ms: 1L,
          effective_until_unix_ms: 9223372036854775806L,
        },
        lease.updated_unix_ms,
      ),
    )
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
  accepted
}

///|
async fn ApiService::observe_node_lease_action(
  self : ApiService,
  node_id : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if !@contracts.valid_identifier(node_id, maximum_length=128) ||
    !self.node_authorized(headers, node_id) {
    return api_error(
      401, "Unauthenticated", "valid node authority is required", false,
    )
  }
  guard self.exclusive_lease_store is Some(leases) &&
    decode_lease_agent_observation(body) is Some(observation) &&
    leases.lease(observation.lease_id) is Some(initial) else {
    return api_error(
      400, "InvalidRequest", "invalid lease agent observation", false,
    )
  }
  if initial.intent.node_id != node_id ||
    initial.generation != observation.observed_generation ||
    observation.observed_unix_ms < initial.updated_unix_ms ||
    observation.observed_unix_ms >
    @async.now() +
    self.global_settings.control_timing.lease_observation_replay_window_ms ||
    !@contracts.valid_identifier(observation.receipt, maximum_length=512) {
    return api_error(
      409, "StaleGeneration", "lease agent observation is stale or misbound", false,
    )
  }
  let expected_action = match observation.action {
    "provision" =>
      @nodelease.LeaseAgentAction::ProvisionAccess(
        lease_id=initial.intent.lease_id,
        username=initial.intent.unix_username,
        credential_ref=initial.intent.access_credential_ref,
        expires_unix_ms=initial.intent.expires_unix_ms,
        generation=initial.generation,
      )
    "revoke" =>
      RevokeAccess(
        lease_id=initial.intent.lease_id,
        username=initial.intent.unix_username,
        generation=initial.generation,
      )
    "sanitize" =>
      SanitizeLease(
        lease_id=initial.intent.lease_id,
        username=initial.intent.unix_username,
        generation=initial.generation,
      )
    "quarantine" =>
      QuarantineNode(
        lease_id=initial.intent.lease_id,
        username=initial.intent.unix_username,
        generation=initial.generation,
      )
    _ => NoAction
  }
  guard @nodelease.signed_helper_receipt_timestamp(
      expected_action,
      observation.receipt,
      self.lease_helper_receipt_secret,
    )
    is Some(helper_timestamp) &&
    helper_timestamp >= initial.updated_unix_ms &&
    helper_timestamp <= observation.observed_unix_ms &&
    observation.observed_unix_ms - helper_timestamp <=
    self.global_settings.control_timing.lease_observation_replay_window_ms else {
    return api_error(
      409, "InvalidCleanupEvidence", "lease helper evidence is invalid or stale",
      false,
    )
  }
  let advance = (
    current : @nodelease.ExclusiveNodeLease,
    state : @nodelease.ExclusiveLeaseState,
  ) => {
    leases.transition(
      current.intent.lease_id,
      {
        expected_generation: current.generation,
        state,
        evidence_receipt: observation.receipt,
      },
      observation.observed_unix_ms,
    )
  }
  let transitioned = try {
    match observation.action {
      "provision" => {
        if initial.state != Provisioning {
          raise Failure::Failure("lease is not ready for provisioning evidence")
        }
        advance(initial, Active)
      }
      "revoke" =>
        if initial.state == RevokingAccess {
          initial
        } else {
          let draining = match initial.state {
            Active | Expiring => advance(initial, Draining)
            Draining => initial
            _ => raise Failure::Failure("lease is not ready for revocation")
          }
          advance(draining, RevokingAccess)
        }
      "sanitize" =>
        if initial.state == Completed {
          initial
        } else {
          let sanitizing = if initial.state == RevokingAccess {
            advance(initial, Sanitizing)
          } else {
            initial
          }
          advance(sanitizing, Completed)
        }
      "quarantine" =>
        if initial.state == Quarantined {
          initial
        } else {
          advance(initial, Quarantined)
        }
      _ => raise Failure::Failure("unsupported lease agent action")
    }
  } catch {
    _ =>
      return api_error(
        409, "InvalidTransition", "lease observation transition was rejected", false,
      )
  } noraise {
    value => value
  }
  if observation.action == "revoke" ||
    observation.action == "sanitize" ||
    observation.action == "quarantine" {
    match self.credential_handoff_store {
      Some(store) =>
        ignore(
          store.revoke_for_lease(transitioned.intent.lease_id, @async.now()),
        )
      None => ()
    }
  }
  self.publish_exclusive_lease_directive(
    transitioned,
    directive_state_for_exclusive_lease(transitioned.state),
  )
  self.operator_audit(
    "exclusive-lease.node-observation",
    transitioned.intent.lease_id,
    observation.receipt,
  )
  if transitioned.state == Completed &&
    !self.meter_completed_exclusive_lease(transitioned) {
    return api_error(
      503, "LeaseMeteringPending", "machine cleanup succeeded but durable commercial metering is pending retry",
      true,
    )
  }
  json_reply(200, transitioned.to_json())
}

///|
async fn ApiService::node_exists(self : ApiService, node_id : String) -> Bool {
  self.store.heartbeats().any(heartbeat => heartbeat.node_id == node_id)
}

///|
pub async fn ApiService::reconcile_expired_exclusive_leases(
  self : ApiService,
) -> Unit {
  guard self.exclusive_lease_store is Some(leases) else { return }
  let before = leases.leases()
  let now = @async.now()
  let changed_any = leases.reconcile_expired(now)
  let after = leases.leases()
  for lease in after {
    let changed = before
      .iter()
      .find_first(previous => previous.intent.lease_id == lease.intent.lease_id)
      .map(previous => previous.generation != lease.generation)
      .unwrap_or(false)
    if changed {
      match self.credential_handoff_store {
        Some(credentials) =>
          ignore(credentials.revoke_for_lease(lease.intent.lease_id, now))
        None => ()
      }
      self.publish_exclusive_lease_directive(
        lease,
        directive_state_for_exclusive_lease(lease.state),
      )
      self.operator_audit(
        "exclusive-lease.expire",
        lease.intent.lease_id,
        lease.authority_receipt,
      )
    }
    if lease.state == Completed {
      ignore(self.meter_completed_exclusive_lease(lease))
    }
  }
  self.record_component_event(
    "event-exclusive-lease-expiry-reconcile-\{now}",
    now,
    Information,
    "controller",
    "ExclusiveLeaseExpiryReconciliationCompleted",
    "exclusive-lease-expiry-reconcile-\{now}",
    "exclusive_lease",
    "healthy",
    200,
    0L,
  )
  ignore(changed_any)
}

///| Controller-owned clock reconciliation. Failures propagate to the structured

///|
/// supervisor so the process cannot remain Ready with a dead expiry loop.
pub async fn ApiService::run_exclusive_lease_expiry_reconciler_forever(
  self : ApiService,
  interval_ms : Int,
) -> Unit {
  if interval_ms < 1000 || interval_ms > 300000 {
    raise Failure::Failure("exclusive lease reconcile interval is invalid")
  }
  for ;; {
    self.reconcile_expired_exclusive_leases()
    @async.sleep(interval_ms)
  }
}

///|
async fn ApiService::begin_exclusive_provisioning_if_drained(
  self : ApiService,
  lease : @nodelease.ExclusiveNodeLease,
) -> @nodelease.ExclusiveNodeLease {
  guard lease.state == Reserved && self.exclusive_lease_store is Some(leases) else {
    return lease
  }
  let now = @async.now()
  if now < lease.intent.starts_unix_ms ||
    now >= lease.intent.expires_unix_ms ||
    self.store
    .assignments()
    .any(assignment => {
      assignment.node_id == lease.intent.node_id &&
      assignment.lease_expires_unix_ms > now
    }) ||
    self.store
    .heartbeats()
    .any(heartbeat => {
      heartbeat.node_id == lease.intent.node_id &&
      heartbeat.running_deployments.length() > 0
    }) {
    return lease
  }
  let provisioning = try
    leases.transition(
      lease.intent.lease_id,
      {
        expected_generation: lease.generation,
        state: Provisioning,
        evidence_receipt: "controller:node-drained",
      },
      now,
    )
  catch {
    _ => return leases.lease(lease.intent.lease_id).unwrap_or(lease)
  } noraise {
    value => value
  }
  self.publish_exclusive_lease_directive(provisioning, Cordoned)
  self.operator_audit(
    "exclusive-lease.begin-provisioning",
    provisioning.intent.lease_id,
    provisioning.authority_receipt,
  )
  provisioning
}

///|
fn directive_state_for_exclusive_lease(
  state : @nodelease.ExclusiveLeaseState,
) -> @contracts.NodeState {
  match state {
    Completed | Cancelled => Active
    Expiring | Draining | RevokingAccess | Sanitizing => Draining
    Requested | Reserved | Provisioning | Active | Quarantined => Cordoned
  }
}

///|
async fn ApiService::publish_exclusive_lease_directive(
  self : ApiService,
  lease : @nodelease.ExclusiveNodeLease,
  desired_state : @contracts.NodeState,
) -> Unit {
  let node_id = lease.intent.node_id
  let receipt_prefix = "exclusive-lease:\{lease.intent.lease_id}:"
  let current = self.store.node_directive(node_id)
  if current is Some(directive) &&
    directive.desired_state == desired_state &&
    directive.receipt.has_prefix(receipt_prefix) &&
    directive.receipt.has_suffix(":\{lease.generation}") {
    return
  }
  let mut generation = 1L
  if current is Some(directive) && generation <= directive.generation {
    generation = directive.generation + 1L
  }
  for heartbeat in self.store.heartbeats() {
    if heartbeat.node_id == node_id &&
      generation <= heartbeat.observed_generation {
      generation = heartbeat.observed_generation + 1L
    }
  }
  let directive : @contracts.NodeDirective = {
    node_id,
    desired_state,
    generation,
    issued_unix_ms: @async.now(),
    receipt: "\{receipt_prefix}node-mode:\{lease.generation}",
  }
  self.with_audit_lock(() => {
    let audit = self.next_audit(
      "exclusive-lease-authority",
      "node.mode",
      node_id,
      "managed-or-previous",
      "\{Repr(desired_state)}",
      "accepted",
      directive.receipt,
      directive.issued_unix_ms,
    )
    self.store.commit_node_directive(directive, audit)
  })
}

///|
async fn ApiService::handle_exclusive_lease_management(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if !self.operator_authorized(headers) {
    return api_error(
      401, "Unauthenticated", "valid operator authority is required", false,
    )
  }
  guard self.exclusive_lease_store is Some(leases) else {
    return api_error(
      503, "ExclusiveLeaseUnavailable", "durable exclusive-node lease authority is unavailable",
      true,
    )
  }
  self.reconcile_expired_exclusive_leases()
  match (verb, path) {
    (Get, "/v1/exclusive-node-leases") =>
      json_reply(200, leases.leases().to_json())
    (Post, "/v1/exclusive-node-leases") => {
      guard decode_exclusive_lease_intent(body) is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid exclusive-node lease intent", false,
        )
      }
      if !self.node_exists(intent.node_id) {
        return api_error(
          409, "NodeUnavailable", "exclusive lease node is not enrolled", false,
        )
      }
      let accepted = try leases.issue(intent, @async.now()) catch {
        @nodelease_store.ExclusiveLeaseStoreError::IdempotencyConflict(_) =>
          return api_error(
            409, "IdempotencyConflict", "idempotency key already identifies a different lease",
            false,
          )
        @nodelease_store.ExclusiveLeaseStoreError::NodeUnavailable(_) =>
          return api_error(
            409, "NodeUnavailable", "node already has an exclusive lease", false,
          )
        _ =>
          return api_error(
            400, "ExclusiveLeaseRejected", "exclusive lease was rejected", false,
          )
      } noraise {
        value => value
      }
      let now = @async.now()
      let has_managed_work = self.store
        .assignments()
        .any(assignment => {
          assignment.node_id == intent.node_id &&
          assignment.lease_expires_unix_ms > now
        }) ||
        self.store
        .heartbeats()
        .any(heartbeat => {
          heartbeat.node_id == intent.node_id &&
          heartbeat.running_deployments.length() > 0
        })
      self.publish_exclusive_lease_directive(
        accepted,
        if has_managed_work {
          Draining
        } else {
          Cordoned
        },
      )
      self.operator_audit(
        "exclusive-lease.reserve",
        accepted.intent.lease_id,
        accepted.authority_receipt,
      )
      json_reply(201, accepted.to_json())
    }
    (Get, _) => {
      let lease_id = path["/v1/exclusive-node-leases/".length():].to_owned()
      if lease_id == "" ||
        lease_id.has_suffix(":transition") ||
        lease_id.has_suffix(":terminate") {
        return api_error(404, "NotFound", "route was not found", false)
      }
      match leases.lease(lease_id) {
        Some(lease) => json_reply(200, lease.to_json())
        None =>
          api_error(
            404, "NotFound", "exclusive-node lease was not found", false,
          )
      }
    }
    (Post, _) if path.has_suffix(":terminate") => {
      let prefix = "/v1/exclusive-node-leases/".length()
      let suffix = ":terminate".length()
      let lease_id = path[prefix:path.length() - suffix].to_owned()
      guard decode_exclusive_lease_termination(body) is Some(request) &&
        @contracts.valid_identifier(request.reason, maximum_length=256) else {
        return api_error(
          400, "InvalidRequest", "invalid exclusive-node termination request", false,
        )
      }
      guard leases.lease(lease_id) is Some(current) else {
        return api_error(
          404, "NotFound", "exclusive-node lease was not found", false,
        )
      }
      if request.expected_generation != current.generation {
        return api_error(
          409, "StaleGeneration", "exclusive lease generation is stale", false,
        )
      }
      let target = match current.state {
        Requested => Some(@nodelease.ExclusiveLeaseState::Cancelled)
        Reserved | Provisioning | Active => Some(Expiring)
        Quarantined => Some(RevokingAccess)
        Expiring
        | Draining
        | RevokingAccess
        | Sanitizing
        | Completed
        | Cancelled => None
      }
      let terminated = match target {
        None => current
        Some(state) =>
          try
            leases.transition(
              lease_id,
              {
                expected_generation: current.generation,
                state,
                evidence_receipt: "operator:terminate:\{request.reason}",
              },
              @async.now(),
            )
          catch {
            @nodelease.ExclusiveLeaseError::StaleGeneration =>
              return api_error(
                409, "StaleGeneration", "exclusive lease generation is stale", false,
              )
            _ =>
              return api_error(
                409, "InvalidTransition", "exclusive lease termination was rejected",
                false,
              )
          } noraise {
            value => value
          }
      }
      self.publish_exclusive_lease_directive(
        terminated,
        directive_state_for_exclusive_lease(terminated.state),
      )
      self.operator_audit(
        "exclusive-lease.terminate",
        lease_id,
        terminated.authority_receipt,
      )
      json_reply(202, terminated.to_json())
    }
    (Post, _) if path.has_suffix(":transition") =>
      api_error(
        409, "NodeEvidenceRequired", "exclusive lease transitions are reconciled from verified node evidence",
        false,
      )
    _ => api_error(404, "NotFound", "route was not found", false)
  }
}
