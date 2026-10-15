///|
fn sweep_plan() -> @planning.SweepPlan {
  {
    schema_version: 1,
    targets: [
      { tested_concurrency: 8, memory_total_mib: 16000, expected_repeats: 2, },
      { tested_concurrency: 4, memory_total_mib: 16000, expected_repeats: 2, },
      { tested_concurrency: 2, memory_total_mib: 16000, expected_repeats: 2, },
    ],
  }
}

///|
fn sweep_input() -> @planning.Input {
  let input = fixture_input()
  let e = input.evidence[0]
  let bad_sample = {
    ..e.run.samples[0],
    latency_ms: 90,
    queue_ms: 30,
    failed: true,
  }
  {
    ..input,
    evidence: [
      { ..e, run: { ..e.run, run_id: "repeat-b", samples: [bad_sample], }, },
      {
        ..e,
        run: { ..e.run, run_id: "unplanned-memory", },
        memory_total_mib: 32000,
      },
      { ..e, run: { ..e.run, run_id: "low-concurrency", concurrency: 2, }, },
      { ..e, run: { ..e.run, run_id: "repeat-a", }, },
    ],
  }
}

///|
test "sweep retains failed repeats missing levels and distinct memory environments" {
  let packet = @planning.prepare(sweep_input())
  let report = @planning.explore_sweep(packet, sweep_plan())
  assert_eq(report.groups.map(g => g.tested_concurrency), [2, 4, 4, 8])
  assert_eq(report.groups.map(g => g.memory_total_mib), [
    16000, 16000, 32000, 16000,
  ])
  assert_eq(report.groups.map(g => g.coverage), [
    "incomplete", "complete", "unplanned", "missing",
  ])
  assert_eq(report.groups.map(g => g.missing_repeats), [
    Some(1),
    Some(0),
    None,
    Some(2),
  ])
  let repeats = report.groups[1]
  assert_eq(repeats.runs.map(r => r.run_id), ["repeat-a", "repeat-b"])
  assert_eq(repeats.sample_count, 4)
  assert_eq(repeats.failed_count, 1)
  assert_eq(repeats.objective_met_runs, 1)
  assert_eq(repeats.envelope_met_runs, 1)
  assert_eq(repeats.ranges[1].minimum, 30)
  assert_eq(repeats.ranges[1].maximum, 90)
  assert_eq(repeats.ranges[3].minimum, 1)
  assert_eq(repeats.ranges[3].maximum, 30)
  assert_eq(report.groups[0].objective_met_runs, 1)
  assert_eq(report.groups[0].envelope_met_runs, 0)
  assert_true(report.groups[3].ranges.is_empty())
  assert_true(report.groups[3].runs.is_empty())
  assert_eq(report.groups[3].sample_count, 0)
  assert_eq(
    report.groups[2].runs[0].observation_sha256,
    @planning.observation_digest(packet.input.evidence[1].run),
  )
  assert_eq(report.workload, packet.input.workload)
  assert_eq(report.objective, packet.input.objective)
  assert_eq(report.origin, SyntheticFixture)
  assert_eq(report.packet_id, packet.packet_id)
}

///|
test "sweep optional plan makes no completeness claim and preserves input isolation" {
  let input = sweep_input()
  let packet = @planning.prepare(input)
  let original = packet.export_json()
  let plan : @planning.SweepPlan = { schema_version: 1, targets: [], }
  let report = @planning.explore_sweep(packet, plan)
  assert_eq(report.groups.length(), 3)
  assert_true(
    report.groups
    .iter()
    .all(g => {
      g.coverage == "unspecified" &&
      g.expected_repeats == None &&
      g.missing_repeats == None
    }),
  )
  assert_true(
    report == @planning.explore_sweep(@planning.reopen(original), plan),
  )
  let reversed = {
    ..input,
    evidence: [
      input.evidence[3],
      input.evidence[2],
      input.evidence[1],
      input.evidence[0],
    ],
  }
  assert_true(
    report.groups ==
    @planning.explore_sweep(@planning.prepare(reversed), plan).groups,
  )
  let declared = sweep_plan()
  let frozen = @planning.explore_sweep(packet, declared)
  declared.targets.clear()
  input.evidence.clear()
  assert_eq(frozen.plan.targets.length(), 3)
  assert_eq(packet.export_json(), original)
}

///|
test "sweep exact failures remain visible below legacy per mille resolution" {
  let input = fixture_input()
  let e = input.evidence[0]
  let samples = Array::make(1001, e.run.samples[0])
  samples[1000] = { ..samples[1000], failed: true, }
  let packet = @planning.prepare({
    ..input,
    evidence: [{ ..e, run: { ..e.run, samples, }, }],
  })
  let report = @planning.explore_sweep(packet, {
    schema_version: 1,
    targets: [],
  })
  let group = report.groups[0]
  assert_eq(group.failed_count, 1)
  assert_eq(group.sample_count, 1001)
  assert_eq(group.runs[0].summary.failure_per_mille, 0)
  assert_false(group.runs[0].exact_count_objective_met)
  assert_eq(group.objective_met_runs, 0)
}

///|
test "sweep rejects invalid plans tampering and incompatible packet context" {
  let packet = @planning.prepare(fixture_input())
  let target = sweep_plan().targets[0]
  for
    plan in [
      @planning.SweepPlan::{ schema_version: 2, targets: [], },
      { schema_version: 1, targets: [target, target], },
      { schema_version: 1, targets: Array::make(9, target), },
      { schema_version: 1, targets: [{ ..target, tested_concurrency: 0, }], },
      { schema_version: 1, targets: [{ ..target, tested_concurrency: 1025, }], },
      { schema_version: 1, targets: [{ ..target, memory_total_mib: 0, }], },
      { schema_version: 1, targets: [{ ..target, expected_repeats: 0, }], },
      { schema_version: 1, targets: [{ ..target, expected_repeats: 9, }], },
    ] {
    assert_true(sweep_rejected(packet, plan))
  }
  for
    text in [
      "{\"schema_version\":1,\"targets\":[],\"unknown\":true}",
      "{\"schema_version\":1,\"targets\":[{\"tested_concurrency\":4,\"memory_total_mib\":16000,\"expected_repeats\":2,\"unknown\":true}]}",
      "not json",
      String::make(65537, ' '),
    ] {
    try @planning.import_sweep_plan(text) catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid sweep plan to raise")
    }
  }
  let plan = sweep_plan()
  assert_true(
    @planning.import_sweep_plan(ToJson::to_json(plan).stringify()) == plan,
  )
  assert_true(sweep_rejected({ ..packet, packet_id: "altered", }, plan))
  let e = packet.input.evidence[0]
  let input = packet.input
  for
    bad in [
      { ..e, run: { ..e.run, run_id: "wrong", runtime_digest: "different", }, },
      {
        ..e,
        run: { ..e.run, run_id: "wrong", hardware_profile: "different", },
      },
      { ..e, run: { ..e.run, run_id: "wrong", }, workload_ref: "different", },
      { ..e, run: { ..e.run, run_id: "wrong", }, origin: LocalObservation, },
    ] {
    let changed = { ..packet, input: { ..input, evidence: [e, bad], }, }
    assert_true(sweep_rejected(changed, plan))
  }
}

///|
test "sweep CSV exposes missing metrics and escapes exact identity text" {
  let input = sweep_input()
  let first = input.evidence[0]
  input.evidence[0] = { ..first, source_ref: "source,\"测量\"\nline", }
  let packet = @planning.prepare(input)
  let csv = @planning.sweep_csv(packet, sweep_plan())
  assert_true(csv.has_prefix("packet_id,origin,profile"))
  assert_true(csv.contains("latency_p95_ms_min,latency_p95_ms_max"))
  assert_true(
    csv.contains(
      ",8,16000,2,0,2,\"missing\",0,0,0,0,,,,,,,,,,,,,,,\"[]\",\"[]\",\"[]\"\r\n",
    ),
    msg=csv,
  )
  assert_true(csv.contains("测量"))
  assert_true(csv.contains("repeat-a"))
  assert_true(csv.contains("repeat-b"))
  assert_eq(
    csv,
    @planning.sweep_csv(@planning.reopen(packet.export_json()), sweep_plan()),
  )
  let one = @planning.explore_sweep(packet, {
    schema_version: 1,
    targets: [
      { tested_concurrency: 4, memory_total_mib: 16000, expected_repeats: 1, },
    ],
  })
  assert_eq(one.groups[1].observed_repeats, 2)
  assert_eq(one.groups[1].missing_repeats, Some(0))
}

///|
fn sweep_rejected(
  packet : @planning.Packet,
  plan : @planning.SweepPlan,
) -> Bool {
  try {
    let _ = @planning.explore_sweep(packet, plan)
    false
  } catch {
    _ => true
  }
}
