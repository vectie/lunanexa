///|
fn customer_machine_access_path(path : String) -> Bool {
  path == "/v1/machine-access/self" ||
  path.has_prefix("/v1/machine-access/self/")
}

///|
fn decode_customer_machine_termination(
  body : String,
) -> @nodelease.CustomerExclusiveLeaseTerminationRequest? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn customer_machine_termination_lease_id(path : String) -> String? {
  let prefix = "/v1/machine-access/self/"
  let suffix = ":terminate"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return None
  }
  let lease_id = path[prefix.length():path.length() - suffix.length()].to_owned()
  if @contracts.valid_identifier(lease_id) {
    Some(lease_id)
  } else {
    None
  }
}

///|
async fn ApiService::customer_machine_heartbeat_time(
  self : ApiService,
  node_id : String,
) -> Int64? {
  for heartbeat in self.store.heartbeats() {
    if heartbeat.node_id == node_id &&
      heartbeat.state != Unreachable &&
      heartbeat.state != Retired {
      return Some(heartbeat.timestamp_unix_ms)
    }
  }
  None
}

///|
async fn ApiService::customer_machine_view(
  self : ApiService,
  lease : @nodelease.ExclusiveNodeLease,
  now_unix_ms : Int64,
) -> @nodelease.CustomerExclusiveMachineView {
  @nodelease.customer_machine_view(
    lease,
    self.customer_machine_heartbeat_time(lease.intent.node_id),
    now_unix_ms,
    self.global_settings.control_timing.heartbeat_timeout_ms,
  )
}

///|
async fn ApiService::customer_machine_audit(
  self : ApiService,
  subject_ref : String,
  lease : @nodelease.ExclusiveNodeLease,
  prior_state : @nodelease.ExclusiveLeaseState,
  now_unix_ms : Int64,
) -> Unit {
  self.with_audit_lock(() => {
    let event = self.next_audit(
      "portal-subject:\{subject_ref}",
      "exclusive-lease.customer-terminate",
      lease.intent.lease_id,
      "\{Repr(prior_state)}",
      "\{Repr(lease.state)}",
      "accepted",
      lease.authority_receipt,
      now_unix_ms,
    )
    self.store.append_audit(event)
  })
}

///|
async fn ApiService::customer_machine_operator_notification(
  self : ApiService,
  lease : @nodelease.ExclusiveNodeLease,
  subject_ref : String,
  now_unix_ms : Int64,
) -> Unit {
  guard self.notification_store is Some(notifications) else { return }
  let lease_ref = lease.intent.lease_id
  ignore(
    notifications.enqueue({
      version: @notifications.contract_version,
      notification_id: "alert-customer-termination-\{lease_ref}-\{lease.generation}",
      deduplication_key: "customer-termination-\{lease_ref}",
      source_receipt: "customer-termination:\{lease_ref}:\{lease.generation}",
      topic: LeaseLifecycle,
      code: "CustomerTerminationRequested",
      severity: Warning,
      audience: PlatformOperators,
      title_key: "alerts.customer_termination.title",
      body_key: "alerts.customer_termination.body",
      parameters: {
        "lease_ref": lease_ref,
        "machine_ref": "assigned-machine:\{lease_ref}",
        "subject_ref": subject_ref,
      },
      created_unix_ms: now_unix_ms,
      expires_unix_ms: None,
    }),
  ) catch {
    // Lease termination remains authoritative. The durable lifecycle/audit
    // record lets the notification reconciler repair this secondary signal.
    _ => ()
  }
}

///|
/// Customer machine access is authorized by both the verified portal identity
/// and the lease's subject. A missing/cross-subject lease is always returned as
/// NotFound so the endpoint cannot enumerate another tenant's records.
async fn ApiService::handle_customer_machine_access(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.portal_store is Some(portal) &&
    self.exclusive_lease_store is Some(leases) else {
    return api_error(
      503, "MachineAccessUnavailable", "durable portal and exclusive-machine state are required",
      true,
    )
  }
  guard self.portal_subject(headers, allow_asserted_subject)
    is Some(subject_ref) else {
    return api_error(
      401, "Unauthenticated", "verified enterprise identity is required", false,
    )
  }
  let portal_view = try portal.self_view(subject_ref) catch {
    error => return portal_error_reply(error)
  } noraise {
    value => value
  }
  self.reconcile_expired_exclusive_leases()
  let now = @async.now()
  let subject_leases = leases.leases_for_subject(subject_ref)
  match (verb, path) {
    (Get, "/v1/machine-access/self") => {
      let views : Array[@nodelease.CustomerExclusiveMachineView] = []
      for lease in subject_leases {
        views.push(self.customer_machine_view(lease, now))
      }
      return json_reply(200, views.to_json())
    }
    (Post, _) => {
      guard customer_machine_termination_lease_id(path) is Some(lease_id) else {
        return api_error(
          404, "NotFound", "machine access route was not found", false,
        )
      }
      guard subject_leases
        .iter()
        .find_first(lease => lease.intent.lease_id == lease_id)
        is Some(current) else {
        return api_error(
          404, "NotFound", "machine access record was not found", false,
        )
      }
      guard decode_customer_machine_termination(body) is Some(request) &&
        @contracts.valid_identifier(request.reason, maximum_length=128) &&
        request.confirmation ==
        @nodelease.customer_termination_confirmation(lease_id) else {
        return api_error(
          400, "ConfirmationRequired", "type the exact lease-specific confirmation before terminating access",
          false,
        )
      }
      if request.expected_generation != current.generation {
        return api_error(
          409, "StaleGeneration", "machine access changed; refresh before retrying",
          true,
        )
      }
      guard @nodelease.customer_termination_target(current.state)
        is Some(target) else {
        return api_error(
          409, "TerminationInProgress", "machine access is already closing or closed",
          false,
        )
      }
      let transitioned = try
        leases.transition(
          lease_id,
          {
            expected_generation: request.expected_generation,
            state: target,
            evidence_receipt: "portal-subject:terminate:\{request.reason}",
          },
          now,
        )
      catch {
        @nodelease.ExclusiveLeaseError::StaleGeneration =>
          return api_error(
            409, "StaleGeneration", "machine access changed; refresh before retrying",
            true,
          )
        _ =>
          return api_error(
            409, "TerminationRejected", "machine access termination was rejected",
            false,
          )
      } noraise {
        value => value
      }
      self.publish_exclusive_lease_directive(
        transitioned,
        directive_state_for_exclusive_lease(transitioned.state),
      )
      self.customer_machine_audit(subject_ref, transitioned, current.state, now)
      self.customer_machine_operator_notification(
        transitioned, subject_ref, now,
      )
      self.refresh_subject_notifications(
        portal_view.membership.tenant_ref,
        subject_ref,
        now,
      )
      return json_reply(
        202,
        self.customer_machine_view(transitioned, now).to_json(),
      )
    }
    _ =>
      return api_error(
        405, "MethodNotAllowed", "machine access supports listing and confirmed termination",
        false,
      )
  }
}
