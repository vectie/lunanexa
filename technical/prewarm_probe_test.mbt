///|
fn model_digest() -> String {
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

///|
fn prewarm_intent() -> @technical.PrewarmIntent {
  {
    operation_id: "prewarm-1",
    deployment_id: "deployment-1",
    node_id: "dgx-2",
    model_digest: model_digest(),
    size_bytes: 1024L,
    created_unix_ms: 1000L,
    expires_unix_ms: 10000L,
  }
}

///|
fn accepted_prewarm(
  decision : @technical.PrewarmDecision,
) -> @technical.PrewarmOperation raise {
  match decision {
    Accepted(operation) => operation
    Rejected(reason) => fail("unexpected rejection: \{Repr(reason)}")
  }
}

///|
test "prewarm reserves transfers verifies and releases reservation" {
  let operation = accepted_prewarm(
    @technical.begin_prewarm(prewarm_intent(), 1000L),
  )
  assert_eq(operation.state, Queued)
  let reserved = accepted_prewarm(
    @technical.advance_prewarm(operation, Reserve, 1100L),
  )
  assert_eq(reserved.state, Reserved)
  assert_true(reserved.reservation is Some(_))
  let transferring = accepted_prewarm(
    @technical.advance_prewarm(reserved, StartTransfer, 1200L),
  )
  let downloaded = accepted_prewarm(
    @technical.advance_prewarm(
      transferring,
      ReportProgress(transferred_bytes=1024L),
      1300L,
    ),
  )
  let verifying = accepted_prewarm(
    @technical.advance_prewarm(downloaded, BeginVerification, 1400L),
  )
  let ready = accepted_prewarm(
    @technical.advance_prewarm(verifying, PublishReady, 1500L),
  )
  assert_eq(ready.state, Ready)
  assert_eq(ready.reservation, None)
}

///|
test "prewarm cancellation and expiry are explicit terminal states" {
  let operation = accepted_prewarm(
    @technical.begin_prewarm(prewarm_intent(), 1000L),
  )
  let cancelling = accepted_prewarm(
    @technical.advance_prewarm(operation, RequestCancellation, 1200L),
  )
  assert_eq(cancelling.state, CancellationRequested)
  let cancelled = accepted_prewarm(
    @technical.advance_prewarm(cancelling, ObserveCancellation, 1300L),
  )
  assert_eq(cancelled.state, Cancelled)
  assert_eq(
    @technical.advance_prewarm(cancelled, Reserve, 1400L),
    Rejected(TerminalState),
  )
  let fresh = accepted_prewarm(
    @technical.begin_prewarm(prewarm_intent(), 1000L),
  )
  let expired = accepted_prewarm(
    @technical.advance_prewarm(fresh, ObserveTime, 10000L),
  )
  assert_eq(expired.state, Expired)
}

///|
fn probe_stage(successes : Int, failures : Int) -> @technical.ProbeStagePolicy {
  {
    initial_delay_ms: 0L,
    period_ms: 1000L,
    timeout_ms: 500L,
    success_threshold: successes,
    failure_threshold: failures,
  }
}

///|
fn probe_policy() -> @technical.ProbePolicy {
  {
    startup: probe_stage(2, 3),
    readiness: probe_stage(2, 2),
    liveness: probe_stage(1, 2),
  }
}

///|
fn applied_probe(
  decision : @technical.ProbeDecision,
) -> @technical.ProbeState raise {
  match decision {
    Applied(state) => state
    Rejected(reason) => fail("unexpected rejection: \{Repr(reason)}")
  }
}

///|
test "startup gates readiness and liveness forces restart" {
  let state = @technical.initial_probe_state(100L)
  assert_eq(
    @technical.evaluate_probe(
      state,
      { kind: Readiness, success: true, observed_unix_ms: 101L },
      probe_policy(),
    ),
    Rejected(StartupIncomplete),
  )
  let one = applied_probe(
    @technical.evaluate_probe(
      state,
      { kind: Startup, success: true, observed_unix_ms: 101L },
      probe_policy(),
    ),
  )
  let started = applied_probe(
    @technical.evaluate_probe(
      one,
      { kind: Startup, success: true, observed_unix_ms: 102L },
      probe_policy(),
    ),
  )
  assert_true(started.startup_complete)
  assert_false(started.route_eligible())
  let ready_one = applied_probe(
    @technical.evaluate_probe(
      started,
      { kind: Readiness, success: true, observed_unix_ms: 103L },
      probe_policy(),
    ),
  )
  let ready = applied_probe(
    @technical.evaluate_probe(
      ready_one,
      { kind: Readiness, success: true, observed_unix_ms: 104L },
      probe_policy(),
    ),
  )
  assert_true(ready.route_eligible())
  let live_one = applied_probe(
    @technical.evaluate_probe(
      ready,
      { kind: Liveness, success: false, observed_unix_ms: 105L },
      probe_policy(),
    ),
  )
  let dead = applied_probe(
    @technical.evaluate_probe(
      live_one,
      { kind: Liveness, success: false, observed_unix_ms: 106L },
      probe_policy(),
    ),
  )
  assert_eq(dead.runtime_state, RestartRequired)
  assert_false(dead.route_eligible())
}
