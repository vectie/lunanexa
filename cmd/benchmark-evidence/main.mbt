///|
/// Bounded offline export of an exact recorded observation. No measurement,
/// provider request, telemetry mutation or provenance inference is performed.
async fn main {
  let args = @env.args()
  guard args.length() == 9 else {
    fail(
      "usage: lunanexa-benchmark-evidence TELEMETRY.json RUN_ID SyntheticFixture|LocalObservation SOURCE_REF WORKLOAD_REF OUTPUT_UNIT MEASURED_TOTAL_MIB MEASURED_PEAK_MIB",
    )
  }
  let file = @fs.open(args[1], mode=ReadOnly)
  defer file.close()
  let size = file.size()
  if size > 33554432L {
    fail("telemetry source exceeds the 32 MiB offline export limit")
  }
  let bytes = file.read_exactly(size.to_int())
  if file.read_some(max_len=1) is Some(_) {
    fail("telemetry source changed while reading")
  }
  let json = @json.parse(@utf8.decode(bytes))
  guard json
    is {
      "schema_version": String("lunanexa.telemetry.v1"),
      "benchmark_runs": runs_json,
      ..
    } else {
    fail("expected a lunanexa.telemetry.v1 snapshot with exact benchmark_runs")
  }
  let runs : Array[@benchmark.BenchmarkRun] = @json.from_json(runs_json)
  if ToJson::to_json(runs) != runs_json {
    fail("recorded observations contain unsupported fields")
  }
  let seen : Map[String, Bool] = Map([])
  for run in runs {
    if seen.contains(run.run_id) {
      fail("duplicate recorded run ID")
    }
    seen[run.run_id] = true
  }
  guard runs.iter().find_first(run => run.run_id == args[2]) is Some(run) else {
    fail("selected run is absent from the recorded snapshot")
  }
  let origin : @planning.Origin = match args[3] {
    "SyntheticFixture" => SyntheticFixture
    "LocalObservation" => LocalObservation
    _ => fail("provenance must be explicitly declared")
  }
  let evidence = @planning.recorded_evidence(
    run,
    @planning.snapshot_digest(runs),
    {
      origin,
      source_ref: args[4],
      workload_ref: args[5],
      output_unit: args[6],
      memory_total_mib: @string.parse_int(args[7]),
      memory_peak_mib: @string.parse_int(args[8]),
    },
  )
  println(ToJson::to_json([evidence]).stringify(indent=2))
}
