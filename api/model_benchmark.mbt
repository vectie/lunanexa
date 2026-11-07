///|
struct ModelBenchmarkConfig {
  origin : String
  state_path : String
} derive(FromJson)

///|
pub extend ModelBenchmarkConfig with @json.FromJson::{from_json}

///|
struct ModelBenchmarkReport {
  run_namespace : String
  status : String
  phase : String
  run_id : String
  model : String
  prepared_users : Int32
  cleaned_users : Int32
  samples : Array[@benchmark.Sample]
  node_counts : Map[String, Int32]
  wall_ms : Int64
  error : String
  warmup_samples : Array[@benchmark.Sample]
  speculative_tokens : Int32
  pool_generation : Int64
  artifact_digest : String
  runtime_image : String
  profile : String
  tuning : @model_pool.Tuning?
  quality_samples : Array[@benchmark.Sample]
  node_ids : Array[String]?
  quality_suite_digest : String?
  quality_node_counts : Map[String, Int32]?
} derive (
  ToJson(fields(run_namespace(rename="namespace"))),
  FromJson(fields(run_namespace(rename="namespace"))),
)

///|
pub extend ModelBenchmarkReport with ToJson::{to_json}

///|
pub extend ModelBenchmarkReport with @json.FromJson::{from_json}

///|
struct ModelBenchmark {
  config : ModelBenchmarkConfig
  mut report : ModelBenchmarkReport
  timings : Map[String, Map[String, Int64]]
  mut baseline : ModelBenchmarkReport?
}

///|
priv suberror ModelBenchmarkError {
  ModelBenchmarkError(String)
}

///|
fn ModelBenchmark::owns_registration(
  self : ModelBenchmark,
  email : String,
) -> Bool {
  if self.report.status != "running" {
    return false
  }
  for number in 1..<=32 {
    if email == self.email(number) {
      return true
    }
  }
  false
}

///|
fn benchmark_error_message(error : Error, phase : String) -> String {
  let detail = match error {
    ModelBenchmarkError(message) => message
    @async.TimeoutError =>
      "平台入口请求超时，请检查控制器到平台 HTTPS 入口的连接"
    @socket.ResolveHostnameError(_) =>
      "平台域名解析失败，请检查控制器 DNS"
    _ => "操作未完成，请检查平台连接及账号服务后重试"
  }
  phase + "：" + detail
}

///|
fn benchmark_enrollment_error(reply : HttpReply) -> String {
  let body = @json.parse(reply.body) catch { _ => Json::null() }
  let reason = match body {
    { "error": { "code": "EventTrialUnavailable", .. }, .. } =>
      "已有试用尚未结束，或测速活动不在有效期内"
    { "error": { "code": "EventScopeDenied", .. }, .. } =>
      "账号已有企业或运维权限，不能用作专用测速账号"
    { "error": { "code": "EventCapacityNotReady", .. }, .. } =>
      "选中节点的模型就绪状态发生变化，请刷新后重试"
    _ => "活动授权失败"
  }
  reason + " HTTP \{reply.status}"
}

///|
async fn ModelBenchmark::save(self : ModelBenchmark) -> Unit {
  let path = self.config.state_path
  @fs.write_file(path + ".tmp", Json(self.report).stringify(), permission=0o600)
  @fs.rename(path + ".tmp", path)
}

///|
pub async fn ApiService::with_model_benchmark_json(
  self : ApiService,
  raw : String?,
) -> ApiService {
  guard raw is Some(raw) else { return self }
  let config : ModelBenchmarkConfig = @json.from_json(@json.parse(raw))
  guard config.origin.has_prefix("https://") &&
    !config.origin[8:].contains("/") &&
    config.state_path.has_prefix("/") &&
    self.model_pool is Some(_) &&
    self.identity_assertion_secret.length() >= 32 else {
    fail("benchmark requires a HTTPS portal origin and configured model pool")
  }
  let report : ModelBenchmarkReport = if @fs.exists(config.state_path) {
    let saved : ModelBenchmarkReport = @json.from_json(
      upgrade_benchmark_report(
        @json.parse(@fs.read_file(config.state_path).text()),
      ),
    )
    if saved.status == "queued" || saved.status == "running" {
      {
        ..saved,
        status: "interrupted",
        phase: "进程重启，正在回收测试权限",
      }
    } else {
      saved
    }
  } else {
    {
      run_namespace: "loadtest-\{@async.now()}",
      status: "idle",
      phase: "尚未测试",
      run_id: "",
      model: "",
      prepared_users: 0,
      cleaned_users: 0,
      samples: [],
      node_counts: {},
      wall_ms: 0L,
      error: "",
      warmup_samples: [],
      speculative_tokens: -1,
      pool_generation: 0L,
      artifact_digest: "",
      runtime_image: "",
      profile: "",
      tuning: None,
      quality_samples: [],
      node_ids: None,
      quality_suite_digest: None,
      quality_node_counts: None,
    }
  }
  let baseline : ModelBenchmarkReport? = if @fs.exists(
      config.state_path + ".baseline",
    ) {
    Some(
      @json.from_json(
        upgrade_benchmark_report(
          @json.parse(@fs.read_file(config.state_path + ".baseline").text()),
        ),
      ),
    )
  } else {
    None
  }
  {
    ..self,
    model_benchmark: Some({ config, report, timings: Map([]), baseline, }),
  }
}

///|
fn upgrade_benchmark_report(value : Json) -> Json {
  if value is Object(fields) {
    for
      (name, default_value) in [
        ("speculative_tokens", Json(-1)),
        ("pool_generation", Json(0L)),
        ("artifact_digest", Json("")),
        ("runtime_image", Json("")),
        ("profile", Json("")),
        ("quality_samples", Json::array([])),
      ] {
      if !fields.contains(name) {
        fields[name] = default_value
      }
    }
    if !fields.contains("warmup_samples") {
      fields["warmup_samples"] = Json::array([])
    }
    if fields.get("samples") is Some(Array(samples)) {
      for sample in samples {
        if sample is Object(item) && !item.contains("timings") {
          item["timings"] = Json::empty_object()
        }
      }
    }
  }
  value
}

///|
fn ApiService::record_benchmark_timing(
  self : ApiService,
  workload_id : String,
  timings : Map[String, Int64],
) -> Unit {
  if self.model_benchmark is Some(benchmark) &&
    benchmark.report.status == "running" {
    benchmark.timings[workload_id] = timings
  }
}

///|
fn ModelBenchmark::attach_timings(
  self : ModelBenchmark,
  sample : @benchmark.Sample,
) -> Unit {
  if sample.receipt.split(":").to_array() is ["workload", workload_id, _] &&
    self.timings.get(workload_id.to_owned()) is Some(timings) {
    for name, elapsed in timings {
      sample.timings[name] = elapsed
    }
    self.timings.remove(workload_id.to_owned())
  }
}

///|
fn ModelBenchmark::email(self : ModelBenchmark, number : Int32) -> String {
  self.report.run_namespace + "-\{number}@trial.example.invalid"
}

///|
async fn benchmark_json(
  origin : String,
  path : String,
  body : Json?,
  token~ : String = "",
  cookie~ : String = "",
) -> (Int32, Json, String) {
  @async.with_timeout(45000) <| () => {
    let client = @http.Client(origin)
    defer client.close()
    let headers : @http.Headers = {
      "Content-Type": "application/json",
      "Origin": origin,
      "Sec-Fetch-Site": "same-origin",
    }
    if token != "" {
      headers["Authorization"] = "Bearer " + token
    }
    if cookie != "" {
      headers["Cookie"] = cookie
    }
    let response = match body {
      Some(value) => client.post(path, value.stringify(), extra_headers=headers)
      None => client.get(path, extra_headers=headers)
    }
    let data = client.read_all().text()
    let parsed = @json.parse(data) catch { _ => Json::null() }
    let cookies = response.cookies.map(c => c.name + "=" + c.value).join("; ")
    (response.code, parsed, if cookies == "" { cookie } else { cookies })
  }
}

///|
async fn ApiService::cleanup_benchmark_users(
  self : ApiService,
  benchmark : ModelBenchmark,
) -> Unit {
  guard self.account_store is Some(accounts) &&
    self.workspace_directory is Some(directory) &&
    self.portal_store is Some(portal) &&
    self.access_store is Some(access) else {
    fail("test authorities unavailable")
  }
  let views = accounts.views()
  let mut cleaned = 0
  for number in 1..<=32 {
    if views.iter().find_first(a => a.email == benchmark.email(number))
      is Some(account) {
      guard account.roles == [EnterpriseUser] else {
        fail("test account scope changed")
      }
      if accounts.trial_for_account(account.account_id) is Some(trial) {
        if trial.api_key_id is Some(key) {
          ignore(access.revoke(key, @async.now()))
        }
        ignore(
          accounts.revoke_trial_for_account(account.account_id, @async.now()),
        )
        let fingerprint = trial.trial_id["trial-".length():].to_owned()
        let workspace = directory.snapshot(@async.now())
        if workspace.access_grants.any(g => {
            g.grant_id == "trial-grant-" + fingerprint && g.state == GrantActive
          }) {
          ignore(
            directory.revoke_access_grant(
              "trial-grant-" + fingerprint,
              @async.now(),
            ),
          )
        }
        if workspace.leases.any(l => {
            l.lease_id == "trial-lease-" + fingerprint && l.state == Active
          }) {
          ignore(
            directory.revoke_lease("trial-lease-" + fingerprint, @async.now()),
          )
        }
      }
      for membership in portal.snapshot().memberships {
        if membership.subject_ref == account.subject_ref &&
          membership.active &&
          membership.membership_id.has_prefix("trial-membership-") {
          ignore(portal.revoke_membership(membership.membership_id))
        }
      }
      if account.state == Active {
        ignore(accounts.set_state(account.account_id, Suspended, @async.now()))
      }
      cleaned += 1
    }
  }
  benchmark.report = { ..benchmark.report, cleaned_users: cleaned, }
}

///|
async fn ApiService::prepare_benchmark_users(
  self : ApiService,
  benchmark : ModelBenchmark,
  policy : @event_trial.Policy,
) -> Array[String] {
  guard self.account_store is Some(accounts) else {
    fail("accounts unavailable")
  }
  let keys : Array[String] = []
  benchmark.report = { ..benchmark.report, cleaned_users: 0, }
  for number in 1..<=32 {
    let email = benchmark.email(number)
    benchmark.report = {
      ..benchmark.report,
      phase: "注册或登录测试账号 \{number}/32",
    }
    benchmark.save()
    let password = "Load!" +
      @crypto.bytes_to_hex_string(
        @crypto.hmac(
          @crypto.SHA256::new(),
          @utf8.encode(self.identity_assertion_secret),
          @utf8.encode("model-benchmark-password/v1:" + email),
        ),
      )
    let existing = accounts.views().iter().find_first(a => a.email == email)
    if existing is Some(account) {
      guard account.roles == [EnterpriseUser] &&
        (account.state == Suspended || account.state == Active) else {
        fail("test account unavailable")
      }
      if account.state == Suspended {
        ignore(accounts.set_state(account.account_id, Active, @async.now()))
      }
    }
    let (status, session, cookie) = if existing is None {
      benchmark_json(
        benchmark.config.origin,
        "/user/auth/register",
        Some({
          "email": email,
          "display_name": "模型验收测试 \{number}",
          "password": password,
          "audience": "enterprise",
        }),
      )
    } else {
      benchmark_json(
        benchmark.config.origin,
        "/user/auth/password",
        Some({
          "username": email,
          "password": password,
          "audience": "enterprise",
        }),
      )
    }
    guard (status == 200 || status == 201) &&
      session is { "session_token": String(token), .. } &&
      cookie != "" else {
      raise ModelBenchmarkError("注册或登录失败 HTTP \{status}")
    }
    let (self_status, account_json, cookie) = benchmark_json(
      benchmark.config.origin,
      "/user/v1/auth/self",
      None,
      token~,
      cookie~,
    )
    guard self_status == 200 &&
      account_json is { "account_id": String(account_id), .. } else {
      raise ModelBenchmarkError(
        "测试账号身份校验失败 HTTP \{self_status}",
      )
    }
    benchmark.report = {
      ..benchmark.report,
      phase: "授权测试账号 \{number}/32",
    }
    benchmark.save()
    let enrolled = self.enroll_event_participant(
      "model-benchmark",
      policy.event_id,
      ({ "account_id": account_id } : Json).stringify(),
      @async.now(),
    )
    guard enrolled.status == 201 &&
      @json.parse(enrolled.body) is { "project_id": String(project), .. } else {
      raise ModelBenchmarkError(benchmark_enrollment_error(enrolled))
    }
    benchmark.report = {
      ..benchmark.report,
      phase: "签发测试密钥 \{number}/32",
    }
    benchmark.save()
    let (key_status, key, _) = benchmark_json(
      benchmark.config.origin,
      "/user/v1/portal/self/api-keys",
      Some({
        "key_id": benchmark.report.run_id + "-\{number}",
        "project_id": project,
        "display_name": "模型性能验收 \{number}",
        "scopes": ["ModelList", "Inference"],
        "allowed_models": Json(policy.allowed_models),
        "expires_unix_ms": Json(policy.expires_unix_ms),
        "maximum_requests": Json(policy.maximum_requests),
      }),
      token~,
      cookie~,
    )
    guard key_status == 201 && key is { "secret": String(secret), .. } else {
      raise ModelBenchmarkError(
        "自助 API 密钥签发失败 HTTP \{key_status}",
      )
    }
    keys.push(secret)
    benchmark.report = {
      ..benchmark.report,
      prepared_users: number,
      phase: "准备真实测试账号 \{number}/32",
    }
    benchmark.save()
  }
  keys
}

///|
async fn ApiService::execute_model_benchmark(
  self : ApiService,
  benchmark : ModelBenchmark,
) -> Unit {
  guard self.account_store is Some(accounts) &&
    self.model_pool is Some(pool) &&
    pool.active() else {
    fail("active model pool required")
  }
  let now = @async.now()
  let policy : @event_trial.Policy = {
    event_id: benchmark.report.run_id,
    title: "选定节点模型 UI 封闭测速",
    starts_unix_ms: now - 1L,
    expires_unix_ms: now + 3600000L,
    maximum_users: 32,
    maximum_requests: 100L,
    max_input_bytes: Some(32768),
    max_output_tokens: None,
    allowed_models: [benchmark.report.model],
    node_ids: pool.selected_targets().map(t => t.node_id),
    per_node_concurrency: 0,
    registration_open: false,
  }
  guard accounts.snapshot().events.unwrap_or([]).all(e => !e.registration_open) else {
    raise ModelBenchmarkError("测速前请关闭公开活动报名")
  }
  guard self.event_trial_ready_nodes(policy, now).length() ==
    pool.selected_targets().length() else {
    raise ModelBenchmarkError("选中节点的新模型尚未全部就绪")
  }
  self.verify_benchmark_configuration(benchmark.report)
  self.cleanup_benchmark_users(benchmark)
  benchmark.report = { ..benchmark.report, phase: "创建封闭测速活动", }
  benchmark.save()
  ignore(accounts.put_event(policy))
  let keys = self.prepare_benchmark_users(benchmark, policy)
  let fixed_quality = benchmark.report.quality_suite_digest is Some(_)
  let quality_rounds = if fixed_quality { 6 } else { 2 }
  benchmark.report = {
    ..benchmark.report,
    phase: "32 人质量回归：长前缀、事实更新与 JSON（两轮）",
  }
  benchmark.save()
  for round in 1..<=quality_rounds {
    self.verify_benchmark_configuration(benchmark.report)
    benchmark.report = {
      ..benchmark.report,
      phase: if fixed_quality {
        "固定题集 · 第 \{(round + 1) / 2}/3 次 · 题组 \{(round - 1) % 2 + 1}/2 · 32 人并发"
      } else {
        "32 人质量回归 · 第 \{round}/2 轮"
      },
    }
    benchmark.save()
    let barrier = @async.now() + 250L
    @async.with_task_group <| group => {
      for user in 1..<=32 {
        group.spawn_bg() <| () => {
          let delay = barrier - @async.now()
          if delay > 0L {
            @async.sleep(delay.to_int())
          }
          let sample = @benchmark.sample(
            benchmark.config.origin,
            keys[user - 1],
            benchmark.report.model,
            user~,
            concurrency=32,
            round~,
            nonce=benchmark.report.run_id + "-quality",
            max_tokens=128,
            quality=true,
            profile=if fixed_quality { "fixed" } else { "short" },
          )
          benchmark.attach_timings(sample)
          benchmark.report.quality_samples.push(sample)
          if benchmark.report.quality_node_counts is Some(counts) &&
            sample.receipt.split(":").to_array() is ["workload", workload_id, _] &&
            self.store.workload_result(workload_id.to_owned()) is Some(response) &&
            response.execution_node_id is Some(node) {
            counts[node] = counts.get(node).unwrap_or(0) + 1
          }
        }
      }
    }
    benchmark.save()
  }
  guard benchmark.report.quality_samples.length() == quality_rounds * 32 &&
    benchmark.report.quality_samples.all(s => {
      s.valid || (s.status == 200 && s.error.has_prefix("quality:"))
    }) else {
    raise ModelBenchmarkError(
      "质量回归请求未完整完成：停止测速，请检查传输与服务状态",
    )
  }
  if fixed_quality {
    let counts = benchmark.report.quality_node_counts.unwrap()
    guard pool
      .selected_targets()
      .all(t => counts.get(t.node_id).unwrap_or(0) > 0) &&
      counts.values().fold(init=0, (a, n) => a + n) == 192 else {
      raise ModelBenchmarkError(
        "固定题集未完整覆盖选中节点，不能判定质量",
      )
    }
  }
  // Semantic failures remain failures in the evidence and UI. Timing still
  // runs so an imperfect baseline can be compared without hiding errors or
  // declaring quality acceptance merely from a fast response.
  let profile = if benchmark.report.profile.contains("repeat") {
    "repeat"
  } else if benchmark.report.profile.contains("cold") {
    "cold"
  } else {
    "short"
  }
  // Exercise every replica before opening a user-facing event. Keep the cold
  // cost visible, separately from the measured single/32-user rounds.
  benchmark.report = {
    ..benchmark.report,
    phase: "选中节点预热（32 路，结果单列）",
  }
  benchmark.save()
  let warmup_barrier = @async.now() + 250L
  @async.with_task_group <| group => {
    for user in 1..<=32 {
      group.spawn_bg() <| () => {
        let delay = warmup_barrier - @async.now()
        if delay > 0L {
          @async.sleep(delay.to_int())
        }
        let sample = @benchmark.sample(
          benchmark.config.origin,
          keys[user - 1],
          benchmark.report.model,
          user~,
          concurrency=32,
          round=0,
          nonce=benchmark.report.run_id,
          max_tokens=32,
          profile~,
        )
        benchmark.attach_timings(sample)
        benchmark.report.warmup_samples.push(sample)
      }
    }
  }
  benchmark.save()
  guard benchmark.report.warmup_samples.all(s => s.valid) else {
    raise ModelBenchmarkError(
      "选中节点预热未全部完成，请检查详情后重试",
    )
  }
  let warmed : Map[String, Bool] = Map([])
  for sample in benchmark.report.warmup_samples {
    if sample.receipt.split(":").to_array() is ["workload", workload_id, _] &&
      self.store.workload_result(workload_id.to_owned()) is Some(response) &&
      response.execution_node_id is Some(node) {
      warmed[node] = true
    }
  }
  guard pool.selected_targets().all(t => warmed.contains(t.node_id)) else {
    raise ModelBenchmarkError(
      "预热未覆盖全部选中节点，未开始正式测速",
    )
  }
  for concurrency in [1, 32] {
    for round in 1..<=3 {
      self.verify_benchmark_configuration(benchmark.report)
      benchmark.report = {
        ..benchmark.report,
        phase: "\{concurrency} 人并发 · 第 \{round}/3 轮",
      }
      benchmark.save()
      let barrier = @async.now() + 250L
      let began = barrier
      @async.with_task_group <| group => {
        for user in 1..<=concurrency {
          group.spawn_bg() <| () => {
            let delay = barrier - @async.now()
            if delay > 0L {
              @async.sleep(delay.to_int())
            }
            let sample = @benchmark.sample(
              benchmark.config.origin,
              keys[user - 1],
              benchmark.report.model,
              user~,
              concurrency~,
              round~,
              nonce=benchmark.report.run_id,
              profile~,
            )
            benchmark.attach_timings(sample)
            benchmark.report.samples.push(sample)
          }
        }
      }
      if concurrency == 32 {
        benchmark.report = {
          ..benchmark.report,
          wall_ms: benchmark.report.wall_ms + @async.now() - began,
        }
      }
      for sample in benchmark.report.samples {
        if sample.concurrency == 32 &&
          sample.round == round &&
          concurrency == 32 &&
          sample.valid {
          if sample.receipt.split(":").to_array()
            is ["workload", workload_id, _] &&
            self.store.workload_result(workload_id.to_owned()) is Some(response) &&
            response.execution_node_id is Some(node) {
            benchmark.report.node_counts[node] = benchmark.report.node_counts
              .get(node)
              .unwrap_or(0) +
              1
          }
        }
      }
      benchmark.save()
    }
  }
  self.verify_benchmark_configuration(benchmark.report)
}

///|
pub async fn ApiService::run_model_benchmark_forever(self : ApiService) -> Unit {
  guard self.model_benchmark is Some(benchmark) else { return }
  for ;; {
    if benchmark.report.status == "queued" ||
      benchmark.report.status == "interrupted" {
      let interrupted = benchmark.report.status == "interrupted"
      benchmark.report = {
        ..benchmark.report,
        status: "running",
        phase: "准备测速",
      }
      benchmark.save()
      let error = if interrupted {
        "进程重启，本次测试中断；未自动重新施加负载"
      } else {
        try {
          self.execute_model_benchmark(benchmark)
          ""
        } catch {
          error => benchmark_error_message(error, benchmark.report.phase)
        }
      }
      let cleanup_error = try {
        self.cleanup_benchmark_users(benchmark)
        ""
      } catch {
        _ =>
          "测试权限回收未完成；授权最长 1 小时，请重试回收"
      }
      benchmark.report = {
        ..benchmark.report,
        status: if error == "" && cleanup_error == "" {
          "complete"
        } else {
          "failed"
        },
        phase: if cleanup_error == "" {
          "测试权限已回收"
        } else {
          "需要回收测试权限"
        },
        error: error +
        (if cleanup_error == "" { "" } else { "；" + cleanup_error }),
      }
      benchmark.save()
    }
    @async.sleep(1000)
  }
}

///|
async fn ApiService::start_model_benchmark(
  self : ApiService,
  profile~ : String = "short",
) -> Unit {
  guard ["short", "cold", "repeat", "fixed"].contains(profile) else {
    fail("未知测速场景")
  }
  guard self.model_benchmark is Some(benchmark) &&
    self.model_pool is Some(pool) &&
    pool.active() &&
    pool.selection() is Some(selection) else {
    fail("测速未配置，或新模型路由尚未启用")
  }
  guard benchmark.report.status != "running" &&
    benchmark.report.status != "queued" else {
    fail("已有测速运行中")
  }
  for target in pool.selected_targets() {
    guard pool.configuration(target.node_id).ready else {
      fail("选中节点解码配置尚未一致就绪，请刷新后重试")
    }
  }
  if profile == "fixed" && pool.tuning().prefix_caching != Some(false) {
    fail(
      "固定题集对照需要先在 UI 关闭前缀缓存；基础 KV Cache 不受影响",
    )
  }
  if benchmark.report.status == "complete" {
    @fs.write_file(
      benchmark.config.state_path + "." + benchmark.report.run_id + ".json",
      Json(benchmark.report).stringify(),
      permission=0o600,
    )
    benchmark.baseline = Some(benchmark.report)
    @fs.write_file(
      benchmark.config.state_path + ".baseline.tmp",
      Json(benchmark.report).stringify(),
      permission=0o600,
    )
    @fs.rename(
      benchmark.config.state_path + ".baseline.tmp",
      benchmark.config.state_path + ".baseline",
      replace=true,
    )
  }
  benchmark.report = {
    run_namespace: benchmark.report.run_namespace,
    status: "queued",
    phase: "等待开始",
    run_id: "benchmark-\{@async.now()}",
    model: selection.model_alias,
    prepared_users: 0,
    cleaned_users: 0,
    samples: [],
    node_counts: {},
    wall_ms: 0L,
    error: "",
    warmup_samples: [],
    speculative_tokens: pool.speculative_tokens(),
    pool_generation: pool.generation(),
    artifact_digest: selection.artifact.digest,
    runtime_image: pool.runtime_image(),
    profile: if profile == "fixed" {
      "trial-32x3-512-short-quality64x3-fixed-v1"
    } else {
      "trial-32x3-512-" + profile + "-quality64-v2"
    },
    tuning: Some(pool.tuning()),
    quality_samples: [],
    node_ids: Some(pool.selected_targets().map(t => t.node_id)),
    quality_suite_digest: if profile == "fixed" {
      Some(fixed_quality_digest(selection.model_alias))
    } else {
      None
    },
    quality_node_counts: if profile == "fixed" {
      Some(Map([]))
    } else {
      None
    },
  }
  benchmark.timings.clear()
  benchmark.save()
}

///|
fn fixed_quality_digest(model : String) -> String {
  let cases : Array[Json] = []
  for round in 1..<=2 {
    for user in 1..<=32 {
      let (payload, expected) = @benchmark.request_fixture(
        model, user, round, "", 128, "fixed", true,
      )
      cases.push({ "request": payload, "expected": Json(expected) })
    }
  }
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(Json(cases).stringify())),
  )
}

///|
async fn ApiService::verify_benchmark_configuration(
  self : ApiService,
  report : ModelBenchmarkReport,
) -> Unit {
  guard self.model_pool is Some(pool) &&
    pool.generation() == report.pool_generation &&
    pool.speculative_tokens() == report.speculative_tokens else {
    raise ModelBenchmarkError(
      "测速期间模型池配置发生变化，结果不作为验收",
    )
  }
  for target in pool.selected_targets() {
    guard pool.configuration(target.node_id).ready else {
      raise ModelBenchmarkError(
        "选中节点解码配置尚未全部生效，结果不作为验收",
      )
    }
  }
}
