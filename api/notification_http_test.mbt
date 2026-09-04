///|
async test "notification HTTP surface isolates tenant inbox and operator alerts" {
  let directory = @fs.tmpdir(prefix="lunanexa-notification-api-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let now = @async.now()
  ignore(
    portal.put_membership({
      membership_id: "member-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [Developer],
      active: true,
      created_unix_ms: now,
    }),
  )
  ignore(
    portal.put_membership({
      membership_id: "member-b",
      tenant_ref: "tenant-b",
      organization_id: "org-b",
      subject_ref: "subject-b",
      roles: [Developer],
      active: true,
      created_unix_ms: now,
    }),
  )
  ignore(
    notifications.enqueue({
      version: @notifications.contract_version,
      notification_id: "notice-subject-a",
      deduplication_key: "lease-a-ready",
      source_receipt: "audit:lease-a:ready",
      topic: LeaseLifecycle,
      code: "LeaseAccessReady",
      severity: Information,
      audience: Subject(tenant_ref="tenant-a", subject_ref="subject-a"),
      title_key: "notifications.lease_ready.title",
      body_key: "notifications.lease_ready.body",
      parameters: { "lease_id": "lease-a" },
      created_unix_ms: now,
      expires_unix_ms: Some(now + 60000L),
    }),
  )
  ignore(
    notifications.enqueue({
      version: @notifications.contract_version,
      notification_id: "alert-node-a",
      deduplication_key: "node-a-unreachable",
      source_receipt: "health:node-a:unreachable",
      topic: ClusterHealth,
      code: "NodeUnreachable",
      severity: Critical,
      audience: PlatformOperators,
      title_key: "alerts.node_unreachable.title",
      body_key: "alerts.node_unreachable.body",
      parameters: { "node_ref": "node-a" },
      created_unix_ms: now,
      expires_unix_ms: None,
    }),
  )
  let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_notification_store(notifications)
  let subject_a = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  let subject_b = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-b",
  }
  let inbox = service.handle(Get, "/v1/notifications/self", subject_a, "")
  assert_eq(inbox.status, 200)
  assert_true(inbox.body.contains("notice-subject-a"))
  assert_false(inbox.body.contains("alert-node-a"))
  let preference = service.handle(
    Put,
    "/v1/notifications/self/preferences",
    subject_a,
    "{\"topic\":\"LeaseLifecycle\",\"channels\":[\"Email\"],\"minimum_severity\":\"Warning\"}",
  )
  assert_eq(preference.status, 200)
  assert_true(preference.body.contains("InApp"))
  assert_true(preference.body.contains("Email"))
  assert_false(preference.body.contains("subject-b"))
  let preferences = service.handle(
    Get,
    "/v1/notifications/self/preferences",
    subject_a,
    "",
  )
  assert_eq(preferences.status, 200)
  assert_true(preferences.body.contains("LeaseLifecycle"))
  assert_true(preferences.body.contains("Email"))
  assert_false(preferences.body.contains("preference_id"))
  assert_false(preferences.body.contains("preference-subject-a"))
  let other_preferences = service.handle(
    Get,
    "/v1/notifications/self/preferences",
    subject_b,
    "",
  )
  assert_eq(other_preferences.status, 200)
  assert_false(other_preferences.body.contains("preference-subject-a"))
  let other = service.handle(Get, "/v1/notifications/self", subject_b, "")
  assert_eq(other.status, 200)
  assert_false(other.body.contains("notice-subject-a"))
  let read = service.handle(
    Post,
    "/v1/notifications/self/notice-subject-a:read",
    subject_a,
    "{\"expected_generation\":\"1\"}",
  )
  if read.status != 200 {
    fail("unexpected read response: \{read.status} \{read.body}")
  }
  assert_true(read.body.contains("Read"))
  let operator = { "Authorization": "Bearer operator-token" }
  let alerts = service.handle(Get, "/v1/notifications/operator", operator, "")
  assert_eq(alerts.status, 200)
  assert_true(alerts.body.contains("alert-node-a"))
  assert_false(alerts.body.contains("notice-subject-a"))
  let delivery_readiness = service.handle(
    Get,
    "/v1/notifications/operator/readiness",
    operator,
    "",
  )
  assert_eq(delivery_readiness.status, 200)
  assert_true(delivery_readiness.body.contains("AdaptersPending"))
  assert_false(delivery_readiness.body.contains("subject-a"))
  let deliveries = service.handle(
    Get,
    "/v1/notifications/operator/deliveries",
    operator,
    "",
  )
  assert_eq(deliveries.status, 200)
  assert_true(deliveries.body.contains("delivery-alert-node-a-in-app"))
  assert_true(deliveries.body.contains("PendingDelivery"))
  assert_false(deliveries.body.contains("operator-token"))
  assert_eq(
    service.handle(
      Get,
      "/v1/notifications/operator/deliveries",
      { "Authorization": "Bearer wrong" },
      "",
    ).status,
    401,
  )
  let acknowledged = service.handle(
    Post,
    "/v1/notifications/operator/alert-node-a:acknowledge",
    operator,
    "{\"expected_generation\":\"1\"}",
  )
  assert_eq(acknowledged.status, 200)
  assert_true(acknowledged.body.contains("Acknowledged"))
  assert_eq(
    service.handle(
      Post,
      "/v1/notifications/operator/alert-node-a:resolve",
      { "Authorization": "Bearer wrong" },
      "{\"expected_generation\":\"2\"}",
    ).status,
    401,
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "operator dead-letter redrive is authorized generation fenced and audited" {
  let directory = @fs.tmpdir(prefix="lunanexa-notification-redrive-api-")
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
    maximum_delivery_attempts=1,
  )
  let now = @async.now()
  ignore(
    notifications.enqueue({
      version: @notifications.contract_version,
      notification_id: "alert-redrive-api",
      deduplication_key: "node-redrive-unreachable",
      source_receipt: "health:node-redrive:unreachable",
      topic: ClusterHealth,
      code: "NodeUnreachable",
      severity: Critical,
      audience: PlatformOperators,
      title_key: "alerts.node_unreachable.title",
      body_key: "alerts.node_unreachable.body",
      parameters: { "node_ref": "node-redrive" },
      created_unix_ms: now,
      expires_unix_ms: None,
    }),
  )
  let claimed = notifications.claim_due_deliveries(now, 100L, 10)[0]
  let dead = notifications.record_delivery_result({
    delivery_id: claimed.delivery_id,
    expected_attempt_count: claimed.attempt_count,
    delivered: false,
    retryable: false,
    provider_receipt: None,
    error_code: Some("AdapterRejectedResponse"),
    next_attempt_unix_ms: None,
    now_unix_ms: now + 1L,
  })
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
    @store.FileStore::open("\{directory}/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  ).with_notification_store(notifications)
  let path = "/v1/notifications/operator/deliveries/\{dead.delivery_id}:redrive"
  let body = "{\"expected_attempt_count\":\{dead.attempt_count},\"expected_updated_unix_ms\":\"\{dead.updated_unix_ms}\"}"
  assert_eq(service.handle(Post, path, Map([]), body).status, 401)
  let accepted = service.handle(
    Post,
    path,
    { "Authorization": "Bearer operator-token" },
    body,
  )
  assert_eq(accepted.status, 202)
  assert_false(accepted.body.contains("node-redrive"))
  assert_eq(
    service.handle(
      Post,
      path,
      { "Authorization": "Bearer operator-token" },
      body,
    ).status,
    409,
  )
  assert_eq(notifications.snapshot().redrive_audit.length(), 1)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "stale node heartbeat raises and recovery resolves a durable alert" {
  let directory = @fs.tmpdir(prefix="lunanexa-node-alert-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  let now = @async.now()
  durable.put_heartbeat({
    ..schedulable_heartbeat(Active),
    timestamp_unix_ms: now - 16000L,
  })
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let operational = @observability.ObservabilityStore::open(
    "\{directory}/observability.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_notification_store(notifications)
    .with_observability_store(operational)
  let operator = { "Authorization": "Bearer operator-token" }
  let summary = service.reconcile_notifications(@async.now())
  assert_eq(summary.operator_alert_count, 1)
  let raised = service.handle(Get, "/v1/notifications/operator", operator, "")
  assert_eq(raised.status, 200)
  assert_true(raised.body.contains("NodeUnreachable"))
  assert_true(raised.body.contains("Critical"))
  durable.put_heartbeat({
    ..schedulable_heartbeat(Active),
    timestamp_unix_ms: @async.now(),
  })
  let recovered = service.handle(
    Get,
    "/v1/notifications/operator",
    operator,
    "",
  )
  assert_eq(recovered.status, 200)
  assert_true(recovered.body.contains("Resolved"))
  let reopened = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  assert_eq(reopened.records_for_operators(@async.now()).length(), 1)
  assert_eq(reopened.records_for_operators(@async.now())[0].lifecycle, Resolved)
  let codes = operational.snapshot().events.map(event => event.event_code)
  assert_true(codes.contains("NotificationReconciliationCompleted"))
  assert_true(codes.contains("NodeHealthReconciled"))
  assert_true(codes.contains("ExclusiveLeaseHealthReconciled"))
  assert_true(codes.contains("NotificationDeliveryHealthReconciled"))
  assert_true(
    operational.snapshot().events.any(event => {
      event.event_code == "NodeHealthReconciled" &&
      event.outcome == "degraded" &&
      event.status_code == 503
    }),
  )
  assert_true(codes.contains("ExclusiveLeaseHealthReconciled"))
  assert_true(codes.contains("NotificationDeliveryHealthReconciled"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "subject inbox reconciles access-ready and expiry notices from durable leases" {
  let directory = @fs.tmpdir(prefix="lunanexa-subject-lease-notices-")
  let now = @async.now()
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  ignore(
    portal.put_membership({
      membership_id: "member-lease",
      tenant_ref: "tenant-lease",
      organization_id: "org-lease",
      subject_ref: "subject-lease",
      roles: [Developer, LegalSigner, LeaseRequester],
      active: true,
      created_unix_ms: now,
    }),
  )
  let leases = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive-leases.json",
    "lease-signing-secret",
  )
  let reserved = leases.issue(
    {
      version: @nodelease.contract_version,
      idempotency_key: "issue-subject-lease",
      lease_id: "exclusive-subject-lease",
      node_id: "node-subject-lease",
      subject_ref: "subject-lease",
      unix_username: "lease_user",
      access_credential_ref: "ssh-cert:exclusive-subject-lease",
      starts_unix_ms: now - 1000L,
      expires_unix_ms: now + 3600000L,
    },
    now,
  )
  let provisioning = leases.transition(
    reserved.intent.lease_id,
    {
      expected_generation: reserved.generation,
      state: Provisioning,
      evidence_receipt: "agent:provisioned",
    },
    now + 1L,
  )
  ignore(
    leases.transition(
      provisioning.intent.lease_id,
      {
        expected_generation: provisioning.generation,
        state: Active,
        evidence_receipt: "agent:access-ready",
      },
      now + 2L,
    ),
  )
  ignore(
    portal.publish_agreement({
      agreement_id: "agreement-subject-lease",
      tenant_ref: "tenant-lease",
      organization_id: "org-lease",
      template_ref: "framework-v1",
      title: "Subject lease agreement",
      summary: "Required for exclusive machine access.",
      rendered_document_hash: "sha256:subject-lease-document",
      state: ReviewRequired,
      generation: 1L,
      signer_subject_ref: None,
      signature_request_receipt: None,
      executed_artifact_hash: None,
      created_unix_ms: now - 5000L,
      updated_unix_ms: now - 5000L,
    }),
  )
  let signature = portal.request_signature(
    "subject-lease",
    {
      agreement_id: "agreement-subject-lease",
      expected_generation: 1L,
      idempotency_key: "sign-subject-lease",
    },
    now - 4000L,
  )
  ignore(
    portal.record_execution(
      {
        agreement_id: "agreement-subject-lease",
        expected_generation: signature.generation,
        signer_subject_ref: "subject-lease",
        executed_artifact_hash: "sha256:subject-lease-executed",
        evidence_receipt: "provider:verified:subject-lease",
      },
      now - 3000L,
    ),
  )
  let request = portal.submit_lease_request(
    "subject-lease",
    {
      request_id: "request-subject-lease",
      idempotency_key: "request-subject-lease",
      tenant_ref: "tenant-lease",
      organization_id: "org-lease",
      project_id: "project-lease",
      unix_username: "lease_user",
      starts_unix_ms: now - 1000L,
      expires_unix_ms: now + 3600000L,
      requested_model_ids: ["model-lease"],
      justification: "Subject notification coverage",
    },
    now - 2000L,
  )
  ignore(
    portal.review_lease_request(
      {
        request_id: request.submission.request_id,
        expected_generation: request.generation,
        decision: Approve,
        node_id: Some("node-subject-lease"),
        evidence_receipt: "operator:approved:subject-lease",
      },
      Some("exclusive-subject-lease"),
      now - 1000L,
    ),
  )
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_exclusive_lease_store(leases)
    .with_notification_store(notifications)
  let headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-lease",
  }
  let inbox = service.handle(Get, "/v1/notifications/self", headers, "")
  assert_eq(inbox.status, 200)
  assert_true(inbox.body.contains("LeaseAccessReady"))
  assert_true(inbox.body.contains("LeaseExpiring"))
  assert_true(inbox.body.contains("LeaseRequestApproved"))
  assert_true(inbox.body.contains("managed-reference-available"))
  assert_false(inbox.body.contains("ssh-cert:exclusive-subject-lease"))
  assert_false(inbox.body.contains("node-subject-lease"))
  let repeated = service.handle(Get, "/v1/notifications/self", headers, "")
  let records : Array[@notifications.NotificationRecord] = @json.from_json(
    @json.parse(repeated.body),
  )
  assert_eq(records.length(), 3)
  let reopened = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  assert_eq(
    reopened
    .records_for_subject("tenant-lease", "subject-lease", @async.now())
    .length(),
    3,
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "autonomous pass raises a quarantine alert without an operator page read" {
  let directory = @fs.tmpdir(prefix="lunanexa-autonomous-quarantine-alert-")
  let now = @async.now()
  let leases = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/leases.json",
    "lease-signing-secret",
  )
  let issued = leases.issue(
    {
      version: @nodelease.contract_version,
      idempotency_key: "issue-quarantine-alert",
      lease_id: "lease-quarantine-alert",
      node_id: "node-quarantine-alert",
      subject_ref: "subject-quarantine-alert",
      unix_username: "quarantine_user",
      access_credential_ref: "ssh-cert:quarantine-alert",
      starts_unix_ms: now,
      expires_unix_ms: now + 3600000L,
    },
    now,
  )
  ignore(
    leases.transition(
      issued.intent.lease_id,
      {
        expected_generation: issued.generation,
        state: Quarantined,
        evidence_receipt: "sanitization:failed",
      },
      now + 1L,
    ),
  )
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let operational = @observability.ObservabilityStore::open(
    "\{directory}/observability.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_exclusive_lease_store(leases)
    .with_notification_store(notifications)
    .with_observability_store(operational)
  let first = service.reconcile_notifications(now + 2L)
  assert_eq(first.operator_alert_count, 1)
  let records = notifications.records_for_operators(now + 3L)
  assert_eq(records[0].event.code, "LeaseSanitizationFailed")
  assert_false(
    records[0].event.parameters
    .to_json()
    .stringify()
    .contains("node-quarantine-alert"),
  )
  let repeated = service.reconcile_notifications(now + 4L)
  assert_eq(repeated.operator_alert_count, 1)
  assert_eq(notifications.records_for_operators(now + 5L).length(), 1)
  @fs.rmdir(directory, recursive=true)
}
