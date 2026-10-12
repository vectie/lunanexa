///|
test "timeline assigns every record once and preserves charges credits and unknown cost" {
  let source = report_snapshot()
  let before = source.to_json().stringify()
  let timeline = @commercial.explore_usage_timeline(
    source,
    report_query(),
    1000L,
  )
  assert_eq(timeline.buckets.length(), 5)
  assert_eq(timeline.buckets[0].started_unix_ms, 1500L)
  assert_eq(timeline.buckets[4].ended_unix_ms, 6000L)
  assert_eq(timeline.buckets[0].report.rows[0].entry_id, "charge-one")
  assert_eq(timeline.buckets[0].crossing_bucket_count, 1)
  assert_eq(timeline.buckets[1].report.rows.length(), 0)
  assert_eq(timeline.buckets[2].report.rows[0].entry_id, "credit-one")
  assert_eq(timeline.buckets[3].report.rows[0].kind, "unpriced_usage")
  assert_eq(timeline.buckets[3].report.groups[0].amount, None)
  let mut rows = 0
  let mut quantity = 0L
  let mut amount = 0L
  for bucket in timeline.buckets {
    rows += bucket.report.rows.length()
    for group in bucket.report.groups {
      quantity += group.quantity
      if group.amount is Some(value) {
        amount += value.minor_units
      }
    }
  }
  assert_eq(rows, 3)
  assert_eq(quantity, 8L)
  assert_eq(amount, 4L)
  assert_eq(before, source.to_json().stringify())
  assert_true(timeline.json_text().contains("\"amount\": null"))
  assert_true(timeline.summary_csv().contains(",empty,0,"))
  assert_false(timeline.json_text().contains("dgx-1"))
}

///|
test "timeline clamps prewindow starts and excludes endpoint-only intersections" {
  let source = report_snapshot()
  let query = {
    ..report_query(),
    started_unix_ms: 2500L,
    ended_unix_ms: 4500L,
  }
  let timeline = @commercial.explore_usage_timeline(source, query, 500L)
  assert_eq(timeline.buckets.length(), 4)
  assert_eq(timeline.buckets[0].report.rows.length(), 1)
  assert_eq(timeline.buckets[0].crossing_bucket_count, 1)
  assert_true(timeline.buckets[0].report.rows[0].crosses_window)
  assert_eq(timeline.buckets[3].report.rows.length(), 1)
  assert_eq(timeline.buckets[3].report.rows[0].kind, "credit")
  let after = @commercial.explore_usage_timeline(
    source,
    { ..report_query(), started_unix_ms: 5000L, },
    1000L,
  )
  assert_eq(after.buckets[0].report.rows.length(), 0)
}

///|
test "timeline validates width count and windows without overflow" {
  let source = report_snapshot()
  for width in [0L, -1L, 1L] {
    try
      @commercial.explore_usage_timeline(source, report_query(), width)
    catch {
      @commercial.InvalidInput(_) => ()
      _ => fail("unexpected commercial error")
    } noraise {
      _ => fail("expected rejected width")
    }
  }
  let near_max = {
    ..report_query(),
    started_unix_ms: 9223372036854775800L,
    ended_unix_ms: 9223372036854775807L,
  }
  let large = @commercial.explore_usage_timeline(
    source, near_max, 9223372036854775807L,
  )
  assert_eq(large.buckets.length(), 1)
  assert_eq(large.buckets[0].ended_unix_ms, near_max.ended_unix_ms)
  let thousand = @commercial.explore_usage_timeline(
    source,
    { ..report_query(), started_unix_ms: 0L, ended_unix_ms: 1000L, },
    1L,
  )
  assert_eq(thousand.buckets.length(), 1000)
  try
    @commercial.explore_usage_timeline(
      source,
      { ..report_query(), ended_unix_ms: 0L, },
      1L,
    )
  catch {
    @commercial.InvalidInput(_) => ()
    _ => fail("unexpected commercial error")
  } noraise {
    _ => fail("expected rejected window")
  }
}

///|
test "timeline is deterministic honors filters and keeps zero distinct from missing" {
  let source = report_snapshot()
  let query = { ..report_query(), group_by: "meter", meter: "nonexistent", }
  let empty = @commercial.explore_usage_timeline(source, query, 2000L)
  assert_true(empty.buckets.all(bucket => bucket.report.rows.is_empty()))
  assert_false(empty.summary_csv().contains(",observed,"))
  let forward = @commercial.explore_usage_timeline(
    source,
    report_query(),
    1000L,
  ).json_text()
  let reversed = {
    ..source,
    usage_observations: source.usage_observations.rev(),
    ledger_entries: source.ledger_entries.rev(),
  }
  assert_eq(
    @commercial.explore_usage_timeline(reversed, report_query(), 1000L).json_text(),
    forward,
  )
}
