///|
fn distribution_packet() -> @planning.Packet raise {
  let input = fixture_input()
  let e = input.evidence[0]
  let sample = e.run.samples[0]
  let samples = [
    { ..sample, latency_ms: 0, queue_ms: 0, first_output_ms: 0, failed: false, },
    { ..sample, latency_ms: 10, queue_ms: 3, first_output_ms: 1, failed: true, },
    {
      ..sample,
      latency_ms: 11,
      queue_ms: 4,
      first_output_ms: 2,
      failed: false,
    },
    { ..sample, latency_ms: 20, queue_ms: 5, first_output_ms: 3, failed: true, },
    {
      ..sample,
      latency_ms: 21,
      queue_ms: 6,
      first_output_ms: 4,
      failed: false,
    },
  ]
  @planning.prepare({
    ..input,
    evidence: [{ ..e, run: { ..e.run, samples, }, }],
  })
}

///|
test "distribution inclusive boundaries overflow empty buckets and failure split" {
  let packet = distribution_packet()
  let original = packet.export_json()
  let plan : @planning.DistributionPlan = {
    schema_version: 1,
    metric: LatencyMs,
    upper_bounds_ms: [0, 10, 20, 30, 40],
  }
  let report = @planning.explore_distribution(
    packet,
    packet.input.evidence[0].run.run_id,
    plan,
  )
  assert_eq(report.unit, "milliseconds")
  assert_eq(report.sample_count, 5)
  assert_eq(report.failed_count, 2)
  assert_eq(report.succeeded_count, 3)
  assert_eq(report.buckets.map(b => b.sample_count), [1, 1, 2, 1, 0, 0])
  assert_eq(report.buckets.map(b => b.failed_count), [0, 1, 1, 0, 0, 0])
  assert_eq(report.buckets.map(b => b.cumulative_sample_count), [
    1, 2, 4, 5, 5, 5,
  ])
  assert_eq(report.buckets.map(b => b.cumulative_failed_count), [
    0, 1, 2, 2, 2, 2,
  ])
  assert_eq(report.buckets[0].lower_exclusive_ms, None)
  assert_eq(report.buckets[0].upper_inclusive_ms, Some(0))
  assert_eq(report.buckets[5].lower_exclusive_ms, Some(40))
  assert_eq(report.buckets[5].upper_inclusive_ms, None)
  guard ToJson::to_json(report.buckets[0]) is Object(first) &&
    ToJson::to_json(report.buckets[5]) is Object(last) else {
    fail("bucket JSON")
  }
  assert_eq(first.get("lower_exclusive_ms"), Some(Json::null()))
  assert_eq(last.get("upper_inclusive_ms"), Some(Json::null()))
  assert_eq(packet.export_json(), original)
  assert_eq(
    report.observation_sha256,
    @planning.observation_digest(packet.input.evidence[0].run),
  )
  assert_eq(
    ToJson::to_json(report.origin),
    ToJson::to_json(packet.input.evidence[0].origin),
  )
  assert_eq(
    ToJson::to_json(report),
    ToJson::to_json(
      @planning.explore_distribution(
        @planning.reopen(original),
        report.run_id,
        plan,
      ),
    ),
  )
  let overflow = @planning.explore_distribution(packet, report.run_id, {
    ..plan,
    upper_bounds_ms: [0, 10],
  })
  assert_eq(overflow.buckets.map(b => b.sample_count), [1, 1, 3])
}

///|
test "all recorded millisecond metrics have independent distribution and count conservation" {
  let packet = distribution_packet()
  let id = packet.input.evidence[0].run.run_id
  for
    (metric, expected) in [
      (@planning.QueueMs, [1, 2, 2]),
      (FirstOutputMs, [1, 4, 0]),
      (LoadMs, [5, 0, 0]),
      (DurationMs, [0, 0, 5]),
    ] {
    let report = @planning.explore_distribution(packet, id, {
      schema_version: 1,
      metric,
      upper_bounds_ms: [0, 4],
    })
    assert_eq(report.buckets.map(b => b.sample_count), expected)
    assert_eq(report.buckets[2].cumulative_sample_count, 5)
    for bucket in report.buckets {
      assert_eq(
        bucket.sample_count,
        bucket.succeeded_count + bucket.failed_count,
      )
    }
  }
}

///|
test "distribution plan exact import rejects bad schema fields bounds and unknown metric" {
  let plan = @planning.import_distribution_plan(
    "{\"schema_version\":1,\"metric\":\"LatencyMs\",\"upper_bounds_ms\":[0,10,2147483647]}",
  )
  assert_eq(plan.upper_bounds_ms, [0, 10, 2147483647])
  for
    text in [
      "{}", "{\"schema_version\":2,\"metric\":\"LatencyMs\",\"upper_bounds_ms\":[1]}",
      "{\"schema_version\":1,\"metric\":\"TokenCount\",\"upper_bounds_ms\":[1]}",
      "{\"schema_version\":1,\"metric\":\"LatencyMs\",\"upper_bounds_ms\":[]}", "{\"schema_version\":1,\"metric\":\"LatencyMs\",\"upper_bounds_ms\":[-1,10]}",
      "{\"schema_version\":1,\"metric\":\"LatencyMs\",\"upper_bounds_ms\":[10,10]}",
      "{\"schema_version\":1,\"metric\":\"LatencyMs\",\"upper_bounds_ms\":[10,9]}",
      "{\"schema_version\":1,\"metric\":\"LatencyMs\",\"upper_bounds_ms\":[1.5]}",
      "{\"schema_version\":1,\"metric\":\"LatencyMs\",\"upper_bounds_ms\":[1],\"unit\":\"seconds\"}",
    ] {
    try @planning.import_distribution_plan(text) catch {
      _ => ()
    } noraise {
      _ => fail("invalid distribution plan accepted")
    }
  }
}

///|
test "distribution selects exact verified run and rejects absent measurements" {
  let packet = distribution_packet()
  let plan : @planning.DistributionPlan = {
    schema_version: 1,
    metric: LatencyMs,
    upper_bounds_ms: [10],
  }
  for
    (candidate, run) in [
      (
        { ..packet, packet_id: "tampered", },
        packet.input.evidence[0].run.run_id,
      ),
      (packet, "missing-run"),
    ] {
    try @planning.explore_distribution(candidate, run, plan) catch {
      _ => ()
    } noraise {
      _ => fail("invalid selection accepted")
    }
  }
  let no_latency = packet
    .export_json()
    .replace_all(old="\"latency_ms\": 0", new="\"latency_ms\": null")
  assert_true(no_latency != packet.export_json())
  try @planning.reopen(no_latency) catch {
    _ => ()
  } noraise {
    _ => fail("missing metric became zero")
  }
}

///|
test "distribution CSV retains provenance and explicit open bounds and handles spreadsheet labels" {
  let base = distribution_packet()
  let e = base.input.evidence[0]
  let packet = @planning.prepare({
    ..base.input,
    evidence: [{ ..e, source_ref: " =SUM(1,2)\n\"计时\"", }],
  })
  let plan : @planning.DistributionPlan = {
    schema_version: 1,
    metric: LatencyMs,
    upper_bounds_ms: [0, 10],
  }
  let csv = @planning.distribution_csv(packet, e.run.run_id, plan)
  let table = @planning.preview_csv(csv)
  assert_eq(table.headers.length(), 25)
  assert_eq(table.sample_count, 3)
  assert_eq(table.first_rows[0][14], "")
  assert_eq(table.first_rows[0][15], "0")
  assert_eq(table.first_rows[2][14], "10")
  assert_eq(table.first_rows[2][15], "")
  assert_eq(table.first_rows[2][16], "3")
  assert_eq(table.first_rows[2][19], "5")
  assert_eq(table.first_rows[0][4], "' =SUM(1,2)\n\"计时\"")
  assert_eq(table.first_rows[0][2], @planning.observation_digest(e.run))
  assert_eq(packet.input.evidence[0].source_ref, " =SUM(1,2)\n\"计时\"")
}
