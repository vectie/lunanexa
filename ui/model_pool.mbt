///|
pub(all) struct ModelPoolReplica {
  node_id : String
  deployment : String
  can_prepare : Bool
  cache_ready : Bool
  switched : Bool
  ready : Bool
  progress : String
  speculative_tokens : Int32
  configuration_ready : Bool
  selected : Bool?
  display_name : String?
  paused : Bool?
} derive(Eq, FromJson)

///|
pub extend ModelPoolReplica with Eq::{equal, not_equal}

///|
pub extend ModelPoolReplica with FromJson::{from_json}

///|
pub(all) struct ModelPoolView {
  tuning : ModelTuning
  adopted : Bool
  active : Bool
  generation : Int64
  model : String
  models : Array[String]
  replicas : Array[ModelPoolReplica]
  benchmark : ModelBenchmarkView?
  baseline_benchmark : ModelBenchmarkView?
  speculative_tokens : Int32
} derive(Eq, FromJson)

///|
pub extend ModelPoolView with Eq::{equal, not_equal}

///|
pub extend ModelPoolView with FromJson::{from_json}

///|
/// The API's optional report is serialized with the core Option encoder,
/// whereas derived optional record fields expect the report object directly.
pub fn decode_model_pool_view(value : Json) -> ModelPoolView raise {
  let value = match value {
    Object(fields) => {
      let fields = fields.copy()
      if !fields.contains("tuning") {
        fields["tuning"] = {
          "cache_aware_routing": false,
          "max_num_batched_tokens": 0,
        }
      }
      if !fields.contains("speculative_tokens") {
        fields["speculative_tokens"] = -1
      }
      if fields.get("replicas") is Some(Array(replicas)) {
        for replica in replicas {
          if replica is Object(r) {
            if !r.contains("speculative_tokens") {
              r["speculative_tokens"] = -1
            }
            if !r.contains("configuration_ready") {
              r["configuration_ready"] = false
            }
          }
        }
      }
      for name in ["benchmark", "baseline_benchmark"] {
        if fields.get(name) is Some(Array([])) {
          fields.remove(name)
        }
        if fields.get(name) is Some(Array([report])) {
          fields[name] = report
        }
        if fields.get(name) is Some(Object(report)) {
          for
            (key, default_value) in [
              ("speculative_tokens", Json(-1)),
              ("model", Json("")),
              ("artifact_digest", Json("")),
              ("runtime_image", Json("")),
              ("profile", Json("")),
              ("run_id", Json("")),
              ("quality_samples", Json::array([])),
            ] {
            if !report.contains(key) {
              report[key] = default_value
            }
          }
          if !report.contains("warmup_samples") {
            report["warmup_samples"] = Json::array([])
          }
          if report.get("samples") is Some(Array(samples)) {
            for sample in samples {
              if sample is Object(item) && !item.contains("timings") {
                item["timings"] = Json::empty_object()
              }
            }
          }
        }
      }
      Json::object(fields)
    }
    _ => value
  }
  @json.from_json(value)
}

///|
pub(all) struct ModelPoolPanel {
  tuning_draft : Map[String, String]
  view : ModelPoolView?
  model : String
  speculative_tokens : String
} derive(Eq)

///|
pub extend ModelPoolPanel with Eq::{equal, not_equal}

///|
pub fn empty_model_pool_panel() -> ModelPoolPanel {
  { view: None, model: "", speculative_tokens: "", tuning_draft: {}, }
}

///|
fn ModelPoolView::participating(
  self : ModelPoolView,
) -> Array[ModelPoolReplica] {
  self.replicas.filter(r => r.selected.unwrap_or(true))
}

///|
pub fn pool_scope_nodes(
  panel : ModelPoolPanel,
  pool : ModelPoolView,
) -> Array[String] {
  pool.replicas
  .filter(r => {
    panel.tuning_draft
    .get("node:" + r.node_id)
    .map_or(r.selected.unwrap_or(true), v => v == "on")
  })
  .map(r => r.node_id)
}

///|
pub fn pool_scope_names(
  panel : ModelPoolPanel,
  pool : ModelPoolView,
) -> Map[String, String] {
  Map::from_array(
    pool.replicas.map(r => {
      (
        r.node_id,
        panel.tuning_draft
        .get("name:" + r.node_id)
        .unwrap_or(r.display_name.unwrap_or(r.node_id)),
      )
    }),
  )
}

///|
fn model_pool_panel(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  guard state.model_pool.view is Some(pool) else { return @html.nothing }
  let busy = state.loading ||
    !state.operator_authenticated ||
    pool.benchmark.map_or(false, b => ["running", "queued"].contains(b.status))
  let scope_nodes = pool_scope_nodes(state.model_pool, pool)
  let scope_names = pool_scope_names(state.model_pool, pool)
  let pending_scope = scope_nodes != pool.participating().map(r => r.node_id) ||
    pool.replicas.any(r => {
      scope_names.get(r.node_id) != Some(r.display_name.unwrap_or(r.node_id))
    })
  let disabled = busy || pending_scope
  let selected = if state.model_pool.model == "" {
    pool.model
  } else {
    state.model_pool.model
  }
  @html.section(class="access-package-panel model-pool-panel", [
    @html.div(class="section-heading", [
      @html.h2("共享模型池"),
      @controls.icon_button(
        Refresh,
        "刷新就绪状态",
        command(emit, Refresh),
        disabled=!state.operator_authenticated,
        busy=state.loading,
      ),
    ]),
    @html.h3(model_generation(pool.model, model_family(pool.model))),
    @html.p(
      if !pool.active {
        "路由未启用"
      } else if pool.participating().is_empty() ||
        !pool.participating().all(r => r.ready) {
        "路由已启用 · 服务未就绪"
      } else {
        "提供服务"
      },
    ),
    @html.div(
      class="pool-running-list",
      [
        ..pool
        .participating()
        .map(r => {
          @html.div(class="pool-running-row", [
            @html.strong(r.display_name.unwrap_or(r.node_id)),
            @html.span(
              if r.ready {
                "已就绪"
              } else if r.switched {
                "启动中"
              } else {
                "未切换"
              },
            ),
          ])
        }),
      ],
    ),
    @html.details(class="pool-deployment-settings", open=pending_scope, [
      @html.summary("切换模型与节点"),
      @html.div(
        class="model-pool-grid",
        [
          for replica in pool.replicas => {
            @html.article(
              class=if scope_nodes.contains(replica.node_id) {
                "access-package-card pool-replica is-selected"
              } else {
                "access-package-card pool-replica"
              },
              [
                @html.div(class="pool-replica-heading", [
                  @html.h3(replica.display_name.unwrap_or(replica.node_id)),
                  @html.p([
                    @html.label([
                      @html.input(
                        input_type=Checkbox,
                        checked=scope_nodes.contains(replica.node_id),
                        attrs=@html.Attrs::build()
                          .disabled(busy)
                          .aria_label(
                            "参与模型服务 · " + replica.node_id,
                          ),
                        on_change=text_command(emit, _ => {
                          ModelPoolTuningSelect(
                            "node:" + replica.node_id,
                            if scope_nodes.contains(replica.node_id) {
                              "off"
                            } else {
                              "on"
                            },
                          )
                        }),
                      ),
                      @html.text("参与"),
                    ]),
                  ]),
                ]),
                @controls.advanced("节点详情", [
                  @html.p(
                    class="mono secondary",
                    replica.node_id + " · " + replica.deployment,
                  ),
                  @html.div(class="field-group", [
                    @html.label(
                      for_="pool-name-" + replica.node_id,
                      "节点显示名称",
                    ),
                    @html.input(
                      id="pool-name-" + replica.node_id,
                      input_type=Text,
                      attrs=@html.Attrs::build()
                        .disabled(busy)
                        .aria_label("节点显示名称 · " + replica.node_id),
                      value=scope_names
                        .get(replica.node_id)
                        .unwrap_or(replica.node_id),
                      on_input=text_command(emit, v => {
                        ModelPoolTuningSelect("name:" + replica.node_id, v)
                      }),
                    ),
                  ]),
                  @html.p(
                    if replica.can_prepare {
                      "节点支持 UI 准备"
                    } else {
                      "节点代理需要更新"
                    },
                  ),
                  @html.p(
                    if replica.configuration_ready {
                      "实际解码：" +
                      speculative_label(replica.speculative_tokens)
                    } else {
                      "解码配置待就绪 / 待核对"
                    },
                  ),
                  @html.p(class="secondary", replica.progress),
                  @html.p(
                    if replica.cache_ready {
                      "权重已校验"
                    } else {
                      "权重待准备"
                    },
                  ),
                ]),
                @html.p(
                  class="pool-replica-state",
                  if replica.selected == Some(false) {
                    if replica.paused == Some(true) {
                      "已退出路由 · 模型已停止"
                    } else {
                      "已退出路由 · 模型待停止 / 释放中"
                    }
                  } else if replica.ready {
                    "新模型已就绪"
                  } else if replica.switched {
                    "模型启动中"
                  } else {
                    "尚未切换"
                  },
                ),
              ],
            )
          }
        ],
      ),
      @html.p(
        "应用后，未选节点的模型服务将退出路由并停止。权重保留。",
      ),
      @html.button(
        disabled=busy || !pool.adopted || scope_nodes.is_empty(),
        on_click=command(emit, ModelPoolAction("scope")),
        "应用节点范围",
      ),
      if pending_scope {
        @html.p(
          "节点范围或名称尚未应用，请先应用再进行调优和测速。",
        )
      } else {
        @html.nothing
      },
      @html.div(class="field-group", [
        @html.label(for_="model-pool-model", "目标模型"),
        @html.select(
          id="model-pool-model",
          attrs=@html.Attrs::build().disabled(disabled),
          on_change=text_command(emit, value => ModelPoolSelect(value)),
          [
            @html.option(value="", selected=selected == "", "请选择模型"),
            ..pool_model_options(pool.models, selected),
          ],
        ),
      ]),
      @html.div(class="form-actions", [
        if !pool.adopted {
          @html.button(
            disabled=disabled || pool.adopted,
            on_click=command(emit, ModelPoolAction("adopt")),
            if pool.adopted {
              "已接管 \{pool.replicas.length()} 个服务"
            } else {
              "接管已配置服务"
            },
          )
        } else {
          @html.nothing
        },
        @html.button(
          disabled=disabled ||
            !pool.adopted ||
            selected == "" ||
            !pool.participating().all(r => r.can_prepare),
          on_click=command(emit, ModelPoolAction("prepare")),
          "准备参与节点权重",
        ),
        @html.button(
          disabled=disabled || !pool.participating().all(r => r.cache_ready),
          on_click=command(emit, ModelPoolAction("switch")),
          "切换参与节点模型",
        ),
        @html.button(
          disabled=disabled ||
            !pool.participating().all(r => r.ready) ||
            pool.active,
          on_click=command(emit, ModelPoolAction("activate")),
          "启用新模型路由",
        ),
        @controls.icon_button(
          Refresh,
          "刷新就绪状态",
          command(emit, Refresh),
          disabled=!state.operator_authenticated,
          busy=state.loading,
        ),
        @html.button(
          disabled=disabled ||
            !pool.adopted ||
            !pool.participating().any(r => r.switched),
          on_click=command(emit, ModelPoolAction("rollback")),
          "恢复原模型",
        ),
      ]),
    ]),
    @controls.advanced("高级设置", [
      speculative_panel(state, pool, disabled, emit),
      tuning_panel(state, pool, disabled, emit),
      model_benchmark_panel(pool, disabled, emit),
    ]),
  ])
}

///|
pub(all) struct ModelBenchmarkSample {
  status : Int32?
  error : String?
  cached_input_tokens : Int32?
  input_tokens : Int32?
  user : Int32
  concurrency : Int32
  round : Int32
  output_tokens : Int32
  ttft_ms : Int64
  decode_tokens_per_second : Double
  end_to_end_tokens_per_second : Double
  valid : Bool
  timings : Map[String, Int64]
} derive(Eq, FromJson)

///|
pub extend ModelBenchmarkSample with Eq::{equal, not_equal}

///|
pub extend ModelBenchmarkSample with FromJson::{from_json}

///|
pub(all) struct ModelBenchmarkView {
  tuning : ModelTuning?
  quality_samples : Array[ModelBenchmarkSample]
  status : String
  phase : String
  prepared_users : Int32
  cleaned_users : Int32
  samples : Array[ModelBenchmarkSample]
  node_counts : Map[String, Int32]
  wall_ms : Int64
  error : String
  warmup_samples : Array[ModelBenchmarkSample]
  speculative_tokens : Int32
  model : String
  artifact_digest : String
  runtime_image : String
  profile : String
  run_id : String
  node_ids : Array[String]?
  quality_suite_digest : String?
  quality_node_counts : Map[String, Int32]?
} derive(Eq, FromJson)

///|
pub extend ModelBenchmarkView with Eq::{equal, not_equal}

///|
pub extend ModelBenchmarkView with FromJson::{from_json}

///|
fn metric_number(value : Double) -> String {
  ((value * 100.0).round() / 100.0).to_string()
}

///|
fn model_benchmark_panel(
  pool : ModelPoolView,
  disabled : Bool,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  guard pool.benchmark is Some(report) else { return @html.nothing }
  let running = report.status == "queued" || report.status == "running"
  @html.section(class="model-benchmark-panel", [
    @html.h3("真实用户测速"),
    @html.button(
      disabled~,
      on_click=command(emit, ModelPoolAction("export")),
      "导出测速证据 JSON",
    ),
    @html.p(
      "本次结果配置：" + speculative_label(report.speculative_tokens),
    ),
    @html.p(
      report.node_ids.map_or(
        "历史报告未记录节点范围；不能作为相同机器条件的对照。",
        ids => {
          "本次测速节点（\{ids.length()} 台）：" + ids.join("、")
        },
      ),
    ),
    @html.p(
      report.tuning.map_or("缓存配置：旧报告未记录", tuning_label),
    ),
    @html.p(
      "场景：" +
      report.profile +
      " · 质量回归 \{report.quality_samples.count_if(s => s.valid)}/\{report.quality_samples.length()}。仅覆盖长前缀事实更新、算术和 JSON；不能代替完整业务质量验收。",
    ),
    if report.quality_suite_digest is Some(digest) {
      @html.div([
        @html.p(
          "固定题集 v1：64 题 × 3 次；相同题目、temperature=0、top_p=1。固定输入不等于保证输出确定性；以重复实测为准。前缀缓存关闭，基础 KV Cache 保留。",
        ),
        @html.details(
          [
            @html.summary("固定题集校验与节点覆盖"),
            @html.p(class="mono", "题集 SHA-256：" + digest),
            ..[
              for (node, count) in report.quality_node_counts.unwrap_or(Map([])) => {
                @html.p("\{node}：\{count} 次质量请求")
              }
            ],
          ],
        ),
      ])
    } else {
      @html.nothing
    },
    @html.details(
      [
        @html.summary("质量回归逐项诊断（不保存回答原文）"),
        ..[
          for sample in report.quality_samples => {
            @html.p(
              "用户 \{sample.user} · 第 \{sample.round} 轮 · HTTP \{sample.status.unwrap_or(0)} · 输出 \{sample.output_tokens} token · " +
              (if sample.valid { "通过" } else { "未通过" }) +
              " · " +
              sample.error.unwrap_or(""),
            )
          }
        ],
      ],
    ),
    benchmark_comparison(pool),
    @html.p(
      class="section-copy",
      "32 个独立测试账号，经正常登录、个人 API 密钥和 /trial/v1。测试输入额度 32 KiB（字节，非 token），不更改普通活动额度。先做 64 项质量检查，再预热参与节点（结果单列），再测单人、32 人并发各 3 轮，每次最多输出 512 token。内容错误保留并继续诊断测速，不算质量通过；传输不完整则停止。仅授权当前模型 1 小时，结束后回收权限，不开放公开报名。",
    ),
    @html.button(
      disabled=disabled ||
        running ||
        !pool.active ||
        !pool.participating().all(r => r.ready),
      on_click=command(emit, ModelPoolAction("benchmark")),
      if running {
        "测速运行中…"
      } else {
        "开始单人 + 32 人测速"
      },
    ),
    @html.div(class="form-actions", [
      @html.button(
        disabled=disabled ||
          running ||
          !pool.active ||
          !pool.participating().all(r => r.ready) ||
          pool.tuning.prefix_caching != Some(false),
        on_click=command(emit, ModelPoolAction("benchmark-fixed")),
        "固定题集复测（64 题 × 3 次）",
      ),
      @html.button(
        disabled=disabled ||
          running ||
          !pool.active ||
          !pool.participating().all(r => r.ready),
        on_click=command(emit, ModelPoolAction("benchmark-cold")),
        "测长上下文（每轮新前缀）",
      ),
      @html.button(
        disabled=disabled ||
          running ||
          !pool.active ||
          !pool.participating().all(r => r.ready),
        on_click=command(emit, ModelPoolAction("benchmark-repeat")),
        "测重复长前缀（预热后）",
      ),
    ]),
    @html.p(
      class="secondary",
      "固定题集复测需先关闭前缀缓存；完成 192 次质量请求后，再跑相同的单人及 32 人三轮测速。不改变线上采样参数或并发限制。",
    ),
    @html.p(
      attrs=@html.Attrs::build().aria_live("polite"),
      "\{report.phase} · 账号 \{report.prepared_users}/32 · 质量请求 \{report.quality_samples.length()}/\{if report.quality_suite_digest is Some(_) { 192 } else { 64 }} · 完成请求 \{report.samples.length()}/99 · 已回收 \{report.cleaned_users}/32",
    ),
    if report.error != "" {
      @html.p(class="error-message", report.error)
    } else {
      @html.nothing
    },
    if !report.warmup_samples.is_empty() {
      let warm = report.warmup_samples
      let cold = warm.fold(init=0L, (a, s) => a.max(s.ttft_ms))
      @html.p(
        "预热：\{warm.count_if(s => s.valid)}/32 成功 · 最长首 token \{metric_number(cold.to_double() / 1000.0)} 秒 · 不计入以下验收",
      )
    } else {
      @html.nothing
    },
    @html.div(
      class="model-pool-grid",
      [
        for concurrency in [1, 32] => {
          let all = report.samples.filter(s => s.concurrency == concurrency)
          let valid = all.filter(s => s.valid)
          @html.article(class="access-package-card", [
            @html.h4(if concurrency == 1 { "单人" } else { "32 人并发" }),
            @html.p("成功 \{valid.length()}/\{all.length()}"),
            if valid.is_empty() {
              @html.p("等待实测")
            } else {
              let rates = valid.map(s => s.decode_tokens_per_second)
              let minimum = rates.fold(init=rates[0], (a, b) => a.min(b))
              let maximum = rates.fold(init=rates[0], (a, b) => a.max(b))
              let average = rates.fold(init=0.0, (a, b) => a + b) /
                rates.length().to_double()
              let ttft = valid.fold(init=0.0, (a, s) => {
                  a + s.ttft_ms.to_double()
                }) /
                valid.length().to_double()
              let e2e = valid.map(s => s.end_to_end_tokens_per_second)
              let e2e_min = e2e.fold(init=e2e[0], (a, b) => a.min(b))
              let e2e_max = e2e.fold(init=e2e[0], (a, b) => a.max(b))
              let measured = valid.filter(s => {
                s.timings.contains("stream_tail_ms")
              })
              @html.div([
                @html.p(
                  "已上报缓存 token：\{valid.filter(s => s.cached_input_tokens is Some(_)).fold(init=0, (n,s) => n + s.cached_input_tokens.unwrap_or(0))} · 有缓存统计 \{valid.count_if(s => s.cached_input_tokens is Some(_))}/\{valid.length()}；未上报不当作零命中。",
                ),
                @html.p(
                  "端到端：\{metric_number(e2e_min)}–\{metric_number(e2e_max)} token/s",
                ),
                @html.p(
                  "端到端 ≥30：\{valid.count_if(s => s.end_to_end_tokens_per_second >= 30.0)}/\{all.length()}",
                ),
                @html.p(
                  "每人输出：\{metric_number(minimum)}–\{metric_number(maximum)} token/s",
                ),
                @html.p("每人平均：\{metric_number(average)} token/s"),
                @html.p("平均首 token：\{metric_number(ttft / 1000.0)} 秒"),
                @html.p(
                  "仅解码 ≥30：\{valid.count_if(s => s.decode_tokens_per_second >= 30.0)}/\{all.length()}",
                ),
                if measured.is_empty() {
                  @html.p("收尾耗时：旧报告未单独记录")
                } else {
                  let tail = measured
                    .fold(init=0L, (a, s) => {
                      a + s.timings.get("stream_tail_ms").unwrap_or(0L)
                    })
                    .to_double() /
                    measured.length().to_double()
                  let max_tail = measured.fold(init=0L, (a, s) => {
                    a.max(s.timings.get("stream_tail_ms").unwrap_or(0L))
                  })
                  @html.p(
                    "收尾平均 / 最长：\{metric_number(tail / 1000.0)} / \{metric_number(max_tail.to_double() / 1000.0)} 秒",
                  )
                },
                @html.details(
                  [
                    @html.summary("延迟拆解（平均 / 最长，毫秒）"),
                    ..[
                      for
                        (key, label) in [
                          ("connect_ms", "连接建立"),
                          ("server_auth_ms", "控制器鉴权"),
                          ("server_admission_ms", "授权与路由准入"),
                          ("server_queue_ms", "执行槽等待"),
                          ("server_runtime_ttft_ms", "模型调用至首 token"),
                          ("server_receipt_ms", "结果与审计持久化"),
                          ("server_release_ms", "释放执行记录"),
                          ("server_billing_ms", "用量计量持久化"),
                          ("close_ms", "客户端流关闭"),
                        ] => {
                        let values = valid
                          .filter(s => s.timings.contains(key))
                          .map(s => s.timings.get(key).unwrap())
                        if values.is_empty() {
                          @html.nothing
                        } else {
                          let mean = values
                            .fold(init=0L, (a, b) => a + b)
                            .to_double() /
                            values.length().to_double()
                          let longest = values.fold(init=0L, (a, b) => a.max(b))
                          @html.p(
                            "\{label}：\{metric_number(mean)} / \{longest}",
                          )
                        }
                      }
                    ],
                  ],
                ),
              ])
            },
          ])
        }
      ],
    ),
    if report.wall_ms > 0L {
      let tokens = report.samples
        .filter(s => s.concurrency == 32 && s.valid)
        .fold(init=0, (a, s) => a + s.output_tokens)
      @html.p(
        "32 人端到端总吞吐（含首 token、收尾）：\{metric_number(tokens.to_double() * 1000.0 / report.wall_ms.to_double())} token/s",
      )
    } else {
      @html.nothing
    },
    if report.node_counts.is_empty() {
      @html.nothing
    } else {
      @html.p(
        "32 人并发分配：" +
        [
          for node, count in report.node_counts => "\{node} · \{count} 次"
        ].join("；"),
      )
    },
    @html.p(
      class="secondary",
      "端到端从发起请求计时至流完整结束；解码速度只计算首个到最后一个 token。收尾是最后一个 token 至 [DONE]。均用模型 usage 的 token 数，不以流式消息条数代替。刷新就绪状态可查看最新结果。",
    ),
  ])
}
