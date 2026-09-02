///|
fn deployment_placement_graph(state : ConsoleState) -> @rabbita.Html {
  @html.section(class="placement-visual-shell", [
    @html.figure(class="placement-visual", [
      @html.div(class="placement-visual-heading", [
        @html.div([
          @html.small(
            localized(state.locale, "Observed relationship", "已观测关系"),
          ),
          @html.h2(
            localized(
              state.locale,
              "Deployment placement",
              "部署放置关系",
            ),
          ),
          @html.p(
            localized(
              state.locale,
              "Services are connected to nodes only when the node reports the same active deployment ID.",
              "仅当节点上报相同的活动部署 ID 时，服务才会连接到该节点。",
            ),
          ),
        ]),
        @html.span(
          class="placement-visual-count",
          localized(
            state.locale,
            "\{state.deployments.length()} deployments",
            "\{state.deployments.length()} 个部署",
          ),
        ),
      ]),
      @html.div(
        class="placement-graph",
        attrs=@html.Attrs::build()
          .tabindex(0)
          .aria_label(
            localized(
              state.locale,
              "Scrollable deployment placement graph",
              "可滚动的部署放置关系图",
            ),
          ),
        [
          if state.deployments.length() == 0 {
            @html.div(class="placement-empty", [
              @html.strong(
                localized(
                  state.locale,
                  "No deployment records",
                  "暂无部署记录",
                ),
              ),
              @html.span(
                localized(
                  state.locale,
                  "Placement cannot be drawn until a deployment is reported.",
                  "收到部署上报后才能绘制放置关系。",
                ),
              ),
            ])
          } else {
            @html.ul(
              class="placement-rows",
              [
                for deployment in state.deployments => {
                  let matching_nodes = state.nodes.filter(node => {
                    deployment.deployment_id != "" &&
                    node.active_assignment == deployment.deployment_id
                  })
                  @html.li(class="placement-row", [
                    @html.div(class="placement-card placement-service-card", [
                      @html.small(
                        localized(state.locale, "Model service", "模型服务"),
                      ),
                      @html.h3(class="mono", deployment.deployment_id),
                      @html.dl(class="placement-state-pair", [
                        @html.div([
                          @html.dt(
                            localized(state.locale, "Desired", "期望状态"),
                          ),
                          @html.dd(
                            deployment_state_badge(
                              state.locale,
                              deployment.desired,
                            ),
                          ),
                        ]),
                        @html.div([
                          @html.dt(
                            localized(state.locale, "Observed", "观测状态"),
                          ),
                          @html.dd(
                            deployment_state_badge(
                              state.locale,
                              deployment.observed,
                            ),
                          ),
                        ]),
                      ]),
                    ]),
                    @html.div(
                      class="placement-edge",
                      attrs=@html.Attrs::build().aria_hidden("true"),
                      @html.span(
                        localized(state.locale, "reported on", "上报于"),
                      ),
                    ),
                    if matching_nodes.length() == 0 {
                      @html.div(class="placement-card placement-missing-card", [
                        @html.small(localized(state.locale, "Node", "节点")),
                        @html.strong(
                          localized(
                            state.locale,
                            "Placement not reported",
                            "未上报放置位置",
                          ),
                        ),
                        @html.span(
                          localized(
                            state.locale,
                            "No enrolled node reports this deployment as its active assignment.",
                            "没有已注册节点将此部署上报为活动分配。",
                          ),
                        ),
                      ])
                    } else {
                      @html.ul(
                        class="placement-node-list",
                        [
                          for node in matching_nodes => {
                            @html.li(
                              class="placement-card placement-node-card",
                              [
                                @html.small(
                                  localized(
                                    state.locale,
                                    "Assigned node",
                                    "分配节点",
                                  ),
                                ),
                                @html.strong(class="mono", node.node_id),
                                @html.div(class="placement-node-state", [
                                  @html.span(
                                    localized(
                                      state.locale,
                                      "Node state",
                                      "节点状态",
                                    ),
                                  ),
                                  node_state_badge(state.locale, node.state),
                                ]),
                              ],
                            )
                          }
                        ],
                      )
                    },
                  ])
                }
              ],
            )
          },
        ],
      ),
      @html.figcaption(
        localized(
          state.locale,
          "Connections reflect NodeRow.active_assignment reports, not inferred scheduler intent. Desired, observed, and node states remain visible as text.",
          "连接来自 NodeRow.active_assignment 上报，而非推断的调度意图。期望、观测和节点状态均以文字显示。",
        ),
      ),
    ]),
    deployment_placement_table(state),
  ])
}

///|
fn deployment_placement_table(state : ConsoleState) -> @rabbita.Html {
  @html.details(class="placement-alternative", [
    @html.summary(
      localized(state.locale, "Placement data table", "放置数据表"),
    ),
    @html.div(
      class="placement-table-scroll",
      attrs=@html.Attrs::build()
        .tabindex(0)
        .aria_label(
          localized(
            state.locale,
            "Scrollable deployment placement table",
            "可滚动的部署放置数据表",
          ),
        ),
      [
        @html.table(class="placement-table", [
          @html.caption(
            localized(
              state.locale,
              "Accessible deployment-to-node relationship data",
              "可访问的部署与节点关系数据",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                scope=Col,
                localized(state.locale, "Deployment", "部署"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Desired", "期望状态"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Observed", "观测状态"),
              ),
              @html.th(scope=Col, localized(state.locale, "Node", "节点")),
              @html.th(
                scope=Col,
                localized(state.locale, "Node state", "节点状态"),
              ),
            ]),
          ),
          @html.tbody(
            if state.deployments.length() == 0 {
              @html.tr(
                @html.td(
                  colspan=5,
                  localized(
                    state.locale,
                    "No deployment records are available.",
                    "暂无部署记录。",
                  ),
                ),
              )
            } else {
              @html.fragment(
                [
                  for deployment in state.deployments => {
                    let matching_nodes = state.nodes.filter(node => {
                      deployment.deployment_id != "" &&
                      node.active_assignment == deployment.deployment_id
                    })
                    if matching_nodes.length() == 0 {
                      @html.tr([
                        @html.td(class="mono", deployment.deployment_id),
                        @html.td(
                          deployment_state_badge(
                            state.locale,
                            deployment.desired,
                          ),
                        ),
                        @html.td(
                          deployment_state_badge(
                            state.locale,
                            deployment.observed,
                          ),
                        ),
                        @html.td(
                          localized(
                            state.locale,
                            "Placement not reported",
                            "未上报放置位置",
                          ),
                        ),
                        @html.td(
                          localized(state.locale, "Not reported", "未上报"),
                        ),
                      ])
                    } else {
                      @html.fragment(
                        [
                          for node in matching_nodes => {
                            @html.tr([
                              @html.td(class="mono", deployment.deployment_id),
                              @html.td(
                                deployment_state_badge(
                                  state.locale,
                                  deployment.desired,
                                ),
                              ),
                              @html.td(
                                deployment_state_badge(
                                  state.locale,
                                  deployment.observed,
                                ),
                              ),
                              @html.td(class="mono", node.node_id),
                              @html.td(
                                node_state_badge(state.locale, node.state),
                              ),
                            ])
                          }
                        ],
                      )
                    }
                  }
                ],
              )
            },
          ),
        ]),
      ],
    ),
  ])
}

///|
fn alert_impact_graph(state : ConsoleState) -> @rabbita.Html {
  @html.section(class="placement-visual-shell alert-impact-shell", [
    @html.figure(class="placement-visual alert-impact-visual", [
      @html.div(class="placement-visual-heading", [
        @html.div([
          @html.small(
            localized(state.locale, "Reported impact", "已上报影响"),
          ),
          @html.h2(
            localized(state.locale, "Alert impact map", "告警影响图"),
          ),
          @html.p(
            localized(
              state.locale,
              "Notification node references are resolved against the current node inventory.",
              "通知中的节点引用会与当前节点清单进行匹配。",
            ),
          ),
        ]),
        @html.span(
          class="placement-visual-count",
          localized(
            state.locale,
            "\{state.notifications.length()} notifications",
            "\{state.notifications.length()} 条通知",
          ),
        ),
      ]),
      @html.div(
        class="placement-graph alert-impact-graph",
        attrs=@html.Attrs::build()
          .tabindex(0)
          .aria_label(
            localized(
              state.locale,
              "Scrollable alert reference graph",
              "可滚动的告警引用关系图",
            ),
          ),
        [
          if state.notifications.length() == 0 {
            @html.div(class="placement-empty alert-quiet", [
              @html.strong(
                localized(
                  state.locale,
                  "No notification records",
                  "暂无通知记录",
                ),
              ),
              @html.span(
                localized(
                  state.locale,
                  "The current snapshot contains no alerts. This does not independently prove node health.",
                  "当前快照不含告警；这并不能独立证明节点健康。",
                ),
              ),
            ])
          } else {
            @html.ul(
              class="placement-rows alert-impact-rows",
              [
                for notification in state.notifications => {
                  let matching_nodes = state.nodes.filter(node => {
                    notification.node_ref != "" &&
                    node.node_id == notification.node_ref
                  })
                  @html.li(class="placement-row alert-impact-row", [
                    @html.div(
                      class="placement-card alert-card alert-card-\{alert_severity_tone(notification.severity)}",
                      [
                        @html.small(
                          alert_severity_label(
                            state.locale,
                            notification.severity,
                          ),
                        ),
                        @html.h3(
                          alert_code_label(state.locale, notification.code),
                        ),
                        @html.div(class="alert-card-meta", [
                          @html.span(class="mono", notification.notification_id),
                          @html.span(
                            alert_lifecycle_label(
                              state.locale,
                              notification.lifecycle,
                            ),
                          ),
                        ]),
                      ],
                    ),
                    @html.div(
                      class="placement-edge alert-impact-edge",
                      attrs=@html.Attrs::build().aria_hidden("true"),
                      @html.span(
                        localized(
                          state.locale,
                          "node reference",
                          "节点引用",
                        ),
                      ),
                    ),
                    if matching_nodes.length() > 0 {
                      @html.ul(
                        class="placement-node-list",
                        [
                          for node in matching_nodes => {
                            @html.li(
                              class="placement-card placement-node-card",
                              [
                                @html.small(
                                  localized(
                                    state.locale,
                                    "Referenced node",
                                    "引用节点",
                                  ),
                                ),
                                @html.strong(class="mono", node.node_id),
                                @html.div(class="placement-node-state", [
                                  @html.span(
                                    localized(
                                      state.locale,
                                      "Node state",
                                      "节点状态",
                                    ),
                                  ),
                                  node_state_badge(state.locale, node.state),
                                ]),
                              ],
                            )
                          }
                        ],
                      )
                    } else if notification.node_ref == "" {
                      @html.div(class="placement-card placement-missing-card", [
                        @html.small(localized(state.locale, "Impact", "影响")),
                        @html.strong(
                          localized(
                            state.locale,
                            "No node reference reported",
                            "未上报节点引用",
                          ),
                        ),
                        @html.span(
                          localized(
                            state.locale,
                            "This notification is not linked to a node.",
                            "此通知未关联节点。",
                          ),
                        ),
                      ])
                    } else {
                      @html.div(class="placement-card placement-missing-card", [
                        @html.small(
                          localized(
                            state.locale,
                            "Referenced node",
                            "引用节点",
                          ),
                        ),
                        @html.strong(class="mono", notification.node_ref),
                        @html.span(
                          localized(
                            state.locale,
                            "Referenced node not found in the current inventory.",
                            "当前节点清单中未找到该引用节点。",
                          ),
                        ),
                      ])
                    },
                  ])
                }
              ],
            )
          },
        ],
      ),
      @html.figcaption(
        localized(
          state.locale,
          "Each connection uses NotificationRow.node_ref and an exact NodeRow.node_id match. Missing references remain explicit.",
          "每条连接均使用 NotificationRow.node_ref 与 NodeRow.node_id 精确匹配；缺失引用会明确显示。",
        ),
      ),
    ]),
    alert_impact_table(state),
  ])
}

///|
fn alert_severity_tone(
  severity : @notifications.NotificationSeverity,
) -> String {
  match severity {
    Information => "information"
    Warning => "warning"
    Critical => "critical"
  }
}

///|
fn alert_impact_table(state : ConsoleState) -> @rabbita.Html {
  @html.details(class="placement-alternative", [
    @html.summary(
      localized(state.locale, "Alert impact table", "告警影响表"),
    ),
    @html.div(
      class="placement-table-scroll",
      attrs=@html.Attrs::build()
        .tabindex(0)
        .aria_label(
          localized(
            state.locale,
            "Scrollable alert reference table",
            "可滚动的告警引用数据表",
          ),
        ),
      [
        @html.table(class="placement-table", [
          @html.caption(
            localized(
              state.locale,
              "Accessible notification-to-node relationship data",
              "可访问的通知与节点关系数据",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                scope=Col,
                localized(state.locale, "Notification", "通知"),
              ),
              @html.th(scope=Col, localized(state.locale, "Alert", "告警")),
              @html.th(
                scope=Col,
                localized(state.locale, "Severity", "严重程度"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Lifecycle", "生命周期"),
              ),
              @html.th(scope=Col, localized(state.locale, "Node", "节点")),
              @html.th(
                scope=Col,
                localized(state.locale, "Node state", "节点状态"),
              ),
            ]),
          ),
          @html.tbody(
            if state.notifications.length() == 0 {
              @html.tr(
                @html.td(
                  colspan=6,
                  localized(
                    state.locale,
                    "No notification records are available.",
                    "暂无通知记录。",
                  ),
                ),
              )
            } else {
              @html.fragment(
                [
                  for notification in state.notifications => {
                    let matching_nodes = state.nodes.filter(node => {
                      notification.node_ref != "" &&
                      node.node_id == notification.node_ref
                    })
                    if matching_nodes.length() > 0 {
                      @html.fragment(
                        [
                          for node in matching_nodes => {
                            @html.tr([
                              @html.td(
                                class="mono",
                                notification.notification_id,
                              ),
                              @html.td(
                                alert_code_label(
                                  state.locale,
                                  notification.code,
                                ),
                              ),
                              @html.td(
                                alert_severity_label(
                                  state.locale,
                                  notification.severity,
                                ),
                              ),
                              @html.td(
                                alert_lifecycle_label(
                                  state.locale,
                                  notification.lifecycle,
                                ),
                              ),
                              @html.td(class="mono", node.node_id),
                              @html.td(
                                node_state_badge(state.locale, node.state),
                              ),
                            ])
                          }
                        ],
                      )
                    } else {
                      @html.tr([
                        @html.td(class="mono", notification.notification_id),
                        @html.td(
                          alert_code_label(state.locale, notification.code),
                        ),
                        @html.td(
                          alert_severity_label(
                            state.locale,
                            notification.severity,
                          ),
                        ),
                        @html.td(
                          alert_lifecycle_label(
                            state.locale,
                            notification.lifecycle,
                          ),
                        ),
                        @html.td(
                          if notification.node_ref == "" {
                            localized(
                              state.locale,
                              "No node reference reported",
                              "未上报节点引用",
                            )
                          } else {
                            notification.node_ref
                          },
                        ),
                        @html.td(
                          if notification.node_ref == "" {
                            localized(
                              state.locale,
                              "Not applicable",
                              "不适用",
                            )
                          } else {
                            localized(
                              state.locale,
                              "Node not found",
                              "未找到节点",
                            )
                          },
                        ),
                      ])
                    }
                  }
                ],
              )
            },
          ),
        ]),
      ],
    ),
  ])
}

///|
fn placement_visual_styles() -> String {
  (
    #|.placement-visual-shell { display: grid; gap: .75rem; margin: 0 0 1.5rem; }
    #|.placement-visual { margin: 0; overflow: hidden; border: 1px solid var(--line); border-radius: .8rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.placement-visual-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; padding: 1.1rem 1.25rem; border-bottom: 1px solid var(--line); background: linear-gradient(135deg, var(--surface), var(--surface-subtle)); }
    #|.placement-visual-heading > div { min-width: 0; }
    #|.placement-visual-heading small { color: var(--muted); font-size: .62rem; font-weight: 760; letter-spacing: .08em; text-transform: uppercase; }
    #|.placement-visual-heading h2 { margin: .15rem 0 .25rem; font-size: 1.25rem; }
    #|.placement-visual-heading p { max-width: 50rem; margin: 0; color: var(--muted); font-size: .76rem; }
    #|.placement-visual-count { flex: none; padding: .32rem .55rem; border: 1px solid var(--line); border-radius: 999px; color: var(--muted-strong); font-size: .68rem; white-space: nowrap; }
    #|.placement-graph { overflow-x: auto; padding: 1.25rem; background-image: linear-gradient(rgba(86,104,117,.05) 1px,transparent 1px),linear-gradient(90deg,rgba(86,104,117,.05) 1px,transparent 1px); background-size: 24px 24px; }
    #|.placement-graph:focus-visible, .placement-table-scroll:focus-visible { outline: 3px solid var(--accent); outline-offset: -3px; }
    #|.placement-rows, .placement-node-list { margin: 0; padding: 0; list-style: none; }
    #|.placement-rows { display: grid; gap: .8rem; min-width: 42rem; }
    #|.placement-row { display: grid; grid-template-columns: minmax(15rem,1fr) minmax(4.5rem,.35fr) minmax(15rem,1fr); align-items: center; }
    #|.placement-card { min-width: 0; padding: .8rem .9rem; border: 1px solid var(--line); border-radius: .58rem; background: var(--surface); box-shadow: 0 .25rem .75rem rgba(15,23,42,.07); }
    #|.placement-card small { display: block; color: var(--muted); font-size: .58rem; font-weight: 760; letter-spacing: .07em; text-transform: uppercase; }
    #|.placement-card h3, .placement-card strong { overflow-wrap: anywhere; }
    #|.placement-card h3 { margin: .15rem 0 .55rem; font-size: .82rem; }
    #|.placement-service-card { border-color: color-mix(in srgb,var(--accent) 42%,var(--line)); }
    #|.placement-state-pair { display: grid; grid-template-columns: repeat(2,minmax(0,1fr)); gap: .55rem; margin: 0; }
    #|.placement-state-pair div { min-width: 0; }
    #|.placement-state-pair dt { margin-bottom: .2rem; color: var(--muted); font-size: .62rem; }
    #|.placement-state-pair dd { margin: 0; }
    #|.placement-edge { position: relative; height: 2px; background: color-mix(in srgb,var(--accent) 52%,var(--line)); }
    #|.placement-edge::after { position: absolute; right: 0; top: 50%; width: .48rem; height: .48rem; border-top: 2px solid var(--accent); border-right: 2px solid var(--accent); content: ""; transform: translateY(-50%) rotate(45deg); }
    #|.placement-edge span { position: absolute; left: 50%; bottom: .55rem; padding: .12rem .3rem; border: 1px solid var(--line); border-radius: .25rem; background: var(--surface); color: var(--muted); font-size: .57rem; white-space: nowrap; transform: translateX(-50%); }
    #|.placement-node-list { display: grid; gap: .4rem; }
    #|.placement-node-card { border-color: color-mix(in srgb,var(--success) 38%,var(--line)); }
    #|.placement-node-card > strong, .placement-missing-card > strong { display: block; margin: .18rem 0 .45rem; font-size: .78rem; }
    #|.placement-node-state { display: flex; align-items: center; justify-content: space-between; gap: .5rem; color: var(--muted); font-size: .62rem; }
    #|.placement-missing-card { border-style: dashed; border-color: color-mix(in srgb,var(--warning) 50%,var(--line)); background: var(--warning-soft); }
    #|.placement-missing-card > span { display: block; color: var(--muted-strong); font-size: .66rem; }
    #|.placement-empty { display: grid; justify-items: center; gap: .35rem; min-height: 8rem; place-content: center; padding: 1.5rem; border: 1px dashed var(--line-strong); border-radius: .6rem; background: var(--surface-subtle); color: var(--muted); text-align: center; }
    #|.placement-empty strong { color: var(--ink); }
    #|.placement-visual figcaption { padding: .65rem 1.25rem; border-top: 1px solid var(--line); color: var(--muted); font-size: .68rem; }
    #|.placement-alternative { border: 1px solid var(--line); border-radius: .6rem; background: var(--surface); }
    #|.placement-alternative summary { min-height: 44px; padding: .65rem .85rem; color: var(--muted-strong); font-size: .72rem; font-weight: 720; cursor: pointer; }
    #|.placement-table-scroll { overflow-x: auto; border-top: 1px solid var(--line); }
    #|.placement-table { width: 100%; min-width: 42rem; border-collapse: collapse; font-size: .74rem; }
    #|.placement-table caption { padding: .65rem .8rem; color: var(--muted); text-align: left; }
    #|.placement-table th, .placement-table td { padding: .58rem .72rem; border-top: 1px solid var(--line); text-align: left; vertical-align: middle; }
    #|.placement-table th { color: var(--muted); font-size: .62rem; letter-spacing: .05em; text-transform: uppercase; }
    #|.alert-card-information { border-left: 4px solid var(--accent); }
    #|.alert-card-warning { border-left: 4px solid var(--warning); }
    #|.alert-card-critical { border-left: 4px solid var(--danger); }
    #|.alert-card-meta { display: flex; flex-wrap: wrap; justify-content: space-between; gap: .35rem; color: var(--muted); font-size: .62rem; }
    #|.alert-impact-edge { background: color-mix(in srgb,var(--danger) 42%,var(--line)); }
    #|.alert-quiet { border-color: color-mix(in srgb,var(--success) 35%,var(--line)); background: color-mix(in srgb,var(--success-soft) 55%,var(--surface)); }
    #|@media (max-width: 760px) { .placement-visual-heading { flex-direction: column; } .placement-visual-count { white-space: normal; } .placement-graph { overflow: visible; padding: .8rem; } .placement-rows { min-width: 0; } .placement-row { grid-template-columns: 1fr; gap: .45rem; } .placement-edge { width: 2px; height: 1.5rem; margin-left: 1.4rem; } .placement-edge::after { right: 50%; top: auto; bottom: 0; transform: translateX(50%) rotate(135deg); } .placement-edge span { left: .75rem; bottom: .45rem; transform: none; } .placement-state-pair { grid-template-columns: 1fr; } }
  )
}
