///|
fn governance_copy(locale : @i18n.Locale, en : String, zh : String) -> String {
  if locale.is_chinese() {
    zh
  } else {
    en
  }
}

///|
fn governance_missing_ref(value : String) -> Bool {
  value.trim() == ""
}

///|
fn governance_workspace_state(
  locale : @i18n.Locale,
  state : @workspace.WorkspaceLeaseState,
) -> String {
  match state {
    Requested => governance_copy(locale, "Requested", "待审批")
    Active => governance_copy(locale, "Active", "有效")
    Suspended => governance_copy(locale, "Suspended", "已暂停")
    Expired => governance_copy(locale, "Expired", "已过期")
    Revoked => governance_copy(locale, "Revoked", "已撤销")
  }
}

///|
fn governance_exclusive_state(locale : @i18n.Locale, state : String) -> String {
  match state {
    "Requested" => governance_copy(locale, "Requested", "待审批")
    "Reserved" => governance_copy(locale, "Reserved", "已预留")
    "Provisioning" => governance_copy(locale, "Provisioning", "正在开通")
    "Active" => governance_copy(locale, "Active", "有效")
    "Expiring" => governance_copy(locale, "Expiring", "正在到期")
    "Draining" => governance_copy(locale, "Draining", "正在排空")
    "RevokingAccess" =>
      governance_copy(locale, "Revoking access", "正在撤销访问")
    "Sanitizing" => governance_copy(locale, "Sanitizing", "正在清理")
    "Verifying" => governance_copy(locale, "Verifying", "正在验证")
    "Completed" => governance_copy(locale, "Completed", "已完成")
    "Cancelled" => governance_copy(locale, "Cancelled", "已取消")
    "Quarantined" => governance_copy(locale, "Quarantined", "已隔离")
    _ => state
  }
}

///|
fn governance_node(
  eyebrow : String,
  title : String,
  detail : String,
  tone : String,
) -> @rabbita.Html {
  @html.div(class="governance-node governance-node-\{tone}", [
    @html.span(class="governance-node-eyebrow", eyebrow),
    @html.strong(title),
    @html.span(class="governance-node-detail", detail),
  ])
}

///|
fn governance_arrow(locale : @i18n.Locale) -> @rabbita.Html {
  @html.span(
    class="governance-arrow",
    attrs=@html.Attrs::build().aria_label(
      governance_copy(locale, "connects to", "连接到"),
    ),
    "→",
  )
}

///|
fn governance_table(
  locale : @i18n.Locale,
  summary : String,
  caption : String,
  headings : Array[String],
  rows : Array[@rabbita.Html],
) -> @rabbita.Html {
  let body_rows = if rows.length() == 0 {
    [
      @html.tr(
        @html.td(
          colspan=headings.length(),
          governance_copy(locale, "No records loaded.", "未加载记录。"),
        ),
      ),
    ]
  } else {
    rows
  }
  @html.details(class="governance-data-alternative", [
    @html.summary(summary),
    @html.div(
      class="governance-table-scroll",
      attrs=@html.Attrs::build().tabindex(0).aria_label(summary),
      [
        @html.table(class="governance-table", [
          @html.caption(caption),
          @html.thead(
            @html.tr(
              [
                for heading in headings => @html.th(scope=Col, heading)
              ],
            ),
          ),
          @html.tbody(body_rows),
        ]),
      ],
    ),
  ])
}

///|
fn lease_lifecycle_graph(state : ConsoleState) -> @rabbita.Html {
  let cards : Array[@rabbita.Html] = []
  let rows : Array[@rabbita.Html] = []
  for lease in state.exclusive_node_leases {
    cards.push(
      @html.article(class="governance-record", [
        @html.span(
          class="governance-authority-label",
          governance_copy(
            state.locale,
            "Exclusive machine authority",
            "独占机器权限",
          ),
        ),
        governance_node(
          governance_copy(state.locale, "Lease", "租约"),
          lease.lease_id,
          "\{lease.node_id} · \{lease.subject_ref}",
          "record",
        ),
        governance_arrow(state.locale),
        governance_node(
          governance_copy(state.locale, "Current state", "当前状态"),
          governance_exclusive_state(state.locale, lease.state),
          governance_copy(
            state.locale,
            "Generation \{lease.generation} · expires \{lease.expires_at}",
            "代际 \{lease.generation} · 到期 \{lease.expires_at}",
          ),
          if lease.state == "Quarantined" {
            "warning"
          } else {
            "current"
          },
        ),
      ]),
    )
    rows.push(
      @html.tr([
        @html.td(
          governance_copy(state.locale, "Exclusive machine", "独占机器"),
        ),
        @html.td(class="mono", lease.lease_id),
        @html.td(governance_exclusive_state(state.locale, lease.state)),
        @html.td(
          "\{lease.node_id} · \{lease.subject_ref} · gen \{lease.generation}",
        ),
      ]),
    )
  }
  for lease in state.compute_leases {
    cards.push(
      @html.article(class="governance-record", [
        @html.span(
          class="governance-authority-label",
          governance_copy(
            state.locale,
            "Workspace capacity authority",
            "工作区容量权限",
          ),
        ),
        governance_node(
          governance_copy(state.locale, "Lease", "租约"),
          lease.lease_id,
          "\{lease.workspace} · \{lease.user_id}",
          "record",
        ),
        governance_arrow(state.locale),
        governance_node(
          governance_copy(state.locale, "Current state", "当前状态"),
          governance_workspace_state(state.locale, lease.state),
          "\{lease.started_at} → \{lease.expires_at}",
          "current",
        ),
      ]),
    )
    rows.push(
      @html.tr([
        @html.td(
          governance_copy(state.locale, "Workspace capacity", "工作区容量"),
        ),
        @html.td(class="mono", lease.lease_id),
        @html.td(governance_workspace_state(state.locale, lease.state)),
        @html.td("\{lease.workspace} · \{lease.user_id}"),
      ]),
    )
  }
  let evidence = if cards.length() == 0 {
    @html.p(
      class="governance-inline-empty",
      governance_copy(
        state.locale,
        "No exclusive-machine or workspace-capacity lease records are loaded.",
        "未加载独占机器或工作区容量租约记录。",
      ),
    )
  } else {
    @html.div(class="governance-record-grid", cards)
  }
  @html.figure(class="governance-graph lease-lifecycle-graph", [
    @html.div(class="governance-graph-body", [
      @html.div(class="governance-current-evidence", [
        @html.div(class="governance-lane-heading", [
          @html.strong(
            governance_copy(state.locale, "Current evidence", "当前证据"),
          ),
          @html.span(
            governance_copy(
              state.locale,
              "Recorded states only",
              "仅显示已记录状态",
            ),
          ),
        ]),
        evidence,
      ]),
      @html.div(class="governance-policy-reference", [
        @html.div(class="governance-lane-heading", [
          @html.strong(
            governance_copy(
              state.locale,
              "Exclusive-machine cleanup policy",
              "独占机器清理策略",
            ),
          ),
          @html.span(
            governance_copy(
              state.locale,
              "Required cleanup chain — not completion evidence",
              "必需清理链——不是完成证据",
            ),
          ),
        ]),
        @html.div(class="governance-policy-flow", [
          governance_node(
            "1",
            governance_copy(state.locale, "Revoke access", "撤销访问"),
            governance_copy(state.locale, "Required stage", "必需阶段"),
            "policy",
          ),
          governance_arrow(state.locale),
          governance_node(
            "2",
            governance_copy(state.locale, "Sanitize", "清理"),
            governance_copy(state.locale, "Required stage", "必需阶段"),
            "policy",
          ),
          governance_arrow(state.locale),
          governance_node(
            "3",
            governance_copy(state.locale, "Verify", "验证"),
            governance_copy(state.locale, "Required stage", "必需阶段"),
            "policy",
          ),
          governance_arrow(state.locale),
          governance_node(
            "4",
            governance_copy(state.locale, "Release", "释放"),
            governance_copy(state.locale, "Required stage", "必需阶段"),
            "policy",
          ),
        ]),
      ]),
      governance_table(
        state.locale,
        governance_copy(
          state.locale,
          "Current lease records — accessible table",
          "当前租约记录——无障碍表格",
        ),
        governance_copy(
          state.locale,
          "Current evidence only; cleanup is a policy sequence.",
          "仅列出当前证据；清理是策略顺序。",
        ),
        [
          governance_copy(state.locale, "Authority", "权限类型"),
          governance_copy(state.locale, "Lease", "租约"),
          governance_copy(state.locale, "Recorded state", "记录状态"),
          governance_copy(state.locale, "Recorded scope", "记录范围"),
        ],
        rows,
      ),
    ]),
    @html.figcaption(
      governance_copy(
        state.locale,
        "Recorded lease state is separate from the mandatory exclusive-machine revoke → sanitize → verify → release policy; that policy does not apply to workspace-capacity leases, and its nodes never assert completed cleanup.",
        "已记录的租约状态与独占机器必须执行的撤销 → 清理 → 验证 → 释放策略相互独立；该策略不适用于工作区容量租约，且策略节点绝不表示清理已经完成。",
      ),
    ),
  ])
}

///|
fn governance_parent_relation(
  state : ConsoleState,
  center : CostCenterRow,
) -> (String, String, String) {
  let parent = center.parent_cost_center_id.trim().to_owned()
  if governance_missing_ref(parent) {
    (
      center.organization_id,
      governance_copy(state.locale, "Organization root", "组织根节点"),
      "root",
    )
  } else if parent == center.cost_center_id {
    (
      parent,
      governance_copy(
        state.locale,
        "Self-reference recorded",
        "记录了自引用",
      ),
      "missing",
    )
  } else {
    let count = state.cost_centers.count_if(candidate => {
      candidate.organization_id == center.organization_id &&
      candidate.cost_center_id == parent
    })
    if count == 1 {
      (
        parent,
        governance_copy(state.locale, "Parent relationship", "父子关系"),
        "child",
      )
    } else if count == 0 {
      (
        parent,
        governance_copy(
          state.locale,
          "Missing parent reference",
          "父级引用缺失",
        ),
        "missing",
      )
    } else {
      (
        parent,
        governance_copy(
          state.locale,
          "Ambiguous parent reference",
          "父级引用不唯一",
        ),
        "missing",
      )
    }
  }
}

///|
fn cost_center_hierarchy_graph(state : ConsoleState) -> @rabbita.Html {
  let organizations : Array[String] = []
  let groups : Array[@rabbita.Html] = []
  let rows : Array[@rabbita.Html] = []
  for center in state.cost_centers {
    if !organizations.contains(center.organization_id) {
      organizations.push(center.organization_id)
    }
    let (source, relation, _) = governance_parent_relation(state, center)
    rows.push(
      @html.tr([
        @html.td(class="mono", center.organization_id),
        @html.td(class="mono", source),
        @html.td(relation),
        @html.td([
          @html.strong(center.display_name),
          @html.span(class="mono governance-table-id", center.cost_center_id),
        ]),
      ]),
    )
  }
  for organization_id in organizations {
    let relations : Array[@rabbita.Html] = []
    for center in state.cost_centers {
      if center.organization_id == organization_id {
        let (source, relation, tone) = governance_parent_relation(state, center)
        relations.push(
          @html.div(
            class="governance-relationship governance-relationship-\{tone}",
            [
              governance_node(
                if tone == "root" {
                  governance_copy(state.locale, "Root source", "根来源")
                } else {
                  governance_copy(
                    state.locale,
                    "Parent reference",
                    "父级引用",
                  )
                },
                source,
                relation,
                if tone == "missing" {
                  "warning"
                } else {
                  "record"
                },
              ),
              governance_arrow(state.locale),
              governance_node(
                governance_copy(state.locale, "Cost center", "成本中心"),
                center.display_name,
                center.cost_center_id,
                "current",
              ),
            ],
          ),
        )
      }
    }
    groups.push(
      @html.section(class="governance-org-group", [
        governance_node(
          governance_copy(state.locale, "Organization", "组织"),
          organization_id,
          governance_copy(
            state.locale,
            "Recorded organization reference",
            "已记录的组织引用",
          ),
          "record",
        ),
        @html.div(class="governance-relationship-list", relations),
      ]),
    )
  }
  let graph = if groups.length() == 0 {
    @html.p(
      class="governance-inline-empty",
      governance_copy(
        state.locale,
        "No cost center relationships are loaded.",
        "未加载成本中心关系。",
      ),
    )
  } else {
    @html.div(class="governance-org-grid", groups)
  }
  @html.figure(class="governance-graph cost-center-hierarchy-graph", [
    @html.div(class="governance-graph-body", [
      @html.div(class="governance-lane-heading", [
        @html.strong(
          governance_copy(
            state.locale,
            "Recorded organization hierarchy",
            "已记录的组织层级",
          ),
        ),
        @html.span(
          governance_copy(
            state.locale,
            "No budget amounts are inferred from formatted labels",
            "不会从格式化标签推断预算金额",
          ),
        ),
      ]),
      graph,
      governance_table(
        state.locale,
        governance_copy(
          state.locale,
          "Cost center relationships — accessible table",
          "成本中心关系——无障碍表格",
        ),
        governance_copy(
          state.locale,
          "Actual organization and parent references.",
          "实际组织与父级引用。",
        ),
        [
          governance_copy(state.locale, "Organization", "组织"),
          governance_copy(state.locale, "Source", "来源"),
          governance_copy(state.locale, "Relationship", "关系"),
          governance_copy(state.locale, "Cost center", "成本中心"),
        ],
        rows,
      ),
    ]),
    @html.figcaption(
      governance_copy(
        state.locale,
        "Roots and unresolved parent references are explicit. Spend and budget strings are not parsed or converted into invented values.",
        "根节点与无法解析的父级引用均被明确标出。支出与预算字符串不会被解析或转换为臆造数值。",
      ),
    ),
  ])
}

///|
fn governance_handoff(
  state : ConsoleState,
  request : EnterpriseLeaseRequestRow,
) -> (String, String, String) {
  match request.state {
    "Submitted" =>
      (
        governance_copy(
          state.locale,
          "Operator decision pending",
          "等待运维决策",
        ),
        governance_copy(
          state.locale,
          "No exclusive-lease handoff recorded",
          "未记录独占租约交接",
        ),
        "policy",
      )
    "Approved" =>
      if governance_missing_ref(request.assigned_node_id) {
        (
          governance_copy(
            state.locale,
            "Assigned-node reference missing",
            "分配节点引用缺失",
          ),
          governance_copy(
            state.locale,
            "Approved state is recorded, but handoff evidence is incomplete",
            "已记录批准状态，但交接证据不完整",
          ),
          "warning",
        )
      } else {
        (
          request.assigned_node_id,
          governance_copy(
            state.locale,
            "Exclusive-lease handoff recorded; activation is not inferred",
            "已记录独占租约交接；不推断已激活",
          ),
          "current",
        )
      }
    "Rejected" | "Cancelled" =>
      (
        governance_copy(state.locale, "No handoff", "无交接"),
        governance_copy(
          state.locale,
          "Recorded state does not create an exclusive lease",
          "已记录状态不会创建独占租约",
        ),
        "record",
      )
    _ =>
      (
        governance_copy(state.locale, "Handoff unknown", "交接未知"),
        governance_copy(
          state.locale,
          "No handoff is inferred from an unrecognized state",
          "不会从未识别状态推断交接",
        ),
        "warning",
      )
  }
}

///|
fn agreement_lifecycle_graph(state : ConsoleState) -> @rabbita.Html {
  let agreement_cards : Array[@rabbita.Html] = []
  let request_cards : Array[@rabbita.Html] = []
  let rows : Array[@rabbita.Html] = []
  for agreement in state.agreements {
    let receipt = if agreement.evidence_receipt.trim() == "" {
      governance_copy(state.locale, "Not recorded", "未记录")
    } else {
      agreement.evidence_receipt
    }
    agreement_cards.push(
      @html.article(class="governance-record governance-agreement-record", [
        governance_node(
          governance_copy(state.locale, "Agreement", "协议"),
          agreement.agreement_id,
          "\{agreement.organization_id} · \{agreement.template_version}",
          "record",
        ),
        governance_arrow(state.locale),
        governance_node(
          governance_copy(state.locale, "Actual state", "实际状态"),
          agreement_state_label(state.locale, agreement.state),
          agreement_type_label(state.locale, agreement.agreement_type),
          "current",
        ),
        governance_arrow(state.locale),
        governance_node(
          governance_copy(state.locale, "Receipt reference", "回执引用"),
          receipt,
          governance_copy(
            state.locale,
            "Reference does not assert external verification",
            "引用不表示外部验证已完成",
          ),
          if agreement.evidence_receipt.trim() == "" {
            "warning"
          } else {
            "record"
          },
        ),
      ]),
    )
    rows.push(
      @html.tr([
        @html.td(governance_copy(state.locale, "Agreement", "协议")),
        @html.td(class="mono", agreement.agreement_id),
        @html.td(agreement_state_label(state.locale, agreement.state)),
        @html.td(receipt),
      ]),
    )
  }
  for request in state.enterprise_lease_requests {
    let (destination, detail, tone) = governance_handoff(state, request)
    request_cards.push(
      @html.article(class="governance-record", [
        governance_node(
          governance_copy(state.locale, "Enterprise request", "企业申请"),
          request.request_id,
          "\{request.organization_id} · gen \{request.generation}",
          "record",
        ),
        governance_arrow(state.locale),
        governance_node(
          enterprise_request_state_label(state.locale, request.state),
          destination,
          detail,
          tone,
        ),
      ]),
    )
    rows.push(
      @html.tr([
        @html.td(
          governance_copy(
            state.locale,
            "Enterprise lease request",
            "企业租用申请",
          ),
        ),
        @html.td(class="mono", request.request_id),
        @html.td(enterprise_request_state_label(state.locale, request.state)),
        @html.td("\{destination} · \{detail}"),
      ]),
    )
  }
  let agreements = if agreement_cards.length() == 0 {
    @html.p(
      class="governance-inline-empty",
      governance_copy(
        state.locale,
        "No agreement lifecycle records are loaded.",
        "未加载协议生命周期记录。",
      ),
    )
  } else {
    @html.div(class="governance-record-grid", agreement_cards)
  }
  let requests = if request_cards.length() == 0 {
    @html.p(
      class="governance-inline-empty",
      governance_copy(
        state.locale,
        "No enterprise lease requests are loaded.",
        "未加载企业租用申请。",
      ),
    )
  } else {
    @html.div(class="governance-record-grid", request_cards)
  }
  @html.figure(class="governance-graph agreement-lifecycle-graph", [
    @html.div(class="governance-graph-body", [
      @html.div(class="governance-lane-heading", [
        @html.strong(
          governance_copy(
            state.locale,
            "Recorded agreement lifecycle",
            "已记录的协议生命周期",
          ),
        ),
        @html.span(
          governance_copy(
            state.locale,
            "Only the actual current state is marked",
            "仅标记实际当前状态",
          ),
        ),
      ]),
      agreements,
      @html.div(class="governance-request-handoff", [
        @html.div(class="governance-lane-heading", [
          @html.strong(
            governance_copy(
              state.locale,
              "Enterprise request handoff",
              "企业申请交接",
            ),
          ),
          @html.span(
            governance_copy(
              state.locale,
              "Approval handoff is not lease activation",
              "批准交接并不等于租约激活",
            ),
          ),
        ]),
        requests,
      ]),
      governance_table(
        state.locale,
        governance_copy(
          state.locale,
          "Agreement and request records — accessible table",
          "协议与申请记录——无障碍表格",
        ),
        governance_copy(
          state.locale,
          "Actual states and recorded references only.",
          "仅列出实际状态与已记录引用。",
        ),
        [
          governance_copy(state.locale, "Record", "记录"),
          governance_copy(state.locale, "Identifier", "标识符"),
          governance_copy(state.locale, "Actual state", "实际状态"),
          governance_copy(state.locale, "Evidence / handoff", "证据 / 交接"),
        ],
        rows,
      ),
    ]),
    @html.figcaption(
      governance_copy(
        state.locale,
        "The graph presents recorded current states and references only; unsupported stages are never marked complete.",
        "图中仅展示已记录的当前状态与引用；不受投影支持的阶段绝不会被标记为已完成。",
      ),
    ),
  ])
}

///|
fn governance_visual_styles() -> String {
  (
    #|.governance-graph{margin:1rem 0 1.25rem;overflow:hidden;border:1px solid var(--line,#d5dee4);border-radius:.75rem;background:var(--surface,#fff)}
    #|.governance-graph-body{display:grid;gap:1rem;padding:1rem}
    #|.governance-graph figcaption{padding:.7rem 1rem;border-top:1px solid var(--line,#d5dee4);color:var(--muted,#60717a);font-size:.7rem;line-height:1.5}
    #|.governance-current-evidence,.governance-policy-reference,.governance-request-handoff{display:grid;gap:.7rem}
    #|.governance-policy-reference{padding:.85rem;border:1px dashed var(--line-strong,#9babb3);border-radius:.65rem}
    #|.governance-lane-heading{display:flex;align-items:baseline;justify-content:space-between;gap:1rem}
    #|.governance-lane-heading strong{font-size:.78rem}
    #|.governance-lane-heading span{color:var(--muted,#60717a);font-size:.68rem}
    #|.governance-record-grid,.governance-org-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,20rem),1fr));gap:.75rem}
    #|.governance-record{display:grid;grid-template-columns:minmax(0,1fr) auto minmax(0,1fr);align-items:stretch;gap:.45rem;padding:.7rem;border:1px solid var(--line,#d5dee4);border-radius:.65rem}
    #|.governance-agreement-record{grid-template-columns:minmax(0,1fr) auto minmax(0,1fr) auto minmax(0,1fr)}
    #|.governance-authority-label{grid-column:1/-1;color:var(--muted,#60717a);font-size:.64rem;font-weight:800;text-transform:uppercase}
    #|.governance-node{min-width:0;display:grid;align-content:center;gap:.2rem;padding:.65rem;border:1px solid var(--line-strong,#9babb3);border-radius:.55rem;background:var(--surface,#fff)}
    #|.governance-node strong,.governance-node-detail{overflow-wrap:anywhere}
    #|.governance-node-eyebrow{color:var(--muted,#60717a);font-size:.6rem;font-weight:850;text-transform:uppercase}
    #|.governance-node-detail{color:var(--muted,#60717a);font-size:.64rem;line-height:1.45}
    #|.governance-node-current{border-width:2px;border-color:var(--accent,var(--mint,#168363))}
    #|.governance-node-warning{border-width:2px;border-color:var(--warning,var(--amber,#b88300))}
    #|.governance-node-policy{border-style:dashed;background:transparent}
    #|.governance-arrow{display:grid;min-width:2rem;place-items:center;color:var(--muted,#60717a);font-weight:900}
    #|.governance-policy-flow{display:grid;grid-template-columns:minmax(7rem,1fr) auto minmax(7rem,1fr) auto minmax(7rem,1fr) auto minmax(7rem,1fr);gap:.4rem}
    #|.governance-inline-empty{margin:0;padding:.8rem;border:1px dashed var(--line,#d5dee4);border-radius:.55rem;color:var(--muted,#60717a);font-size:.72rem}
    #|.governance-data-alternative{padding-top:.75rem;border-top:1px solid var(--line,#d5dee4)}
    #|.governance-data-alternative summary{min-height:44px;display:flex;align-items:center;cursor:pointer;font-size:.7rem;font-weight:800}
    #|.governance-table-scroll{overflow-x:auto}
    #|.governance-table-scroll:focus-visible{outline:3px solid var(--accent,var(--mint,#168363));outline-offset:-3px}
    #|.governance-table{width:100%;border-collapse:collapse;font-size:.68rem}
    #|.governance-table caption{padding:.4rem 0;color:var(--muted,#60717a);text-align:left}
    #|.governance-table th,.governance-table td{padding:.55rem;border:1px solid var(--line,#d5dee4);text-align:left;vertical-align:top}
    #|.governance-table-id{display:block;color:var(--muted,#60717a)}
    #|.governance-org-group{display:grid;gap:.65rem;padding:.75rem;border:1px solid var(--line,#d5dee4);border-radius:.65rem}
    #|.governance-relationship-list{display:grid;gap:.55rem}
    #|.governance-relationship{display:grid;grid-template-columns:minmax(0,1fr) auto minmax(0,1fr);gap:.4rem}
    #|.governance-relationship-missing{padding:.35rem;border:1px dashed var(--warning,var(--amber,#b88300));border-radius:.6rem}
    #|.governance-request-handoff{padding-top:.5rem;border-top:1px solid var(--line,#d5dee4)}
    #|@media(max-width:60rem){.governance-policy-flow,.governance-agreement-record{grid-template-columns:1fr}.governance-policy-flow .governance-arrow,.governance-agreement-record .governance-arrow{transform:rotate(90deg)}}
    #|@media(max-width:42rem){.governance-graph-body{padding:.75rem}.governance-lane-heading{align-items:flex-start;flex-direction:column;gap:.2rem}.governance-record,.governance-relationship{grid-template-columns:1fr}.governance-record .governance-arrow,.governance-relationship .governance-arrow{transform:rotate(90deg)}.governance-data-alternative summary{min-height:3rem}.governance-table{min-width:38rem}}
    #|@media(prefers-reduced-motion:reduce){.governance-graph *{scroll-behavior:auto!important;transition:none!important}}
    #|@media(forced-colors:active){.governance-node-current,.governance-node-warning,.governance-relationship-missing{border-width:3px}.governance-node-policy,.governance-policy-reference{border-style:dashed}}
  )
}
