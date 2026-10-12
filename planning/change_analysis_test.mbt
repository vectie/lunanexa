///|
fn change_input() -> @planning.ChangeInput {
  let old = fixture_input()
  let baseline = old.evidence[0]
  let candidate = {
    ..baseline,
    run: {
      ..baseline.run,
      run_id: "candidate-runtime-v2",
      runtime_digest: "sha256:candidate-runtime-v2",
      concurrency: 8,
      samples: baseline.run.samples.map(s => {
        ..s,
        latency_ms: s.latency_ms / 2,
        duration_ms: 125,
        queue_ms: 0,
      }),
    },
    memory_peak_mib: 10000,
  }
  {
    baseline,
    candidate,
    objective: old.objective,
    minimum_tested_concurrency: 4,
  }
}

///|
test "runtime change analysis exposes latency throughput memory tradeoff under a fixed objective" {
  let report = @planning.analyze_change(change_input())
  assert_eq(report.metrics[1].baseline, 30)
  assert_eq(report.metrics[1].candidate, 15)
  assert_eq(report.metrics[1].delta, -15)
  assert_eq(report.metrics[1].relative_per_mille, Some(-500L))
  assert_eq(report.metrics[5].candidate, 800)
  assert_eq(report.metrics[5].delta, -200)
  assert_eq(report.metrics[6].delta, -2000)
  assert_eq(report.metrics[7].delta, 2000)
  assert_true(report.baseline_meets_objective)
  assert_false(report.candidate_meets_objective)
  assert_eq(report.configuration_changes.map(c => c.field), [
    "runtime_digest", "tested_concurrency",
  ])
  assert_eq(report.failure_rate_direction, "unchanged")
  assert_true(report == @planning.reopen_change(report.export_json()))
  let text = report.summary_text()
  for
    expected in [
      "Fixed baseline objective", "delta -15", "delta -200", "SyntheticFixture",
      "not fleet throughput", "Model output quality is not evaluated", "sha256:candidate-runtime-v2",
    ] {
    assert_true(text.contains(expected))
  }
}

///|
test "zero baseline gives unavailable relative change without hiding an absolute queue delta" {
  let input = change_input()
  let baseline = {
    ..input.baseline,
    run: {
      ..input.baseline.run,
      samples: input.baseline.run.samples.map(s => { ..s, queue_ms: 0, }),
    },
  }
  let candidate = {
    ..input.candidate,
    run: {
      ..input.candidate.run,
      samples: input.candidate.run.samples.map(s => { ..s, queue_ms: 5, }),
    },
  }
  let report = @planning.analyze_change({ ..input, baseline, candidate, })
  assert_eq(report.metrics[3].delta, 5)
  assert_eq(report.metrics[3].relative_per_mille, None)
  assert_true(
    report.summary_text().contains("relative change unavailable: zero baseline"),
  )
}

///|
test "failure rate direction uses exact fractions with unequal sample counts and rounded zero rates" {
  let input = change_input()
  let sample = input.baseline.run.samples[0]
  let baseline = {
    ..input.baseline,
    run: {
      ..input.baseline.run,
      samples: [{ ..sample, failed: true, }] + Array::make(1000, sample),
    },
  }
  let candidate = {
    ..input.candidate,
    run: {
      ..input.candidate.run,
      samples: [{ ..sample, failed: true, }] + Array::make(2001, sample),
    },
  }
  let report = @planning.analyze_change({ ..input, baseline, candidate, })
  assert_eq(report.baseline_summary.failure_per_mille, 0)
  assert_eq(report.candidate_summary.failure_per_mille, 0)
  assert_eq(report.failure_rate_direction, "lower")
  assert_false(report.baseline_meets_objective)
  assert_false(report.candidate_meets_objective)
}

///|
test "separate packets retain baseline objective even when candidate had a relaxed objective" {
  let input = change_input()
  let baseline = @planning.prepare(fixture_input())
  let candidate = @planning.prepare({
    ..fixture_input(),
    workload: {
      ..fixture_input().workload,
      runtime_digest: input.candidate.run.runtime_digest,
    },
    objective: { ..input.objective, minimum_throughput_units_per_second: 700, },
    evidence: [input.candidate],
  })
  assert_true(candidate.choices[0].meets_declared_envelope)
  let report = @planning.compare_packet_runs(
    baseline,
    input.baseline.run.run_id,
    candidate,
    input.candidate.run.run_id,
  )
  assert_eq(report.input.objective.minimum_throughput_units_per_second, 900)
  assert_false(report.candidate_meets_objective)
  assert_true(
    change_rejected(() => {
      @planning.compare_packet_runs(
        baseline,
        "missing",
        candidate,
        input.candidate.run.run_id,
      )
    }),
  )
  assert_true(
    change_rejected(() => {
      @planning.compare_packet_runs(
        { ..baseline, packet_id: "modified", },
        input.baseline.run.run_id,
        candidate,
        input.candidate.run.run_id,
      )
    }),
  )
}

///|
test "different workloads units origins and benchmark kinds are not comparable" {
  let input = change_input()
  for
    candidate in [
      { ..input.candidate, workload_ref: "fixture:another-dataset", },
      { ..input.candidate, output_unit: "images", },
      { ..input.candidate, origin: LocalObservation, },
      { ..input.candidate, run: { ..input.candidate.run, kind: ColdStart, }, },
      {
        ..input.candidate,
        run: { ..input.candidate.run, profile: "another-profile", },
      },
    ] {
    assert_true(
      change_rejected(() => @planning.analyze_change({ ..input, candidate, })),
    )
  }
}

///|
test "analysis inputs are isolated and changed results or unknown fields are rejected on reopen" {
  let input = change_input()
  let report = @planning.analyze_change(input)
  let before = report.export_json()
  input.candidate.run.samples[0] = {
    ..input.candidate.run.samples[0],
    latency_ms: 100,
  }
  assert_eq(report.export_json(), before)
  assert_true(
    change_rejected(() => {
      @planning.reopen_change(
        { ..report, candidate_meets_objective: true, }.export_json(),
      )
    }),
  )
  assert_true(
    change_rejected(() => {
      @planning.reopen_change({ ..report, schema_version: 2, }.export_json())
    }),
  )
  let json = ToJson::to_json(report)
  guard json is Object(fields) else { fail("object") }
  fields["extra"] = true
  assert_true(change_rejected(() => @planning.reopen_change(json.stringify())))
}

///|
test "same run ID across snapshots is allowed and model hardware changes are disclosed" {
  let input = change_input()
  let report = @planning.analyze_change({
    ..input,
    candidate: {
      ..input.candidate,
      memory_total_mib: 32000,
      run: {
        ..input.candidate.run,
        run_id: input.baseline.run.run_id,
        model_digest: "sha256:new-model",
        hardware_profile: "fixture-host-driver-v2",
      },
    },
  })
  assert_eq(report.configuration_changes.map(c => c.field), [
    "model_digest", "runtime_digest", "hardware_profile", "tested_concurrency", "memory_total_mib",
  ])
  assert_eq(report.input.baseline.run.run_id, report.input.candidate.run.run_id)
  assert_true(
    @planning.observation_digest(report.input.baseline.run) !=
    @planning.observation_digest(report.input.candidate.run),
  )
}

///|
test "concurrency envelope remains distinct from the sample objective" {
  let input = change_input()
  let report = @planning.analyze_change({
    ..input,
    candidate: input.baseline,
    minimum_tested_concurrency: 8,
  })
  assert_true(report.baseline_meets_objective)
  assert_false(report.baseline_meets_envelope)
  assert_true(report.configuration_changes.is_empty())
}

///|
fn change_rejected(f : () -> @planning.ChangeReport raise) -> Bool {
  try {
    ignore(f())
    false
  } catch {
    _ => true
  }
}
