///|
fn csv_spec_fixture() -> @planning.CsvImportSpec {
  let e = evidence()
  {
    schema_version: 1,
    run_id: e.run.run_id,
    profile: e.run.profile,
    model_digest: e.run.model_digest,
    runtime_digest: e.run.runtime_digest,
    hardware_profile: e.run.hardware_profile,
    kind: e.run.kind,
    concurrency: e.run.concurrency,
    metadata: {
      origin: e.origin,
      source_ref: e.source_ref,
      workload_ref: e.workload_ref,
      output_unit: e.output_unit,
      memory_total_mib: e.memory_total_mib,
      memory_peak_mib: e.memory_peak_mib,
    },
    columns: {
      latency_ms: "elapsed",
      queue_ms: "queue",
      load_ms: "load",
      first_output_ms: "ttft",
      output_units: "tokens",
      duration_ms: "duration",
      utilization_per_mille: "busy",
      failed: "error",
    },
  }
}

///|
fn raw_csv_fixture() -> String {
  "elapsed,queue,load,ttft,tokens,duration,busy,error,ignored\r\n10,1,0,4,100,100,500,false,a\r\n20,1,0,4,100,100,500,0,b\r\n30,1,0,4,100,100,500,FALSE,c\r\n"
}

///|
test "mapped CSV retains every observation and uses unchanged packet and change analysis" {
  let spec = csv_spec_fixture()
  let imported = @planning.import_csv(raw_csv_fixture(), spec)
  assert_eq(imported, evidence())
  let packet = @planning.prepare({ ..fixture_input(), evidence: [imported], })
  assert_eq(packet, @planning.prepare(fixture_input()))
  assert_eq(@planning.reopen(packet.export_json()), packet)
  assert_true(packet.summary_csv().contains(imported.run.run_id))
  assert_true(
    @planning.samples_csv(imported, false, RecordedOrder).contains("latency_ms"),
  )
  let change = @planning.compare_packet_runs(
    packet,
    imported.run.run_id,
    packet,
    imported.run.run_id,
  )
  assert_eq(change.metrics[0].delta, 0)
  assert_true(
    @planning.import_csv_spec(ToJson::to_json(spec).stringify()) == spec,
  )
  let columns : @planning.CsvColumns = {
    latency_ms: "latency_ms",
    queue_ms: "queue_ms",
    load_ms: "load_ms",
    first_output_ms: "first_output_ms",
    output_units: "output_units",
    duration_ms: "duration_ms",
    utilization_per_mille: "utilization_per_mille",
    failed: "failed",
  }
  assert_eq(
    @planning.import_csv(
      @planning.samples_csv(imported, false, RecordedOrder),
      { ..spec, columns, },
    ),
    imported,
  )
}

///|
test "CSV accepts BOM unicode escaped quotes multiline fields and both newline styles" {
  let csv = "\uFEFF elapsed ,queue,load,ttft,tokens,duration,busy,error,\"note,观察\"\r\n\"10\", 1 ,0,4,100,100,500,false,\"line one\n\"\"line two\"\"😀\""
  let preview = @planning.preview_csv(csv)
  assert_eq(preview.headers[0], "elapsed")
  assert_eq(preview.headers[8], "note,观察")
  assert_eq(preview.first_rows[0][8], "line one\n\"line two\"😀")
  assert_eq(
    @planning.import_csv(csv, csv_spec_fixture()).run.samples[0],
    evidence().run.samples[0],
  )
  assert_eq(
    @planning.import_csv(
      raw_csv_fixture().replace(old="\r\n", new="\n"),
      csv_spec_fixture(),
    ),
    evidence(),
  )
}

///|
test "CSV structural errors never skip records or make partial evidence" {
  for
    text in [
      "", "elapsed,queue", "a,a\n1,2", "a, a \n1,2", ",b\n1,2", "a,b\n1", "a,b\n1,2,3",
      "a,b\n1,2\n\n", "a,b\n\"1\"x,2", "a,b\n1\"x,2", "a,b\n\"unterminated,2",
    ] {
    assert_true(csv_bad_preview(text), msg=text)
  }
}

///|
test "CSV rejects wrong units missing values overflow and ambiguous mappings with location" {
  let spec = csv_spec_fixture()
  for cell in ["", "-1", "1.5", "1e2", "NaN", "0x10", "+1", "2147483648"] {
    let csv = "elapsed,queue,load,ttft,tokens,duration,busy,error\n\{cell},1,0,4,100,100,500,false"
    try @planning.import_csv(csv, spec) catch {
      error =>
        assert_true("\{Repr(error)}".contains("record 2, column elapsed"))
    } noraise {
      _ => fail("invalid metric accepted")
    }
  }
  for
    text in [
      raw_csv_fixture().replace(old="false", new="success"),
      raw_csv_fixture().replace(old="100,100,500", new="100,0,500"),
      raw_csv_fixture().replace(old="100,100,500", new="100,100,1001"),
    ] {
    assert_true(csv_bad(text, spec))
  }
  for
    columns in [
      { ..spec.columns, latency_ms: "missing", },
      { ..spec.columns, queue_ms: "elapsed", },
      { ..spec.columns, failed: "", },
    ] {
    assert_true(csv_bad(raw_csv_fixture(), { ..spec, columns, }))
  }
}

///|
test "CSV enforces run context summary bounds strict version and unknown fields" {
  let spec = csv_spec_fixture()
  for
    invalid in [
      { ..spec, schema_version: 2, },
      { ..spec, run_id: "", },
      { ..spec, concurrency: 0, },
      { ..spec, metadata: { ..spec.metadata, source_ref: "", }, },
      { ..spec, metadata: { ..spec.metadata, memory_peak_mib: 17000, }, },
    ] {
    assert_true(csv_bad(raw_csv_fixture(), invalid))
  }
  assert_true(
    csv_bad(
      raw_csv_fixture().replace(old="100,100,500", new="2147484,100,500"),
      spec,
    ),
  )
  let unknown = ToJson::to_json(spec)
    .stringify()
    .replace(old="\"schema_version\":1", new="\"extra\":1,\"schema_version\":1")
  assert_true(csv_bad_spec(unknown))
  let unknown = ToJson::to_json(spec)
    .stringify()
    .replace(old="\"latency_ms\":", new="\"extra\":1,\"latency_ms\":")
  assert_true(csv_bad_spec(unknown))
}

///|
test "CSV accepts exact sample limit and bounds preview columns and text" {
  let header = "elapsed,queue,load,ttft,tokens,duration,busy,error\n"
  let row = "10,1,0,4,100,100,500,0\n"
  let csv = header + row.repeat(10000)
  assert_eq(
    @planning.import_csv(csv, csv_spec_fixture()).run.samples.length(),
    10000,
  )
  let preview = @planning.preview_csv(csv)
  assert_eq(preview.sample_count, 10000)
  assert_eq(preview.first_rows.length(), 5)
  assert_true(csv_bad_preview(csv + row))
  assert_true(csv_bad_preview("a".repeat(4194305)))
  let headers = [ for index in 0..<129 => "h\{index}" ].join(",")
  assert_true(csv_bad_preview(headers + "\n" + headers))
}

///|
test "CSV failure flags preserve exact failure evidence rather than success labels" {
  let csv = raw_csv_fixture()
    .replace(old="false", new="true")
    .replace(old=",0,b", new=",1,b")
    .replace(old="FALSE", new="TRUE")
  let imported = @planning.import_csv(csv, csv_spec_fixture())
  assert_eq(@planning.observed_failure_count(imported), 3)
  let packet = @planning.prepare({ ..fixture_input(), evidence: [imported], })
  assert_false(packet.choices[0].meets_declared_envelope)
}

///|
fn csv_bad_preview(text : String) -> Bool {
  try {
    ignore(@planning.preview_csv(text))
    false
  } catch {
    _ => true
  }
}

///|
fn csv_bad_spec(text : String) -> Bool {
  try {
    ignore(@planning.import_csv_spec(text))
    false
  } catch {
    _ => true
  }
}

///|
fn csv_bad(text : String, spec : @planning.CsvImportSpec) -> Bool {
  try {
    ignore(@planning.import_csv(text, spec))
    false
  } catch {
    _ => true
  }
}
