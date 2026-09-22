///|
async test "delivery media binding is limited to the exact organization project and lease" {
  let directory = @fs.tmpdir(prefix="delivery-media-authority-")
  defer @fs.rmdir(directory, recursive=true)
  let durable = @store.FileStore::open("\{directory}/state.json")
  let deliveries = @delivery.DeliveryStore::open("\{directory}/deliveries.json")
  let now = @async.now()
  let operation = deliveries.create(
    {
      tenant_id: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      authorization_ref: "admin-grant",
      lease_id: "lease-a",
      idempotency_key: "start-a",
      kind: Workspace,
      template_id: "video",
      template_version: "v1",
      model_digest: Some(
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      node_count: 1,
      expires_at_ms: now + 60000L,
    },
    now,
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "",
    "v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
    durable, runtime, "operator", "inference", "node", "test",
  ).with_delivery_store(deliveries)
  let owner : @media_jobs.Owner = {
    tenant_ref: "tenant-a",
    subject_ref: "subject-a",
    organization_id: "org-a",
    project_id: "project-a",
    authority: PrivateWorkspace("lease-a"),
  }
  let context : @media_jobs.ExecutionContext = {
    deployment_id: operation.operation_id,
    generation: 1L,
    node_id: "node-a",
    instance_id: None,
  }
  assert_true(service.media_order_matches(owner, context))
  assert_false(
    service.media_order_matches({ ..owner, tenant_ref: "tenant-b", }, context),
  )
  assert_false(
    service.media_order_matches({ ..owner, project_id: "project-b", }, context),
  )
  assert_false(
    service.media_order_matches(
      { ..owner, authority: PrivateWorkspace("other-lease"), },
      context,
    ),
  )
  assert_false(
    service.media_order_matches(
      { ..owner, authority: DedicatedOrder("other-order"), },
      context,
    ),
  )
}

///|
async test "workspace provisioning is tracked before ready and stopping requires separate workload evidence" {
  let directory = @fs.tmpdir(prefix="delivery-workspace-stop-")
  defer @fs.rmdir(directory, recursive=true)
  let store = @delivery.DeliveryStore::open("\{directory}/deliveries.json")
  let now = @async.now()
  let created = store.create(
    {
      tenant_id: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      authorization_ref: "admin-grant",
      lease_id: "lease-a",
      idempotency_key: "start-a",
      kind: GpuContainer,
      template_id: "gpu-container",
      template_version: "v1",
      model_digest: None,
      node_count: 1,
      expires_at_ms: now + 60000L,
    },
    now,
  )
  let reserved = store.observe(
    created.operation_id,
    created.generation,
    Reserved(reservation_id="reservation-a", node_ids=["node-a"]),
    now,
  )
  let provisioning = store.observe(
    created.operation_id,
    reserved.generation,
    WorkspaceStarting(workspace_id="workspace-a"),
    now,
  )
  assert_eq(provisioning.stage, StartingWorkspace)
  assert_eq(provisioning.workspace_id, Some("workspace-a"))
  let stopping = store.stop(created.operation_id, provisioning.generation, now)
  let stopped = store.observe(
    created.operation_id,
    stopping.generation,
    WorkspaceStopped,
    now,
  )
  assert_eq(stopped.workspace_id, None)
  assert_eq(stopped.stage, Stopping)
}

///|
async test "reserved assignment publication rejects shared and foreign owners but accepts its service claim" {
  let directory = @fs.tmpdir(prefix="delivery-publication-")
  defer @fs.rmdir(directory, recursive=true)
  let now = @async.now()
  let template = machine_dedicated_template()
  let registry = machine_dedicated_registry(
    "\{directory}/registry.json",
    template,
  )
  let durable = @store.FileStore::open("\{directory}/state.json")
  let scheduler = @scheduler.FileScheduler::open(
    "\{directory}/scheduler.json",
    8,
  )
  ignore(
    scheduler.reserve_nodes(
      {
        reservation_id: "reservation-a",
        idempotency_key: "reserve-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        authority_ref: "admin-grant",
        lease_id: "lease-a",
        node_ids: ["node-a"],
        starts_unix_ms: now - 1L,
        expires_unix_ms: now + 60000L,
        memory_mib_per_node: 100000,
        gpu_memory_mib_per_node: 90000,
        max_concurrency_per_node: 4,
      },
      ["node-a"],
      now,
    ),
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "",
    "v1",
    template.runtime.image_digest,
    template.artifact.digest,
    allow_http_loopback=true,
  )
  let base = ApiService::with_registry(
    durable, registry, runtime, "operator", "inference", "node", "test",
  ).with_assignment_signing_secret("assignment-secret")
  let taints : Map[String, Json] = Map([])
  let host = @reservation_host.ReservationHost::new(
    (verb, path, body) => {
      if path.has_prefix("/api/v1/pods?") {
        return (200, { "items": [] })
      }
      if verb == "PATCH" {
        guard body is Some(Array(ops)) && ops[1] is { "value": value, .. } else {
          fail("invalid taint patch")
        }
        taints["current"] = value
      }
      (
        200,
        {
          "metadata": { "name": "spark-a", "resourceVersion": "1" },
          "spec": { "taints": taints.get("current").unwrap_or([]) },
        },
      )
    },
    "workspaces",
    [],
  )
  let service = { ..base, scheduler: Some(scheduler), }.with_reservation_host(
    host,
    { "node-a": "spark-a" },
  )
  let assignment : @contracts.DesiredAssignment = {
    assignment_id: "delivery-model",
    deployment_id: "delivery-a",
    node_id: "node-a",
    artifact: template.artifact,
    runtime: template.runtime,
    resources: template.resources,
    devices: ["gpu-0"],
    network: template.network,
    health: template.health,
    data_policy: template.data_policy,
    generation: 1L,
    lease_expires_unix_ms: now + 30000L,
    controller_epoch: durable.controller_epoch(),
    group: None,
    reservation: None,
    signature: "",
  }
  try service.publish_planned_assignment(assignment) catch {
    @deployment.DeploymentError::InvalidState(_) => ()
    error => raise error
  } noraise {
    _ => fail("shared publication entered reserved node")
  }
  ignore(
    scheduler.claim_node_service(
      "reservation-a",
      "tenant-a",
      {
        service_id: assignment.assignment_id,
        node_id: "node-a",
        memory_mib: 2048,
        gpu_memory_mib: 1024,
        concurrency: 1,
      },
      now,
    ),
  )
  try
    service.publish_planned_assignment(
      assignment,
      reservation_id="reservation-a",
      tenant_ref="tenant-b",
    )
  catch {
    @deployment.DeploymentError::InvalidState(_) => ()
    error => raise error
  } noraise {
    _ => fail("foreign publication entered reserved node")
  }
  service.publish_planned_assignment(
    assignment,
    reservation_id="reservation-a",
    tenant_ref="tenant-a",
  )
  assert_true(
    durable
    .assignment(assignment.assignment_id)
    .map_or(false, value => value.signature != ""),
  )
  let published = durable.assignment(assignment.assignment_id).unwrap()
  assert_eq(
    published.reservation,
    Some({ reservation_id: "reservation-a", tenant_ref: "tenant-a", }),
  )
  assert_true(taints.contains("current"))
  try
    service.publish_planned_assignment(
      { ..assignment, reservation: published.reservation, },
      reservation_id="reservation-a",
      tenant_ref="tenant-a",
    )
  catch {
    @deployment.DeploymentError::InvalidState(_) => ()
    error => raise error
  } noraise {
    _ => fail("caller-controlled reservation metadata accepted")
  }
}
