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
  let direct_transition = service.handle(
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
  assert_eq(direct_transition.status, 409)
  assert_true(direct_transition.body.contains("NodeEvidenceRequired"))
  let node_headers = {
    "Authorization": "Node node-token",
    "X-LunaNexa-Node-Id": "node-a",
  }
  durable.put_heartbeat({
    ..schedulable_heartbeat(Active),
    running_deployments: ["managed-service-still-draining"],
  })
  let still_reserved_reply = service.handle(
    Get,
    "/v1/nodes/node-a/exclusive-lease",
    node_headers,
    "",
  )
  assert_eq(still_reserved_reply.status, 200)
  let still_reserved : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(still_reserved_reply.body),
  )
  assert_eq(still_reserved.state, Reserved)
  durable.put_heartbeat({
    ..schedulable_heartbeat(Active),
    running_deployments: [],
  })
  let provisioning_reply = service.handle(
    Get,
    "/v1/nodes/node-a/exclusive-lease",
    node_headers,
    "",
  )
  assert_eq(provisioning_reply.status, 200)
  let provisioning : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(provisioning_reply.body),
  )
  assert_eq(provisioning.state, Provisioning)
  let provision_action = @nodelease.LeaseAgentAction::ProvisionAccess(
    lease_id=provisioning.intent.lease_id,
    username=provisioning.intent.unix_username,
    credential_ref=provisioning.intent.access_credential_ref,
    expires_unix_ms=provisioning.intent.expires_unix_ms,
    generation=provisioning.generation,
  )
  let stale = service.handle(
    Post,
    "/v1/nodes/node-a/exclusive-lease:observe",
    node_headers,
    @nodelease.LeaseAgentObservation::{
      lease_id: provisioning.intent.lease_id,
      observed_generation: created.generation,
      action: "provision",
      receipt: @nodelease.helper_receipt(provision_action, @async.now()),
      observed_unix_ms: @async.now(),
    }
    .to_json()
    .stringify(),
  )
  assert_eq(stale.status, 409)
  assert_true(stale.body.contains("StaleGeneration"))
  let active = service.handle(
    Post,
    "/v1/nodes/node-a/exclusive-lease:observe",
    node_headers,
    @nodelease.LeaseAgentObservation::{
      lease_id: provisioning.intent.lease_id,
      observed_generation: provisioning.generation,
      action: "provision",
      receipt: @nodelease.helper_receipt(provision_action, @async.now()),
      observed_unix_ms: @async.now(),
    }
    .to_json()
    .stringify(),
  )
  assert_eq(active.status, 200)
  assert_true(active.body.contains("Active"))
  let active_lease : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(active.body),
  )
  let terminated_reply = service.handle(
    Post,
    "/v1/exclusive-node-leases/exclusive-lease-1:terminate",
    headers,
    @nodelease.ExclusiveLeaseTerminationRequest::{
      expected_generation: active_lease.generation,
      reason: "operator-requested",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(terminated_reply.status, 202)
  let expiring : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(terminated_reply.body),
  )
  assert_eq(expiring.state, Expiring)
  assert_eq(durable.node_directive("node-a").unwrap().desired_state, Draining)
  assert_true(lease_store.node_blocks_managed_placement("node-a"))
  let duplicate_termination = service.handle(
    Post,
    "/v1/exclusive-node-leases/exclusive-lease-1:terminate",
    headers,
    @nodelease.ExclusiveLeaseTerminationRequest::{
      expected_generation: expiring.generation,
      reason: "operator-requested",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(duplicate_termination.status, 202)
  let duplicate_lease : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(duplicate_termination.body),
  )
  assert_eq(duplicate_lease.generation, expiring.generation)
  let stale_termination = service.handle(
    Post,
    "/v1/exclusive-node-leases/exclusive-lease-1:terminate",
    headers,
    @nodelease.ExclusiveLeaseTerminationRequest::{
      expected_generation: active_lease.generation,
      reason: "stale-retry",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(stale_termination.status, 409)
  assert_true(stale_termination.body.contains("StaleGeneration"))
  let revoke_action = @nodelease.LeaseAgentAction::RevokeAccess(
    lease_id=expiring.intent.lease_id,
    username=expiring.intent.unix_username,
    generation=expiring.generation,
  )
  let forged_cleanup = service.handle(
    Post,
    "/v1/nodes/node-a/exclusive-lease:observe",
    node_headers,
    @nodelease.LeaseAgentObservation::{
      lease_id: expiring.intent.lease_id,
      observed_generation: expiring.generation,
      action: "revoke",
      receipt: "helper:accepted:unbound",
      observed_unix_ms: @async.now(),
    }
    .to_json()
    .stringify(),
  )
  assert_eq(forged_cleanup.status, 409)
  assert_true(forged_cleanup.body.contains("InvalidCleanupEvidence"))
  assert_eq(
    lease_store.lease(expiring.intent.lease_id).unwrap().state,
    Expiring,
  )
  let revoked_reply = service.handle(
    Post,
    "/v1/nodes/node-a/exclusive-lease:observe",
    node_headers,
    @nodelease.LeaseAgentObservation::{
      lease_id: expiring.intent.lease_id,
      observed_generation: expiring.generation,
      action: "revoke",
      receipt: @nodelease.helper_receipt(revoke_action, @async.now()),
      observed_unix_ms: @async.now(),
    }
    .to_json()
    .stringify(),
  )
  assert_eq(revoked_reply.status, 200)
  let revoked : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(revoked_reply.body),
  )
  assert_eq(revoked.state, RevokingAccess)
  let sanitize_action = @nodelease.LeaseAgentAction::SanitizeLease(
    lease_id=revoked.intent.lease_id,
    username=revoked.intent.unix_username,
    generation=revoked.generation,
  )
  let completed_reply = service.handle(
    Post,
    "/v1/nodes/node-a/exclusive-lease:observe",
    node_headers,
    @nodelease.LeaseAgentObservation::{
      lease_id: revoked.intent.lease_id,
      observed_generation: revoked.generation,
      action: "sanitize",
      receipt: @nodelease.helper_receipt(sanitize_action, @async.now()),
      observed_unix_ms: @async.now(),
    }
    .to_json()
    .stringify(),
  )
  assert_eq(completed_reply.status, 200)
  let completed : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(completed_reply.body),
  )
  assert_eq(completed.state, Completed)
  assert_eq(durable.node_directive("node-a").unwrap().desired_state, Active)
  assert_false(lease_store.node_blocks_managed_placement("node-a"))
  let next_created_reply = service.handle(
    Post,
    "/v1/exclusive-node-leases",
    headers,
    {
      ..exclusive_lease_intent(@async.now()),
      idempotency_key: "exclusive-request-next",
      lease_id: "exclusive-lease-next",
      subject_ref: "subject-next",
      unix_username: "user_next",
      access_credential_ref: "ssh-cert:exclusive-lease-next",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(next_created_reply.status, 201)
  let next_lease : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(next_created_reply.body),
  )
  let quarantine_action = @nodelease.LeaseAgentAction::QuarantineNode(
    lease_id=next_lease.intent.lease_id,
    generation=next_lease.generation,
  )
  let quarantined_reply = service.handle(
    Post,
    "/v1/nodes/node-a/exclusive-lease:observe",
    node_headers,
    @nodelease.LeaseAgentObservation::{
      lease_id: next_lease.intent.lease_id,
      observed_generation: next_lease.generation,
      action: "quarantine",
      receipt: @nodelease.helper_receipt(quarantine_action, @async.now()),
      observed_unix_ms: @async.now(),
    }
    .to_json()
    .stringify(),
  )
  assert_eq(quarantined_reply.status, 200)
  let quarantined : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(quarantined_reply.body),
  )
  assert_eq(quarantined.state, Quarantined)
  assert_true(lease_store.node_blocks_managed_placement("node-a"))
  let repeat_action = @nodelease.LeaseAgentAction::QuarantineNode(
    lease_id=quarantined.intent.lease_id,
    generation=quarantined.generation,
  )
  let repeated = service.handle(
    Post,
    "/v1/nodes/node-a/exclusive-lease:observe",
    node_headers,
    @nodelease.LeaseAgentObservation::{
      lease_id: quarantined.intent.lease_id,
      observed_generation: quarantined.generation,
      action: "quarantine",
      receipt: @nodelease.helper_receipt(repeat_action, @async.now()),
      observed_unix_ms: @async.now(),
    }
    .to_json()
    .stringify(),
  )
  assert_eq(repeated.status, 200)
  let repeated_lease : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(repeated.body),
  )
  assert_eq(repeated_lease.generation, quarantined.generation)
  let recovery_start_reply = service.handle(
    Post,
    "/v1/exclusive-node-leases/\{repeated_lease.intent.lease_id}:terminate",
    headers,
    @nodelease.ExclusiveLeaseTerminationRequest::{
      expected_generation: repeated_lease.generation,
      reason: "operator-recovery",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(recovery_start_reply.status, 202)
  let recovery_start : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(recovery_start_reply.body),
  )
  assert_eq(recovery_start.state, RevokingAccess)
  let recovery_revoke = @nodelease.LeaseAgentAction::RevokeAccess(
    lease_id=recovery_start.intent.lease_id,
    username=recovery_start.intent.unix_username,
    generation=recovery_start.generation,
  )
  let recovery_revoked_reply = service.handle(
    Post,
    "/v1/nodes/node-a/exclusive-lease:observe",
    node_headers,
    @nodelease.LeaseAgentObservation::{
      lease_id: recovery_start.intent.lease_id,
      observed_generation: recovery_start.generation,
      action: "revoke",
      receipt: @nodelease.helper_receipt(recovery_revoke, @async.now()),
      observed_unix_ms: @async.now(),
    }
    .to_json()
    .stringify(),
  )
  assert_eq(recovery_revoked_reply.status, 200)
  let recovery_revoked : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(recovery_revoked_reply.body),
  )
  assert_eq(recovery_revoked.state, RevokingAccess)
  let recovery_sanitize = @nodelease.LeaseAgentAction::SanitizeLease(
    lease_id=recovery_revoked.intent.lease_id,
    username=recovery_revoked.intent.unix_username,
    generation=recovery_revoked.generation,
  )
  let recovery_completed_reply = service.handle(
    Post,
    "/v1/nodes/node-a/exclusive-lease:observe",
    node_headers,
    @nodelease.LeaseAgentObservation::{
      lease_id: recovery_revoked.intent.lease_id,
      observed_generation: recovery_revoked.generation,
      action: "sanitize",
      receipt: @nodelease.helper_receipt(recovery_sanitize, @async.now()),
      observed_unix_ms: @async.now(),
    }
    .to_json()
    .stringify(),
  )
  assert_eq(recovery_completed_reply.status, 200)
  let recovery_completed : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(recovery_completed_reply.body),
  )
  assert_eq(recovery_completed.state, Completed)
  assert_false(lease_store.node_blocks_managed_placement("node-a"))
  let reserved_reply = service.handle(
    Post,
    "/v1/exclusive-node-leases",
    headers,
    {
      ..exclusive_lease_intent(@async.now()),
      idempotency_key: "exclusive-request-reserved-stop",
      lease_id: "exclusive-reserved-stop",
      subject_ref: "subject-reserved-stop",
      unix_username: "user_reserved",
      access_credential_ref: "ssh-cert:exclusive-reserved-stop",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(reserved_reply.status, 201)
  let reserved_lease : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(reserved_reply.body),
  )
  let reserved_stop_reply = service.handle(
    Post,
    "/v1/exclusive-node-leases/\{reserved_lease.intent.lease_id}:terminate",
    headers,
    @nodelease.ExclusiveLeaseTerminationRequest::{
      expected_generation: reserved_lease.generation,
      reason: "cancel-before-login",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(reserved_stop_reply.status, 202)
  let reserved_stopped : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(reserved_stop_reply.body),
  )
  assert_eq(reserved_stopped.state, Expiring)
  assert_true(lease_store.node_blocks_managed_placement("node-a"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "node polling converts a naturally expired active lease into cleanup" {
  let directory = @fs.tmpdir(prefix="lunanexa-exclusive-natural-expiry-")
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.put_heartbeat({
    ..schedulable_heartbeat(Active),
    running_deployments: [],
  })
  let lease_store = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/exclusive-leases.json",
    "lease-signing-secret",
  )
  let now = @async.now()
  let historical_intent = {
    ..exclusive_lease_intent(now),
    starts_unix_ms: now - 3000L,
    expires_unix_ms: now - 1000L,
  }
  let reserved = lease_store.issue(historical_intent, now - 2500L)
  let provisioning = lease_store.transition(
    historical_intent.lease_id,
    {
      expected_generation: reserved.generation,
      state: Provisioning,
      evidence_receipt: "node:provisioning",
    },
    now - 2400L,
  )
  ignore(
    lease_store.transition(
      historical_intent.lease_id,
      {
        expected_generation: provisioning.generation,
        state: Active,
        evidence_receipt: "node:active",
      },
      now - 2300L,
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
  let service = @api.ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_exclusive_lease_store(lease_store)
  let reply = service.handle(
    Get,
    "/v1/nodes/node-a/exclusive-lease",
    { "Authorization": "Node node-token", "X-LunaNexa-Node-Id": "node-a" },
    "",
  )
  assert_eq(reply.status, 200)
  let expired : @nodelease.ExclusiveNodeLease = @json.from_json(
    @json.parse(reply.body),
  )
  assert_eq(expired.state, Expiring)
  assert_eq(durable.node_directive("node-a").unwrap().desired_state, Draining)
  assert_true(lease_store.node_blocks_managed_placement("node-a"))
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
