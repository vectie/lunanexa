///|
test "sample explorer retains stable original indices and exact captured data" {
  let base = evidence()
  let sample = base.run.samples[0]
  let e = {
    ..base,
    run: {
      ..base.run,
      samples: [
        { ..sample, latency_ms: 80, queue_ms: 2, },
        { ..sample, latency_ms: 80, queue_ms: 9, failed: true, },
        { ..sample, latency_ms: 20, queue_ms: 5, failed: true, },
      ],
    },
  }
  let original = ToJson::to_json(e).stringify()
  assert_eq(
    @planning.explore_samples(e, false, SlowestLatency).map(r => r.sample_index),
    [1, 2, 3],
  )
  assert_eq(
    @planning.explore_samples(e, false, LongestQueue).map(r => r.sample_index),
    [2, 3, 1],
  )
  assert_eq(
    @planning.explore_samples(e, true, RecordedOrder).map(r => r.sample_index),
    [2, 3],
  )
  assert_eq(@planning.explore_samples(base, true, RecordedOrder).length(), 0)
  assert_eq(ToJson::to_json(e).stringify(), original)
  let csv = @planning.samples_csv(e, true, LongestQueue)
  assert_true(csv.contains("sample_index,latency_ms,queue_ms"))
  assert_true(csv.contains(",2,80,9,0,4,100,100,500,true\r\n"))
  assert_true(csv.contains(@planning.observation_digest(e.run)))
  assert_eq(csv.split("\r\n").collect().length(), 4)
}

///|
test "summary CSV keeps exact failed count alongside rounded legacy rate" {
  let input = fixture_input()
  let e = input.evidence[0]
  let samples = Array::make(1001, e.run.samples[0])
  samples[1000] = { ..samples[1000], failed: true, }
  let packet = @planning.prepare({
    ..input,
    evidence: [{ ..e, run: { ..e.run, samples, }, }],
  })
  let csv = packet.summary_csv()
  assert_true(csv.contains("failed_count,failure_per_mille_rounded"))
  assert_true(csv.contains(",1001,1,0,4,4,"))
  assert_true(csv.contains(",false,false\r\n"))
  assert_eq(csv, @planning.reopen(packet.export_json()).summary_csv())
  let tampered = { ..packet, packet_id: "changed", }
  try tampered.summary_csv() catch {
    _ => ()
  } noraise {
    _ => fail("CSV accepted a changed packet")
  }
}

///|
test "spreadsheet CSV quotes unicode commas quotes newlines and formula-like metadata" {
  let input = fixture_input()
  let e = input.evidence[0]
  let special = { ..e, source_ref: " =SUM(1,2)\n\"测量\"", }
  let packet = @planning.prepare({ ..input, evidence: [special], })
  assert_true(
    packet.summary_csv().contains("\"' =SUM(1,2)\n\"\"测量\"\"\""),
    msg=packet.summary_csv(),
  )
  assert_eq(packet.input.evidence[0].source_ref, special.source_ref)
  let no_failures = @planning.samples_csv(e, true, RecordedOrder)
  assert_eq(no_failures.split("\r\n").collect().length(), 2)
}
