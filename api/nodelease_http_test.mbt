///|
fn exclusive_lease_intent(now : Int64) -> @nodelease.ExclusiveNodeLeaseIntent {
  {
    version: @nodelease.contract_version,
    idempotency_key: "exclusive-request-1",
    lease_id: "exclusive-lease-1",
    node_id: "node-a",
    subject_ref: "subject-1",
    unix_username: "user_1",
    access_credential_ref: "ssh-cert:exclusive-lease-1",
    starts_unix_ms: now - 1000L,
    expires_unix_ms: now + 60000L,
  }
}

///|
async test "exclusive lease reserves only the named node and fences managed work" {
  let directory = @fs.tmpdir(prefix="lunanexa-exclusive-api-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.put_heartbeat({
    ..schedulable_heartbeat(Active),
    running_deployments: [],
  })
  let registry = @registry.FileRegistry::open("\{directory}/registry.json")
  let enrollment = @node.FileEnrollmentService::open(
    "\{directory}/enrollment.json",
  )
  let scheduler = @scheduler.FileScheduler::open(
    "\{directory}/scheduler.json",
    4,
  )
  let telemetry = @telemetry.FileTelemetry::open("\{directory}/telemetry.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let lease_store = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive-leases.json",
    "lease-signing-secret",
  )
  let service = @api.ApiService::with_control_plane(
    durable, registry, enrollment, scheduler, telemetry, runtime, "operator-token",
    "inference-token", "node-token", "0.1.0",
  ).with_exclusive_lease_store(lease_store)
  let operator_headers = { "Authorization": "Bearer operator-token" }
  let now = @async.now()
  let reserved = service.handle(
    Post,
    "/v1/exclusive-node-leases",
    operator_headers,
    exclusive_lease_intent(now).to_json().stringify(),
  )
  assert_eq(reserved.status, 201)
  let lease : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(reserved.body),
  )
  assert_eq(lease.state, Reserved)
  assert_eq(lease.intent.node_id, "node-a")
  assert_false(reserved.body.contains("runtime-secret"))
  assert_eq(durable.node_directive("node-a").unwrap().desired_state, Cordoned)
  let forecast = service.handle(
    Post,
    "/v1/capacity:forecast",
    operator_headers,
    ({ "instance_memory_mib": 1000 } : Json).stringify(),
  )
  assert_eq(forecast.status, 200)
  let capacity : @scheduler.CapacityForecast = @json.from_json(
    @json.parse(forecast.body),
  )
  assert_eq(capacity.schedulable_nodes, 0)
  let assignment = { ..api_assignment(), signature: "" }
  let rejected_assignment = service.handle(
    Put,
    "/v1/assignments",
    operator_headers,
    assignment.to_json().stringify(),
  )
  assert_eq(rejected_assignment.status, 409)
  assert_true(rejected_assignment.body.contains("NodeExclusiveLease"))
  let second_intent = {
    ..exclusive_lease_intent(now),
    idempotency_key: "exclusive-request-2",
    lease_id: "exclusive-lease-2",
    subject_ref: "subject-2",
    unix_username: "user_2",
    access_credential_ref: "ssh-cert:exclusive-lease-2",
  }
  let rejected_second = service.handle(
    Post,
    "/v1/exclusive-node-leases",
    operator_headers,
    second_intent.to_json().stringify(),
  )
  assert_eq(rejected_second.status, 409)
  assert_eq(lease_store.leases().length(), 1)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "exclusive lease activation is generation fenced and rejects raw credentials" {
  let directory = @fs.tmpdir(prefix="lunanexa-exclusive-transition-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.put_heartbeat({
    ..schedulable_heartbeat(Active),
    running_deployments: [],
  })
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let lease_store = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive-leases.json",
    "lease-signing-secret",
  )
  let service = @api.ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_exclusive_lease_store(lease_store)
  let headers = { "Authorization": "Bearer operator-token" }
  let now = @async.now()
  let unsafe_intent = {
    ..exclusive_lease_intent(now),
    idempotency_key: "unsafe-request",
    lease_id: "unsafe-lease",
    access_credential_ref: "plain-text-password",
  }
  let rejected = service.handle(
    Post,
    "/v1/exclusive-node-leases",
    headers,
    unsafe_intent.to_json().stringify(),
  )
  assert_eq(rejected.status, 400)
  assert_false(
    @fs.read_file("\{directory}/exclusive-leases.json")
    .text()
    .contains("plain-text-password"),
  )
  let created_reply = service.handle(
    Post,
    "/v1/exclusive-node-leases",
    headers,
    exclusive_lease_intent(now).to_json().stringify(),
  )
  let created : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(created_reply.body),
  )
  let provisioning_reply = service.handle(
    Post,
    "/v1/exclusive-node-leases/exclusive-lease-1:transition",
    headers,
    @nodelease.ExclusiveLeaseTransitionRequest::{
      expected_generation: created.generation,
      state: Provisioning,
      evidence_receipt: "node:provisioning",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(provisioning_reply.status, 200)
  let provisioning : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(provisioning_reply.body),
  )
  let stale = service.handle(
    Post,
    "/v1/exclusive-node-leases/exclusive-lease-1:transition",
    headers,
    @nodelease.ExclusiveLeaseTransitionRequest::{
      expected_generation: created.generation,
      state: Active,
      evidence_receipt: "node:ready",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(stale.status, 409)
  assert_true(stale.body.contains("StaleGeneration"))
  let active = service.handle(
    Post,
    "/v1/exclusive-node-leases/exclusive-lease-1:transition",
    headers,
    @nodelease.ExclusiveLeaseTransitionRequest::{
      expected_generation: provisioning.generation,
      state: Active,
      evidence_receipt: "node:ready",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(active.status, 200)
  assert_true(active.body.contains("Active"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "exclusive lease also blocks one-click deployment planning" {
  let directory = @fs.tmpdir(prefix="lunanexa-exclusive-deployment-")
  let template = management_template()
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.fence_controller(1L)
  durable.put_heartbeat(management_heartbeat([]))
  let registry = management_registry("\{directory}/registry.json", template)
  let deployments = @deployment_store.FileDeploymentStore::open(
    "\{directory}/deployments.json",
    "catalog-secret",
  )
  let lease_store = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive-leases.json",
    "lease-secret",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    template.runtime.version,
    template.runtime.image_digest,
    template.artifact.digest,
    allow_http_loopback=true,
  )
  let service = @api.ApiService::with_registry(
      durable, registry, runtime, "operator-token", "inference-token", "node-token",
      "0.1.0",
    )
    .with_deployment_store(deployments, available_secret_refs=["runtime-token"])
    .with_assignment_signing_secret("assignment-secret")
    .with_exclusive_lease_store(lease_store)
  let headers = { "Authorization": "Bearer operator-token" }
  let registered = service.handle(
    Post,
    "/v1/catalog/templates",
    headers,
    template.to_json().stringify(),
  )
  assert_eq(registered.status, 201)
  let reserved = service.handle(
    Post,
    "/v1/exclusive-node-leases",
    headers,
    exclusive_lease_intent(@async.now()).to_json().stringify(),
  )
  assert_eq(reserved.status, 201)
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "blocked-deploy",
    deployment_id: "blocked-service",
    template: { template_id: "text-small", version: "v1" },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
  }
  let plan_reply = service.handle(
    Post,
    "/v1/deployment-plans",
    headers,
    intent.to_json().stringify(),
  )
  assert_eq(plan_reply.status, 200)
  let plan : @deployment.DeploymentPlan = @json.from_json(
    @json.parse(plan_reply.body),
  )
  assert_false(plan.executable)
  assert_eq(plan.replicas, [])
  assert_true(plan.findings.any(finding => finding.code == NoCompatibleNode))
  assert_eq(durable.assignments(), [])
  @fs.rmdir(directory, recursive=true)
}
