///|
fn benchmark_test_fixture(path : String) -> ModelBenchmark {
  {
    config: { origin: "https://portal.example.invalid", state_path: path, },
    report: {
      namespace: "loadtest-fixture",
      status: "running",
      phase: "准备测速",
      run_id: "benchmark-fixture",
      model: "test",
      prepared_users: 0,
      cleaned_users: 0,
      samples: [],
      node_counts: {},
      wall_ms: 0L,
      error: "",
      warmup_samples: [],
      speculative_tokens: 0,
      pool_generation: 1L,
      artifact_digest: "fixture",
      runtime_image: "fixture",
      profile: "trial-32x3-512-warm32-v1",
      tuning: None,
      quality_samples: [],
      node_ids: None,
      quality_suite_digest: None,
      quality_node_counts: None,
    },
    timings: Map([]),
    baseline: None,
  }
}

///|
test "old benchmark reports migrate without manufacturing latency evidence" {
  let old = Json(benchmark_test_fixture("/unused").report)
  guard old is Object(fields) else { fail("expected report") }
  fields.remove("warmup_samples")
  fields.remove("speculative_tokens")
  fields.remove("profile")
  fields.remove("quality_suite_digest")
  fields.remove("quality_node_counts")
  fields["samples"] = [
    {
      "user": 1,
      "concurrency": 1,
      "round": 1,
      "status": 200,
      "output_tokens": 512,
      "ttft_ms": "17000",
      "elapsed_ms": "24000",
      "decode_tokens_per_second": 75,
      "end_to_end_tokens_per_second": 21,
      "valid": true,
      "response_id": "test",
      "receipt": "workload:test:hash",
      "error": "",
    },
  ]
  let upgraded : ModelBenchmarkReport = @json.from_json(
    upgrade_benchmark_report(old),
  )
  assert_true(upgraded.warmup_samples.is_empty())
  assert_eq(upgraded.speculative_tokens, -1)
  assert_eq(upgraded.profile, "")
  assert_eq(upgraded.quality_suite_digest, None)
  assert_eq(upgraded.quality_node_counts, None)
  assert_true(upgraded.samples[0].timings.is_empty())
  let restored : ModelBenchmarkReport = @json.from_json(Json(upgraded))
  assert_eq(restored.samples[0].ttft_ms, 17000L)
}

///|
test "fixed quality digest is repeatable and includes model identity" {
  assert_eq(fixed_quality_digest("test"), fixed_quality_digest("test"))
  assert_eq(fixed_quality_digest("test").length(), 64)
  assert_false(fixed_quality_digest("test") == fixed_quality_digest("other"))
}

///|
test "benchmark registration ownership is exact and active only" {
  let benchmark = benchmark_test_fixture("/unused")
  assert_true(benchmark.owns_registration(benchmark.email(1)))
  assert_true(benchmark.owns_registration(benchmark.email(32)))
  for
    email in [
      benchmark.email(0),
      benchmark.email(33),
      "other@trial.example.invalid",
      "loadtest-fixture-1@example.com",
    ] {
    assert_false(benchmark.owns_registration(email))
  }
  benchmark.report = { ..benchmark.report, status: "complete", }
  assert_false(benchmark.owns_registration(benchmark.email(1)))
}

///|
async test "benchmark failures give a stage without leaking arbitrary exception content" {
  let timeout_message = try {
    @async.with_timeout(1, () => @async.sleep(100))
    "unexpected completion"
  } catch {
    error => benchmark_error_message(error, "注册测试账号 1/32")
  }
  assert_eq(
    timeout_message, "注册测试账号 1/32：平台入口请求超时，请检查控制器到平台 HTTPS 入口的连接",
  )
  assert_false(
    benchmark_error_message(Failure("secret-not-for-display"), "准备测速").contains(
      "secret-not-for-display",
    ),
  )
  let reply = api_error(409, "EventTrialUnavailable", "private detail", false)
  assert_eq(
    benchmark_enrollment_error(reply),
    "已有试用尚未结束，或测速活动不在有效期内 HTTP 409",
  )
}

///|
async test "benchmark registration defers legacy trial without changing ordinary registration" {
  let path = @fs.tmpdir(prefix="benchmark-registration-")
  defer @fs.rmdir(path, recursive=true)
  let accounts = @account.AccountStore::open(
    path + "/accounts.json",
    "benchmark-test-secret-more-than-thirty-two-bytes",
  )
  let portal = @portal_store.FilePortalStore::open(path + "/portal.json")
  let workspace = @directory.FileWorkspaceDirectory::open(
    path + "/workspace.json",
  )
  let durable = @store.FileStore::open(path + "/control.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses",
    "",
    "test",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
  )
  let base = ApiService::new(
      durable, runtime, "operator", "inference", "node", "test",
    )
    .with_account_store(
      accounts, "benchmark-assertion-secret-more-than-thirty-two-bytes",
    )
    .with_portal_store(portal)
    .with_workspace_directory(workspace, true)
  let benchmark = benchmark_test_fixture(path + "/benchmark.json")
  let service = { ..base, model_benchmark: Some(benchmark), }
  let now = @async.now()
  for
    (id, email, dedicated) in [
      ("benchmark-user", benchmark.email(1), true),
      ("ordinary-user", "ordinary@example.invalid", false),
    ] {
    let account = accounts.create({
      version: @account.contract_version,
      account_id: "account-" + id,
      subject_ref: "subject-" + id,
      identity_issuer: "https://identity.example.invalid",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example.invalid", id,
      ),
      display_name: id,
      email,
      identity_receipt: "identity-proof:" + id,
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    })
    let trial = service.ensure_registration_trial(
      account,
      now,
      3600000L,
      100L,
      ["test"],
    )
    if dedicated {
      assert_true(trial is None)
      assert_true(accounts.trial_for_account(account.account_id) is None)
    } else {
      assert_true(trial is Some(_))
    }
  }
  assert_eq(accounts.snapshot().event_mode_selected, Some(false))
}
