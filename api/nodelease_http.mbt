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
      "sanitize" => {
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
  if !bearer_authorized(headers, self.operator_token) {
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
