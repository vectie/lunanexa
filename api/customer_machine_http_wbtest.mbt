///|
async fn customer_machine_test_service(
  directory : String,
  now : Int64,
) -> (
  ApiService,
  @nodelease_store.FileExclusiveLeaseStore,
  @portal_store.FilePortalStore,
  @credential_store.CredentialHandoffStore,
) {
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.put_heartbeat(customer_machine_test_heartbeat(now))
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  for
    membership in [
      @portal.EnterpriseMembership::{
        membership_id: "member-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "subject-a",
        roles: [Developer],
        active: true,
        created_unix_ms: now,
      },
      {
        membership_id: "member-b",
        tenant_ref: "tenant-b",
        organization_id: "org-b",
        subject_ref: "subject-b",
        roles: [Developer],
        active: true,
        created_unix_ms: now,
      },
    ] {
    ignore(portal.put_membership(membership))
  }
  let leases = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive.json",
    "lease-signing-secret",
  )
  let reserved = leases.issue(
    {
      version: @nodelease.contract_version,
      idempotency_key: "customer-machine-a",
      lease_id: "lease-customer-a",
      node_id: "customer-node-a",
      subject_ref: "subject-a",
      unix_username: "alice",
      access_credential_ref: "secret:internal-customer-a",
      starts_unix_ms: now - 10000L,
      expires_unix_ms: now + 600000L,
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
        evidence_receipt: "agent:active",
      },
      now + 2L,
    ),
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_portal_store(portal)
    .with_exclusive_lease_store(leases)
  let unsigned_issuer : @credential.CredentialIssuerReadinessEvidence = {
    version: @credential.issuer_readiness_contract_version,
    adapter_id: "test-ssh-ca",
    health_endpoint: "https://issuer.example/healthz",
    evidence_ref: "retained-test-issuer-health",
    checked_unix_ms: now,
    expires_unix_ms: now + 600000L,
    healthy: true,
    signature: "",
  }
  let issuer_secret = "customer-machine-issuer-evidence-more-than-32-bytes"
  let issuer_evidence = {
    ..unsigned_issuer,
    signature: @credential_store.issuer_readiness_signature(
      unsigned_issuer, issuer_secret,
    ),
  }
  let credentials = @credential_store.CredentialHandoffStore::open(
    "\{directory}/credential-handoffs.json",
    "customer-machine-credential-secret-more-than-32-bytes",
  ).with_issuer_readiness(issuer_evidence)
  (
    service.with_credential_handoff_store(credentials),
    leases,
    portal,
    credentials,
  )
}

///|
fn customer_machine_test_heartbeat(now : Int64) -> @contracts.NodeHeartbeat {
  {
    node_id: "customer-node-a",
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: "customer-node-a",
      agent_version: "0.1.0",
      os_release: "test",
      runtime_names: [],
      accelerators: [],
      labels: Map([]),
      taints: [],
    },
    running_deployments: [],
    timestamp_unix_ms: now,
    signature: "",
  }
}

///|
fn customer_headers(subject_ref : String) -> Map[String, String] {
  {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": subject_ref,
  }
}

///|
async test "customer machine listing is live tenant safe and secret free" {
  let directory = @fs.tmpdir(prefix="lunanexa-customer-machine-")
  let now = @async.now()
  let (service, leases, _, credentials) = customer_machine_test_service(
    directory, now,
  )
  let own = service.handle(
    Get,
    "/v1/machine-access/self",
    customer_headers("subject-a"),
    "",
  )
  assert_eq(own.status, 200)
  let views : Array[@nodelease.CustomerExclusiveMachineView] = @json.from_json(
    @json.parse(own.body),
  )
  assert_eq(views.length(), 1)
  assert_eq(views[0].state, Active)
  assert_eq(views[0].reachability, Online)
  assert_eq(views[0].credential_handoff.state, Pending)
  assert_false(own.body.contains("customer-node-a"))
  assert_false(own.body.contains("internal-customer-a"))
  assert_false(own.body.contains("access_credential_ref"))
  let lease = leases.lease("lease-customer-a").unwrap()
  ignore(
    credentials.issue(
      {
        request_id: "customer-machine-handoff-a",
        lease_id: lease.intent.lease_id,
        expected_generation: lease.generation,
        host_alias: "machine.cluster.example",
        ssh_port: 22,
        host_key_fingerprint: "SHA256:abcdefghijklmnopqrstuvwxyzABCDEFG1234567890_-",
        issuer_redirect_url: "https://issuer.example/redeem/customer-machine-a",
      },
      lease,
      @async.now(),
    ),
  )
  let with_handoff = service.handle(
    Get,
    "/v1/machine-access/self",
    customer_headers("subject-a"),
    "",
  )
  let issued_views : Array[@nodelease.CustomerExclusiveMachineView] = @json.from_json(
    @json.parse(with_handoff.body),
  )
  assert_eq(issued_views[0].credential_handoff.state, Available)
  let other = service.handle(
    Get,
    "/v1/machine-access/self",
    customer_headers("subject-b"),
    "",
  )
  assert_eq(other.status, 200)
  assert_eq(
    (
      @json.from_json(@json.parse(other.body)) :
      Array[@nodelease.CustomerExclusiveMachineView]).length(),
    0,
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "customer termination requires subject confirmation and generation" {
  let directory = @fs.tmpdir(prefix="lunanexa-customer-terminate-")
  let now = @async.now()
  let (service, leases, _, _) = customer_machine_test_service(directory, now)
  let current = leases.lease("lease-customer-a").unwrap()
  let request : @nodelease.CustomerExclusiveLeaseTerminationRequest = {
    expected_generation: current.generation,
    confirmation: "TERMINATE lease-customer-a",
    reason: "customer-requested",
  }
  let denied = service.handle(
    Post,
    "/v1/machine-access/self/lease-customer-a:terminate",
    customer_headers("subject-b"),
    request.to_json().stringify(),
  )
  assert_eq(denied.status, 404)
  let unconfirmed = service.handle(
    Post,
    "/v1/machine-access/self/lease-customer-a:terminate",
    customer_headers("subject-a"),
    { ..request, confirmation: "yes" }.to_json().stringify(),
  )
  assert_eq(unconfirmed.status, 400)
  let stale = service.handle(
    Post,
    "/v1/machine-access/self/lease-customer-a:terminate",
    customer_headers("subject-a"),
    { ..request, expected_generation: current.generation - 1L }
    .to_json()
    .stringify(),
  )
  assert_eq(stale.status, 409)
  let accepted = service.handle(
    Post,
    "/v1/machine-access/self/lease-customer-a:terminate",
    customer_headers("subject-a"),
    request.to_json().stringify(),
  )
  assert_eq(accepted.status, 202)
  let view : @nodelease.CustomerExclusiveMachineView = @json.from_json(
    @json.parse(accepted.body),
  )
  assert_eq(view.state, Expiring)
  assert_eq(view.credential_handoff.state, Closed)
  assert_false(view.can_terminate)
  assert_eq(leases.lease("lease-customer-a").unwrap().state, Expiring)
  let audit = service.store.audit_events()
  assert_true(
    audit.any(event => {
      event.actor == "portal-subject:subject-a" &&
      event.action == "exclusive-lease.customer-terminate"
    }),
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "customer termination creates durable operator signal when enabled" {
  let directory = @fs.tmpdir(prefix="lunanexa-customer-signal-")
  let now = @async.now()
  let (base, leases, _, _) = customer_machine_test_service(directory, now)
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let service = base.with_notification_store(notifications)
  let current = leases.lease("lease-customer-a").unwrap()
  let response = service.handle(
    Post,
    "/v1/machine-access/self/lease-customer-a:terminate",
    customer_headers("subject-a"),
    @nodelease.CustomerExclusiveLeaseTerminationRequest::{
      expected_generation: current.generation,
      confirmation: "TERMINATE lease-customer-a",
      reason: "customer-requested",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(response.status, 202)
  let operator_records = notifications.records_for_operators(@async.now())
  assert_eq(operator_records.length(), 1)
  assert_eq(operator_records[0].event.code, "CustomerTerminationRequested")
  assert_false(operator_records[0].event.parameters.contains("credential_ref"))
  let reopened = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  assert_eq(reopened.records_for_operators(@async.now()).length(), 1)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "customer machine expiry reconciles durably across restart" {
  let directory = @fs.tmpdir(prefix="lunanexa-customer-expiry-")
  let now = @async.now()
  let (service, leases, portal, _) = customer_machine_test_service(
    directory, now,
  )
  let active = leases.lease("lease-customer-a").unwrap()
  let expiring_intent = {
    ..active.intent,
    idempotency_key: "customer-machine-expiry",
    lease_id: "lease-customer-expiry",
    node_id: "customer-node-expiry",
    expires_unix_ms: now + 20L,
  }
  ignore(leases.issue(expiring_intent, now))
  @async.sleep(25)
  let response = service.handle(
    Get,
    "/v1/machine-access/self",
    customer_headers("subject-a"),
    "",
  )
  assert_eq(response.status, 200)
  let expired = leases.lease("lease-customer-expiry").unwrap()
  assert_eq(expired.state, Expiring)
  assert_true(leases.node_blocks_managed_placement(expired.intent.node_id))
  let reopened = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive.json",
    "lease-signing-secret",
  )
  assert_eq(reopened.lease(expired.intent.lease_id).unwrap().state, Expiring)
  let _ = portal
  @fs.rmdir(directory, recursive=true)
}
