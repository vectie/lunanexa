///|
fn speculative_label(tokens : Int32) -> String {
  if tokens == 0 {
    "关闭（普通解码）"
  } else if tokens > 0 {
    "MTP · \{tokens} 个草稿 token"
  } else {
    "未记录，不能判定"
  }
}

///|
fn speculative_panel(
  state : ConsoleState,
  pool : ModelPoolView,
  disabled : Bool,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let draft = if state.model_pool.speculative_tokens == "" {
    pool.speculative_tokens.to_string()
  } else {
    state.model_pool.speculative_tokens
  }
  let running = pool.benchmark.map_or(false, b => {
    b.status == "queued" || b.status == "running"
  })
  let unavailable = disabled ||
    running ||
    !pool.adopted ||
    pool.model == "" ||
    !pool.participating().all(r => r.cache_ready)
  @html.section(class="model-benchmark-panel", [
    @html.h3("推测解码 · Speculative decoding"),
    @html.p(
      attrs=@html.Attrs::build().aria_live("polite"),
      "目标：" +
      speculative_label(pool.speculative_tokens) +
      " · 已生效 \{pool.participating().count_if(r => r.configuration_ready && r.ready)}/\{pool.participating().length()} 台",
    ),
    @html.label(for_="model-pool-speculative", "解码方式"),
    @html.select(
      id="model-pool-speculative",
      attrs=@html.Attrs::build().disabled(unavailable),
      on_change=text_command(emit, value => ModelPoolSpeculativeSelect(value)),
      [
        for tokens in [0, 1, 2, 3, 4, 5] => {
          @html.option(
            value=tokens.to_string(),
            selected=draft == tokens.to_string(),
            speculative_label(tokens),
          )
        }
      ],
    ),
    @html.p(
      class="secondary",
      "使用当前模型自带的 MTP 层，无需额外下载。应用会重启参与节点的模型服务，期间暂不可用；不改变并发限制。先测关闭基线，再开启对照，收益以实测为准。",
    ),
    @html.div(class="form-actions", [
      @html.button(
        disabled=unavailable,
        on_click=command(emit, ModelPoolAction("speculative")),
        "应用解码配置到参与节点（重启）",
      ),
      @html.button(
        disabled=unavailable ||
          (
            pool.speculative_tokens == 0 &&
            pool.participating().all(r => r.configuration_ready)
          ),
        on_click=command(emit, ModelPoolAction("speculative-off")),
        "关闭并恢复普通解码",
      ),
    ]),
  ])
}

///|
fn benchmark_comparison(pool : ModelPoolView) -> @rabbita.Html {
  guard pool.baseline_benchmark is Some(baseline) &&
    pool.benchmark is Some(current) else {
    return @html.nothing
  }
  let comparable = baseline.status == "complete" &&
    current.status == "complete" &&
    baseline.profile != "" &&
    baseline.profile == current.profile &&
    baseline.node_ids is Some(_) &&
    baseline.node_ids == current.node_ids &&
    baseline.model == current.model &&
    baseline.artifact_digest == current.artifact_digest &&
    baseline.runtime_image == current.runtime_image
  @html.section([
    @html.h4("上轮 / 本轮对照 · 32 人 × 3 轮"),
    @html.p(
      if comparable {
        "同模型、同运行时、同测速规格；速度和质量分别判定，有质量失败不宣称完整验收。"
      } else {
        "对照尚未完成，或节点范围、模型、运行时、规格不一致，暂不判定收益。"
      },
    ),
    @html.p(paired_quality_summary(baseline, current, comparable)),
    @html.div(
      class="model-pool-grid",
      [
        for report in [baseline, current] => {
          let samples = report.samples.filter(s => s.concurrency == 32)
          let valid = samples.filter(s => s.valid)
          let rates = valid.map(s => s.end_to_end_tokens_per_second)
          @html.article(class="access-package-card", [
            @html.h4(speculative_label(report.speculative_tokens)),
            @html.p(report.tuning.map_or("缓存配置未记录", tuning_label)),
            @html.p("场景：" + report.profile),
            @html.p(
              "成功 \{valid.length()}/96 · 端到端 ≥30：\{valid.count_if(s => s.end_to_end_tokens_per_second >= 30.0)}/96",
            ),
            if rates.is_empty() {
              @html.p("等待结果")
            } else {
              @html.p(
                "端到端 \{metric_number(rates.fold(init=rates[0], (a,b) => a.min(b)))}–\{metric_number(rates.fold(init=rates[0], (a,b) => a.max(b)))} token/s",
              )
            },
            comparison_latencies(report),
            @html.p(
              if report.status == "complete" &&
                samples.length() == 96 &&
                samples.all(s => {
                  s.valid && s.end_to_end_tokens_per_second >= 30.0
                }) {
                if report.quality_samples.length() ==
                  (if report.quality_suite_digest is Some(_) {
                    192
                  } else {
                    64
                  }) &&
                  report.quality_samples.all(s => s.valid) {
                  "本轮速度与本题集检查均通过：三轮均为 32/32，质量 \{report.quality_samples.length()}/\{report.quality_samples.length()}"
                } else {
                  "速度达到三轮 32/32；质量检查未通过或未记录，不能判定完整验收"
                }
              } else {
                "尚未达到三轮均为 32/32"
              },
            ),
          ])
        }
      ],
    ),
  ])
}

///|
fn paired_quality_summary(
  baseline : ModelBenchmarkView,
  current : ModelBenchmarkView,
  comparable : Bool,
) -> String {
  if baseline.quality_suite_digest is Some(_) ||
    current.quality_suite_digest is Some(_) {
    return fixed_quality_summary(baseline, current, comparable)
  }
  guard comparable &&
    baseline.quality_samples.length() == 64 &&
    current.quality_samples.length() == 64 else {
    return "同题质量对照未齐全；旧报告没有质量记录时不能推断质量不变。"
  }
  let mut new_failures = 0
  let mut repeated_failures = 0
  for round in 1..<=2 {
    for user in 1..<=32 {
      let before = baseline.quality_samples.filter(s => {
        s.user == user && s.round == round
      })
      let after = current.quality_samples.filter(s => {
        s.user == user && s.round == round
      })
      guard before.length() == 1 && after.length() == 1 else {
        return "同题质量对照缺项或重复，不能判定。"
      }
      if !after[0].valid {
        if before[0].valid {
          new_failures += 1
        } else {
          repeated_failures += 1
        }
      }
    }
  }
  "旧版同类题质量对照：新增失败 \{new_failures}，重复失败 \{repeated_failures}。提示：运行标识随轮次改变，并非字节一致的固定题集，不据此确认质量不变。"
}

///|
fn fixed_quality_summary(
  baseline : ModelBenchmarkView,
  current : ModelBenchmarkView,
  comparable : Bool,
) -> String {
  guard comparable &&
    baseline.quality_suite_digest is Some(digest) &&
    digest != "" &&
    current.quality_suite_digest == Some(digest) &&
    baseline.tuning is Some(tuning) &&
    tuning.prefix_caching == Some(false) &&
    current.tuning == Some(tuning) else {
    return "固定题集对照条件不一致或未齐全；需相同题集校验值、节点、运行时、模型和缓存/预填充配置。"
  }
  for report in [baseline, current] {
    guard report.quality_samples.length() == 192 &&
      report.node_ids is Some(ids) &&
      !ids.is_empty() &&
      report.quality_node_counts is Some(counts) &&
      counts.length() == ids.length() &&
      ids.all(id => counts.get(id).unwrap_or(0) > 0) &&
      counts.values().fold(init=0, (a, n) => a + n) == 192 else {
      return "固定题集记录或节点覆盖未齐全，不能判定。"
    }
    for round in 1..<=6 {
      for user in 1..<=32 {
        let samples = report.quality_samples.filter(s => {
          s.user == user && s.round == round
        })
        guard samples.length() == 1 && samples[0].concurrency == 32 else {
          return "固定题集缺项或重复，不能判定。"
        }
        guard samples[0].status == Some(200) &&
          (
            samples[0].valid ||
            samples[0].error.unwrap_or("").has_prefix("quality:")
          ) else {
          return "固定题集存在传输失败，不能判定质量。"
        }
      }
    }
  }
  let mut worse = 0
  let mut better = 0
  for variant in 1..<=2 {
    for user in 1..<=32 {
      let before = baseline.quality_samples.count_if(s => {
        s.user == user && (s.round - 1) % 2 + 1 == variant && !s.valid
      })
      let after = current.quality_samples.count_if(s => {
        s.user == user && (s.round - 1) % 2 + 1 == variant && !s.valid
      })
      if after > before {
        worse += 1
      }
      if after < before {
        better += 1
      }
    }
  }
  "固定题集逐题三次对照：失败次数增加 \{worse}/64 题，减少 \{better}/64 题。" +
  (if worse == 0 {
    "本固定题集未观察到质量退步；仍不代表完整业务质量保证。"
  } else {
    "存在逐题退步信号，不据此启用新解码配置；需复测。"
  })
}

///|
fn comparison_latencies(report : ModelBenchmarkView) -> @rabbita.Html {
  let valid = report.samples.filter(s => s.concurrency == 32 && s.valid)
  if valid.is_empty() {
    return @html.nothing
  }
  let ttft = valid.map(s => s.ttft_ms)
  let tails = valid
    .filter(s => s.timings.contains("stream_tail_ms"))
    .map(s => s.timings["stream_tail_ms"])
  @html.div([
    @html.p(
      "端到端平均：\{metric_number(valid.fold(init=0.0, (a,s) => a + s.end_to_end_tokens_per_second) / valid.length().to_double())} token/s",
    ),
    @html.p(
      "总吞吐：" +
      (if report.wall_ms > 0L {
        metric_number(
          valid.fold(init=0, (a, s) => a + s.output_tokens).to_double() *
          1000.0 /
          report.wall_ms.to_double(),
        )
      } else {
        "未记录"
      }) +
      " token/s",
    ),
    latency_summary("首 token", ttft),
    latency_summary("收尾", tails),
    @html.p(
      "质量检查：\{report.quality_samples.count_if(s => s.valid)}/\{report.quality_samples.length()}",
    ),
  ])
}

///|
fn latency_summary(label : String, values : Array[Int64]) -> @rabbita.Html {
  if values.is_empty() {
    return @html.p(label + "：未记录")
  }
  let ordered = values.copy()
  ordered.sort()
  let mean = ordered.fold(init=0L, (a, b) => a + b).to_double() /
    ordered.length().to_double() /
    1000.0
  let p95 = ordered[(ordered.length() * 95 + 99) / 100 - 1].to_double() / 1000.0
  @html.p(
    label +
    "平均 / P95 / 最长：\{metric_number(mean)} / \{metric_number(p95)} / \{metric_number(ordered.last().unwrap().to_double() / 1000.0)} 秒",
  )
}
