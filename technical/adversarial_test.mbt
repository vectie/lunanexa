///|
test "adversarial prewarm progress cannot regress exceed size or travel backward" {
  let operation = accepted_prewarm(
    @technical.begin_prewarm(prewarm_intent(), 1000L),
  )
  let reserved = accepted_prewarm(
    @technical.advance_prewarm(operation, Reserve, 1100L),
  )
  let transferring = accepted_prewarm(
    @technical.advance_prewarm(reserved, StartTransfer, 1200L),
  )
  let half = accepted_prewarm(
    @technical.advance_prewarm(
      transferring,
      ReportProgress(transferred_bytes=512L),
      1300L,
    ),
  )
  assert_eq(
    @technical.advance_prewarm(
      half,
      ReportProgress(transferred_bytes=511L),
      1400L,
    ),
    Rejected(ProgressRegressed),
  )
  assert_eq(
    @technical.advance_prewarm(
      half,
      ReportProgress(transferred_bytes=1025L),
      1400L,
    ),
    Rejected(ProgressExceedsArtifact),
  )
  assert_eq(
    @technical.advance_prewarm(half, BeginVerification, 1400L),
    Rejected(TransferIncomplete),
  )
  assert_eq(
    @technical.advance_prewarm(half, ObserveTime, 1299L),
    Rejected(ObservationBeforeLastUpdate),
  )
  assert_eq(
    @technical.advance_prewarm(
      { ..half, progress: { ..half.progress, total_bytes: 1L } },
      ObserveTime,
      1400L,
    ),
    Rejected(InvalidOperation),
  )
}

///|
test "digest mutation fuzz rejects every non lowercase hexadecimal position" {
  let base = model_digest()
  for position in 0..<64 {
    let candidate = base[:position].to_owned() +
      "g" +
      base[position + 1:].to_owned()
    assert_eq(
      @technical.begin_prewarm(
        { ..prewarm_intent(), model_digest: candidate },
        1000L,
      ),
      Rejected(InvalidDigest),
    )
  }
  for length in [0, 1, 63, 65, 128] {
    assert_eq(
      @technical.begin_prewarm(
        { ..prewarm_intent(), model_digest: "a".repeat(length) },
        1000L,
      ),
      Rejected(InvalidDigest),
    )
  }
}

///|
test "probe evaluator rejects stale and impossible policies" {
  let state = @technical.initial_probe_state(100L)
  assert_eq(
    @technical.evaluate_probe(
      state,
      { kind: Startup, success: true, observed_unix_ms: 100L },
      probe_policy(),
    ),
    Rejected(StaleObservation),
  )
  assert_eq(
    @technical.evaluate_probe(
      state,
      { kind: Startup, success: true, observed_unix_ms: 101L },
      {
        ..probe_policy(),
        startup: { ..probe_policy().startup, timeout_ms: 1001L },
      },
    ),
    Rejected(InvalidPolicy),
  )
  let delayed = {
    ..probe_policy(),
    startup: { ..probe_policy().startup, initial_delay_ms: 10L },
  }
  assert_eq(
    @technical.evaluate_probe(
      state,
      { kind: Startup, success: true, observed_unix_ms: 109L },
      delayed,
    ),
    Rejected(InitialDelayActive),
  )
  assert_eq(
    @technical.evaluate_probe(
      { ..state, startup_complete: true },
      { kind: Readiness, success: true, observed_unix_ms: 110L },
      probe_policy(),
    ),
    Rejected(InvalidState),
  )
}

///|
test "grant binding mutations all fail closed" {
  let grant = transfer_grant()
  let requested = transfer_use()
  let mismatches : Array[
    (@technical.TransferGrantUse, @technical.TransferGrantRejection),
  ] = [
    ({ ..requested, node_id: "other" }, NodeMismatch),
    ({ ..requested, deployment_id: "other" }, DeploymentMismatch),
    ({ ..requested, model_digest: "b".repeat(64) }, ModelMismatch),
    ({ ..requested, scope: RuntimeImageRead }, ScopeMismatch),
  ]
  for pair in mismatches {
    let (request, expected) = pair
    assert_eq(
      @technical.validate_transfer_grant(
        grant,
        request,
        Verified,
        [],
        1500L,
        1000L,
      ),
      Rejected(expected),
    )
  }
  assert_eq(
    @technical.validate_transfer_grant(
      grant,
      requested,
      Verified,
      [],
      1500L,
      @technical.transfer_grant_absolute_max_lifetime_ms + 1L,
    ),
    Rejected(UnsafeLifetimePolicy),
  )
}
