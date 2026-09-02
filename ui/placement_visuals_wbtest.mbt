///|
#warnings("-alert_unstable")
fn render_visual(html : @rabbita.Html) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(html))
}

///|
test "deployment placement graph uses exact reported deployment relationship" {
  let base = default_state()
  let state : ConsoleState = {
    ..base,
    deployments: [
      {
        assignment_id: "assignment-1",
        deployment_id: "service-1",
        desired: Ready,
        observed: Degraded,
        placement_reason: "scheduler evidence",
      },
    ],
    nodes: [
      {
        node_id: "node-1",
        state: Draining,
        architecture: "nvidia-gb10",
        total_memory_mib: 100,
        free_memory_mib: 40,
        used_memory_mib: 60,
        utilization_per_mille: 500,
        temperature_celsius: 45,
        power_watts: 80,
        workloads: 1,
        lease_holder: "",
        active_assignment: "service-1",
        last_seen: "now",
      },
    ],
  }
  let html = render_visual(deployment_placement_graph(state))
  assert_true(html.contains("<figure"))
  assert_true(html.contains("<figcaption"))
  assert_true(html.contains("service-1"))
  assert_true(html.contains("node-1"))
  assert_true(html.contains("Desired"))
  assert_true(html.contains("Ready"))
  assert_true(html.contains("Observed"))
  assert_true(html.contains("Degraded"))
  assert_true(html.contains("Node state"))
  assert_true(html.contains("Draining"))
  assert_true(html.contains("<table"))
}

///|
test "deployment placement graph does not infer an unmatched node" {
  let demo = demo_state()
  let html = render_visual(
    deployment_placement_graph({
      ..demo,
      deployments: [
        {
          assignment_id: "assignment-missing",
          deployment_id: "service-missing",
          desired: Pending,
          observed: Pending,
          placement_reason: "node-should-not-be-inferred",
        },
      ],
    }),
  )
  assert_true(html.contains("Placement not reported"))
  assert_false(html.contains("node-should-not-be-inferred"))
  assert_false(html.contains("dgx-spark-01"))
}

///|
test "alert graph renders an honest zero-notification state" {
  let html = render_visual(alert_impact_graph(default_state()))
  assert_true(html.contains("No notification records"))
  assert_true(html.contains("does not independently prove node health"))
  assert_true(html.contains("<figure"))
  assert_true(html.contains("<table"))
  assert_false(html.contains("Affected node"))
}

///|
test "alert graph keeps an unknown node reference explicit" {
  let html = render_visual(
    alert_impact_graph({
      ..default_state(),
      notifications: [
        {
          notification_id: "notification-unknown-node",
          code: "NodeUnreachable",
          severity: Warning,
          lifecycle: Read,
          topic: ClusterHealth,
          created_unix_ms: 1L,
          generation: 1L,
          node_ref: "node-not-in-inventory",
          assigned_to: "",
          silenced_until_unix_ms: None,
        },
      ],
    }),
  )
  assert_true(html.contains("node-not-in-inventory"))
  assert_true(html.contains("Referenced node not found"))
  assert_true(html.contains("Node not found"))
  assert_false(html.contains("Affected node"))
}

///|
test "placement visuals localize labels in Chinese" {
  let demo = demo_state()
  let deployments = render_visual(
    deployment_placement_graph({ ..demo, locale: ChineseSimplified }),
  )
  assert_true(deployments.contains("部署放置关系"))
  assert_true(deployments.contains("期望状态"))
  assert_true(deployments.contains("观测状态"))
  assert_true(deployments.contains("分配节点"))
  let alerts = render_visual(
    alert_impact_graph({ ..demo, locale: ChineseSimplified, notifications: [] }),
  )
  assert_true(alerts.contains("告警影响图"))
  assert_true(alerts.contains("暂无通知记录"))
  assert_true(alerts.contains("不能独立证明节点健康"))
}

///|
test "placement visuals escape hostile identifiers and alert values" {
  let hostile = "<script>alert('x')</script>&\""
  let base = default_state()
  let node : NodeRow = {
    node_id: hostile,
    state: Unreachable,
    architecture: "hostile",
    total_memory_mib: 1,
    free_memory_mib: 0,
    used_memory_mib: 1,
    utilization_per_mille: 1000,
    temperature_celsius: 99,
    power_watts: 99,
    workloads: 1,
    lease_holder: "",
    active_assignment: hostile,
    last_seen: "never",
  }
  let deployment_html = render_visual(
    deployment_placement_graph({
      ..base,
      nodes: [node],
      deployments: [
        {
          assignment_id: hostile,
          deployment_id: hostile,
          desired: Failed,
          observed: Failed,
          placement_reason: hostile,
        },
      ],
    }),
  )
  assert_false(deployment_html.contains("<script>"))
  assert_true(deployment_html.contains("&lt;script&gt;"))
  let alert_html = render_visual(
    alert_impact_graph({
      ..base,
      nodes: [node],
      notifications: [
        {
          notification_id: hostile,
          code: hostile,
          severity: Critical,
          lifecycle: Unread,
          topic: ClusterHealth,
          created_unix_ms: 1L,
          generation: 1L,
          node_ref: hostile,
          assigned_to: hostile,
          silenced_until_unix_ms: None,
        },
      ],
    }),
  )
  assert_false(alert_html.contains("<script>"))
  assert_true(alert_html.contains("&lt;script&gt;"))
  assert_true(alert_html.contains("Unreachable"))
}

///|
test "placement visualization styles provide responsive graph layout" {
  let styles = placement_visual_styles()
  assert_true(styles.contains("@media (max-width: 760px)"))
  assert_true(styles.contains(".placement-row"))
  assert_true(styles.contains(".alert-card-critical"))
}
