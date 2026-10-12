///|
fn group_context(id : String) -> @planning.CsvRunContext {
  let single = csv_spec_fixture()
  {
    run_id: id,
    profile: single.profile,
    model_digest: single.model_digest,
    runtime_digest: single.runtime_digest,
    hardware_profile: single.hardware_profile,
    kind: single.kind,
    concurrency: single.concurrency,
    metadata: { ..single.metadata, source_ref: "fixture:" + id, },
  }
}

///|
fn group_spec() -> @planning.GroupedCsvImportSpec {
  {
    schema_version: 1,
    run_id_column: "trial",
    columns: csv_spec_fixture().columns,
    runs: [group_context("alpha"), group_context("beta")],
  }
}

///|
fn group_csv() -> String {
  "trial,elapsed,queue,load,ttft,tokens,duration,busy,error,note\r\nbeta,80,2,0,4,20,100,600,true,first\r\nalpha,10,1,0,4,100,100,500,false,second\r\nbeta,90,3,0,5,20,100,700,false,third\r\nalpha,30,1,0,4,100,100,500,false,last\r\n"
}

///|
fn rejects_group(csv : String, spec : @planning.GroupedCsvImportSpec) -> Bool {
  try {
    ignore(@planning.import_grouped_csv(csv, spec))
    false
  } catch {
    _ => true
  }
}

///|
test "grouped CSV interleaving preserves per-run samples context and independent results" {
  let spec = group_spec()
  let before = ToJson::to_json(spec).stringify()
  let runs = @planning.import_grouped_csv(group_csv(), spec)
  assert_eq(runs.map(e => e.run.run_id), ["alpha", "beta"])
  assert_eq(runs[0].run.samples.map(s => s.latency_ms), [10, 30])
  assert_eq(runs[1].run.samples.map(s => s.latency_ms), [80, 90])
  assert_eq(runs.map(e => e.source_ref), ["fixture:alpha", "fixture:beta"])
  assert_eq(runs.map(e => @planning.observed_failure_count(e)), [0, 1])
  assert_eq(@planning.import_evidence(ToJson::to_json(runs).stringify()), runs)
  let packet = @planning.prepare({ ..fixture_input(), evidence: runs, })
  assert_eq(@planning.reopen(packet.export_json()), packet)
  assert_eq(packet.choices.length(), 2)
  assert_true(packet.choices[0].meets_declared_envelope)
  assert_false(packet.choices[1].meets_declared_envelope)
  assert_true(packet.summary_csv().contains("alpha"))
  assert_true(packet.summary_csv().contains("beta"))
  assert_eq(ToJson::to_json(spec).stringify(), before)
  assert_eq(@planning.import_grouped_csv(group_csv(), spec), runs)
}

///|
test "group keys are exact CSV text including quoted commas quotes newlines and Unicode" {
  let spec = group_spec()
  let key = "组,\"A\"\n😀"
  let csv = "\uFEFFtrial,elapsed,queue,load,ttft,tokens,duration,busy,error\r\n\"组,\"\"A\"\"\n😀\",10,1,0,4,100,100,500,0\r\nbeta,20,1,0,4,100,100,500,1\r\n"
  let runs = @planning.import_grouped_csv(csv, {
    ..spec,
    runs: [group_context(key), group_context("beta")],
  })
  assert_eq(runs[0].run.run_id, key)
  assert_eq(runs[0].run.samples.length(), 1)
  assert_eq(runs[1].run.samples.length(), 1)
  for invalid in ["", "ALPHA", " alpha", "alpha ", "unknown"] {
    assert_true(
      rejects_group(group_csv().replace(old="alpha,", new=invalid + ","), spec),
    )
  }
}

///|
test "group contexts must exactly cover every observed run without aliasing or extras" {
  let spec = group_spec()
  for
    runs in [
      [],
      [group_context("alpha")],
      [group_context("alpha"), group_context("alpha")],
      [group_context("alpha"), group_context("beta"), group_context("unused")],
      [group_context(" alpha"), group_context("beta")],
      [group_context(""), group_context("beta")],
      [
        for i in 0..<9 => group_context("r\{i}")
      ],
    ] {
    assert_true(rejects_group(group_csv(), { ..spec, runs, }))
  }
  for
    invalid in [
      { ..spec, schema_version: 2, },
      { ..spec, run_id_column: "absent", },
      { ..spec, run_id_column: "elapsed", },
      { ..spec, columns: { ..spec.columns, queue_ms: "elapsed", }, },
      { ..spec, columns: { ..spec.columns, failed: "absent", }, },
    ] {
    assert_true(rejects_group(group_csv(), invalid))
  }
}

///|
test "grouped mappings reject wrong versions unknown root nested and run fields" {
  let spec = group_spec()
  let json = ToJson::to_json(spec).stringify()
  assert_true(@planning.import_grouped_csv_spec(json) == spec)
  for
    invalid in [
      "{}",
      "[]",
      "null",
      "broken",
      "x".repeat(65537),
      json.replace(old="\"schema_version\":1", new="\"schema_version\":2"),
      json.replace(
        old="\"schema_version\":1",
        new="\"extra\":0,\"schema_version\":1",
      ),
      json.replace(old="\"run_id\":", new="\"extra\":0,\"run_id\":"),
      json.replace(old="\"latency_ms\":", new="\"extra\":0,\"latency_ms\":"),
      json.replace(old="\"origin\":", new="\"extra\":0,\"origin\":"),
    ] {
    try @planning.import_grouped_csv_spec(invalid) catch {
      _ => ()
    } noraise {
      _ => fail("invalid grouped mapping accepted")
    }
  }
}

///|
test "every grouped record validates and metric errors retain global logical record number" {
  let spec = group_spec()
  for cell in ["", "-1", "2.5", "1e2", "2147483648"] {
    let bad = group_csv().replace(old="alpha,30,", new="alpha,\{cell},")
    try @planning.import_grouped_csv(bad, spec) catch {
      error =>
        assert_true("\{Repr(error)}".contains("record 5, column elapsed"))
    } noraise {
      _ => fail("bad final record accepted")
    }
  }
  for
    bad in [
      group_csv() + "\n",
      group_csv().replace(old="beta,90,3", new="beta,90"),
      group_csv().replace(old="first", new="\"unclosed"),
      group_csv().replace(old="false", new="success"),
      group_csv().replace(old="100,500", new="0,500"),
      group_csv().replace(old="100,500", new="100,1001"),
    ] {
    assert_true(rejects_group(bad, spec))
  }
  let beta = group_context("beta")
  assert_true(
    rejects_group(group_csv(), {
      ..spec,
      runs: [
        group_context("alpha"),
        { ..beta, metadata: { ..beta.metadata, memory_peak_mib: 0, }, },
      ],
    }),
  )
}

///|
test "grouped CSV accepts eight runs and exact total row limit without expanding legacy limits" {
  let header = "trial,elapsed,queue,load,ttft,tokens,duration,busy,error\n"
  let row = ",10,1,0,4,1,100,500,0\n"
  let spec = group_spec()
  let eight = { ..spec, runs: [ for i in 0..<8 => group_context("r\{i}") ], }
  let csv = header + [ for i in 0..<8 => "r\{i}" + row ].join("")
  assert_eq(@planning.import_grouped_csv(csv, eight).length(), 8)
  let csv = header + ("alpha" + row + "beta" + row).repeat(5000)
  let runs = @planning.import_grouped_csv(csv, spec)
  assert_eq(runs.map(e => e.run.samples.length()), [5000, 5000])
  assert_true(rejects_group(csv + "alpha" + row, spec))
  assert_true(rejects_group("x".repeat(4194305), spec))
}

///|
test "grouping never disguises incompatible contexts as a comparable or pooled run" {
  let spec = group_spec()
  let beta = group_context("beta")
  let runs = @planning.import_grouped_csv(group_csv(), {
    ..spec,
    runs: [
      group_context("alpha"),
      { ..beta, runtime_digest: "different-runtime", },
    ],
  })
  assert_eq(runs[1].run.runtime_digest, "different-runtime")
  try @planning.prepare({ ..fixture_input(), evidence: runs, }) catch {
    _ => ()
  } noraise {
    _ => fail("incompatible grouped evidence accepted into one capacity plan")
  }
}
