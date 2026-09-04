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
priv struct NotificationPreferenceRequest {
  topic : @notifications.NotificationTopic
  channels : Array[@notifications.NotificationChannel]
  minimum_severity : @notifications.NotificationSeverity
} derive(FromJson)

///|
priv struct NotificationRedriveRequest {
  expected_attempt_count : Int
  expected_updated_unix_ms : Int64
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
fn decode_notification_preference(
  body : String,
) -> NotificationPreferenceRequest? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn decode_notification_redrive(body : String) -> NotificationRedriveRequest? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn notification_topic_key(topic : @notifications.NotificationTopic) -> String {
  match topic {
    ClusterHealth => "cluster-health"
    ArtifactHealth => "artifact-health"
    WorkloadAdmission => "workload-admission"
    CommercialAction => "commercial-action"
    Reconciliation => "reconciliation"
    LeaseLifecycle => "lease-lifecycle"
    AccessCredential => "access-credential"
    GuideDiagnostics => "guide-diagnostics"
    DeliveryHealth => "delivery-health"
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
async fn ApiService::refresh_exclusive_lease_operator_notifications(
  self : ApiService,
  now_unix_ms : Int64,
) -> Unit {
  guard self.notification_store is Some(store) &&
    self.exclusive_lease_store is Some(leases) else {
    return
  }
  for lease in leases.leases() {
    let deduplication_key = "exclusive-lease-sanitization-\{lease.intent.lease_id}"
    let active = lease.state == Quarantined
    match
      store.record_by_deduplication_key(deduplication_key, PlatformOperators) {
      Some(record) if active && record.lifecycle != Resolved => ()
      Some(record) if !active && record.lifecycle != Resolved =>
        ignore(
          store.resolve_operator({
            notification_id: record.event.notification_id,
            expected_generation: record.generation,
            actor_ref: "controller-reconciler",
            now_unix_ms,
          }),
        )
      Some(record) if active && record.lifecycle == Resolved =>
        ignore(
          store.enqueue({
            version: @notifications.contract_version,
            notification_id: "alert-sanitization-failed-\{lease.intent.lease_id}-\{now_unix_ms}",
            deduplication_key,
            source_receipt: "exclusive-lease:\{lease.intent.lease_id}:quarantined:\{lease.generation}",
            topic: LeaseLifecycle,
            code: "LeaseSanitizationFailed",
            severity: Critical,
            audience: PlatformOperators,
            title_key: "alerts.lease_sanitization_failed.title",
            body_key: "alerts.lease_sanitization_failed.body",
            parameters: { "lease_ref": lease.intent.lease_id },
            created_unix_ms: now_unix_ms,
            expires_unix_ms: None,
          }),
        )
      Some(_) => ()
      None if active =>
        ignore(
          store.enqueue({
            version: @notifications.contract_version,
            notification_id: "alert-sanitization-failed-\{lease.intent.lease_id}-\{now_unix_ms}",
            deduplication_key,
            source_receipt: "exclusive-lease:\{lease.intent.lease_id}:quarantined:\{lease.generation}",
            topic: LeaseLifecycle,
            code: "LeaseSanitizationFailed",
            severity: Critical,
            audience: PlatformOperators,
            title_key: "alerts.lease_sanitization_failed.title",
            body_key: "alerts.lease_sanitization_failed.body",
            parameters: { "lease_ref": lease.intent.lease_id },
            created_unix_ms: now_unix_ms,
            expires_unix_ms: None,
          }),
        )
      None => ()
    }
  }
}

///|
async fn reconcile_platform_condition(
  store : @notification_store.NotificationStore,
  active : Bool,
  deduplication_key : String,
  code : String,
  topic : @notifications.NotificationTopic,
  severity : @notifications.NotificationSeverity,
  source_receipt : String,
  parameters : Map[String, String],
  now_unix_ms : Int64,
) -> Unit {
  match
    store.record_by_deduplication_key(deduplication_key, PlatformOperators) {
    Some(record) if active && record.lifecycle != Resolved => ()
    Some(record) if !active && record.lifecycle != Resolved =>
      ignore(
        store.resolve_operator({
          notification_id: record.event.notification_id,
          expected_generation: record.generation,
          actor_ref: "controller-reconciler",
          now_unix_ms,
        }),
      )
    Some(record) if active && record.lifecycle == Resolved =>
      ignore(
        store.enqueue({
          version: @notifications.contract_version,
          notification_id: "alert-\{code}-\{now_unix_ms}",
          deduplication_key,
          source_receipt,
          topic,
          code,
          severity,
          audience: PlatformOperators,
          title_key: "alerts.\{code}.title",
          body_key: "alerts.\{code}.body",
          parameters,
          created_unix_ms: now_unix_ms,
          expires_unix_ms: None,
        }),
      )
    Some(_) => ()
    None if active =>
      ignore(
        store.enqueue({
          version: @notifications.contract_version,
          notification_id: "alert-\{code}-\{now_unix_ms}",
          deduplication_key,
          source_receipt,
          topic,
          code,
          severity,
          audience: PlatformOperators,
          title_key: "alerts.\{code}.title",
          body_key: "alerts.\{code}.body",
          parameters,
          created_unix_ms: now_unix_ms,
          expires_unix_ms: None,
        }),
      )
    None => ()
  }
}

///|
async fn ApiService::refresh_production_health_notifications(
  self : ApiService,
  now_unix_ms : Int64,
) -> Unit {
  guard self.notification_store is Some(store) else { return }
  match self.management_database {
    Some(database) => {
      let available = database.ping()
      reconcile_platform_condition(
        store,
        !available,
        "postgres-availability",
        "PostgresUnavailable",
        Reconciliation,
        Critical,
        "database-health:postgres:\{now_unix_ms}",
        { "database": "management-postgres" },
        now_unix_ms,
      )
      self.record_component_event(
        "event-database-health-\{now_unix_ms}",
        now_unix_ms,
        if available {
          Information
        } else {
          Error
        },
        "controller",
        "ManagementDatabaseHealthChecked",
        "production-health-\{now_unix_ms}",
        "database",
        if available {
          "healthy"
        } else {
          "degraded"
        },
        if available {
          200
        } else {
          503
        },
        0L,
      )
    }
    None => ()
  }
  let epoch = self.store.controller_epoch()
  reconcile_platform_condition(
    store,
    !self.store.current_epoch_is_durable(),
    "controller-recovery-epoch-\{epoch}",
    "ControllerRecoveryIncomplete",
    Reconciliation,
    Critical,
    "controller-recovery:\{epoch}:\{now_unix_ms}",
    { "controller_epoch": epoch.to_string() },
    now_unix_ms,
  )
  match self.registry {
    Some(registry) => {
      let verifications = registry.snapshot().verifications
      let mut failed_count = 0
      for verification in verifications {
        let failed = !verification.signature_verified ||
          !verification.provenance_verified
        if failed {
          failed_count += 1
        }
        let reference = digest_hex(verification.digest)[:24]
        reconcile_platform_condition(
          store,
          failed,
          "artifact-verification-\{reference}",
          "ArtifactVerificationFailed",
          ArtifactHealth,
          Critical,
          "artifact-verification:\{reference}:\{verification.verified_unix_ms}",
          { "artifact_ref": "artifact-\{reference}" },
          now_unix_ms,
        )
      }
      self.record_component_event(
        "event-artifact-verification-health-\{now_unix_ms}",
        now_unix_ms,
        if failed_count > 0 {
          Error
        } else {
          Information
        },
        "controller",
        "ArtifactVerificationHealthReconciled",
        "production-health-\{now_unix_ms}",
        "artifact",
        if failed_count > 0 {
          "degraded"
        } else {
          "healthy"
        },
        if failed_count > 0 {
          503
        } else {
          200
        },
        0L,
      )
    }
    None => ()
  }
  match self.offline_commerce_store {
    Some(commerce) => {
      let snapshot = commerce.snapshot()
      for order in snapshot.orders {
        let overdue = order.state == UnderReconciliation &&
          now_unix_ms - order.updated_unix_ms >= 259200000L
        reconcile_platform_condition(
          store,
          overdue,
          "offline-review-overdue-\{order.order_id}",
          "OfflineReviewOverdue",
          Reconciliation,
          Warning,
          "offline-review:\{order.order_id}:\{order.generation}",
          { "order_ref": order.order_id },
          now_unix_ms,
        )
        reconcile_platform_condition(
          store,
          order.state == NeedsCorrection,
          "offline-reconciliation-failed-\{order.order_id}",
          "OfflineReconciliationNeedsCorrection",
          Reconciliation,
          Warning,
          "offline-reconciliation:\{order.order_id}:\{order.generation}",
          { "order_ref": order.order_id },
          now_unix_ms,
        )
      }
      for reversal in snapshot.reversals {
        reconcile_platform_condition(
          store,
          reversal.state == ReversalFailed,
          "commercial-reversal-failed-\{reversal.reversal_id}",
          "PaymentInvoiceReconciliationFailed",
          CommercialAction,
          Critical,
          "commercial-reversal:\{reversal.reversal_id}:\{reversal.expected_order_generation}",
          { "order_ref": reversal.order_id },
          now_unix_ms,
        )
      }
      let degraded = snapshot.orders.any(order => {
          order.state == NeedsCorrection ||
          (
            order.state == UnderReconciliation &&
            now_unix_ms - order.updated_unix_ms >= 259200000L
          )
        }) ||
        snapshot.reversals.any(reversal => reversal.state == ReversalFailed)
      self.record_component_event(
        "event-commercial-reconciliation-health-\{now_unix_ms}",
        now_unix_ms,
        if degraded {
          Error
        } else {
          Information
        },
        "controller",
        "CommercialReconciliationHealthReconciled",
        "production-health-\{now_unix_ms}",
        "commercial",
        if degraded {
          "degraded"
        } else {
          "healthy"
        },
        if degraded {
          503
        } else {
          200
        },
        0L,
      )
    }
    None => ()
  }
}

///| Runs one bounded reconciliation pass independently of browser traffic.

///| `cmd/control` schedules this method; the HTTP list routes also retain their

///|
/// repair-on-read behavior as defense in depth.
pub async fn ApiService::reconcile_notifications(
  self : ApiService,
  now_unix_ms : Int64,
) -> @notifications.NotificationReconciliationSummary {
  guard self.notification_store is Some(store) else {
    raise @notifications.NotificationError::InvalidInput(
      "durable notification authority is unavailable",
    )
  }
  if now_unix_ms <= 0L {
    raise @notifications.NotificationError::InvalidInput(
      "invalid reconciliation time",
    )
  }
  let started = @async.now()
  let expired_silences = store.expire_silences(now_unix_ms)
  self.refresh_node_health_notifications(now_unix_ms)
  self.refresh_delivery_health_notifications(now_unix_ms)
  self.refresh_exclusive_lease_operator_notifications(now_unix_ms)
  self.refresh_production_health_notifications(now_unix_ms)
  match self.observability_store {
    Some(operational) => {
      let recent_rejections = operational.recent_outcome_count(
        "ApiRequestCompleted",
        "workload",
        "rejected",
        (now_unix_ms - 300000L).max(1L),
      )
      let existing = store.record_by_deduplication_key(
        "workload-admission-rejections",
        PlatformOperators,
      )
      if recent_rejections < 5 {
        match existing {
          Some(record) if record.lifecycle != Resolved =>
            ignore(
              store.resolve_operator({
                notification_id: record.event.notification_id,
                expected_generation: record.generation,
                actor_ref: "controller-reconciler",
                now_unix_ms,
              }),
            )
          _ => ()
        }
      }
    }
    None => ()
  }
  let mut subject_count = 0
  match self.portal_store {
    Some(portal) =>
      for membership in portal.snapshot().memberships {
        if membership.active {
          self.refresh_subject_notifications(
            membership.tenant_ref,
            membership.organization_id,
            membership.subject_ref,
            now_unix_ms,
          )
          subject_count += 1
        }
      }
    None => ()
  }
  let snapshot = store.snapshot()
  let summary : @notifications.NotificationReconciliationSummary = {
    reconciled_unix_ms: now_unix_ms,
    subject_count,
    operator_alert_count: snapshot.records.count_if(record => {
      record.event.audience == PlatformOperators && record.lifecycle != Resolved
    }),
    expired_silence_count: expired_silences,
    pending_delivery_count: snapshot.deliveries.count_if(delivery => {
      delivery.state == PendingDelivery ||
      delivery.state == RetryScheduled ||
      delivery.state == Delivering
    }),
    dead_letter_count: snapshot.deliveries.count_if(delivery => {
      delivery.state == DeadLetter
    }),
  }
  let correlation = "notification-reconcile-\{now_unix_ms}"
  let duration = (@async.now() - started).max(0L)
  let node_degraded = self.store
    .heartbeats()
    .any(heartbeat => {
      heartbeat.state == Unreachable ||
      now_unix_ms - heartbeat.timestamp_unix_ms >
      self.global_settings.control_timing.heartbeat_timeout_ms
    })
  let lease_degraded = match self.exclusive_lease_store {
    Some(leases) => leases.leases().any(lease => lease.state == Quarantined)
    None => false
  }
  self.record_component_event(
    "event-notification-reconcile-\{now_unix_ms}",
    now_unix_ms,
    if summary.dead_letter_count > 0 {
      Error
    } else {
      Information
    },
    "controller",
    "NotificationReconciliationCompleted",
    correlation,
    "notification",
    if summary.dead_letter_count > 0 {
      "degraded"
    } else {
      "healthy"
    },
    if summary.dead_letter_count > 0 {
      503
    } else {
      200
    },
    duration,
  )
  self.record_component_event(
    "event-node-health-reconcile-\{now_unix_ms}",
    now_unix_ms,
    if node_degraded {
      Error
    } else {
      Information
    },
    "controller",
    "NodeHealthReconciled",
    correlation,
    "node",
    if node_degraded {
      "degraded"
    } else {
      "healthy"
    },
    if node_degraded {
      503
    } else {
      200
    },
    duration,
  )
  self.record_component_event(
    "event-exclusive-lease-reconcile-\{now_unix_ms}",
    now_unix_ms,
    if lease_degraded {
      Error
    } else {
      Information
    },
    "controller",
    "ExclusiveLeaseHealthReconciled",
    correlation,
    "exclusive_lease",
    if lease_degraded {
      "degraded"
    } else {
      "healthy"
    },
    if lease_degraded {
      503
    } else {
      200
    },
    duration,
  )
  self.record_component_event(
    "event-delivery-health-reconcile-\{now_unix_ms}",
    now_unix_ms,
    if summary.dead_letter_count > 0 {
      Error
    } else {
      Information
    },
    "controller",
    "NotificationDeliveryHealthReconciled",
    correlation,
    "notification_delivery",
    if summary.dead_letter_count > 0 {
      "degraded"
    } else {
      "healthy"
    },
    if summary.dead_letter_count > 0 {
      503
    } else {
      200
    },
    duration,
  )
  summary
}

///| Runs the autonomous notification repair loop. This is deliberately part

///| of the controller service rather than either browser application, so

///| alert creation, silence expiry, and 72/24/1-hour warnings continue while

///|
/// no user has a page open.
pub async fn ApiService::run_notification_reconciler_forever(
  self : ApiService,
  interval_ms : Int,
) -> Unit noraise {
  if interval_ms < 1000 || interval_ms > 300000 {
    return
  }
  for ;; {
    let now = @async.now()
    ignore(self.reconcile_notifications(now)) catch {
      _ =>
        ignore(
          self.record_component_event(
            "event-notification-reconcile-failed-\{now}",
            now,
            Error,
            "controller",
            "NotificationReconciliationFailed",
            "notification-reconcile-\{now}",
            "notification",
            "degraded",
            503,
            0L,
          ),
        ) catch {
          _ => ()
        }
    }
    ignore(@async.sleep(interval_ms)) catch {
      _ => return
    }
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
  organization_id : String,
  subject_ref : String,
  now_unix_ms : Int64,
) -> Unit {
  guard self.portal_store is Some(portal) else { return }
  let view = portal.self_view_for_organization(subject_ref, organization_id) catch {
    _ => return
  }
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
  let selected_lease_ids : Map[String, Unit] = Map([])
  for request in view.lease_requests {
    if request.subject_ref == subject_ref &&
      request.submission.tenant_ref == tenant_ref &&
      request.submission.organization_id == organization_id &&
      request.exclusive_lease_id is Some(lease_id) {
      selected_lease_ids[lease_id] = ()
    }
  }
  for lease in leases.leases() {
    if lease.intent.subject_ref != subject_ref ||
      !selected_lease_ids.contains(lease.intent.lease_id) {
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
) -> (String, String, String)? {
  guard self.portal_store is Some(portal) &&
    self.portal_subject(headers, allow_asserted_subject) is Some(subject_ref) else {
    return None
  }
  try portal_view_for_request(portal, subject_ref, headers) catch {
    _ => None
  } noraise {
    view =>
      Some(
        (
          view.membership.tenant_ref,
          view.membership.organization_id,
          subject_ref,
        ),
      )
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
  if path == "/v1/notifications/operator/readiness" {
    if !self.operator_authorized(headers) {
      return api_error(
        401, "Unauthorized", "operator authorization is required", false,
      )
    }
    if verb != Get {
      return api_error(
        405, "MethodNotAllowed", "notification readiness requires GET", false,
      )
    }
    return json_reply(
      200,
      store
      .delivery_readiness(self.notification_delivery_adapter_configured)
      .to_json(),
    )
  }
  if path == "/v1/notifications/operator/deliveries" {
    if !self.operator_authorized(headers) {
      return api_error(
        401, "Unauthorized", "operator authorization is required", false,
      )
    }
    if verb != Get {
      return api_error(
        405, "MethodNotAllowed", "notification delivery listing requires GET", false,
      )
    }
    return json_reply(200, store.snapshot().deliveries.to_json())
  }
  if path == "/v1/notifications/operator" {
    if !self.operator_authorized(headers) {
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
      is Some((tenant_ref, organization_id, subject_ref)) else {
      return api_error(
        401, "Unauthorized", "trusted portal identity is required", false,
      )
    }
    if verb != Get {
      return api_error(
        405, "MethodNotAllowed", "notification inbox listing requires GET", false,
      )
    }
    self.refresh_subject_notifications(
      tenant_ref, organization_id, subject_ref, now,
    )
    return json_reply(
      200,
      store.records_for_subject(tenant_ref, subject_ref, now).to_json(),
    )
  }
  if path == "/v1/notifications/self/preferences" {
    guard self.notification_subject_context(headers, allow_asserted_subject)
      is Some((tenant_ref, _, subject_ref)) else {
      return api_error(
        401, "Unauthorized", "trusted portal identity is required", false,
      )
    }
    match verb {
      Get =>
        return json_reply(
          200,
          store
          .preferences_for_subject(tenant_ref, subject_ref)
          .map(@notifications.preference_view)
          .to_json(),
        )
      Put => {
        guard decode_notification_preference(body) is Some(request) else {
          return api_error(
            400, "InvalidRequest", "valid notification preference is required", false,
          )
        }
        let topic_key = notification_topic_key(request.topic)
        let preference_scope = digest_hex(
            "notification-preference-v1|\{tenant_ref}|\{subject_ref}|\{topic_key}",
          )[:32]
        let channels = if request.channels.contains(InApp) {
          request.channels
        } else {
          [InApp, ..request.channels]
        }
        return json_reply(
          200,
          @notifications.preference_view(
            store.set_preference({
              preference_id: "preference-\{preference_scope}",
              tenant_ref,
              subject_ref,
              topic: request.topic,
              channels,
              minimum_severity: request.minimum_severity,
              updated_unix_ms: now,
            }),
          ).to_json(),
        ) catch {
          error => notification_error_reply(error)
        }
      }
      _ =>
        return api_error(
          405, "MethodNotAllowed", "notification preferences require GET or PUT",
          false,
        )
    }
  }
  if notification_action_path(path, "/v1/notifications/self/")
    is Some((notification_id, action)) {
    if action != ":read" || verb != Post {
      return api_error(
        405, "MethodNotAllowed", "notification read action requires POST", false,
      )
    }
    guard self.notification_subject_context(headers, allow_asserted_subject)
      is Some((tenant_ref, _, subject_ref)) else {
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
  let redrive_prefix = "/v1/notifications/operator/deliveries/"
  if path.has_prefix(redrive_prefix) && path.has_suffix(":redrive") {
    if !self.operator_authorized(headers) {
      return api_error(
        401, "Unauthorized", "operator authorization is required", false,
      )
    }
    if verb != Post {
      return api_error(
        405, "MethodNotAllowed", "delivery redrive requires POST", false,
      )
    }
    let delivery_id = path[redrive_prefix.length():path.length() -
    ":redrive".length()].to_owned()
    guard @contracts.valid_identifier(delivery_id) &&
      decode_notification_redrive(body) is Some(request) else {
      return api_error(
        400, "InvalidRequest", "generation-fenced redrive is required", false,
      )
    }
    return try {
      let receipt = store.redrive_dead_letter({
        delivery_id,
        expected_attempt_count: request.expected_attempt_count,
        expected_updated_unix_ms: request.expected_updated_unix_ms,
        actor_ref: "platform-operator",
        now_unix_ms: now,
      })
      self.operator_audit(
        "notification.delivery_redrive", delivery_id, "accepted",
      )
      json_reply(202, receipt.to_json())
    } catch {
      error => notification_error_reply(error)
    }
  }
  if notification_action_path(path, "/v1/notifications/operator/")
    is Some((notification_id, action)) {
    if !self.operator_authorized(headers) {
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
