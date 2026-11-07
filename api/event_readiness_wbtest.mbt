///|
test "event heartbeat freshness uses the authenticated intake skew boundary" {
  let timing = @settings.default_global_admin_settings().control_timing
  let now = 1000000L
  // Reproduced .177 failure: its accepted heartbeat leads management by 453ms.
  assert_eq(event_heartbeat_time_blocker(now + 453L, now, timing), None)
  assert_eq(event_heartbeat_time_blocker(now, now, timing), None)
  assert_eq(
    event_heartbeat_time_blocker(now - timing.heartbeat_timeout_ms, now, timing),
    None,
  )
  assert_eq(
    event_heartbeat_time_blocker(
      now - timing.heartbeat_timeout_ms - 1L,
      now,
      timing,
    ),
    Some("heartbeat is stale"),
  )
  assert_eq(
    event_heartbeat_time_blocker(
      now + timing.heartbeat_replay_window_ms,
      now,
      timing,
    ),
    None,
  )
  assert_eq(
    event_heartbeat_time_blocker(
      now + timing.heartbeat_replay_window_ms + 1L,
      now,
      timing,
    ),
    Some("heartbeat clock exceeds accepted skew"),
  )
}

///|
async test "zero execution concurrency disables the extra semaphore without disabling admission" {
  let directory = @fs.tmpdir(prefix="uncapped-runtime-")
  let store = @store.FileStore::open(directory + "/control.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses",
    "",
    "test-runtime",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
  )
  let service = ApiService::new(
    store, runtime, "operator", "inference", "node", "test",
  )
  let uncapped = service.with_runtime_concurrency(0)
  assert_true(uncapped.execution_slots is None)
  assert_eq(uncapped.global_settings.scheduler.admission_capacity, 128)
  assert_true(service.with_runtime_concurrency(4).execution_slots is Some(_))
  @fs.rmdir(directory, recursive=true)
}
