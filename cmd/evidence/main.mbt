///|
async fn write_atomic(path : String, document : String) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    document,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
async fn load_telemetry(path : String) -> @telemetry.TelemetrySnapshot {
  @json.from_json(@json.parse(@fs.read_file(path).text()))
}

///|
async fn export_bundle(
  telemetry_path : String,
  input_path : String,
  output_path : String,
) -> Unit {
  let snapshot = load_telemetry(telemetry_path)
  let input : @telemetry.EvidenceBundleInput = @json.from_json(
    @json.parse(@fs.read_file(input_path).text()),
  )
  let bundle = @telemetry.build_evidence_bundle(
    snapshot.benchmark_summaries,
    input,
  )
  write_atomic(output_path, bundle.export_json())
  println(
    if bundle.release_ready() {
      "evidence bundle exported: release-ready"
    } else {
      "evidence bundle exported: acceptance incomplete"
    },
  )
}

///|
async fn export_recommendation(
  telemetry_path : String,
  input_path : String,
  output_path : String,
) -> Unit {
  let snapshot = load_telemetry(telemetry_path)
  let input : @telemetry.RecommendationInput = @json.from_json(
    @json.parse(@fs.read_file(input_path).text()),
  )
  let recommendation = @telemetry.build_recommendation(
    snapshot.benchmark_summaries,
    input,
  )
  write_atomic(output_path, recommendation.to_json().stringify(indent=2))
  println("capacity and service-objective recommendation exported")
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 5 && args[1] == "bundle" {
    export_bundle(args[2], args[3], args[4])
  } else if args.length() == 5 && args[1] == "recommend" {
    export_recommendation(args[2], args[3], args[4])
  } else {
    raise Failure::Failure(
      "usage: lunanexa-evidence bundle TELEMETRY.json INPUT.json OUTPUT.json | recommend TELEMETRY.json INPUT.json OUTPUT.json",
    )
  }
}
