///|
test "two-machine controls exclude parked replicas and keep unapplied scope explicit" {
  let pool = decode_model_pool_view({
    "adopted": true,
    "active": true,
    "generation": Json(3L),
    "model": "qwen",
    "models": ["qwen"],
    "speculative_tokens": 1,
    "replicas": Json(
      [
        for i in 0..<4 => {
          (
            {
              "node_id": "node-\{i}",
              "display_name": "\{176 + i}",
              "deployment": "service-\{i}",
              "can_prepare": true,
              "cache_ready": true,
              "switched": true,
              "ready": i < 2,
              "configuration_ready": i < 2,
              "speculative_tokens": 1,
              "selected": i < 2,
              "paused": i >= 2,
              "progress": "",
            } : Json)
        }
      ],
    ),
    "benchmark": [],
  })
  let panel = { ..empty_model_pool_panel(), view: Some(pool), }
  assert_eq(pool_scope_nodes(panel, pool), ["node-0", "node-1"])
  let state = { ..demo_state(), route: Deployments, model_pool: panel, }
  let html = render(state)
  assert_true(html.contains("共享模型池"))
  assert_true(html.contains("已生效 2/2 台"))
  assert_true(html.contains("已退出路由 · 模型已停止"))
  assert_false(html.contains("已生效 2/4 台"))
  let pending = { ..panel, tuning_draft: { "node:node-1": "off" }, }
  assert_eq(pool_scope_nodes(pending, pool), ["node-0"])
  assert_true(
    render({ ..state, model_pool: pending, }).contains(
      "节点范围或名称尚未应用",
    ),
  )
}
