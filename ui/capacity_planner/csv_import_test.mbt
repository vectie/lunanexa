///|
fn csv_text_fixture() -> String {
  "elapsed,queue_ms,load_ms,first_output_ms,output_units,duration_ms,utilization_per_mille,failed,notes\n20,1,0,4,100,100,500,false,\"观察,<script>\"\n30,2,0,5,100,100,600,true,slow"
}

///|
fn csv_authored(state : @capacity_planner.State) -> @capacity_planner.State {
  let mut state = @capacity_planner.update(
    state,
    CsvTextChanged(csv_text_fixture()),
  )
  state = @capacity_planner.update(state, CsvPreview)
  state = @capacity_planner.update(state, CsvMap(0, "elapsed"))
  for
    (field, value) in [
      (@capacity_planner.CsvField::RunId, "csv-observations"),
      (Profile, "text-short-v1"),
      (ModelDigest, "sha256:model-fixture"),
      (RuntimeDigest, "sha256:runtime-fixture"),
      (HardwareProfile, "fixture-host-v1"),
      (Concurrency, "4"),
    ] {
    state = @capacity_planner.update(state, EditCsv(field, value))
  }
  for
    (field, value) in [
      (@capacity_planner.MetadataField::Origin, "SyntheticFixture"),
      (SourceRef, "fixture:external-csv"),
      (WorkloadRef, "fixture:workload-revision-1"),
      (OutputUnit, "tokens"),
      (MemoryTotal, "16000"),
      (MemoryPeak, "12000"),
    ] {
    state = @capacity_planner.update(state, EditCsvMetadata(field, value))
  }
  state
}

///|
test "CSV mapped import enters editable sources and existing prepare reopen explore and compare" {
  let staged = csv_authored(@capacity_planner.initial())
  assert_true(staged.sources.is_empty())
  let added = @capacity_planner.update(staged, AddCsv)
  assert_true(added.csv.error is None)
  assert_eq(added.sources.length(), 1)
  assert_eq(added.sources[0].run.samples.length(), 2)
  assert_eq(added.selected, ["csv-observations"])
  assert_eq(added.draft.profile, "text-short-v1")
  assert_eq(added.draft.maximum_p95, "")
  let spec = @planning.import_csv_spec(added.csv.mapping_json.unwrap())
  assert_eq(@planning.import_csv(csv_text_fixture(), spec), added.sources[0])
  let mut state = added
  for
    (field, value) in [
      (@capacity_planner.Field::MinimumConcurrency, "4"),
      (MaximumP95, "35"),
      (MinimumThroughput, "900"),
      (MaximumFailures, "0"),
    ] {
    state = @capacity_planner.update(state, Edit(field, value))
  }
  state = @capacity_planner.update(state, Prepare)
  let packet = state.packet.unwrap()
  assert_false(packet.choices[0].meets_declared_envelope)
  assert_eq(@planning.observed_failure_count(packet.input.evidence[0]), 1)
  let reopened = @capacity_planner.update(
    @capacity_planner.initial(),
    ReopenPacketFile(packet.export_json()),
  )
  assert_eq(reopened.packet, state.packet)
  let exploring = @capacity_planner.update(
    @capacity_planner.update(state, ExploreRun("csv-observations")),
    ExportSamples,
  )
  assert_true(
    exploring.explorer.export_csv.unwrap().contains("csv-observations"),
  )
  let comparing = @capacity_planner.update(
    @capacity_planner.update(state, ChangeCaptureBaseline),
    ChangeCompare,
  )
  assert_true(comparing.change_analysis.report is Some(_))
}

///|
test "CSV staging and failed imports retain prepared comparison then add replaces only named source" {
  let prepared = @capacity_planner.update(authored(), Prepare)
  let staged = csv_authored(prepared)
  assert_eq(staged.packet, prepared.packet)
  let failed = @capacity_planner.update(
    @capacity_planner.update(staged, CsvMap(0, "missing")),
    AddCsv,
  )
  assert_true(failed.csv.error is Some(_))
  assert_eq(failed.packet, prepared.packet)
  assert_eq(failed.sources, prepared.sources)
  let added = @capacity_planner.update(staged, AddCsv)
  assert_true(added.packet is None)
  assert_eq(added.sources.length(), 3)
  assert_true(added.selected.contains("csv-observations"))
  let added_again = @capacity_planner.update(added, AddCsv)
  assert_eq(added_again.sources, added.sources)
  assert_eq(added_again.selected, added.selected)
  let replacement = @capacity_planner.update(
    @capacity_planner.update(added, EditCsv(RunId, "fixture-run-4")),
    AddCsv,
  )
  assert_eq(replacement.sources.length(), 3)
  assert_eq(replacement.sources[2].run.samples.length(), 2)
  assert_eq(replacement.sources[0].run.run_id, "fixture-run-8")
}

///|
test "CSV requires explicit provenance and bounds total comparison sources" {
  let staged = csv_authored(@capacity_planner.initial())
  let missing = @capacity_planner.update(
    @capacity_planner.update(staged, EditCsvMetadata(Origin, "")),
    AddCsv,
  )
  assert_true(missing.csv.error is Some(_))
  assert_true(missing.sources.is_empty())
  let mut many = staged
  for index in 0..<8 {
    many = @capacity_planner.update(
      @capacity_planner.update(many, EditCsv(RunId, "run-\{index}")),
      AddCsv,
    )
  }
  assert_eq(many.sources.length(), 8)
  let full = @capacity_planner.update(
    @capacity_planner.update(many, EditCsv(RunId, "run-9")),
    AddCsv,
  )
  assert_true(full.csv.error is Some(_))
  assert_eq(full.sources, many.sources)
  let replaced = @capacity_planner.update(
    @capacity_planner.update(full, EditCsv(RunId, "run-0")),
    AddCsv,
  )
  assert_true(replaced.csv.error is None)
  assert_eq(replaced.sources.length(), 8)
}

///|
test "CSV file completion is fenced by repeated selection edits clear and reset" {
  let pending = @capacity_planner.update(csv_authored(authored()), ReadCsvFile)
  let accepted = @capacity_planner.update(
    pending,
    CsvFileRead(pending.revision, Ok(csv_text_fixture())),
  )
  assert_true(accepted.csv.preview is Some(_))
  assert_false(accepted.reading_file)
  for
    message in [
      @capacity_planner.Message::ReadCsvFile,
      ClearCsv,
      Reset,
      EditCsv(RunId, "newer"),
      CsvTextChanged("newer"),
      ReadFile(true),
    ] {
    let newer = @capacity_planner.update(pending, message)
    assert_true(
      @capacity_planner.update(
        newer,
        CsvFileRead(pending.revision, Ok(csv_text_fixture())),
      ) ==
      newer,
    )
  }
  let failed = @capacity_planner.update(
    pending,
    CsvFileRead(pending.revision, Err("cannot read")),
  )
  assert_eq(failed.csv.text, pending.csv.text)
  assert_eq(failed.sources, pending.sources)
  assert_true(failed.csv.error is Some(_))
  let bad = @capacity_planner.update(
    pending,
    CsvFileRead(pending.revision, Ok("invalid")),
  )
  assert_eq(bad.csv.text, pending.csv.text)
  assert_true(bad.csv.error is Some(_))
}

///|
test "CSV clear preserves captured work while reset removes staging and mapping download follows edits" {
  let added = @capacity_planner.update(csv_authored(authored()), AddCsv)
  assert_true(added.csv.mapping_json is Some(_))
  for
    message in [
      @capacity_planner.Message::CsvMap(0, "elapsed"),
      EditCsv(RunId, "new"),
      EditCsvMetadata(SourceRef, "new"),
      CsvTextChanged(csv_text_fixture()),
    ] {
    let edited = @capacity_planner.update(added, message)
    assert_true(edited.csv.mapping_json is None)
    assert_eq(edited.sources, added.sources)
  }
  let cleared = @capacity_planner.update(added, ClearCsv)
  assert_eq(cleared.sources, added.sources)
  assert_eq(cleared.csv.text, "")
  let reset = @capacity_planner.update(added, Reset)
  assert_eq(reset.csv.text, "")
  assert_true(reset.sources.is_empty())
}

///|
test "compiled CSV view renders mapping preview warnings exports and escapes raw cells" {
  let state = @capacity_planner.update(csv_authored(authored()), AddCsv)
  let html = render(state)
  for
    required in [
      "Import raw benchmark CSV observations", "CSV preview, before metric conversion",
      "Map observed metrics", "Add / replace CSV run", "Clear CSV staging", "Download CSV import mapping JSON",
      "1 means failed", "2 sample records", "&lt;script&gt;",
    ] {
    assert_true(html.contains(required), msg=required)
  }
  assert_false(html.contains("<script>"))
  assert_false(html.contains("id=\"capacity-csv-Run ID\""))
  let changed = @capacity_planner.update(
    state,
    CsvTextChanged(csv_text_fixture()),
  )
  assert_false(render(changed).contains(">Add / replace CSV run</button>"))
}
