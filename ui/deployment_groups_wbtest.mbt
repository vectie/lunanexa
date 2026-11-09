///|
test "deployment family comes from artifact identity and preserves company ownership" {
  let base = demo_state()
  let known = { ..base.models[0], model_id: "incoai-glm-5.3-flash-dflash2", }
  let row = {
    ..base.deployments[0],
    deployment_id: "qwen-is-just-a-service-name",
    model_digest: known.artifact_digest,
    node_id: "node-owned",
    resource_owner: "tenant-owned",
  }
  let state = {
    ..base,
    route: Deployments,
    models: [known],
    deployments: [row],
  }
  assert_eq(deployment_model_id(state, row), known.model_id)
  let html = render(state)
  assert_true(html.contains("GLM 5.3"))
  assert_true(html.contains("Company reservation"))
  assert_true(html.contains("node-owned"))
  assert_true(html.contains(row.assignment_id))
  assert_true(html.contains("Stop…"))
  let unknown = { ..row, model_digest: "unmatched", }
  assert_eq(deployment_model_id(state, unknown), "")
  assert_true(
    render({ ..state, deployments: [unknown], }).contains("Unidentified model"),
  )
}

///|
test "pool picker groups only available models by family and numeric generation" {
  let pool = decode_model_pool_view({
    "adopted": true,
    "active": true,
    "generation": Json(1L),
    "model": "qwen3.8-b",
    "models": ["qwen3.6-a", "qwen3.8-b"],
    "replicas": [],
  })
  let html = render({
    ..demo_state(),
    route: Deployments,
    model_pool: { ..empty_model_pool_panel(), view: Some(pool), },
  })
  assert_true(html.contains("<optgroup label=\"Qwen 3.8\">"))
  assert_true(
    html.find("<optgroup label=\"Qwen 3.8\">").unwrap() <
    html.find("<optgroup label=\"Qwen 3.6\">").unwrap(),
  )
  assert_false(html.contains("<optgroup label=\"GLM"))
  assert_true(html.contains("<summary>高级设置</summary>"))
  assert_true(html.contains("<details class=\"pool-deployment-settings\">"))
  assert_true(html.contains("服务未就绪"))
}

///|
#warnings("-alert_unstable")
test "stopped managed service offers start as a normal action while stop stays destructive" {
  let base = demo_state().deployments[0]
  let stopped = {
    ..base,
    assignment_id: "service:existing-service",
    observed: Stopped,
  }
  let start = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(deployment_item(ChineseSimplified, stopped, None))
  })
  assert_true(start.contains("class=\"primary-button\""))
  assert_true(start.contains(">启动</button>"))
  assert_false(start.contains("danger-secondary"))
  let running = { ..stopped, observed: Ready, }
  let stop = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(deployment_item(ChineseSimplified, running, None))
  })
  assert_true(stop.contains("class=\"danger-secondary\""))
  assert_true(stop.contains(">停止…</button>"))
  let assignment = { ..stopped, assignment_id: "assignment:old", }
  let legacy = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(deployment_item(ChineseSimplified, assignment, None))
  })
  assert_false(legacy.contains(">启动</button>"))
}
