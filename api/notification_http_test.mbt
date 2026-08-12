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
  let inbox = service.handle(Get, "/v1/notifications/self", subject_a, "")
  assert_eq(inbox.status, 200)
  assert_true(inbox.body.contains("notice-subject-a"))
  assert_false(inbox.body.contains("alert-node-a"))
  let subject_b = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-b",
  }
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
  ).with_notification_store(notifications)
  let operator = { "Authorization": "Bearer operator-token" }
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
      roles: [Developer],
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
  assert_true(inbox.body.contains("ssh-cert:exclusive-subject-lease"))
  let repeated = service.handle(Get, "/v1/notifications/self", headers, "")
  let records : Array[@notifications.NotificationRecord] = @json.from_json(
    @json.parse(repeated.body),
  )
  assert_eq(records.length(), 2)
  let reopened = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  assert_eq(
    reopened
    .records_for_subject("tenant-lease", "subject-lease", @async.now())
    .length(),
    2,
  )
  @fs.rmdir(directory, recursive=true)
}
