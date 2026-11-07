///|
async test "model pool actions require operator authority and configured scope" {
  let directory = @fs.tmpdir(prefix="model-pool-api-")
  defer @fs.rmdir(directory, recursive=true)
  let store = @store.FileStore::open(directory + "/control.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses",
    "",
    "test",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
  )
  let service = ApiService::new(
    store, runtime, "operator", "inference", "node", "test",
  )
  for
    action in [
      "adopt", "prepare", "switch", "activate", "rollback", "benchmark", "speculative",
      "tuning", "scope",
    ] {
    assert_eq(
      service.handle(Post, "/v1/model-pool:" + action, Map([]), "{}").status,
      401,
    )
    assert_eq(
      service.handle(
        Post,
        "/v1/model-pool:" + action,
        { "Authorization": "Bearer operator" },
        "{}",
      ).status,
      503,
    )
  }
  assert_true(store.assignments().is_empty())
}

///|
async test "scope UI action drains routing before pause and retries without interrupting a stream" {
  let directory = @fs.tmpdir(prefix="model-pool-scope-api-")
  defer @fs.rmdir(directory, recursive=true)
  let targets : Array[@model_pool.Target] = [
    for i in 0..<4 => {
      {
        deployment: "model-\{i}",
        node_id: "node-\{i}",
        kube_node: "node-\{i}",
        cache_root: "/cache",
      }
    }
  ]
  let writes : Array[String] = []
  let transport : @model_pool.Transport = (verb, path, _) => {
    let target = targets
      .iter()
      .find_first(t => path.has_suffix("/" + t.deployment))
      .unwrap()
    if verb == "PATCH" {
      writes.push(target.node_id)
      return (200, {})
    }
    (
      200,
      {
        "metadata": {
          "name": target.deployment,
          "uid": target.node_id,
          "resourceVersion": "1",
        },
        "spec": {
          "replicas": 1,
          "template": {
            "spec": {
              "nodeSelector": { "kubernetes.io/hostname": target.kube_node },
            },
          },
        },
      },
    )
  }
  let pool = @model_pool.Pool::open(
    transport,
    "models",
    targets,
    directory + "/pool.json",
  )
  pool.adopt()
  let store = @store.FileStore::open(directory + "/control.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses",
    "",
    "test",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
  )
  let service = ApiService::new(
    store, runtime, "operator", "inference", "node", "test",
  ).with_event_text_pool(
    {
      model_alias: "test",
      served_model: "test",
      runtime_version: "v1",
      image_digest: "sha256:" + "b".repeat(64),
      artifact_digest: "sha256:" + "a".repeat(64),
      replicas: [
        for i in 0..<4 => {
          { node_id: "node-\{i}", origin: "http://127.0.0.1:\{9000 + i}", }
        }
      ],
    },
    "credential",
  )
  let service = { ..service, model_pool: Some(pool), }
  let deployments = @deployment_store.FileDeploymentStore::open(
    directory + "/deployments.json",
    "fixture-authority",
  )
  let service = service.with_deployment_store(deployments)
  for target in targets {
    deployments.adopt_service({
      service_id: target.deployment,
      model_alias: "test",
      artifact_digest: "sha256:" + "a".repeat(64),
      owner: { tenant_ref: "", organization_id: "", reservation_id: None, },
      node_ids: [target.node_id],
      runtime_kind: Kubernetes,
      binding_ref: target.deployment,
      exclusive: true,
      generation: 1L,
      desired_running: true,
      observed: Running,
      updated_unix_ms: @async.now(),
    })
  }
  assert_eq(
    service.event_trial_router.reserve("live", ["node-2"], 0),
    Some("node-2"),
  )
  let body : Json = {
    "node_ids": ["node-0", "node-1"],
    "names": { "node-0": "176", "node-1": "177" },
  }
  let first = service.handle(
    Post,
    "/v1/model-pool:scope",
    { "Authorization": "Bearer operator" },
    body.stringify(),
  )
  assert_eq(first.status, 409)
  assert_true(first.body.contains("不会中断回答"))
  assert_true(writes.is_empty())
  assert_eq(service.active_event_routes().map(r => r.node_id), [
    "node-0", "node-1",
  ])
  service.event_trial_router.release("live")
  let retry = service.handle(
    Post,
    "/v1/model-pool:scope",
    { "Authorization": "Bearer operator" },
    body.stringify(),
  )
  assert_eq(retry.status, 200)
  assert_eq(writes, ["node-2", "node-3"])
  assert_true(retry.body.contains("177"))
}
