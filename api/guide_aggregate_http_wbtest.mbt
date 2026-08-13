///|
async test "guide diagnostics token receives aggregate-only controller evidence" {
  let directory = @fs.tmpdir(prefix="lunanexa-guide-aggregate-")
  let store = @store.FileStore::open("\{directory}/state.json")
  store.put_heartbeat({
    node_id: "private-node-identity",
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: "private-node-identity",
      agent_version: "test",
      os_release: "test",
      runtime_names: [],
      accelerators: [],
      labels: Map([]),
      taints: [],
    },
    running_deployments: [],
    timestamp_unix_ms: @async.now(),
    signature: "",
  })
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
    store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_guide_diagnostics_token(
    "guide-readonly-diagnostics-token-more-than-thirty-two-bytes",
  )
  let operator_denied = service.handle(
    Get,
    "/v1/guide-diagnostics/aggregate",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(operator_denied.status, 401)
  let response = service.handle(
    Get,
    "/v1/guide-diagnostics/aggregate",
    {
      "Authorization": "Bearer guide-readonly-diagnostics-token-more-than-thirty-two-bytes",
    },
    "",
  )
  assert_eq(response.status, 200)
  assert_true(response.body.contains("lunanexa.guide-controller-aggregate.v1"))
  assert_true(response.body.contains("\"health\":\"degraded\""))
  assert_true(response.body.contains("\"Active\""))
  assert_false(response.body.contains("private-node-identity"))
  assert_false(response.body.contains("node_id"))
  assert_false(response.body.contains("subject_ref"))
  assert_false(response.body.contains("credential"))
  assert_true(response.body.length() < 65536)
  assert_true(
    store
    .audit_events()
    .any(event => event.action == "guide-diagnostics.aggregate-read"),
  )
  @fs.rmdir(directory, recursive=true)
}
