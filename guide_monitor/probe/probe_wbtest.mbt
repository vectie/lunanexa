///|
fn test_policy() -> @guide_monitor.GuideMonitorPolicy {
  {
    target_ref: "coursebook-primary",
    probe_interval_ms: 10000L,
    observation_max_age_ms: 120000L,
    future_skew_ms: 5000L,
    knowledge_max_age_ms: 604800000L,
  }
}

///|
fn test_config(origin : String) -> GuideProbeConfig {
  {
    origin,
    allow_https: false,
    actor_ref: "oidc:guide-monitor",
    role: "operator",
    maximum_response_bytes: 1024,
    request_timeout_ms: 1000,
  }
}

///|
let identity_test_secret : String = "guide-identity-test-secret-at-least-32-bytes"

///|
let observation_test_secret : String = "guide-observation-test-secret-at-least-32-bytes"

///|
async fn send_json(
  connection : @http.ServerConnection,
  status : Int,
  reason : String,
  body : String,
) -> Unit {
  connection.send_response(status, reason, extra_headers={
    "Content-Type": "application/json",
  })
  connection.write_string(body)
  connection.end_response()
}

///|
priv enum ResponseMode {
  Healthy
  Redirect
  Oversize
  Malformed
  Stale
  Forged
  KnowledgeStale
  PrivateFields
} derive(Eq)

///|
fn diagnostics_body(mode : ResponseMode, correlation : String) -> String {
  let receipt = if mode == Forged { "forged-receipt" } else { correlation }
  let generated = if mode == Stale { 99999L } else { 100000L }
  let private_fields = if mode == PrivateFields {
    ",\"raw_logs\":\"private-body-secret\",\"prompt\":\"private-body-secret\""
  } else {
    ""
  }
  let knowledge_age = if mode == KnowledgeStale { 700000000L } else { 1000L }
  let knowledge_stale = mode == KnowledgeStale
  "{\"ok\":true,\"category\":\"overview\",\"correlation_receipt\":\"\{receipt}\",\"diagnostics\":{\"contract_version\":\"lunanexa.guide-diagnostics.v1\",\"generated_unix_ms\":\{generated},\"knowledge\":{\"revision\":\"revision-2026-08-12\",\"age_ms\":\{knowledge_age},\"stale\":\{knowledge_stale}}\{private_fields}}}"
}

///|
async fn exercise_response(
  mode : ResponseMode,
) -> (GuideProbeRunResult, Bool, String) {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let identity_verified = [false]
  let observed_diagnostics_path = [""]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(allow_failure=true) <| ((request, _, connection) => {
        if request.path == "/health" {
          match mode {
            Redirect => {
              connection.send_response(302, "Found", extra_headers={
                "Location": "http://127.0.0.1:1/private",
                "Content-Type": "application/json",
              })
              connection.write_string("{\"secret\":\"private-body-secret\"}")
              connection.end_response()
            }
            Oversize => {
              connection.send_response(200, "OK", extra_headers={
                "Content-Type": "application/json",
              })
              connection.write_string("{\"private\":\"")
              for _ in 0..<2048 {
                connection.write_string("x")
              }
              connection.write_string("private-body-secret\"}")
              connection.end_response()
            }
            Malformed =>
              send_json(connection, 200, "OK", "{malformed private-body-secret")
            _ =>
              send_json(
                connection, 200, "OK", "{\"ok\":true,\"dependencies\":{\"coursebook\":{\"ok\":true},\"admin_diagnostics\":{\"ok\":true,\"enabled\":true}},\"raw_logs\":\"private-body-secret\"}",
              )
          }
        } else if request.path ==
          "/api/coursebook/admin/diagnostics?category=overview" {
          observed_diagnostics_path[0] = request.path
          let actor = header_value(request.headers, "x-lunanexa-actor").unwrap_or(
            "",
          )
          let role = header_value(request.headers, "x-lunanexa-role").unwrap_or(
            "",
          )
          let timestamp = header_value(
            request.headers,
            "x-lunanexa-auth-timestamp",
          ).unwrap_or("")
          let signature = header_value(
            request.headers,
            "x-lunanexa-auth-signature",
          ).unwrap_or("")
          let correlation = header_value(
            request.headers,
            "x-lunanexa-correlation-id",
          ).unwrap_or("")
          identity_verified[0] = actor == "oidc:guide-monitor" &&
            role == "operator" &&
            timestamp == "100000" &&
            signature ==
            identity_signature(
              "/api/coursebook/admin/diagnostics", actor, role, 100000L, identity_test_secret,
            ) &&
            correlation == "guide-probe-1-100000"
          send_json(connection, 200, "OK", diagnostics_body(mode, correlation))
        } else {
          send_json(connection, 404, "Not Found", "{\"ok\":false}")
        }
      })
    }
    let directory = @fs.tmpdir(prefix="lunanexa-guide-probe-http-")
    let notifications = @store.NotificationStore::open(
      "\{directory}/notifications.json",
    )
    let worker = GuideProbeWorker::open(
      test_config("http://\{server.addr}"),
      test_policy(),
      "\{directory}/scheduler.json",
      notifications,
      identity_test_secret,
      observation_test_secret,
    )
    let result = worker.run_once(100000L)
    let projection = result.to_json().stringify() +
      notifications.snapshot().to_json().stringify()
    @fs.rmdir(directory, recursive=true)
    (result, identity_verified[0], projection)
  }
}

///|
test "origin validation permits only exact loopback HTTP or explicit HTTPS" {
  validate_origin("http://127.0.0.1:4390", false)
  validate_origin("http://localhost:80", false)
  validate_origin("http://[::1]:8080", false)
  validate_origin("https://guide.example.com", true)
  validate_origin("https://guide.example.com:8443", true)
  for
    origin in [
      "http://127.0.0.1:4390/path", "http://127.0.0.1.evil.test:4390", "http://localhost:4390@evil.test",
      "http://0.0.0.0:4390", "https://guide.example.com", " https://guide.example.com",
      "https://user@guide.example.com", "https://guide.example.com/path",
    ] {
    try {
      validate_origin(origin, false)
      fail("unsafe origin was accepted: \{origin}")
    } catch {
      InvalidConfiguration(_) => ()
      _ => fail("unexpected origin validation error")
    }
  }
}

///|
async test "scheduler state is atomic durable and corruption fails closed" {
  let directory = @fs.tmpdir(prefix="lunanexa-guide-probe-state-")
  let path = "\{directory}/scheduler.json"
  let scheduler = GuideProbeScheduler::open(path)
  let plan = scheduler.reserve_due(test_policy(), 100000L).unwrap()
  assert_eq(plan.correlation_receipt, "guide-probe-1-100000")
  assert_false(@fs.exists("\{path}.next"))
  let reopened = GuideProbeScheduler::open(path)
  let restored = reopened.snapshot()
  assert_eq(restored.sequence, 1L)
  assert_eq(restored.last_scheduled_unix_ms, Some(100000L))
  assert_true(reopened.reserve_due(test_policy(), 105000L) is None)
  assert_eq(
    reopened.reserve_due(test_policy(), 110000L).unwrap().correlation_receipt,
    "guide-probe-2-110000",
  )
  @fs.write_file(
    path,
    "{\"schema_version\":\"broken\",\"sequence\":0}",
    create_mode=CreateOrTruncate,
    permission=0o644,
  )
  try {
    ignore(GuideProbeScheduler::open(path))
    fail("corrupt scheduler state was replaced")
  } catch {
    InvalidSchedulerState => ()
    _ => fail("unexpected corrupt scheduler error")
  }
  assert_true(@fs.read_file(path).text().contains("broken"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "real loopback probe uses signed fixed-route identity and reconciles healthy state" {
  let (result, identity_verified, projection) = exercise_response(Healthy)
  assert_true(result.was_due)
  assert_true(result.probe_ok)
  assert_true(identity_verified)
  assert_eq(
    result.monitor_result.unwrap().observation_id,
    "guide-observation-guide-probe-1-100000",
  )
  assert_false(projection.contains("private-body-secret"))
  assert_false(result.monitor_result.unwrap().adapter_alert_active)
  assert_false(result.monitor_result.unwrap().knowledge_alert_active)
}

///|
async test "redirect oversize and malformed responses fail closed without body leakage" {
  for
    entry in [
      (Redirect, "RedirectRejected"),
      (Oversize, "ResponseTooLarge"),
      (Malformed, "MalformedResponse"),
    ] {
    let (mode, expected) = entry
    let (result, _, projection) = exercise_response(mode)
    assert_false(result.probe_ok)
    assert_eq(result.failure_code, Some(expected))
    assert_true(result.monitor_result.unwrap().adapter_alert_active)
    assert_false(result.monitor_result.unwrap().knowledge_alert_active)
    assert_false(projection.contains("private-body-secret"))
  }
}

///|
async test "stale and forged diagnostics fail closed and private fields are discarded" {
  for mode in [Stale, Forged] {
    let (result, identity_verified, projection) = exercise_response(mode)
    assert_true(identity_verified)
    assert_false(result.probe_ok)
    assert_eq(result.failure_code, Some("UntrustedResponse"))
    assert_false(projection.contains("private-body-secret"))
  }
  let (private_result, identity_verified, projection) = exercise_response(
    PrivateFields,
  )
  assert_true(identity_verified)
  assert_true(private_result.probe_ok)
  assert_false(projection.contains("private-body-secret"))
}

///|
async test "authenticated stale knowledge raises only the knowledge alert" {
  let (result, identity_verified, projection) = exercise_response(
    KnowledgeStale,
  )
  assert_true(identity_verified)
  assert_true(result.probe_ok)
  assert_false(result.monitor_result.unwrap().adapter_alert_active)
  assert_true(result.monitor_result.unwrap().knowledge_alert_active)
  assert_false(projection.contains("private-body-secret"))
}
