///|
test "operator Benchmarks route owns the planner and core refresh preserves edits" {
  let current = {
    ..@ui.default_state(),
    route: Benchmarks,
    capacity_planner: @capacity_planner.update(
      @capacity_planner.initial(),
      Edit(MaximumP95, "123"),
    ),
  }
  let merged = merge_loaded_console(current, @ui.default_state())
  assert_true(merged.capacity_planner == current.capacity_planner)
  assert_eq(merged.route, Benchmarks)
  let html = @ui.render(merged)
  assert_true(html.contains("Capacity-plan workbench"))
  assert_true(html.contains("value=\"123\""))
}

///|
test "planner authoring remains local in both normal and demo console modes" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = deferred_read_test_model(Benchmarks)
  for demo_mode in [false, true] {
    let (next, _) = update(
      { ..model, demo_mode, },
      Console(CapacityPlanner(Edit(MinimumConcurrency, "4"))),
      emit,
    )
    assert_eq(next.console.capacity_planner.draft.minimum_concurrency, "4")
    assert_true(next.console_read_groups == model.console_read_groups)
    assert_eq(next.console.loading, model.console.loading)
    let (next, _) = update(next, Console(CapacityPlanner(Prepare)), emit)
    assert_true(next.console.capacity_planner.error is Some(_))
  }
}

///|
test "CSV staging survives console navigation and core refresh without initiating telemetry writes" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = deferred_read_test_model(Benchmarks)
  let (staged, _) = update(
    model,
    Console(CapacityPlanner(CsvTextChanged("raw CSV draft"))),
    emit,
  )
  let (staged, _) = update(
    staged,
    Console(CapacityPlanner(EditCsv(RunId, "external-run"))),
    emit,
  )
  assert_true(staged.console_read_groups == model.console_read_groups)
  let (away, _) = update(staged, Console(Navigate(Catalog)), emit)
  let (back, _) = update(away, Console(Navigate(Benchmarks)), emit)
  let merged = merge_loaded_console(back.console, @ui.default_state())
  assert_eq(merged.capacity_planner.csv.text, "raw CSV draft")
  assert_eq(merged.capacity_planner.csv.run_id, "external-run")
}
