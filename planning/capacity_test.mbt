///|
fn evidence() -> @planning.Evidence {
  {
    run: {
      run_id: "synthetic-concurrency-4",
      profile: "text-short-v1",
      model_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      runtime_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      hardware_profile: "fixture-host-driver-v1",
      kind: Concurrency,
      concurrency: 4,
      samples: [
        for latency in [10, 20, 30] => {
          {
            latency_ms: latency,
            queue_ms: 1,
            load_ms: 0,
            first_output_ms: 4,
            output_units: 100,
            duration_ms: 100,
            utilization_per_mille: 500,
            failed: false,
          }
        }
      ],
    },
    origin: SyntheticFixture,
    source_ref: "fixture:capacity-v1",
    workload_ref: "fixture:text-short-v1:128-input-100-output",
    output_unit: "tokens",
    memory_total_mib: 16000,
    memory_peak_mib: 12000,
  }
}

///|
fn fixture_input() -> @planning.Input {
  let e = evidence()
  {
    schema_version: 1,
    workload: {
      profile: e.run.profile,
      model_digest: e.run.model_digest,
      runtime_digest: e.run.runtime_digest,
      hardware_profile: e.run.hardware_profile,
      kind: e.run.kind,
      workload_ref: e.workload_ref,
      output_unit: e.output_unit,
      minimum_tested_concurrency: 4,
    },
    objective: {
      profile: e.run.profile,
      maximum_p95_ms: 35,
      minimum_throughput_units_per_second: 900,
      maximum_failure_per_mille: 0,
    },
    evidence: [e],
  }
}

///|
fn rejected(input : @planning.Input) -> Bool {
  try {
    let _ = @planning.prepare(input)
    false
  } catch {
    _ => true
  }
}

///|
test "actual pure benchmark fixture is deterministic and packet reopens exact inputs" {
  let input = fixture_input()
  let packet = @planning.prepare(input)
  let choice = packet.choices[0]
  assert_eq(
    choice.recommendation.summary,
    @benchmark.summarize(input.evidence[0].run),
  )
  assert_eq(choice.recommendation.summary.latency_p50_ms, 20)
  assert_eq(choice.recommendation.summary.latency_p95_ms, 30)
  assert_eq(choice.recommendation.summary.throughput_units_per_second, 1000)
  assert_eq(choice.recommendation.summary.sample_count, 3)
  assert_eq(choice.recommendation.capacity.memory_headroom_mib, 4000)
  assert_eq(choice.recommendation.capacity.recommended_concurrency, 4)
  assert_true(choice.meets_declared_envelope)
  assert_eq(packet, @planning.prepare(input))
  let second = {
    ..input.evidence[0],
    run: {
      ..input.evidence[0].run,
      run_id: "synthetic-concurrency-8",
      concurrency: 8,
    },
  }
  // Golden ID produced by the native offline CLI for the committed two-run
  // fixture; this assertion also runs on JS to protect cross-target identity.
  assert_eq(
    @planning.prepare({ ..input, evidence: input.evidence + [second], }).packet_id,
    "capacity-v1:sha256:26ff77972cf8f8442a53f1351011fb6d66021ef20f76c1bd546b8c81eeec8b77",
  )
  assert_eq(@planning.reopen(packet.export_json()), packet)
  assert_eq(@planning.reopen(packet.export_json()).input, input)
  assert_eq(choice.origin, SyntheticFixture)
  assert_eq(choice.source_ref, input.evidence[0].source_ref)
  assert_eq(
    @planning.import_evidence(ToJson::to_json(input.evidence).stringify()),
    input.evidence,
  )
}

///|
test "objective and workload changes make a new packet with retained historical bytes" {
  let input = fixture_input()
  let packet = @planning.prepare(input)
  let bytes = packet.export_json()
  let changed = @planning.prepare({
    ..input,
    objective: { ..input.objective, maximum_p95_ms: 25, },
  })
  assert_not_eq(packet.packet_id, changed.packet_id)
  assert_false(changed.choices[0].recommendation.objective_met)
  assert_eq(bytes, packet.export_json())
  let changed = @planning.prepare({
    ..input,
    workload: { ..input.workload, minimum_tested_concurrency: 5, },
  })
  assert_not_eq(packet.packet_id, changed.packet_id)
  assert_false(changed.choices[0].meets_declared_envelope)
}

///|
test "every compatibility identity is checked instead of pooling runs" {
  let input = fixture_input()
  let e = input.evidence[0]
  for
    changed in [
      { ..e, run: { ..e.run, profile: "other", }, },
      { ..e, run: { ..e.run, model_digest: "other", }, },
      { ..e, run: { ..e.run, runtime_digest: "other", }, },
      { ..e, run: { ..e.run, hardware_profile: "other", }, },
      { ..e, run: { ..e.run, kind: Saturation, }, },
      { ..e, workload_ref: "other", },
      { ..e, output_unit: "images", },
    ] {
    assert_true(rejected({ ..input, evidence: [changed], }))
  }
  assert_true(
    rejected({ ..input, objective: { ..input.objective, profile: "other", }, }),
  )
}

///|
test "empty samples invalid duration negative metrics and overflow are rejected" {
  let input = fixture_input()
  let e = input.evidence[0]
  let s = e.run.samples[0]
  assert_true(
    rejected({ ..input, evidence: [{ ..e, run: { ..e.run, samples: [], }, }], }),
  )
  for
    sample in [
      { ..s, duration_ms: 0, },
      { ..s, duration_ms: -1, },
      { ..s, output_units: -1, },
      { ..s, output_units: 2147484, },
      { ..s, latency_ms: -1, },
      { ..s, queue_ms: -1, },
      { ..s, first_output_ms: -1, },
      { ..s, load_ms: -1, },
      { ..s, utilization_per_mille: 1001, },
      { ..s, utilization_per_mille: -1, },
    ] {
    assert_true(
      rejected({
        ..input,
        evidence: [{ ..e, run: { ..e.run, samples: [sample], }, }],
      }),
    )
  }
  assert_true(
    rejected({
      ..input,
      evidence: [
        {
          ..e,
          run: { ..e.run, samples: [{ ..s, duration_ms: 2147483647, }, s], },
        },
      ],
    }),
  )
}

///|
test "bounds provenance missing identifiers duplicate ids and incompatible origins" {
  let input = fixture_input()
  let e = input.evidence[0]
  assert_true(rejected({ ..input, evidence: [], }))
  assert_true(rejected({ ..input, evidence: [e, e], }))
  assert_true(rejected({ ..input, evidence: [ for _ in 0..<9 => e ], }))
  for
    bad in [
      { ..e, source_ref: "", },
      { ..e, source_ref: "   ", },
      { ..e, run: { ..e.run, run_id: "", }, },
      { ..e, run: { ..e.run, concurrency: 0, }, },
      { ..e, run: { ..e.run, concurrency: 1025, }, },
      { ..e, memory_total_mib: 0, },
      { ..e, memory_peak_mib: 0, },
      { ..e, memory_peak_mib: 16001, },
    ] {
    assert_true(rejected({ ..input, evidence: [bad], }))
  }
  let observed = {
    ..e,
    origin: LocalObservation,
    run: { ..e.run, run_id: "local-1", },
  }
  assert_true(rejected({ ..input, evidence: [e, observed], }))
  let packet = @planning.prepare({ ..input, evidence: [observed], })
  assert_eq(packet.choices[0].origin, LocalObservation)
  assert_eq(@planning.reopen(packet.export_json()).input.evidence[0], observed)
}

///|
test "objective must be explicit valid and version supported" {
  let input = fixture_input()
  for
    o in [
      { ..input.objective, maximum_p95_ms: 0, },
      { ..input.objective, minimum_throughput_units_per_second: 0, },
      { ..input.objective, maximum_failure_per_mille: -1, },
      { ..input.objective, maximum_failure_per_mille: 1001, },
    ] {
    assert_true(rejected({ ..input, objective: o, }))
  }
  assert_true(rejected({ ..input, schema_version: 2, }))
  for n in [0, 1025] {
    assert_true(
      rejected({
        ..input,
        workload: { ..input.workload, minimum_tested_concurrency: n, },
      }),
    )
  }
}

///|
test "two bounded tested choices preserve sample counts and the existing failure heuristic" {
  let input = fixture_input()
  let e = input.evidence[0]
  let s = e.run.samples[0]
  let next = {
    ..e,
    run: {
      ..e.run,
      run_id: "synthetic-concurrency-8",
      concurrency: 8,
      samples: [s, { ..s, failed: true, }],
    },
  }
  let packet = @planning.prepare({ ..input, evidence: [e, next], })
  assert_eq(packet.choices.length(), 2)
  assert_eq(packet.choices[0].recommendation.summary.sample_count, 3)
  assert_eq(packet.choices[1].recommendation.summary.sample_count, 2)
  assert_eq(packet.choices[1].tested_concurrency, 8)
  assert_eq(
    packet.choices[1].recommendation.capacity.recommended_concurrency,
    7,
  )
  assert_false(packet.choices[1].meets_declared_envelope)
}

///|
test "reopen recomputes all results and rejects tampered identity inputs and unsupported schema" {
  let packet = @planning.prepare(fixture_input())
  for
    changed in [
      { ..packet, schema_version: 2, },
      { ..packet, packet_id: "forged", },
      { ..packet, choices: [], },
      {
        ..packet,
        choices: [{ ..packet.choices[0], meets_declared_envelope: false, }],
      },
      {
        ..packet,
        input: {
          ..packet.input,
          objective: { ..packet.input.objective, maximum_p95_ms: 500, },
        },
      },
    ] {
    assert_true(
      try {
        let _ = @planning.reopen(changed.export_json())
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      let _ = @planning.reopen("{}")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @planning.import_evidence("[]")
      false
    } catch {
      _ => true
    },
  )
}

///|
test "prepared input arrays are detached from mutable authoring samples" {
  let input = fixture_input()
  let packet = @planning.prepare(input)
  let before = packet.export_json()
  input.evidence[0].run.samples.push(input.evidence[0].run.samples[0])
  assert_eq(packet.export_json(), before)
  assert_eq(packet.input.evidence[0].run.samples.length(), 3)
}

///|
test "strict imports reject unknown semantic fields instead of silently dropping them" {
  let input = fixture_input()
  let packet = @planning.prepare(input)
  assert_eq(@planning.import_input(ToJson::to_json(input).stringify()), input)
  let unknown_packet = packet
    .export_json()
    .replace(
      old="\"schema_version\": 1,",
      new="\"schema_version\": 1, \"unknown\": true,",
    )
  assert_true(
    try {
      let _ = @planning.reopen(unknown_packet)
      false
    } catch {
      _ => true
    },
  )
  let unknown_evidence = ToJson::to_json(input.evidence)
    .stringify()
    .replace(old="\"source_ref\":", new="\"unknown\":true,\"source_ref\":")
  assert_true(
    try {
      let _ = @planning.import_evidence(unknown_evidence)
      false
    } catch {
      _ => true
    },
  )
  let unknown_input = ToJson::to_json(input)
    .stringify()
    .replace(old="\"profile\":", new="\"unknown\":true,\"profile\":")
  assert_true(
    try {
      let _ = @planning.import_input(unknown_input)
      false
    } catch {
      _ => true
    },
  )
}

///|
test "planner exact-count objective does not mistake rounded zero for no failures" {
  let input = fixture_input()
  let e = input.evidence[0]
  let samples = [ for _ in 0..<1001 => e.run.samples[0] ]
  samples[0] = { ..samples[0], failed: true, }
  let evidence = { ..e, run: { ..e.run, samples, }, }
  let packet = @planning.prepare({ ..input, evidence: [evidence], })
  let choice = packet.choices[0]
  assert_eq(choice.recommendation.summary.failure_per_mille, 0)
  assert_eq(choice.recommendation.capacity.recommended_concurrency, 4)
  assert_true(choice.recommendation.objective_met)
  assert_eq(@planning.observed_failure_count(evidence), 1)
  assert_false(
    @planning.observed_objective_met(evidence, choice.recommendation),
  )
  assert_false(choice.meets_declared_envelope)
  assert_eq(@planning.reopen(packet.export_json()), packet)
  let allowed = @planning.prepare({
    ..input,
    objective: { ..input.objective, maximum_failure_per_mille: 1, },
    evidence: [evidence],
  })
  assert_true(allowed.choices[0].meets_declared_envelope)
  samples[1] = { ..samples[1], failed: true, }
  let over = @planning.prepare({
    ..input,
    objective: { ..input.objective, maximum_failure_per_mille: 1, },
    evidence: [evidence],
  })
  assert_eq(over.choices[0].recommendation.summary.failure_per_mille, 1)
  assert_true(over.choices[0].recommendation.objective_met)
  assert_false(over.choices[0].meets_declared_envelope)
}
