///|
fn observability_localized(
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
fn observability_request_metric(
  label : String,
  value : String,
  unit : String,
  context : String,
  mark : String,
) -> @rabbita.Html {
  @html.div(class="obs-metric", [
    @html.span(
      class="obs-metric-mark",
      attrs=@html.Attrs::build().aria_hidden("true"),
      mark,
    ),
    @html.div(class="obs-metric-copy", [
      @html.span(class="obs-metric-label", label),
      @html.span(class="obs-metric-value", [
        @html.strong(value),
        if unit == "" {
          @html.nothing
        } else {
          @html.small(unit)
        },
      ]),
      @html.span(class="obs-metric-context", context),
    ]),
  ])
}

///|
fn request_telemetry_chart(state : ConsoleState) -> @rabbita.Html {
  let locale = state.locale
  let all_zero = state.requests.count == 0 &&
    state.requests.p95_ms == 0 &&
    state.requests.throughput_per_second == 0 &&
    state.requests.errors == 0
  @html.figure(class="obs-figure obs-request-figure", [
    @html.div(class="obs-figure-heading", [
      @html.div([
        @html.p(
          class="eyebrow",
          observability_localized(locale, "Current telemetry", "当前遥测"),
        ),
        @html.h3(
          observability_localized(
            locale, "Aggregate request snapshot", "请求聚合快照",
          ),
        ),
      ]),
      @html.span(
        class="obs-scope-badge",
        observability_localized(
          locale, "Window/profile: not supplied", "时间窗口/配置：未提供",
        ),
      ),
    ]),
    @html.div(
      class="obs-metric-plot",
      attrs=@html.Attrs::build().aria_hidden("true"),
      [
        observability_request_metric(
          observability_localized(locale, "Audited count", "已审计数量"),
          state.requests.count.to_string(),
          observability_localized(locale, "events", "个事件"),
          observability_localized(
            locale, "Aggregate count in this snapshot", "此快照中的聚合数量",
          ),
          "#",
        ),
        observability_request_metric(
          observability_localized(locale, "p95 latency", "p95 延迟"),
          state.requests.p95_ms.to_string(),
          "ms",
          observability_localized(
            locale, "Reported percentile; sampling window unavailable", "已上报百分位；采样窗口不可用",
          ),
          "P95",
        ),
        observability_request_metric(
          observability_localized(locale, "Throughput", "吞吐量"),
          state.requests.throughput_per_second.to_string(),
          "/s",
          observability_localized(
            locale, "Reported aggregate rate", "已上报聚合速率",
          ),
          "TPS",
        ),
        observability_request_metric(
          observability_localized(locale, "Errors", "错误"),
          state.requests.errors.to_string(),
          observability_localized(locale, "events", "个事件"),
          observability_localized(
            locale, "Absolute error count; no target supplied", "错误绝对数量；未提供目标值",
          ),
          "!",
        ),
      ],
    ),
    if all_zero {
      @html.p(
        class="obs-zero-note",
        observability_localized(
          locale, "All four values in the current snapshot are zero.", "当前快照中的四项数值均为零。",
        ),
      )
    } else {
      @html.nothing
    },
    @html.details(class="obs-data-alternative", [
      @html.summary(
        observability_localized(locale, "Request data table", "请求数据表"),
      ),
      @html.div(
        class="table-scroll",
        attrs=@html.Attrs::build()
          .tabindex(0)
          .aria_label(
            observability_localized(
              locale, "Scrollable request telemetry table", "可滚动的请求遥测数据表",
            ),
          ),
        [
          @html.table(class="resource-table obs-data-table", [
            @html.caption(
              observability_localized(
                locale, "Current request telemetry values", "当前请求遥测数值",
              ),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  observability_localized(locale, "Metric", "指标"),
                ),
                @html.th(
                  scope=Col,
                  observability_localized(locale, "Value", "数值"),
                ),
                @html.th(
                  scope=Col,
                  observability_localized(locale, "Scope", "范围"),
                ),
              ]),
            ),
            @html.tbody([
              @html.tr([
                @html.th(
                  scope=Row,
                  observability_localized(
                    locale, "Audited count", "已审计数量",
                  ),
                ),
                @html.td(state.requests.count.to_string()),
                @html.td(
                  observability_localized(
                    locale, "Current aggregate snapshot", "当前聚合快照",
                  ),
                ),
              ]),
              @html.tr([
                @html.th(
                  scope=Row,
                  observability_localized(locale, "p95 latency", "p95 延迟"),
                ),
                @html.td("\{state.requests.p95_ms} ms"),
                @html.td(
                  observability_localized(
                    locale, "Window not supplied", "未提供时间窗口",
                  ),
                ),
              ]),
              @html.tr([
                @html.th(
                  scope=Row,
                  observability_localized(locale, "Throughput", "吞吐量"),
                ),
                @html.td("\{state.requests.throughput_per_second}/s"),
                @html.td(
                  observability_localized(
                    locale, "Current aggregate snapshot", "当前聚合快照",
                  ),
                ),
              ]),
              @html.tr([
                @html.th(
                  scope=Row,
                  observability_localized(locale, "Errors", "错误"),
                ),
                @html.td(state.requests.errors.to_string()),
                @html.td(
                  observability_localized(
                    locale, "No target supplied", "未提供目标值",
                  ),
                ),
              ]),
            ]),
          ]),
        ],
      ),
    ]),
    @html.figcaption(
      observability_localized(
        locale, "Values come directly from the current ConsoleState aggregate. No time series, target, sampling window, or workload profile is available, so the tiles do not imply a shared scale or trend.",
        "数值直接来自当前 ConsoleState 聚合数据。由于没有时间序列、目标值、采样窗口或工作负载配置，这些方块不表示共用比例或趋势。",
      ),
    ),
  ])
}

///|
fn benchmark_comparison_chart(state : ConsoleState) -> @rabbita.Html {
  let locale = state.locale
  @html.figure(class="obs-figure obs-benchmark-figure", [
    @html.div(class="obs-figure-heading", [
      @html.div([
        @html.p(
          class="eyebrow",
          observability_localized(locale, "Evidence comparison", "证据比较"),
        ),
        @html.h3(
          observability_localized(
            locale, "Recorded benchmark evidence", "已记录的基准证据",
          ),
        ),
      ]),
      @html.span(
        class="obs-scope-badge",
        observability_localized(locale, "Text evidence only", "仅文本证据"),
      ),
    ]),
    if state.benchmark_evidence.length() == 0 {
      @html.p(
        class="empty-state compact",
        observability_localized(
          locale, "No benchmark evidence is available.", "暂无基准测试证据。",
        ),
      )
    } else {
      @html.ol(
        class="obs-evidence-plot",
        attrs=@html.Attrs::build().aria_hidden("true"),
        [
          for i, evidence in state.benchmark_evidence => {
            @html.li(class="obs-evidence-lane", [
              @html.span(class="obs-evidence-index", (i + 1).to_string()),
              @html.strong(class="mono", evidence),
            ])
          }
        ],
      )
    },
    if state.benchmark_evidence.length() == 0 {
      @html.nothing
    } else {
      @html.details(class="obs-data-alternative", [
        @html.summary(
          observability_localized(
            locale, "Benchmark evidence table", "基准测试证据表",
          ),
        ),
        @html.div(
          class="table-scroll",
          attrs=@html.Attrs::build()
            .tabindex(0)
            .aria_label(
              observability_localized(
                locale, "Scrollable benchmark evidence table", "可滚动的基准证据表",
              ),
            ),
          [
            @html.table(class="resource-table obs-data-table", [
              @html.caption(
                observability_localized(
                  locale, "Unparsed benchmark evidence in recorded order", "按记录顺序展示的未解析基准测试证据",
                ),
              ),
              @html.thead(
                @html.tr([
                  @html.th(
                    scope=Col,
                    observability_localized(locale, "Lane", "通道"),
                  ),
                  @html.th(
                    scope=Col,
                    observability_localized(
                      locale, "Recorded evidence", "已记录证据",
                    ),
                  ),
                ]),
              ),
              @html.tbody(
                [
                  for i, evidence in state.benchmark_evidence => {
                    @html.tr([
                      @html.th(scope=Row, (i + 1).to_string()),
                      @html.td(class="mono", evidence),
                    ])
                  }
                ],
              ),
            ]),
          ],
        ),
      ])
    },
    @html.figcaption(
      observability_localized(
        locale, "Each lane is the exact benchmark evidence string supplied by ConsoleState. Lane length and order carry no numeric performance meaning; typed model, runtime, hardware, metric, unit, and target fields are not available for a quantitative plot.",
        "每个通道均为 ConsoleState 提供的原始基准证据字符串。通道长度和顺序不代表数值性能；当前没有可用于定量绘图的类型化模型、运行时、硬件、指标、单位和目标字段。",
      ),
    ),
  ])
}

///|
fn observability_audit_node(
  kind : String,
  label : String,
  value : String,
) -> @rabbita.Html {
  @html.div(class="obs-audit-node obs-audit-node-\{kind}", [
    @html.span(class="obs-audit-label", label),
    @html.strong(class=if kind == "receipt" { "mono" } else { "" }, value),
  ])
}

///|
fn audit_decision_graph(state : ConsoleState) -> @rabbita.Html {
  let locale = state.locale
  @html.figure(class="obs-figure obs-audit-figure", [
    @html.div(class="obs-figure-heading", [
      @html.div([
        @html.p(
          class="eyebrow",
          observability_localized(locale, "Decision lineage", "决策链路"),
        ),
        @html.h3(
          observability_localized(
            locale, "Actor to immutable receipt", "从操作者到不可变回执",
          ),
        ),
      ]),
      @html.span(
        class="obs-scope-badge",
        observability_localized(
          locale,
          "\{state.audit.length()} recorded paths",
          "\{state.audit.length()} 条已记录路径",
        ),
      ),
    ]),
    if state.audit.length() == 0 {
      @html.p(
        class="empty-state compact",
        observability_localized(
          locale, "No audit decision paths are available.", "暂无审计决策路径。",
        ),
      )
    } else {
      @html.ol(
        class="obs-audit-plot",
        attrs=@html.Attrs::build()
          .tabindex(0)
          .aria_label(
            observability_localized(
              locale, "Scrollable audit decision paths", "可滚动的审计决策路径",
            ),
          ),
        [
          for event in state.audit => {
            @html.li(class="obs-audit-path", [
              observability_audit_node(
                "actor",
                observability_localized(locale, "Actor", "操作者"),
                event.actor,
              ),
              @html.span(class="obs-audit-edge", "→"),
              observability_audit_node(
                "decision",
                observability_localized(locale, "Decision", "决策"),
                event.decision,
              ),
              @html.span(class="obs-audit-edge", "→"),
              observability_audit_node(
                "evidence",
                observability_localized(locale, "Evidence", "证据"),
                event.evidence,
              ),
              @html.span(class="obs-audit-edge", "→"),
              observability_audit_node(
                "result",
                observability_localized(locale, "Result", "结果"),
                event.result,
              ),
              @html.span(class="obs-audit-edge", "→"),
              observability_audit_node(
                "receipt",
                observability_localized(locale, "Receipt", "回执"),
                event.receipt,
              ),
            ])
          }
        ],
      )
    },
    if state.audit.length() == 0 {
      @html.nothing
    } else {
      @html.details(class="obs-data-alternative", [
        @html.summary(
          observability_localized(locale, "Audit path table", "审计路径表"),
        ),
        @html.div(
          class="table-scroll",
          attrs=@html.Attrs::build()
            .tabindex(0)
            .aria_label(
              observability_localized(
                locale, "Scrollable audit path table", "可滚动的审计路径表",
              ),
            ),
          [
            @html.table(class="resource-table obs-data-table obs-audit-table", [
              @html.caption(
                observability_localized(
                  locale, "Actor, decision, evidence, result, and receipt for every audit record",
                  "每条审计记录的操作者、决策、证据、结果和回执",
                ),
              ),
              @html.thead(
                @html.tr([
                  @html.th(
                    scope=Col,
                    observability_localized(locale, "Actor", "操作者"),
                  ),
                  @html.th(
                    scope=Col,
                    observability_localized(locale, "Decision", "决策"),
                  ),
                  @html.th(
                    scope=Col,
                    observability_localized(locale, "Evidence", "证据"),
                  ),
                  @html.th(
                    scope=Col,
                    observability_localized(locale, "Result", "结果"),
                  ),
                  @html.th(
                    scope=Col,
                    observability_localized(locale, "Receipt", "回执"),
                  ),
                ]),
              ),
              @html.tbody(
                [
                  for event in state.audit => {
                    @html.tr([
                      @html.td(event.actor),
                      @html.td(event.decision),
                      @html.td(event.evidence),
                      @html.td(event.result),
                      @html.td(class="mono", event.receipt),
                    ])
                  }
                ],
              ),
            ]),
          ],
        ),
      ])
    },
    @html.figcaption(
      observability_localized(
        locale, "Every path is rendered from one AuditRow: actor → decision → evidence → result → receipt. Text labels preserve state when color is unavailable.",
        "每条路径均由一条 AuditRow 渲染：操作者 → 决策 → 证据 → 结果 → 回执。即使颜色不可用，文本标签也会保留状态含义。",
      ),
    ),
  ])
}

///|
fn observability_visual_styles() -> String {
  (
    #|.obs-figure { margin: 1rem 0 1.25rem; overflow: hidden; border: 1px solid var(--line); border-radius: .7rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.obs-figure-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; padding: 1rem 1.1rem; border-bottom: 1px solid var(--line); background: linear-gradient(135deg, var(--surface), var(--surface-subtle)); }
    #|.obs-figure-heading h3 { margin: 0; }
    #|.obs-scope-badge { display: inline-flex; align-items: center; min-height: 2rem; padding: .3rem .55rem; border: 1px solid var(--line-strong); border-radius: 999px; background: var(--surface); color: var(--muted-strong); font-size: .7rem; font-weight: 720; text-align: center; }
    #|.obs-metric-plot { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .7rem; padding: 1rem 1.1rem; }
    #|.obs-metric { position: relative; min-width: 0; min-height: 8rem; display: grid; grid-template-columns: 2.2rem minmax(0, 1fr); gap: .7rem; align-items: start; padding: .85rem; border: 1px solid var(--line); border-radius: .55rem; background: var(--surface-subtle); }
    #|.obs-metric-mark { display: grid; place-items: center; width: 2.2rem; height: 2.2rem; border: 1px solid color-mix(in srgb, var(--accent) 34%, var(--line)); border-radius: .45rem; background: var(--accent-soft); color: var(--accent); font-size: .63rem; font-weight: 800; letter-spacing: .02em; }
    #|.obs-metric-copy { min-width: 0; display: grid; gap: .15rem; }
    #|.obs-metric-label, .obs-audit-label { color: var(--muted); font-size: .68rem; font-weight: 720; letter-spacing: .04em; text-transform: uppercase; }
    #|.obs-metric-value { display: flex; flex-wrap: wrap; align-items: baseline; gap: .25rem; color: var(--ink); }
    #|.obs-metric-value strong { font-size: 1.55rem; line-height: 1.15; letter-spacing: -.035em; }
    #|.obs-metric-value small { color: var(--muted-strong); font-size: .72rem; font-weight: 700; }
    #|.obs-metric-context { color: var(--muted); font-size: .68rem; line-height: 1.4; }
    #|.obs-zero-note { margin: 0 1.1rem .85rem; padding: .65rem .75rem; border-left: .2rem solid var(--line-strong); background: var(--surface-subtle); color: var(--muted); font-size: .74rem; }
    #|.obs-evidence-plot, .obs-audit-plot { margin: 0; padding: 1rem 1.1rem; list-style: none; }
    #|.obs-evidence-plot { display: grid; gap: .65rem; }
    #|.obs-evidence-lane { min-width: 0; display: grid; grid-template-columns: 2rem minmax(0, 1fr); gap: .65rem; align-items: center; padding: .7rem .8rem; border: 1px solid var(--line); border-radius: .5rem; background: var(--surface-subtle); }
    #|.obs-evidence-index { display: grid; place-items: center; width: 1.75rem; height: 1.75rem; border-radius: 999px; background: var(--ink); color: var(--surface); font-size: .68rem; font-weight: 800; }
    #|.obs-evidence-lane strong { min-width: 0; overflow-wrap: anywhere; font-size: .75rem; }
    #|.obs-audit-plot { display: grid; gap: .8rem; overflow-x: auto; }
    #|.obs-audit-plot:focus-visible, .obs-data-alternative .table-scroll:focus-visible { outline: 3px solid var(--accent); outline-offset: -3px; }
    #|.obs-audit-path { min-width: 58rem; display: grid; grid-template-columns: repeat(4, minmax(8rem, 1fr) 1.2rem) minmax(10rem, 1.15fr); align-items: stretch; }
    #|.obs-audit-node { min-width: 0; display: grid; align-content: start; gap: .25rem; padding: .7rem .75rem; border: 1px solid var(--line); border-radius: .48rem; background: var(--surface-subtle); }
    #|.obs-audit-node strong { overflow-wrap: anywhere; font-size: .76rem; line-height: 1.4; }
    #|.obs-audit-node-receipt { border-style: dashed; background: var(--surface); }
    #|.obs-audit-edge { display: grid; place-items: center; color: var(--muted); font-size: .9rem; font-weight: 800; }
    #|.obs-data-alternative { margin: 0 1.1rem 1rem; border: 1px solid var(--line); border-radius: .5rem; background: var(--surface); }
    #|.obs-data-alternative summary { min-height: 44px; display: flex; align-items: center; padding: .55rem .7rem; color: var(--muted-strong); font-size: .75rem; font-weight: 720; cursor: pointer; }
    #|.obs-data-alternative .table-scroll { margin: 0 .7rem .7rem; box-shadow: none; }
    #|.obs-data-table { min-width: 38rem; }
    #|.obs-data-table caption { padding: .65rem .8rem; color: var(--muted); font-size: .72rem; text-align: left; }
    #|.obs-figure > .empty-state { margin: 1rem 1.1rem; }
    #|.obs-figure figcaption { padding: .7rem 1.1rem; border-top: 1px solid var(--line); background: var(--surface-subtle); color: var(--muted); font-size: .7rem; line-height: 1.45; }
    #|@media (max-width: 68rem) { .obs-metric-plot { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
    #|@media (max-width: 54rem) { .obs-figure-heading { flex-direction: column; } .obs-scope-badge { border-radius: .45rem; } }
    #|@media (max-width: 40rem) { .obs-metric-plot { grid-template-columns: 1fr; padding: .8rem; } .obs-metric { min-height: 0; } .obs-evidence-plot, .obs-audit-plot { padding: .8rem; } .obs-data-alternative { margin-inline: .8rem; } .obs-figure figcaption { padding-inline: .8rem; } }
  )
}
