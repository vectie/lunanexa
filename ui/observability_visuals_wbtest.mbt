///|
#warnings("-alert_unstable")
fn render_observability_visual(html : @rabbita.Html) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(html))
}

///|
test "observability visuals render populated demo values without inventing scales" {
  let state = demo_state()
  let requests = render_observability_visual(request_telemetry_chart(state))
  assert_true(requests.contains("Aggregate request snapshot"))
  assert_true(requests.contains("Window/profile: not supplied"))
  for value in ["1842", "142", "38", "3"] {
    assert_true(requests.contains(value))
  }
  assert_true(requests.contains("do not imply a shared scale or trend"))
  let benchmarks = render_observability_visual(
    benchmark_comparison_chart(state),
  )
  assert_true(
    benchmarks.contains(
      "demo-throughput · p95 142 ms · 38/s · failures 1‰ · demo-run-01",
    ),
  )
  assert_true(benchmarks.contains("Lane length and order carry no numeric"))
  let audit = render_observability_visual(audit_decision_graph(state))
  for
    value in [
      "demo-operator", "cluster.snapshot", "4-node demo fleet", "accepted", "demo:audit:01",
    ] {
    assert_true(audit.contains(value))
  }
  assert_true(
    audit.contains("actor → decision → evidence → result → receipt"),
  )
}

///|
test "observability visuals keep empty state and zero snapshot explicit" {
  let state = default_state()
  let requests = render_observability_visual(request_telemetry_chart(state))
  assert_true(
    requests.contains("All four values in the current snapshot are zero."),
  )
  assert_true(requests.contains("Window not supplied"))
  let benchmarks = render_observability_visual(
    benchmark_comparison_chart(state),
  )
  assert_true(benchmarks.contains("No benchmark evidence is available."))
  let audit = render_observability_visual(audit_decision_graph(state))
  assert_true(audit.contains("No audit decision paths are available."))
}

///|
test "observability visuals localize structure while preserving evidence" {
  let state = {
    ..demo_state(),
    locale: ChineseSimplified,
    benchmark_evidence: ["profile.raw · p95 77 ms · opaque-unit"],
    audit: [
      {
        actor: "操作员甲",
        decision: "decision.raw",
        evidence: "证据甲",
        result: "vendor-result",
        receipt: "receipt:原始",
      },
    ],
  }
  let requests = render_observability_visual(request_telemetry_chart(state))
  assert_true(requests.contains("请求聚合快照"))
  assert_true(requests.contains("时间窗口/配置：未提供"))
  assert_true(requests.contains("已上报百分位；采样窗口不可用"))
  let benchmarks = render_observability_visual(
    benchmark_comparison_chart(state),
  )
  assert_true(benchmarks.contains("已记录的基准证据"))
  assert_true(benchmarks.contains("profile.raw · p95 77 ms · opaque-unit"))
  let audit = render_observability_visual(audit_decision_graph(state))
  for
    value in [
      "从操作者到不可变回执", "操作员甲", "decision.raw", "vendor-result",
      "receipt:原始",
    ] {
    assert_true(audit.contains(value))
  }
}

///|
test "observability visual evidence is escaped and has accessible alternatives" {
  let hostile = "<img src=x onerror=alert(1)>"
  let state = {
    ..default_state(),
    benchmark_evidence: [hostile],
    audit: [
      {
        actor: hostile,
        decision: hostile,
        evidence: hostile,
        result: hostile,
        receipt: hostile,
      },
    ],
  }
  let benchmark = render_observability_visual(benchmark_comparison_chart(state))
  let audit = render_observability_visual(audit_decision_graph(state))
  for html in [benchmark, audit] {
    assert_false(html.contains(hostile))
    assert_false(html.contains("<img"))
    assert_true(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
    assert_true(html.contains("<figure"))
    assert_true(html.contains("<figcaption"))
    assert_true(html.contains("<table"))
  }
  let requests = render_observability_visual(request_telemetry_chart(state))
  assert_true(requests.contains("Request data table"))
  assert_true(requests.contains("<figcaption"))
  let styles = observability_visual_styles()
  assert_true(styles.contains("@media (max-width: 54rem)"))
  assert_true(styles.contains(".obs-audit-path"))
}
