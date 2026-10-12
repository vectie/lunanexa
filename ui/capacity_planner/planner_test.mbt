///|
fn fixture_evidence() -> @planning.Evidence {
  {
    run: {
      run_id: "fixture-run-4",
      profile: "text-short-v1",
      model_digest: "sha256:model-fixture",
      runtime_digest: "sha256:runtime-fixture",
      hardware_profile: "fixture-host-v1",
      kind: Concurrency,
      concurrency: 4,
      samples: [
        {
          latency_ms: 20,
          queue_ms: 1,
          load_ms: 0,
          first_output_ms: 4,
          output_units: 100,
          duration_ms: 100,
          utilization_per_mille: 500,
          failed: false,
        },
      ],
    },
    origin: SyntheticFixture,
    source_ref: "fixture:ui-planner-v1",
    workload_ref: "fixture:workload-revision-1",
    output_unit: "tokens",
    memory_total_mib: 16000,
    memory_peak_mib: 12000,
  }
}

///|
fn imported() -> @capacity_planner.State {
  let first = fixture_evidence()
  let second = {
    ..first,
    run: { ..first.run, run_id: "fixture-run-8", concurrency: 8, },
  }
  @capacity_planner.update(
    @capacity_planner.update(
      @capacity_planner.initial(),
      ImportTextChanged(ToJson::to_json([first, second]).stringify()),
    ),
    ImportEvidence,
  )
}

///|
fn authored() -> @capacity_planner.State {
  let mut state = imported()
  for
    (field, value) in [
      (@capacity_planner.Field::MinimumConcurrency, "4"),
      (MaximumP95, "30"),
      (MinimumThroughput, "900"),
      (MaximumFailures, "0"),
    ] {
    state = @capacity_planner.update(state, Edit(field, value))
  }
  state
}

///|
#warnings("-alert_unstable")
fn render(state : @capacity_planner.State) -> String {
  @rabbita.render_to_string(() => {
    @rabbita.Val::constant(@capacity_planner.view(state, English, None))
  })
}

///|
test "operator imports selects authors prepares exports and reopens exact editable inputs" {
  let source = imported()
  assert_eq(source.sources.length(), 2)
  assert_eq(source.selected, ["fixture-run-4"])
  assert_true(@capacity_planner.update(source, Prepare).error is Some(_))
  let selected = @capacity_planner.update(
    authored(),
    ToggleRun("fixture-run-8"),
  )
  let prepared = @capacity_planner.update(selected, Prepare)
  let packet = prepared.packet.unwrap()
  assert_eq(packet.choices.length(), 2)
  assert_eq(packet.choices[0].recommendation.summary.sample_count, 1)
  let html = render(prepared)
  for
    required in [
      "Capacity-plan workbench",
      "Import benchmark evidence",
      "Minimum tested concurrency",
      "Maximum p95 latency",
      "Bounded choices",
      "SYNTHETIC FIXTURE",
      "Download exact planning packet",
      "data:application/json;charset=utf-8;base64,",
      "Verify and reopen packet",
      packet.packet_id,
    ] {
    assert_true(html.contains(required), msg=required)
  }
  let reopened = @capacity_planner.update(
    @capacity_planner.update(
      @capacity_planner.initial(),
      ReopenTextChanged(packet.export_json()),
    ),
    ReopenPacket,
  )
  assert_eq(reopened.packet, prepared.packet)
  assert_true(reopened.draft == prepared.draft)
  assert_eq(@capacity_planner.input(reopened), packet.input)
  assert_eq(@capacity_planner.update(reopened, Prepare).packet, prepared.packet)
}

///|
test "material edits invalidate exports while retained packets remain immutable" {
  let prepared = @capacity_planner.update(authored(), Prepare)
  let old = prepared.packet.unwrap().export_json()
  let edited = @capacity_planner.update(prepared, Edit(MaximumP95, "10"))
  assert_true(edited.packet is None)
  assert_false(render(edited).contains("Download exact planning packet"))
  let next = @capacity_planner.update(edited, Prepare)
  assert_not_eq(
    next.packet.unwrap().packet_id,
    prepared.packet.unwrap().packet_id,
  )
  assert_eq(prepared.packet.unwrap().export_json(), old)
  assert_true(
    @capacity_planner.update(prepared, ToggleRun("fixture-run-4")).packet
    is None,
  )
  let reset = @capacity_planner.update(prepared, Reset)
  assert_true(reset.sources.is_empty())
  assert_true(reset.packet is None)
  assert_true(reset.draft == @capacity_planner.initial().draft)
}

///|
test "failed imports and reopen retain current authoring state and explain the error" {
  let prepared = @capacity_planner.update(authored(), Prepare)
  let failed = @capacity_planner.update(
    @capacity_planner.update(prepared, ImportTextChanged("[]")),
    ImportEvidence,
  )
  assert_eq(failed.sources, prepared.sources)
  assert_true(failed.draft == prepared.draft)
  assert_eq(failed.packet, prepared.packet)
  assert_true(failed.error is Some(_))
  let failed = @capacity_planner.update(
    @capacity_planner.update(prepared, ReopenTextChanged("{}")),
    ReopenPacket,
  )
  assert_true(failed.draft == prepared.draft)
  assert_eq(failed.packet, prepared.packet)
  assert_true(render(failed).contains("role=\"alert\""))
}

///|
test "selection cannot prepare mismatched hardware or unknown run and never supplies default SLA" {
  assert_eq(@capacity_planner.initial().draft.maximum_p95, "")
  let initial = authored()
  let invalid = @capacity_planner.update(
    initial,
    Edit(HardwareProfile, "other-host"),
  )
  assert_true(@capacity_planner.update(invalid, Prepare).error is Some(_))
  assert_true(
    @capacity_planner.update(initial, ToggleRun("unknown")).error is Some(_),
  )
  let deselected = @capacity_planner.update(initial, ToggleRun("fixture-run-4"))
  assert_true(@capacity_planner.update(deselected, Prepare).error is Some(_))
  assert_eq(
    @capacity_planner.update(initial, Prepare).packet,
    @capacity_planner.update(initial, Prepare).packet,
  )
}

///|
test "hostile source labels are escaped and exported data remains exact" {
  let evidence = {
    ..fixture_evidence(),
    source_ref: "<script>alert('x')</script>",
  }
  let imported = @capacity_planner.update(
    @capacity_planner.update(
      authored(),
      ImportTextChanged(ToJson::to_json([evidence]).stringify()),
    ),
    ImportEvidence,
  )
  let prepared = @capacity_planner.update(imported, Prepare)
  assert_true(prepared.packet is Some(_))
  let html = render(prepared)
  assert_false(html.contains("<script>alert('x')</script>"))
  assert_true(html.contains("&lt;script&gt;"))
  assert_eq(
    @planning.reopen(prepared.packet.unwrap().export_json()).input.evidence[0].source_ref,
    evidence.source_ref,
  )
}

///|
test "real Rabbita emits the typed local actions without network commands" {
  let messages : Array[@capacity_planner.Message] = []
  let emit : @rabbita.Emit[@capacity_planner.Message] = Emit(message => {
    messages.push(message)
    @rabbita.none
  })
  let _ = @capacity_planner.view(authored(), English, Some(emit))
  // The supplied emitter observes command construction, not browser clicks.
  for
    message in [
      @capacity_planner.Message::ImportEvidence,
      Prepare,
      ReopenPacket,
      Reset,
      ToggleRun("fixture-run-4"),
    ] {
    assert_true(messages.contains(message))
  }
}

///|
test "workbench shows failed counts and exact objective status despite rounded zero" {
  let evidence = fixture_evidence()
  let samples = [ for _ in 0..<1001 => evidence.run.samples[0] ]
  samples[0] = { ..samples[0], failed: true, }
  let evidence = { ..evidence, run: { ..evidence.run, samples, }, }
  let state = @capacity_planner.update(
    @capacity_planner.update(
      authored(),
      ImportTextChanged(ToJson::to_json([evidence]).stringify()),
    ),
    ImportEvidence,
  )
  let state = @capacity_planner.update(state, Prepare)
  assert_true(state.packet.unwrap().choices[0].recommendation.objective_met)
  assert_false(state.packet.unwrap().choices[0].meets_declared_envelope)
  let html = render(state)
  assert_true(html.contains("1/1001 · 0‰ (rounded down)"))
  assert_true(html.contains("Exact-count objective / envelope"))
  assert_true(html.contains("Objective not met / Outside workload envelope"))
  assert_false(html.contains("false / false"))
  assert_true(html.contains("0‰ can include failed samples"))
}
