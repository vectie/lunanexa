///|
fn offline_lifecycle_copy(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
}

///|
fn offline_lifecycle_current_record(
  state : ConsoleState,
) -> (String, String, String)? {
  let commerce = state.offline_commerce
  let selected = match commerce.selected_order_id {
    Some(id) =>
      match commerce.orders.iter().find_first(order => order.order_id == id) {
        Some(order) => Some(order)
        None => commerce.orders.get(0)
      }
    None => commerce.orders.get(0)
  }
  match selected {
    None => None
    Some(order) => {
      let (code, english, chinese) = match order.state {
        Draft => ("Draft", "Draft", "草稿")
        Quoted => ("Quoted", "Quote ready", "报价已就绪")
        PendingInternalApproval =>
          ("PendingInternalApproval", "Internal approval", "内部审批中")
        PendingOfflineExecution =>
          ("PendingOfflineExecution", "Offline execution", "线下办理")
        PendingEvidenceUpload =>
          ("PendingEvidenceUpload", "Evidence upload", "上传凭证")
        UnderReconciliation =>
          ("UnderReconciliation", "Evidence reconciliation", "凭证核验")
        FulfillmentPending =>
          ("FulfillmentPending", "Activation pending", "权益激活中")
        Fulfilled => ("Fulfilled", "Fulfilled", "已履约")
        ReversalPending =>
          ("ReversalPending", "Revocation pending", "访问撤销中")
        ReversalManualIntervention =>
          (
            "ReversalManualIntervention", "Manual intervention", "撤销需人工处理",
          )
        Revoked => ("Revoked", "Access revoked", "访问已撤销")
        NeedsCorrection =>
          ("NeedsCorrection", "Correction required", "需要补正")
        Rejected => ("Rejected", "Rejected", "已拒绝")
        Cancelled => ("Cancelled", "Cancelled", "已取消")
        Expired => ("Expired", "Expired", "已过期")
      }
      Some(
        (
          order.order_id,
          code,
          offline_lifecycle_copy(state.locale, english, chinese),
        ),
      )
    }
  }
}

///|
fn offline_lifecycle_state_node(
  locale : @i18n.Locale,
  code : String,
  english : String,
  chinese : String,
  current_code : String,
) -> @rabbita.Html {
  let is_current = code == current_code
  @html.div(
    class=if is_current {
      "offline-life-node is-current"
    } else {
      "offline-life-node"
    },
    [
      @html.span(class="offline-life-node-code mono", code),
      @html.strong(offline_lifecycle_copy(locale, english, chinese)),
      if is_current {
        @html.span(
          class="offline-life-current-marker",
          offline_lifecycle_copy(locale, "Current", "当前"),
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn offline_lifecycle_context_node(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
) -> @rabbita.Html {
  @html.div(class="offline-life-node offline-life-context-node", [
    @html.span(
      class="offline-life-node-code",
      offline_lifecycle_copy(locale, "Authority scope", "权限范围"),
    ),
    @html.strong(offline_lifecycle_copy(locale, english, chinese)),
  ])
}

///|
fn offline_lifecycle_edge(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
) -> @rabbita.Html {
  @html.div(class="offline-life-edge", [
    @html.span(
      class="offline-life-arrow",
      attrs=@html.Attrs::build().aria_hidden("true"),
      "→",
    ),
    @html.small(offline_lifecycle_copy(locale, english, chinese)),
  ])
}

///|
fn offline_lifecycle_transition_row(
  from : String,
  action : String,
  to : String,
  note : String,
) -> @rabbita.Html {
  @html.tr([
    @html.th(scope=Row, class="mono", from),
    @html.td(action),
    @html.td(class="mono", to),
    @html.td(note),
  ])
}

///|
#warnings("-unused_value")
fn offline_commerce_lifecycle_graph(state : ConsoleState) -> @rabbita.Html {
  let locale = state.locale
  let current = offline_lifecycle_current_record(state)
  let current_code = current.map(record => record.1).unwrap_or("")
  @html.figure(class="offline-life-figure", [
    @html.header(class="offline-life-heading", [
      @html.div([
        @html.p(
          class="eyebrow",
          offline_lifecycle_copy(
            locale, "Authority state map", "权威状态图",
          ),
        ),
        @html.h2(
          offline_lifecycle_copy(
            locale, "Offline commerce lifecycle", "线下商务生命周期",
          ),
        ),
        @html.p(
          offline_lifecycle_copy(
            locale, "Happy-path progress, evidence correction, terminal exits, and entitlement reversal from the typed commerce authority.",
            "展示类型化商务权限中的主流程、凭证补正、终止出口与权益撤销路径。",
          ),
        ),
      ]),
      match current {
        Some((order_id, code, label)) =>
          @html.div(class="offline-life-current-summary", [
            @html.span(
              offline_lifecycle_copy(locale, "Selected order", "当前订单"),
            ),
            @html.strong(label),
            @html.span(class="mono", "\{order_id} · \{code}"),
          ])
        None =>
          @html.div(class="offline-life-current-summary is-empty", [
            @html.span(
              offline_lifecycle_copy(locale, "Selected order", "当前订单"),
            ),
            @html.strong(
              offline_lifecycle_copy(
                locale, "No order selected", "未选择订单",
              ),
            ),
            @html.span(
              offline_lifecycle_copy(
                locale, "Reference map only", "仅显示参考状态图",
              ),
            ),
          ])
      },
    ]),
    @html.div(
      class="offline-life-graph",
      attrs=@html.Attrs::build().aria_label(
        offline_lifecycle_copy(
          locale, "Offline commerce lifecycle relationships", "线下商务生命周期关系",
        ),
      ),
      [
        @html.section(
          class="offline-life-lane",
          attrs=@html.Attrs::build()
            .tabindex(0)
            .aria_label(
              offline_lifecycle_copy(
                locale, "Scrollable happy-path lifecycle", "可滚动的主流程生命周期",
              ),
            ),
          [
            @html.div(class="offline-life-lane-heading", [
              @html.h3(
                offline_lifecycle_copy(locale, "Happy path", "主流程"),
              ),
              @html.span(
                offline_lifecycle_copy(
                  locale, "Internal approval is conditional", "内部审批按策略决定",
                ),
              ),
            ]),
            @html.div(class="offline-life-flow offline-life-happy-flow", [
              offline_lifecycle_state_node(
                locale, "Draft", "Draft", "草稿", current_code,
              ),
              offline_lifecycle_edge(locale, "Quote", "报价"),
              offline_lifecycle_state_node(
                locale, "Quoted", "Quoted", "已报价", current_code,
              ),
              offline_lifecycle_edge(
                locale, "Approval when required", "需要时审批",
              ),
              offline_lifecycle_state_node(
                locale, "PendingInternalApproval", "Internal approval", "内部审批",
                current_code,
              ),
              offline_lifecycle_edge(locale, "Approve", "批准"),
              offline_lifecycle_state_node(
                locale, "PendingOfflineExecution", "Offline execution", "线下办理",
                current_code,
              ),
              offline_lifecycle_edge(
                locale, "Release packet", "发布资料包",
              ),
              offline_lifecycle_state_node(
                locale, "PendingEvidenceUpload", "Evidence upload", "上传凭证",
                current_code,
              ),
              offline_lifecycle_edge(locale, "Accept evidence", "接受凭证"),
              offline_lifecycle_state_node(
                locale, "UnderReconciliation", "Reconciliation", "凭证核验",
                current_code,
              ),
              offline_lifecycle_edge(
                locale, "Request activation", "请求激活",
              ),
              offline_lifecycle_state_node(
                locale, "FulfillmentPending", "Activation pending", "等待激活",
                current_code,
              ),
              offline_lifecycle_edge(
                locale, "Authority confirms", "权限方确认",
              ),
              offline_lifecycle_state_node(
                locale, "Fulfilled", "Fulfilled", "已履约", current_code,
              ),
            ]),
            @html.p(
              class="offline-life-lane-note",
              offline_lifecycle_copy(
                locale, "When internal approval is not required, Quoted proceeds directly to PendingOfflineExecution.",
                "无需内部审批时，Quoted 会直接进入 PendingOfflineExecution。",
              ),
            ),
          ],
        ),
        @html.section(class="offline-life-lane", [
          @html.div(class="offline-life-lane-heading", [
            @html.h3(
              offline_lifecycle_copy(locale, "Correction loop", "补正循环"),
            ),
            @html.span(
              offline_lifecycle_copy(
                locale, "Scanner or reviewer evidence", "扫描或审核凭证",
              ),
            ),
          ]),
          @html.div(class="offline-life-flow offline-life-branch-flow", [
            offline_lifecycle_context_node(
              locale, "Evidence check", "凭证检查",
            ),
            offline_lifecycle_edge(locale, "Rejected", "未通过"),
            offline_lifecycle_state_node(
              locale, "NeedsCorrection", "Correction required", "需要补正", current_code,
            ),
            offline_lifecycle_edge(
              locale, "Corrected evidence accepted", "接受补正凭证",
            ),
            offline_lifecycle_state_node(
              locale, "UnderReconciliation", "Reconciliation", "凭证核验", current_code,
            ),
          ]),
        ]),
        @html.section(class="offline-life-lane", [
          @html.div(class="offline-life-lane-heading", [
            @html.h3(
              offline_lifecycle_copy(
                locale, "Pre-activation exits", "激活前退出",
              ),
            ),
            @html.span(
              offline_lifecycle_copy(locale, "Terminal records", "终止记录"),
            ),
          ]),
          @html.div(class="offline-life-exit-layout", [
            @html.div(class="offline-life-flow offline-life-exit-flow", [
              offline_lifecycle_context_node(
                locale, "Eligible pre-activation states", "可退出的激活前状态",
              ),
              offline_lifecycle_edge(
                locale, "Cancel or expire", "取消或到期",
              ),
              @html.div(class="offline-life-terminal-stack", [
                offline_lifecycle_state_node(
                  locale, "Cancelled", "Cancelled", "已取消", current_code,
                ),
                offline_lifecycle_state_node(
                  locale, "Expired", "Expired", "已过期", current_code,
                ),
              ]),
            ]),
            @html.div(class="offline-life-unlinked-state", [
              offline_lifecycle_state_node(
                locale, "Rejected", "Rejected", "已拒绝", current_code,
              ),
              @html.p(
                offline_lifecycle_copy(
                  locale, "Typed terminal record; the current backend publishes no transition constructor into this state.",
                  "类型化终止记录；当前后端未发布进入此状态的转换构造器。",
                ),
              ),
            ]),
          ]),
        ]),
        @html.section(class="offline-life-lane", [
          @html.div(class="offline-life-lane-heading", [
            @html.h3(
              offline_lifecycle_copy(
                locale, "Entitlement reversal", "权益撤销",
              ),
            ),
            @html.span(
              offline_lifecycle_copy(
                locale, "After fulfillment only", "仅履约后",
              ),
            ),
          ]),
          @html.div(class="offline-life-reversal-stack", [
            @html.div(class="offline-life-flow offline-life-branch-flow", [
              offline_lifecycle_state_node(
                locale, "Fulfilled", "Fulfilled", "已履约", current_code,
              ),
              offline_lifecycle_edge(locale, "Request reversal", "请求撤销"),
              offline_lifecycle_state_node(
                locale, "ReversalPending", "Revocation pending", "撤销中", current_code,
              ),
              offline_lifecycle_edge(
                locale, "Authority confirms", "权限方确认",
              ),
              offline_lifecycle_state_node(
                locale, "Revoked", "Access revoked", "访问已撤销", current_code,
              ),
            ]),
            @html.div(class="offline-life-flow offline-life-branch-flow", [
              offline_lifecycle_state_node(
                locale, "ReversalPending", "Revocation pending", "撤销中", current_code,
              ),
              offline_lifecycle_edge(
                locale, "Authority failure", "权限方失败",
              ),
              offline_lifecycle_state_node(
                locale, "ReversalManualIntervention", "Manual intervention", "人工处理",
                current_code,
              ),
              offline_lifecycle_edge(
                locale, "Retry or reconcile", "重试或核对",
              ),
              @html.div(class="offline-life-terminal-stack", [
                offline_lifecycle_state_node(
                  locale, "ReversalPending", "Retry reversal", "重试撤销", current_code,
                ),
                offline_lifecycle_state_node(
                  locale, "Revoked", "Confirm revoked", "确认已撤销", current_code,
                ),
                offline_lifecycle_state_node(
                  locale, "Fulfilled", "Confirm still active", "确认仍有效",
                  current_code,
                ),
              ]),
            ]),
          ]),
        ]),
      ],
    ),
    @html.details(class="offline-life-table-alternative", [
      @html.summary(
        offline_lifecycle_copy(
          locale, "Authoritative transition table", "权威转换表",
        ),
      ),
      @html.div(
        class="table-scroll",
        attrs=@html.Attrs::build()
          .tabindex(0)
          .aria_label(
            offline_lifecycle_copy(
              locale, "Scrollable authoritative transition table", "可滚动的权威转换表",
            ),
          ),
        [
          @html.table(class="resource-table offline-life-transition-table", [
            @html.caption(
              offline_lifecycle_copy(
                locale, "Offline commerce transitions and typed terminal records",
                "线下商务转换与类型化终止记录",
              ),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  offline_lifecycle_copy(locale, "From", "起始状态"),
                ),
                @html.th(
                  scope=Col,
                  offline_lifecycle_copy(
                    locale, "Authority result", "权限结果",
                  ),
                ),
                @html.th(
                  scope=Col,
                  offline_lifecycle_copy(locale, "To", "目标状态"),
                ),
                @html.th(
                  scope=Col,
                  offline_lifecycle_copy(locale, "Limit", "限制"),
                ),
              ]),
            ),
            @html.tbody([
              offline_lifecycle_transition_row(
                "Draft",
                offline_lifecycle_copy(locale, "Quote recorded", "记录报价"),
                "Quoted",
                "—",
              ),
              offline_lifecycle_transition_row(
                "Quoted",
                offline_lifecycle_copy(
                  locale, "Internal approval required", "需要内部审批",
                ),
                "PendingInternalApproval",
                "—",
              ),
              offline_lifecycle_transition_row(
                "Quoted",
                offline_lifecycle_copy(
                  locale, "Internal approval not required", "无需内部审批",
                ),
                "PendingOfflineExecution",
                "—",
              ),
              offline_lifecycle_transition_row(
                "PendingInternalApproval",
                offline_lifecycle_copy(
                  locale, "Approval evidence accepted", "接受审批凭证",
                ),
                "PendingOfflineExecution",
                "—",
              ),
              offline_lifecycle_transition_row(
                "PendingInternalApproval",
                offline_lifecycle_copy(
                  locale, "Approval evidence rejected", "审批凭证未通过",
                ),
                "NeedsCorrection",
                offline_lifecycle_copy(
                  locale, "Store evidence transition", "存储层凭证转换",
                ),
              ),
              offline_lifecycle_transition_row(
                "PendingOfflineExecution",
                offline_lifecycle_copy(
                  locale, "Verified packet released", "发布已验证资料包",
                ),
                "PendingEvidenceUpload",
                "—",
              ),
              offline_lifecycle_transition_row(
                "PendingEvidenceUpload",
                offline_lifecycle_copy(
                  locale, "Evidence accepted", "接受凭证",
                ),
                "UnderReconciliation",
                "—",
              ),
              offline_lifecycle_transition_row(
                "PendingEvidenceUpload / UnderReconciliation",
                offline_lifecycle_copy(
                  locale, "Scan or review rejected", "扫描或审核未通过",
                ),
                "NeedsCorrection",
                offline_lifecycle_copy(
                  locale, "Store evidence transition", "存储层凭证转换",
                ),
              ),
              offline_lifecycle_transition_row(
                "NeedsCorrection",
                offline_lifecycle_copy(
                  locale, "Corrected evidence accepted", "接受补正凭证",
                ),
                "UnderReconciliation",
                "—",
              ),
              offline_lifecycle_transition_row(
                "UnderReconciliation",
                offline_lifecycle_copy(
                  locale, "Activation requested", "请求激活",
                ),
                "FulfillmentPending",
                "—",
              ),
              offline_lifecycle_transition_row(
                "FulfillmentPending",
                offline_lifecycle_copy(
                  locale, "Activation confirmed", "确认激活",
                ),
                "Fulfilled",
                "—",
              ),
              offline_lifecycle_transition_row(
                "FulfillmentPending",
                offline_lifecycle_copy(
                  locale, "Activation rejected", "拒绝激活",
                ),
                "UnderReconciliation",
                offline_lifecycle_copy(
                  locale, "Returns for reconciliation", "返回核验",
                ),
              ),
              offline_lifecycle_transition_row(
                "Fulfilled",
                offline_lifecycle_copy(
                  locale, "Reversal requested or fulfilled order expires", "请求撤销或已履约订单到期",
                ),
                "ReversalPending",
                "—",
              ),
              offline_lifecycle_transition_row(
                "ReversalPending",
                offline_lifecycle_copy(
                  locale, "Reversal confirmed", "确认撤销",
                ),
                "Revoked",
                "—",
              ),
              offline_lifecycle_transition_row(
                "ReversalPending",
                offline_lifecycle_copy(
                  locale, "Authority failure", "权限方失败",
                ),
                "ReversalManualIntervention",
                "—",
              ),
              offline_lifecycle_transition_row(
                "ReversalManualIntervention",
                offline_lifecycle_copy(locale, "Retry reversal", "重试撤销"),
                "ReversalPending",
                "—",
              ),
              offline_lifecycle_transition_row(
                "ReversalManualIntervention",
                offline_lifecycle_copy(
                  locale, "Confirm revoked", "确认已撤销",
                ),
                "Revoked",
                "—",
              ),
              offline_lifecycle_transition_row(
                "ReversalManualIntervention",
                offline_lifecycle_copy(
                  locale, "Confirm still active", "确认仍有效",
                ),
                "Fulfilled",
                "—",
              ),
              offline_lifecycle_transition_row(
                "Draft / Quoted / PendingInternalApproval / PendingOfflineExecution / PendingEvidenceUpload / UnderReconciliation / NeedsCorrection",
                offline_lifecycle_copy(locale, "Cancel", "取消"),
                "Cancelled",
                offline_lifecycle_copy(
                  locale, "Pre-activation only", "仅激活前",
                ),
              ),
              offline_lifecycle_transition_row(
                "Draft / Quoted / PendingInternalApproval / PendingOfflineExecution / PendingEvidenceUpload / UnderReconciliation / NeedsCorrection",
                offline_lifecycle_copy(
                  locale, "Order clock expires", "订单时钟到期",
                ),
                "Expired",
                offline_lifecycle_copy(
                  locale, "Fulfilled expiry requests reversal instead", "已履约订单到期会请求撤销",
                ),
              ),
              offline_lifecycle_transition_row(
                "—",
                offline_lifecycle_copy(
                  locale, "No published constructor", "未发布构造器",
                ),
                "Rejected",
                offline_lifecycle_copy(
                  locale, "Typed terminal record only", "仅类型化终止记录",
                ),
              ),
            ]),
          ]),
        ],
      ),
    ]),
    @html.figcaption(
      offline_lifecycle_copy(
        locale, "Solid arrows are transitions implemented by the current authority. The Rejected state is intentionally unlinked because no source transition is published; the table records that limit explicitly.",
        "实线箭头表示当前权限实现的转换。Rejected 状态因没有已发布的来源转换而刻意不连线；表格会明确记录此限制。",
      ),
    ),
  ])
}

///|
#warnings("-unused_value")
fn offline_commerce_visual_styles() -> String {
  (
    #|.offline-life-lane:focus-visible,.offline-life-table-alternative .table-scroll:focus-visible{outline:3px solid var(--accent,var(--mint,#168363));outline-offset:-3px}
    #|.offline-life-figure{margin:0 0 1.25rem;overflow:hidden;border:1px solid var(--line,#d5dee4);border-radius:.75rem;background:var(--surface,var(--panel,#fff));box-shadow:var(--shadow-sm,0 .1rem .3rem rgba(0,0,0,.08))}.offline-life-heading{display:flex;align-items:flex-start;justify-content:space-between;gap:1.25rem;padding:1.05rem 1.15rem;border-bottom:1px solid var(--line,#d5dee4);background:linear-gradient(135deg,var(--surface,var(--panel,#fff)),var(--surface-subtle,rgba(128,148,156,.08)))}.offline-life-heading h2{margin:0}.offline-life-heading p:last-child{max-width:58rem;margin:.3rem 0 0;color:var(--muted,#80949c)}.offline-life-current-summary{min-width:14rem;display:grid;gap:.15rem;padding:.65rem .75rem;border:2px solid var(--accent,var(--mint,#168363));border-radius:.55rem;background:var(--surface,var(--panel,#fff))}.offline-life-current-summary>span:first-child{color:var(--muted,#80949c);font-size:.65rem;font-weight:750;letter-spacing:.06em;text-transform:uppercase}.offline-life-current-summary>span:last-child{color:var(--muted,#80949c);font-size:.68rem;overflow-wrap:anywhere}.offline-life-current-summary.is-empty{border-style:dashed;border-color:var(--line-strong,#9babb3)}.offline-life-graph{display:grid;gap:1rem;padding:1rem 1.15rem}.offline-life-lane{display:grid;gap:.65rem;padding:.85rem;overflow-x:auto;border:1px solid var(--line,#d5dee4);border-radius:.65rem;background:var(--surface-subtle,rgba(128,148,156,.05))}.offline-life-lane-heading{display:flex;align-items:baseline;justify-content:space-between;gap:1rem}.offline-life-lane-heading h3{margin:0;font-size:.9rem}.offline-life-lane-heading span,.offline-life-lane-note{color:var(--muted,#80949c);font-size:.68rem}.offline-life-lane-note{margin:0;padding-top:.5rem;border-top:1px dashed var(--line,#d5dee4)}.offline-life-flow{display:grid;align-items:stretch;gap:.4rem}.offline-life-happy-flow{min-width:88rem;grid-template-columns:repeat(7,minmax(7.5rem,1fr) minmax(3.5rem,.5fr)) minmax(7.5rem,1fr)}.offline-life-branch-flow{grid-template-columns:minmax(9rem,1fr) minmax(4.5rem,.5fr) minmax(9rem,1fr) minmax(4.5rem,.5fr) minmax(9rem,1fr)}.offline-life-node{position:relative;min-width:0;display:grid;align-content:start;gap:.25rem;padding:.65rem;border:1px solid var(--line-strong,#9babb3);border-radius:.5rem;background:var(--surface,var(--panel,#fff))}.offline-life-node-code{color:var(--muted,#80949c);font-size:.6rem;overflow-wrap:anywhere}.offline-life-node strong{font-size:.75rem;overflow-wrap:anywhere}.offline-life-node.is-current{border-width:3px;border-color:var(--accent,var(--mint,#168363));padding:.55rem}.offline-life-current-marker{width:max-content;padding:.15rem .35rem;border-radius:999px;background:var(--accent-soft,rgba(53,189,141,.12));color:var(--accent,var(--mint,#168363));font-size:.6rem;font-weight:850}.offline-life-context-node{border-style:dashed;background:transparent}.offline-life-edge{min-width:0;display:grid;place-items:center;text-align:center;color:var(--muted,#80949c)}.offline-life-arrow{font-size:1rem;font-weight:900}.offline-life-edge small{font-size:.6rem;line-height:1.25}.offline-life-exit-layout{display:grid;grid-template-columns:minmax(24rem,1fr) minmax(14rem,.55fr);gap:.8rem}.offline-life-exit-flow{grid-template-columns:minmax(10rem,1fr) minmax(4.5rem,.5fr) minmax(10rem,1fr)}.offline-life-terminal-stack{display:grid;gap:.4rem}.offline-life-unlinked-state{display:grid;gap:.4rem;padding:.55rem;border:1px dashed var(--warning,#b88300);border-radius:.55rem}.offline-life-unlinked-state p{margin:0;color:var(--muted,#80949c);font-size:.66rem;line-height:1.4}.offline-life-reversal-stack{display:grid;gap:.55rem}.offline-life-table-alternative{margin:0 1.15rem 1rem;border:1px solid var(--line,#d5dee4);border-radius:.55rem;background:var(--surface,var(--panel,#fff))}.offline-life-table-alternative summary{min-height:44px;display:flex;align-items:center;padding:.55rem .7rem;color:var(--ink,#18242a);font-size:.75rem;font-weight:750;cursor:pointer}.offline-life-table-alternative .table-scroll{margin:0 .7rem .7rem;box-shadow:none}.offline-life-transition-table{min-width:58rem}.offline-life-transition-table caption{padding:.65rem .8rem;color:var(--muted,#80949c);font-size:.72rem;text-align:left}.offline-life-figure figcaption{padding:.7rem 1.15rem;border-top:1px solid var(--line,#d5dee4);background:var(--surface-subtle,rgba(128,148,156,.06));color:var(--muted,#80949c);font-size:.7rem;line-height:1.45}@media(max-width:64rem){.offline-life-heading{flex-direction:column}.offline-life-current-summary{width:100%}.offline-life-branch-flow,.offline-life-exit-flow{grid-template-columns:1fr}.offline-life-branch-flow .offline-life-edge,.offline-life-exit-flow .offline-life-edge{min-height:1.4rem}.offline-life-branch-flow .offline-life-arrow,.offline-life-exit-flow .offline-life-arrow{transform:rotate(90deg)}.offline-life-exit-layout{grid-template-columns:1fr}.offline-life-happy-flow{min-width:0;grid-template-columns:1fr}.offline-life-happy-flow .offline-life-edge{min-height:1.4rem}.offline-life-happy-flow .offline-life-arrow{transform:rotate(90deg)}}@media(max-width:40rem){.offline-life-graph{padding:.75rem}.offline-life-lane{padding:.65rem}.offline-life-lane-heading{align-items:flex-start;flex-direction:column;gap:.2rem}.offline-life-table-alternative{margin-inline:.75rem}.offline-life-figure figcaption{padding-inline:.75rem}}@media(prefers-reduced-motion:reduce){.offline-life-figure *{scroll-behavior:auto!important;transition:none!important}}@media(forced-colors:active){.offline-life-node.is-current{border-width:4px}.offline-life-unlinked-state,.offline-life-context-node{border-style:dashed}}
  )
}
