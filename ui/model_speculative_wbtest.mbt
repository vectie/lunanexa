///|
test "speculative controls disclose restart and retain draft while reporting observed state" {
  let pool : ModelPoolView = {
    tuning: default_model_tuning(),
    adopted: true,
    active: true,
    generation: 2L,
    model: "test",
    models: ["test"],
    speculative_tokens: 1,
    benchmark: None,
    baseline_benchmark: None,
    replicas: [
      for i in 0..<4 => {
        {
          node_id: "node-\{i}",
          deployment: "replica-\{i}",
          can_prepare: true,
          cache_ready: true,
          switched: true,
          ready: i < 3,
          progress: "",
          speculative_tokens: 1,
          configuration_ready: i < 3,
          selected: None,
          display_name: None,
          paused: None,
        }
      }
    ],
  }
  let state = {
    ..demo_state(),
    route: Deployments,
    model_pool: {
      view: Some(pool),
      model: "",
      speculative_tokens: "2",
      tuning_draft: {},
    },
  }
  let html = render(state)
  assert_true(html.contains("已生效 3/4 台"))
  assert_true(html.contains("应用解码配置到参与节点（重启）"))
  assert_true(html.contains("关闭并恢复普通解码"))
  assert_true(html.contains("model-pool-speculative"))
  assert_true(html.contains("pool-prefix_caching"))
  assert_true(html.contains("pool-cache_aware_routing"))
  assert_true(html.contains("每步 token 预算（不是并发上限）"))
  assert_true(html.contains("仅改路由无需重启"))
  assert_true(html.contains("速度达标不代表质量通过"))
  assert_true(html.contains("显式批 token 预算请选 2048 或以上"))
  assert_false(html.contains("本轮验收通过"))
}

///|
test "old reports do not manufacture speculative decoding evidence" {
  let pool = decode_model_pool_view({
    "adopted": true,
    "active": true,
    "generation": Json(1L),
    "model": "test",
    "models": ["test"],
    "replicas": [],
    "benchmark": [],
  })
  assert_eq(pool.speculative_tokens, -1)
  assert_true(pool.baseline_benchmark is None)
}

///|
test "paired quality reports retain failures and reject missing or duplicated cases" {
  let samples : Array[ModelBenchmarkSample] = []
  for round in 1..<=2 {
    for user in 1..<=32 {
      samples.push({
        user,
        round,
        concurrency: 32,
        valid: user != 1,
        status: Some(200),
        error: Some(""),
        cached_input_tokens: None,
        input_tokens: None,
        output_tokens: 24,
        ttft_ms: 1000L,
        decode_tokens_per_second: 40.0,
        end_to_end_tokens_per_second: 32.0,
        timings: {},
      })
    }
  }
  let baseline : ModelBenchmarkView = {
    tuning: None,
    quality_samples: samples,
    status: "complete",
    phase: "done",
    prepared_users: 32,
    cleaned_users: 32,
    samples: [],
    node_counts: {},
    wall_ms: 0L,
    error: "",
    warmup_samples: [],
    speculative_tokens: 0,
    model: "test",
    artifact_digest: "digest",
    runtime_image: "image",
    profile: "profile",
    run_id: "baseline",
    node_ids: Some(["node-1", "node-2"]),
    quality_suite_digest: None,
    quality_node_counts: None,
  }
  assert_true(
    paired_quality_summary(baseline, baseline, true).contains(
      "新增失败 0，重复失败 2",
    ),
  )
  let changed = samples.copy()
  changed[1] = { ..changed[1], valid: false, }
  assert_true(
    paired_quality_summary(
      baseline,
      { ..baseline, quality_samples: changed, },
      true,
    ).contains("新增失败 1，重复失败 2"),
  )
  changed[1] = changed[0]
  assert_true(
    paired_quality_summary(
      baseline,
      { ..baseline, quality_samples: changed, },
      true,
    ).contains("缺项或重复"),
  )
  assert_true(
    paired_quality_summary(baseline, { ..baseline, quality_samples: [], }, true).contains(
      "未齐全",
    ),
  )
  assert_true(
    paired_quality_summary(baseline, baseline, false).contains("未齐全"),
  )
}

///|
fn fixed_quality_test_report() -> ModelBenchmarkView {
  let samples : Array[ModelBenchmarkSample] = []
  for round in 1..<=6 {
    for user in 1..<=32 {
      samples.push({
        user,
        round,
        concurrency: 32,
        valid: true,
        status: Some(200),
        error: Some(""),
        cached_input_tokens: Some(0),
        input_tokens: Some(3000),
        output_tokens: 24,
        ttft_ms: 1000L,
        decode_tokens_per_second: 40.0,
        end_to_end_tokens_per_second: 32.0,
        timings: {},
      })
    }
  }
  {
    tuning: Some({ ..default_model_tuning(), prefix_caching: Some(false), }),
    quality_samples: samples,
    status: "complete",
    phase: "done",
    prepared_users: 32,
    cleaned_users: 32,
    samples: [],
    node_counts: {},
    wall_ms: 0L,
    error: "",
    warmup_samples: [],
    speculative_tokens: 0,
    model: "test",
    artifact_digest: "artifact",
    runtime_image: "runtime",
    profile: "trial-32x3-512-short-quality64x3-fixed-v1",
    run_id: "test",
    node_ids: Some(["176", "177"]),
    quality_suite_digest: Some("fixed-digest"),
    quality_node_counts: Some({ "176": 96, "177": 96 }),
  }
}

///|
test "fixed quality compares per-case failure frequency and not just aggregate score" {
  let before = fixed_quality_test_report()
  assert_true(
    fixed_quality_summary(before, before, true).contains(
      "未观察到质量退步",
    ),
  )
  let earlier = before.quality_samples.copy()
  earlier[0] = {
    ..earlier[0],
    valid: false,
    error: Some("quality: mismatch total"),
  }
  let later = before.quality_samples.copy()
  later[1] = {
    ..later[1],
    valid: false,
    error: Some("quality: mismatch total"),
  }
  let comparison = fixed_quality_summary(
    { ..before, quality_samples: earlier, },
    { ..before, quality_samples: later, speculative_tokens: 1, },
    true,
  )
  assert_true(
    comparison.contains("失败次数增加 1/64 题，减少 1/64 题"),
  )
  assert_false(comparison.contains("未观察到质量退步"))
  // The same case failing in a different repetition is not a new regression.
  later[1] = before.quality_samples[1]
  later[64] = {
    ..later[64],
    valid: false,
    error: Some("quality: mismatch total"),
  }
  assert_true(
    fixed_quality_summary(
      { ..before, quality_samples: earlier, },
      { ..before, quality_samples: later, },
      true,
    ).contains("失败次数增加 0/64 题"),
  )
}

///|
test "fixed quality refuses mismatched input conditions partial coverage and malformed evidence" {
  let before = fixed_quality_test_report()
  for
    changed in [
      { ..before, quality_suite_digest: Some("other"), },
      { ..before, quality_suite_digest: None, },
      { ..before, tuning: Some(default_model_tuning()), },
    ] {
    assert_true(
      fixed_quality_summary(before, changed, true).contains("条件不一致"),
    )
  }
  assert_true(
    fixed_quality_summary(before, before, false).contains("条件不一致"),
  )
  for
    changed in [
      { ..before, quality_node_counts: Some({ "176": 192 }), },
      { ..before, quality_node_counts: Some({ "176": 96, "177": 95 }), },
      {
        ..before,
        quality_node_counts: Some({ "176": 95, "177": 96, "178": 1 }),
      },
      { ..before, quality_samples: [], },
    ] {
    assert_true(
      fixed_quality_summary(before, changed, true).contains("未齐全"),
    )
  }
  let duplicated = before.quality_samples.copy()
  duplicated[1] = duplicated[0]
  assert_true(
    fixed_quality_summary(
      before,
      { ..before, quality_samples: duplicated, },
      true,
    ).contains("缺项或重复"),
  )
  let transport = before.quality_samples.copy()
  transport[0] = { ..transport[0], valid: false, status: Some(503), }
  assert_true(
    fixed_quality_summary(
      before,
      { ..before, quality_samples: transport, },
      true,
    ).contains("传输失败"),
  )
}
