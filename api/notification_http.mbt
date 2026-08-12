///|
fn notification_path(path : String) -> Bool {
  path == "/v1/notifications/operator" ||
  path.has_prefix("/v1/notifications/operator/") ||
  path == "/v1/notifications/self" ||
  path.has_prefix("/v1/notifications/self/")
}

///|
priv struct NotificationGenerationRequest {
  expected_generation : Int64
} derive(FromJson)

///|
priv struct NotificationSilenceRequest {
  expected_generation : Int64
  silenced_until_unix_ms : Int64
} derive(FromJson)

///|
priv struct NotificationAssignmentRequest {
  expected_generation : Int64
  assignee_ref : String?
} derive(FromJson)

///|
fn decode_notification_generation(
  body : String,
) -> NotificationGenerationRequest? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn decode_notification_silence(body : String) -> NotificationSilenceRequest? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn decode_notification_assignment(
  body : String,
) -> NotificationAssignmentRequest? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn notification_error_reply(error : Error) -> HttpReply {
  match error {
    @notifications.NotificationError::Unauthorized =>
      api_error(
        403, "NotificationAccessDenied", "notification access is denied", false,
      )
    @notifications.NotificationError::NotFound(_) =>
      api_error(404, "NotFound", "notification was not found", false)
    @notifications.NotificationError::StaleGeneration =>
      api_error(
        409, "StaleGeneration", "notification changed; refresh before retrying",
        true,
      )
    @notifications.NotificationError::InvalidTransition(_) =>
      api_error(
        409, "InvalidTransition", "notification transition is not allowed", false,
      )
    _ =>
      api_error(
        400, "NotificationRejected", "notification request was rejected", false,
      )
  }
}

///|
async fn ApiService::refresh_node_health_notifications(
  self : ApiService,
  now_unix_ms : Int64,
) -> Unit {
  guard self.notification_store is Some(notifications) else { return }
  for heartbeat in self.store.heartbeats() {
    let deduplication_key = "node-unreachable-\{heartbeat.node_id}"
    let unhealthy = heartbeat.state == Unreachable ||
      now_unix_ms - heartbeat.timestamp_unix_ms >
      self.global_settings.control_timing.heartbeat_timeout_ms
    match
      notifications.record_by_deduplication_key(
        deduplication_key,
        PlatformOperators,
      ) {
      Some(record) if unhealthy && record.lifecycle != Resolved => ()
      Some(record) if unhealthy && record.lifecycle == Resolved =>
        ignore(
          notifications.enqueue({
            version: @notifications.contract_version,
            notification_id: "alert-node-unreachable-\{heartbeat.node_id}-\{now_unix_ms}",
            deduplication_key,
            source_receipt: "node-health:\{heartbeat.node_id}:\{now_unix_ms}",
            topic: ClusterHealth,
            code: "NodeUnreachable",
            severity: Critical,
            audience: PlatformOperators,
            title_key: "alerts.node_unreachable.title",
            body_key: "alerts.node_unreachable.body",
            parameters: { "node_ref": heartbeat.node_id },
            created_unix_ms: now_unix_ms,
            expires_unix_ms: None,
          }),
        )
      Some(record) if !unhealthy && record.lifecycle != Resolved =>
        ignore(
          notifications.resolve_operator({
            notification_id: record.event.notification_id,
            expected_generation: record.generation,
            actor_ref: "controller-reconciler",
            now_unix_ms,
          }),
        )
      Some(_) => ()
      None if unhealthy =>
        ignore(
          notifications.enqueue({
            version: @notifications.contract_version,
            notification_id: "alert-node-unreachable-\{heartbeat.node_id}-\{now_unix_ms}",
            deduplication_key,
            source_receipt: "node-health:\{heartbeat.node_id}:\{now_unix_ms}",
            topic: ClusterHealth,
            code: "NodeUnreachable",
            severity: Critical,
            audience: PlatformOperators,
            title_key: "alerts.node_unreachable.title",
            body_key: "alerts.node_unreachable.body",
            parameters: { "node_ref": heartbeat.node_id },
            created_unix_ms: now_unix_ms,
            expires_unix_ms: None,
          }),
        )
      None => ()
    }
  }
}

///|
async fn ApiService::refresh_delivery_health_notifications(
  self : ApiService,
  now_unix_ms : Int64,
) -> Unit {
  guard self.notification_store is Some(store) else { return }
  let dead_letters = store.snapshot().deliveries.count_if(delivery => {
    delivery.state == DeadLetter
  })
  let deduplication_key = "notification-delivery-dead-letter"
  match
    store.record_by_deduplication_key(deduplication_key, PlatformOperators) {
    Some(record) if dead_letters == 0 && record.lifecycle != Resolved =>
      ignore(
        store.resolve_operator({
          notification_id: record.event.notification_id,
          expected_generation: record.generation,
          actor_ref: "controller-reconciler",
          now_unix_ms,
        }),
      )
    Some(record) if dead_letters > 0 && record.lifecycle == Resolved =>
      ignore(
        store.enqueue({
          version: @notifications.contract_version,
          notification_id: "alert-delivery-dead-letter-\{now_unix_ms}",
          deduplication_key,
          source_receipt: "notification-delivery:dead-letter:\{now_unix_ms}",
          topic: DeliveryHealth,
          code: "DeliveryAttemptLimit",
          severity: Critical,
          audience: PlatformOperators,
          title_key: "alerts.delivery_failed.title",
          body_key: "alerts.delivery_failed.body",
          parameters: { "count": dead_letters.to_string() },
          created_unix_ms: now_unix_ms,
          expires_unix_ms: None,
        }),
      )
    Some(_) => ()
    None if dead_letters > 0 =>
      ignore(
        store.enqueue({
          version: @notifications.contract_version,
          notification_id: "alert-delivery-dead-letter-\{now_unix_ms}",
          deduplication_key,
          source_receipt: "notification-delivery:dead-letter:\{now_unix_ms}",
          topic: DeliveryHealth,
          code: "DeliveryAttemptLimit",
          severity: Critical,
          audience: PlatformOperators,
          title_key: "alerts.delivery_failed.title",
          body_key: "alerts.delivery_failed.body",
          parameters: { "count": dead_letters.to_string() },
          created_unix_ms: now_unix_ms,
          expires_unix_ms: None,
        }),
      )
    None => ()
  }
}

///|
async fn ApiService::enqueue_subject_notification(
  self : ApiService,
  tenant_ref : String,
  subject_ref : String,
  code : String,
  topic : @notifications.NotificationTopic,
  severity : @notifications.NotificationSeverity,
  resource_ref : String,
  source_receipt : String,
  parameters : Map[String, String],
  now_unix_ms : Int64,
) -> Unit {
  guard self.notification_store is Some(store) else { return }
  let audience = @notifications.NotificationAudience::Subject(
    tenant_ref~,
    subject_ref~,
  )
  let deduplication_key = "subject-\{code}-\{resource_ref}"
  if store.record_by_deduplication_key(deduplication_key, audience) is Some(_) {
    return
  }
  ignore(
    store.enqueue({
      version: @notifications.contract_version,
      notification_id: "notice-\{code}-\{resource_ref}",
      deduplication_key,
      source_receipt,
      topic,
      code,
      severity,
      audience,
      title_key: "notifications.\{code}.title",
      body_key: "notifications.\{code}.body",
      parameters,
      created_unix_ms: now_unix_ms,
      expires_unix_ms: None,
    }),
  )
}

///|
async fn ApiService::refresh_subject_notifications(
  self : ApiService,
  tenant_ref : String,
  subject_ref : String,
  now_unix_ms : Int64,
) -> Unit {
  guard self.portal_store is Some(portal) else { return }
  let view = portal.self_view(subject_ref) catch { _ => return }
  for request in view.lease_requests {
    if request.state == Approved && request.subject_ref == subject_ref {
      self.enqueue_subject_notification(
        tenant_ref,
        subject_ref,
        "LeaseRequestApproved",
        LeaseLifecycle,
        Information,
        request.submission.request_id,
        "portal-lease:\{request.submission.request_id}:\{request.generation}",
        Map([
          ("request_ref", request.submission.request_id),
          ("lease_ref", request.exclusive_lease_id.unwrap_or("pending")),
        ]),
        now_unix_ms,
      )
    }
  }
  guard self.exclusive_lease_store is Some(leases) else { return }
  for lease in leases.leases() {
    if lease.intent.subject_ref != subject_ref {
      continue
    }
    let lease_ref = lease.intent.lease_id
    let parameters = Map([
      ("lease_ref", lease_ref),
      ("handoff_status", "managed-reference-available"),
      ("expires_unix_ms", lease.intent.expires_unix_ms.to_string()),
    ])
    match lease.state {
      Active => {
        self.enqueue_subject_notification(
          tenant_ref,
          subject_ref,
          "LeaseAccessReady",
          AccessCredential,
          Information,
          lease_ref,
          "exclusive-lease:\{lease_ref}:active:\{lease.generation}",
          parameters,
          now_unix_ms,
        )
        let remaining = lease.intent.expires_unix_ms - now_unix_ms
        let expiry_window = if remaining > 0L && remaining <= 3600000L {
          Some("1h")
        } else if remaining > 0L && remaining <= 86400000L {
          Some("24h")
        } else if remaining > 0L && remaining <= 259200000L {
          Some("72h")
        } else {
          None
        }
        if expiry_window is Some(window) {
          self.enqueue_subject_notification(
            tenant_ref,
            subject_ref,
            "LeaseExpiring",
            LeaseLifecycle,
            Warning,
            "\{lease_ref}-\{window}",
            "exclusive-lease:\{lease_ref}:expiry-\{window}",
            parameters,
            now_unix_ms,
          )
        }
      }
      Expiring =>
        self.enqueue_subject_notification(
          tenant_ref,
          subject_ref,
          "LeaseExpiring",
          LeaseLifecycle,
          Warning,
          lease_ref,
          "exclusive-lease:\{lease_ref}:expiring:\{lease.generation}",
          parameters,
          now_unix_ms,
        )
      Draining | RevokingAccess | Sanitizing =>
        self.enqueue_subject_notification(
          tenant_ref,
          subject_ref,
          "LeaseTerminating",
          LeaseLifecycle,
          Warning,
          lease_ref,
          "exclusive-lease:\{lease_ref}:terminating",
          parameters,
          now_unix_ms,
        )
      Completed | Cancelled =>
        self.enqueue_subject_notification(
          tenant_ref,
          subject_ref,
          "LeaseCompleted",
          LeaseLifecycle,
          Information,
          lease_ref,
          "exclusive-lease:\{lease_ref}:completed",
          parameters,
          now_unix_ms,
        )
      Quarantined =>
        self.enqueue_subject_notification(
          tenant_ref,
          subject_ref,
          "LeaseTerminating",
          AccessCredential,
          Critical,
          "\{lease_ref}-quarantined",
          "exclusive-lease:\{lease_ref}:quarantined",
          parameters,
          now_unix_ms,
        )
      Requested | Reserved | Provisioning => ()
    }
  }
}

///|
fn notification_action_path(
  path : String,
  prefix : String,
) -> (String, String)? {
  if !path.has_prefix(prefix) {
    return None
  }
  let suffix = path[prefix.length():].to_owned()
  for action in [":read", ":acknowledge", ":resolve", ":silence", ":assign"] {
    if suffix.has_suffix(action) {
      let notification_id = suffix[:suffix.length() - action.length()].to_owned()
      if @contracts.valid_identifier(notification_id) {
        return Some((notification_id, action))
      }
    }
  }
  None
}

///|
async fn ApiService::notification_subject_context(
  self : ApiService,
  headers : Map[String, String],
  allow_asserted_subject : Bool,
) -> (String, String)? {
  guard self.portal_store is Some(portal) &&
    self.portal_subject(headers, allow_asserted_subject) is Some(subject_ref) else {
    return None
  }
  try portal.self_view(subject_ref) catch {
    _ => None
  } noraise {
    view => Some((view.membership.tenant_ref, subject_ref))
  }
}

///|
async fn ApiService::handle_notifications(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.notification_store is Some(store) else {
    return api_error(
      503, "NotificationsUnavailable", "durable notification authority is unavailable",
      true,
    )
  }
  let now = @async.now()
  if path == "/v1/notifications/operator" {
    if !bearer_authorized(headers, self.operator_token) {
      return api_error(
        401, "Unauthorized", "operator authorization is required", false,
      )
    }
    if verb != Get {
      return api_error(
        405, "MethodNotAllowed", "operator alert listing requires GET", false,
      )
    }
    self.refresh_node_health_notifications(now)
    self.refresh_delivery_health_notifications(now)
    return json_reply(200, store.records_for_operators(now).to_json())
  }
  if path == "/v1/notifications/self" {
    guard self.notification_subject_context(headers, allow_asserted_subject)
      is Some((tenant_ref, subject_ref)) else {
      return api_error(
        401, "Unauthorized", "trusted portal identity is required", false,
      )
    }
    if verb != Get {
      return api_error(
        405, "MethodNotAllowed", "notification inbox listing requires GET", false,
      )
    }
    self.refresh_subject_notifications(tenant_ref, subject_ref, now)
    return json_reply(
      200,
      store.records_for_subject(tenant_ref, subject_ref, now).to_json(),
    )
  }
  if notification_action_path(path, "/v1/notifications/self/")
    is Some((notification_id, action)) {
    if action != ":read" || verb != Post {
      return api_error(
        405, "MethodNotAllowed", "notification read action requires POST", false,
      )
    }
    guard self.notification_subject_context(headers, allow_asserted_subject)
      is Some((tenant_ref, subject_ref)) else {
      return api_error(
        401, "Unauthorized", "trusted portal identity is required", false,
      )
    }
    guard decode_notification_generation(body) is Some(request) else {
      return api_error(
        400, "InvalidRequest", "expected generation is required", false,
      )
    }
    return json_reply(
      200,
      store
      .mark_read_for_subject(tenant_ref, subject_ref, {
        notification_id,
        expected_generation: request.expected_generation,
        actor_ref: subject_ref,
        now_unix_ms: now,
      })
      .to_json(),
    ) catch {
      error => notification_error_reply(error)
    }
  }
  if notification_action_path(path, "/v1/notifications/operator/")
    is Some((notification_id, action)) {
    if !bearer_authorized(headers, self.operator_token) {
      return api_error(
        401, "Unauthorized", "operator authorization is required", false,
      )
    }
    if verb != Post {
      return api_error(
        405, "MethodNotAllowed", "operator alert action requires POST", false,
      )
    }
    return try {
      let record = match action {
        ":acknowledge" => {
          guard decode_notification_generation(body) is Some(request) else {
            return api_error(
              400, "InvalidRequest", "expected generation is required", false,
            )
          }
          store.acknowledge_operator({
            notification_id,
            expected_generation: request.expected_generation,
            actor_ref: "platform-operator",
            now_unix_ms: now,
          })
        }
        ":resolve" => {
          guard decode_notification_generation(body) is Some(request) else {
            return api_error(
              400, "InvalidRequest", "expected generation is required", false,
            )
          }
          store.resolve_operator({
            notification_id,
            expected_generation: request.expected_generation,
            actor_ref: "platform-operator",
            now_unix_ms: now,
          })
        }
        ":silence" => {
          guard decode_notification_silence(body) is Some(request) else {
            return api_error(
              400, "InvalidRequest", "bounded silence is required", false,
            )
          }
          store.silence_operator({
            notification_id,
            expected_generation: request.expected_generation,
            actor_ref: "platform-operator",
            now_unix_ms: now,
            silenced_until_unix_ms: request.silenced_until_unix_ms,
          })
        }
        ":assign" => {
          guard decode_notification_assignment(body) is Some(request) else {
            return api_error(
              400, "InvalidRequest", "valid assignment is required", false,
            )
          }
          store.assign_operator({
            notification_id,
            expected_generation: request.expected_generation,
            actor_ref: "platform-operator",
            assignee_ref: request.assignee_ref,
            now_unix_ms: now,
          })
        }
        _ =>
          return api_error(
            404, "NotFound", "notification action was not found", false,
          )
      }
      self.operator_audit(
        "notification.\{action[1:]}",
        notification_id,
        "accepted",
      )
      json_reply(200, record.to_json())
    } catch {
      error => notification_error_reply(error)
    }
  }
  api_error(404, "NotFound", "notification route was not found", false)
}
