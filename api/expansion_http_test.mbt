///|
async fn expansion_service(path : String) -> @api.ApiService {
  let durable = @store.FileStore::open(path)
  durable.fence_controller(1L)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses", "test-only-upstream-reference", "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  @api.ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  )
}

///|
async test "commercial API exposes tenant-scoped cost ledger vertical slice" {
  let directory = @fs.tmpdir(prefix="lunanexa-commercial-api-")
  let service = expansion_service("\{directory}/state.json")
  let headers = { "Authorization": "Bearer operator-token" }
  let organization : @commercial.Organization = {
    organization_id: "org-one",
    display_name: "Organization One",
    state: Active,
    verification_ref: Some("opaque-verification-reference"),
    created_unix_ms: 1000L,
  }
  let organization_reply = service.handle(
    Post,
    "/v1/commercial/organizations",
    headers,
    organization.to_json().stringify(),
  )
  assert_eq(organization_reply.status, 201)
  let center : @commercial.CostCenter = {
    cost_center_id: "center-ai",
    organization_id: "org-one",
    parent_cost_center_id: None,
    display_name: "AI Platform",
    created_unix_ms: 1001L,
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/commercial/cost-centers",
      headers,
      center.to_json().stringify(),
    ).status,
    201,
  )
  let project : @commercial.Project = {
    project_id: "project-maas",
    organization_id: "org-one",
    cost_center_id: "center-ai",
    display_name: "Managed inference",
    created_unix_ms: 1002L,
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/commercial/projects",
      headers,
      project.to_json().stringify(),
    ).status,
    201,
  )
  let usage : @commercial.UsageObservation = {
    event_id: "usage-one",
    organization_id: "org-one",
    project_id: "project-maas",
    actor_ref: "opaque-user",
    workload_id: "deployment-one",
    node_id: "dgx-2",
    lease_epoch: 4L,
    meter: "node-second",
    quantity: 60L,
    unit: "second",
    started_unix_ms: 2000L,
    ended_unix_ms: 62000L,
    observed_unix_ms: 62001L,
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/commercial/usage",
      headers,
      usage.to_json().stringify(),
    ).status,
    201,
  )
  let rate : @commercial.RateCard = {
    rate_card_id: "rate-node-second",
    version: "v1",
    meter: "node-second",
    unit: "second",
    unit_price: @commercial.money(2L, "CNY", 2),
    effective_from_unix_ms: 1L,
    effective_until_unix_ms: 100000L,
  }
  let rated = service.handle(
    Post,
    "/v1/commercial/usage:rate",
    headers,
    (
      {
        "event_id": "usage-one",
        "entry_id": "entry-one",
        "rate": rate.to_json(),
        "recorded_unix_ms": 62002L.to_json(),
      } : Json).stringify(),
  )
  assert_eq(rated.status, 201)
  assert_true(rated.body.contains("entry-one"))
  let snapshot = service.handle(
    Get,
    "/v1/commercial/organizations/org-one/snapshot",
    headers,
    "",
  )
  assert_eq(snapshot.status, 200)
  assert_true(snapshot.body.contains("project-maas"))
  let unauthorized = service.handle(
    Get,
    "/v1/commercial/organizations/org-one/snapshot",
    {},
    "",
  )
  assert_eq(unauthorized.status, 401)
}

///|
async test "technical decision API fails closed and returns fenced autoscale decision" {
  let directory = @fs.tmpdir(prefix="lunanexa-technical-api-")
  let service = expansion_service("\{directory}/state.json")
  let headers = { "Authorization": "Bearer operator-token" }
  let policy : @technical.AutoscalePolicy = {
    policy_version: "policy-v1",
    min_replicas: 1,
    max_replicas: 4,
    scale_up_step: 1,
    scale_down_step: 1,
    sample_window_ms: 30000L,
    cooldown_ms: 10000L,
    target_p95_latency_ms: 500L,
    target_queue_depth: 2,
    required_lease_generation: 7L,
  }
  let snapshot : @technical.AutoscaleSnapshot = {
    deployment_id: "deployment-one",
    desired_replicas: 1,
    ready_replicas: 1,
    available_replica_capacity: 2,
    p95_latency_ms: 900L,
    queue_depth: 5,
    oldest_sample_unix_ms: 10000L,
    newest_sample_unix_ms: 40000L,
    last_scale_unix_ms: None,
    observed_lease_generation: 7L,
    lease_expires_unix_ms: 100000L,
    now_unix_ms: 50000L,
  }
  let reply = service.handle(
    Post,
    "/v1/technical/autoscale:decide",
    headers,
    ({ "policy": policy.to_json(), "snapshot": snapshot.to_json() } : Json).stringify(),
  )
  assert_eq(reply.status, 200)
  assert_true(reply.body.contains("ScaleUp"))
  let stale = { ..snapshot, observed_lease_generation: 6L }
  let fenced = service.handle(
    Post,
    "/v1/technical/autoscale:decide",
    headers,
    ({ "policy": policy.to_json(), "snapshot": stale.to_json() } : Json).stringify(),
  )
  assert_eq(fenced.status, 200)
  assert_true(fenced.body.contains("LeaseFenceMismatch"))
  let unauthorized = service.handle(
    Post,
    "/v1/technical/autoscale:decide",
    {},
    "{}",
  )
  assert_eq(unauthorized.status, 401)
}
