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
fn decode_exclusive_lease_transition(
  body : String,
) -> @nodelease.ExclusiveLeaseTransitionRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
async fn ApiService::node_exists(self : ApiService, node_id : String) -> Bool {
  self.store.heartbeats().any(heartbeat => heartbeat.node_id == node_id)
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
      if lease_id == "" || lease_id.has_suffix(":transition") {
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
    (Post, _) if path.has_suffix(":transition") => {
      let prefix = "/v1/exclusive-node-leases/".length()
      let suffix = ":transition".length()
      let lease_id = path[prefix:path.length() - suffix].to_owned()
      guard decode_exclusive_lease_transition(body) is Some(request) else {
        return api_error(
          400, "InvalidRequest", "invalid exclusive-node lease transition", false,
        )
      }
      guard leases.lease(lease_id) is Some(current) else {
        return api_error(
          404, "NotFound", "exclusive-node lease was not found", false,
        )
      }
      let now = @async.now()
      if request.state == Active &&
        (
          now < current.intent.starts_unix_ms ||
          now >= current.intent.expires_unix_ms ||
          self.store
          .assignments()
          .any(assignment => {
            assignment.node_id == current.intent.node_id &&
            assignment.lease_expires_unix_ms > now
          }) ||
          self.store
          .heartbeats()
          .any(heartbeat => {
            heartbeat.node_id == current.intent.node_id &&
            heartbeat.running_deployments.length() > 0
          })
        ) {
        return api_error(
          409, "NodeNotDrained", "exclusive lease cannot activate before managed workloads are drained",
          true,
        )
      }
      let transitioned = try leases.transition(lease_id, request, now) catch {
        @nodelease.ExclusiveLeaseError::StaleGeneration =>
          return api_error(
            409, "StaleGeneration", "exclusive lease generation is stale", false,
          )
        _ =>
          return api_error(
            409, "InvalidTransition", "exclusive lease transition was rejected",
            false,
          )
      } noraise {
        value => value
      }
      self.publish_exclusive_lease_directive(
        transitioned,
        directive_state_for_exclusive_lease(transitioned.state),
      )
      self.operator_audit(
        "exclusive-lease.transition",
        lease_id,
        transitioned.authority_receipt,
      )
      json_reply(200, transitioned.to_json())
    }
    _ => api_error(404, "NotFound", "route was not found", false)
  }
}
