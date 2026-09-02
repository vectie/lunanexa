///|
#warnings("-alert_unstable")
fn render_governance_visual(value : @rabbita.Html) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(value))
}

///|
test "lease graph separates current evidence from cleanup policy" {
  let state = demo_state()
  let html = render_governance_visual(lease_lifecycle_graph(state))
  assert_true(html.contains("<figure"))
  assert_true(html.contains("<figcaption"))
  assert_true(html.contains("Current evidence"))
  assert_true(html.contains("Exclusive machine authority"))
  assert_true(html.contains("Workspace capacity authority"))
  assert_true(html.contains("Exclusive-machine cleanup policy"))
  assert_true(html.contains("does not apply to workspace-capacity leases"))
  assert_true(html.contains("Revoke access"))
  assert_true(html.contains("Sanitize"))
  assert_true(html.contains("Verify"))
  assert_true(html.contains("Release"))
  assert_true(html.contains("not completion evidence"))
  assert_true(html.contains("accessible table"))
}

///|
test "governance graphs render explicit empty states" {
  let state = default_state()
  let leases = render_governance_visual(lease_lifecycle_graph(state))
  let centers = render_governance_visual(cost_center_hierarchy_graph(state))
  let agreements = render_governance_visual(agreement_lifecycle_graph(state))
  assert_true(leases.contains("No exclusive-machine or workspace-capacity"))
  assert_true(centers.contains("No cost center relationships"))
  assert_true(agreements.contains("No agreement lifecycle records"))
  assert_true(agreements.contains("No enterprise lease requests"))
  assert_true(leases.contains("<tbody"))
  assert_true(centers.contains("<tbody"))
  assert_true(agreements.contains("<tbody"))
}

///|
test "cost center graph exposes roots children and missing parents" {
  let state = {
    ..default_state(),
    cost_centers: [
      {
        cost_center_id: "cc-root",
        organization_id: "org-a",
        display_name: "Root center",
        parent_cost_center_id: "",
        project_count: 0,
        provisional_spend: "CNY 999.00",
        budget_posture: "Threshold 77%",
      },
      {
        cost_center_id: "cc-child",
        organization_id: "org-a",
        display_name: "Child center",
        parent_cost_center_id: "cc-root",
        project_count: 0,
        provisional_spend: "CNY 999.00",
        budget_posture: "Threshold 77%",
      },
      {
        cost_center_id: "cc-orphan",
        organization_id: "org-a",
        display_name: "Orphan center",
        parent_cost_center_id: "cc-missing",
        project_count: 0,
        provisional_spend: "CNY 999.00",
        budget_posture: "Threshold 77%",
      },
    ],
  }
  let html = render_governance_visual(cost_center_hierarchy_graph(state))
  assert_true(html.contains("Organization root"))
  assert_true(html.contains("Parent relationship"))
  assert_true(html.contains("Missing parent reference"))
  assert_true(html.contains("cc-missing"))
  assert_true(html.contains("governance-relationship-missing"))
  assert_false(html.contains("provisional_spend"))
  assert_false(html.contains("CNY 999.00"))
  assert_false(html.contains("Threshold 77%"))
}

///|
test "agreement graph shows actual state and conservative request handoff" {
  let state = {
    ..default_state(),
    agreements: [
      {
        agreement_id: "agreement-review",
        agreement_type: "Data processing",
        template_version: "dpa-v1",
        organization_id: "org-a",
        state: "Awaiting signature",
        evidence_receipt: "receipt-ref",
      },
    ],
    enterprise_lease_requests: [
      {
        request_id: "request-submitted",
        organization_id: "org-a",
        subject_ref: "subject-a",
        project_id: "project-a",
        unix_username: "alice",
        requested_models: "model-a",
        state: "Submitted",
        generation: 1L,
        assigned_node_id: "—",
      },
      {
        request_id: "request-approved",
        organization_id: "org-a",
        subject_ref: "subject-b",
        project_id: "project-b",
        unix_username: "bob",
        requested_models: "model-b",
        state: "Approved",
        generation: 2L,
        assigned_node_id: "node-2",
      },
    ],
  }
  let html = render_governance_visual(agreement_lifecycle_graph(state))
  assert_true(html.contains("Awaiting signature"))
  assert_true(html.contains("Operator decision pending"))
  assert_true(html.contains("No exclusive-lease handoff recorded"))
  assert_true(html.contains("node-2"))
  assert_true(html.contains("activation is not inferred"))
  assert_false(html.contains(">Executed<"))
}

///|
test "governance graphs localize Chinese evidence qualifiers" {
  let state = { ..demo_state(), locale: ChineseSimplified }
  let leases = render_governance_visual(lease_lifecycle_graph(state))
  let centers = render_governance_visual(cost_center_hierarchy_graph(state))
  let agreements = render_governance_visual(agreement_lifecycle_graph(state))
  assert_true(leases.contains("当前证据"))
  assert_true(leases.contains("独占机器清理策略"))
  assert_true(leases.contains("不是完成证据"))
  assert_true(centers.contains("已记录的组织层级"))
  assert_true(centers.contains("组织根节点"))
  assert_true(agreements.contains("已记录的协议生命周期"))
  assert_true(agreements.contains("企业申请交接"))
}

///|
test "governance graphs escape hostile labels and references" {
  let hostile = "<script>alert('x')</script>"
  let base = demo_state()
  let leases = render_governance_visual(
    lease_lifecycle_graph({
      ..base,
      exclusive_node_leases: [
        { ..base.exclusive_node_leases[0], lease_id: hostile },
      ],
    }),
  )
  let centers = render_governance_visual(
    cost_center_hierarchy_graph({
      ..base,
      cost_centers: [{ ..base.cost_centers[0], display_name: hostile }],
    }),
  )
  let agreements = render_governance_visual(
    agreement_lifecycle_graph({
      ..base,
      agreements: [{ ..base.agreements[0], evidence_receipt: hostile }],
      enterprise_lease_requests: [],
    }),
  )
  assert_false(leases.contains(hostile))
  assert_false(centers.contains(hostile))
  assert_false(agreements.contains(hostile))
  assert_true(leases.contains("&lt;script&gt;"))
  assert_true(centers.contains("&lt;script&gt;"))
  assert_true(agreements.contains("&lt;script&gt;"))
}

///|
test "governance styles cover narrow screens reduced motion and contrast" {
  let styles = governance_visual_styles()
  assert_true(styles.contains("@media(max-width:42rem)"))
  assert_true(styles.contains("prefers-reduced-motion"))
  assert_true(styles.contains("forced-colors"))
  assert_true(styles.contains("min-height:3rem"))
}
