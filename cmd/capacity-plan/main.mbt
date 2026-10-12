///|
async fn read_input(path : String, analysis? : Bool = false) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  if size > (if analysis { 33554432L } else { 16777216L }) {
    fail(
      "input exceeds the file limit (packets 16 MiB; change analyses 32 MiB)",
    )
  }
  let bytes = file.read_exactly(size.to_int())
  if file.read_some(max_len=1) is Some(_) {
    fail("input changed while reading")
  }
  let text = @utf8.decode(bytes)
  if text.length() > (if analysis { 8388608 } else { 4194304 }) {
    fail(
      "input exceeds the character limit (packets 4 Mi; change analyses 8 Mi)",
    )
  }
  text
}

///|
/// Offline only: no controller client, network, credentials or allocations.
async fn execute() -> Unit {
  let args = @env.args()
  guard args.length() >= 3 && args.length() <= 6 else {
    fail(
      "usage: lunanexa-capacity-plan distribution PACKET.json RUN_ID PLAN.json | distribution-csv PACKET.json RUN_ID PLAN.json | sweep PACKET.json [SWEEP_PLAN.json] | sweep-csv PACKET.json [SWEEP_PLAN.json] | import-grouped-csv OBSERVATIONS.csv GROUPED_MAPPING.json | import-csv OBSERVATIONS.csv MAPPING.json | prepare INPUT.json | reopen PACKET.json | summary PACKET.json | samples PACKET.json RUN_ID [all|failed] [recorded|latency|queue] | analyze BASELINE.json BASELINE_RUN CANDIDATE.json CANDIDATE_RUN | review ANALYSIS.json | reopen-analysis ANALYSIS.json",
    )
  }
  if args[1] == "sweep" || args[1] == "sweep-csv" {
    guard args.length() == 3 || args.length() == 4 else {
      fail(
        "sweep and sweep-csv require a saved packet and an optional sweep plan",
      )
    }
    let packet = @planning.reopen(read_input(args[2]))
    let plan : @planning.SweepPlan = if args.length() == 4 {
      @planning.import_sweep_plan(read_input(args[3]))
    } else {
      { schema_version: 1, targets: [], }
    }
    let output = if args[1] == "sweep" {
      ToJson::to_json(@planning.explore_sweep(packet, plan)).stringify(indent=2) +
      "\n"
    } else {
      @planning.sweep_csv(packet, plan)
    }
    @stdio.stdout.write(output)
    return
  }
  if args[1] == "distribution" || args[1] == "distribution-csv" {
    guard args.length() == 5 else {
      fail(
        "distribution and distribution-csv require PACKET.json RUN_ID DISTRIBUTION_PLAN.json",
      )
    }
    let packet = @planning.reopen(read_input(args[2]))
    let plan = @planning.import_distribution_plan(read_input(args[4]))
    let output = if args[1] == "distribution" {
      ToJson::to_json(@planning.explore_distribution(packet, args[3], plan)).stringify(
        indent=2,
      ) +
      "\n"
    } else {
      @planning.distribution_csv(packet, args[3], plan)
    }
    @stdio.stdout.write(output)
    return
  }
  if args[1] == "import-grouped-csv" {
    guard args.length() == 4 else {
      fail(
        "import-grouped-csv requires CSV observations and a grouped mapping JSON file",
      )
    }
    let spec = @planning.import_grouped_csv_spec(read_input(args[3]))
    let evidence = @planning.import_grouped_csv(read_input(args[2]), spec)
    // Compact output preserves the existing evidence import character bound.
    let output = ToJson::to_json(evidence).stringify()
    @stdio.stdout.write(output)
    return
  }
  if args[1] == "import-csv" {
    guard args.length() == 4 else {
      fail("import-csv requires CSV observations and a mapping JSON file")
    }
    let spec = @planning.import_csv_spec(read_input(args[3]))
    let evidence = @planning.import_csv(read_input(args[2]), spec)
    println(ToJson::to_json([evidence]).stringify(indent=2))
    return
  }
  if args[1] == "analyze" {
    guard args.length() == 6 else {
      fail(
        "analyze requires baseline packet, baseline run, candidate packet and candidate run",
      )
    }
    let baseline = @planning.reopen(read_input(args[2]))
    let candidate = @planning.reopen(read_input(args[4]))
    println(
      @planning.compare_packet_runs(baseline, args[3], candidate, args[5]).export_json(),
    )
    return
  }
  if args[1] != "samples" && args.length() != 3 {
    fail(
      "prepare, reopen, summary, review and reopen-analysis take exactly one input file",
    )
  }
  if args[1] == "review" || args[1] == "reopen-analysis" {
    let report = @planning.reopen_change(read_input(args[2], analysis=true))
    if args[1] == "review" {
      @stdio.stdout.write(report.summary_text())
    } else {
      println(report.export_json())
    }
    return
  }
  let text = read_input(args[2])
  let packet = match args[1] {
    "prepare" => {
      let input = @planning.import_input(text)
      @planning.prepare(input)
    }
    "reopen" | "summary" | "samples" => @planning.reopen(text)
    _ =>
      fail(
        "command must be distribution, distribution-csv, sweep, sweep-csv, import-grouped-csv, import-csv, prepare, reopen, summary, samples, analyze, review or reopen-analysis",
      )
  }
  match args[1] {
    "summary" => @stdio.stdout.write(packet.summary_csv())
    "samples" => {
      guard args.length() >= 4 else { fail("samples requires an exact run ID") }
      guard packet.input.evidence
        .iter()
        .find_first(e => e.run.run_id == args[3])
        is Some(evidence) else {
        fail("selected run is absent from the verified packet")
      }
      let failed_only = match args.get(4).unwrap_or("all") {
        "all" => false
        "failed" => true
        _ => fail("sample filter must be all or failed")
      }
      let order : @planning.SampleOrder = match
        args.get(5).unwrap_or("recorded") {
        "recorded" => RecordedOrder
        "latency" => SlowestLatency
        "queue" => LongestQueue
        _ => fail("sample order must be recorded, latency or queue")
      }
      @stdio.stdout.write(@planning.samples_csv(evidence, failed_only, order))
    }
    _ => println(packet.export_json())
  }
}

///|
async fn main {
  execute() catch {
    @planning.InvalidInput(message) => {
      @stdio.stderr.write("lunanexa-capacity-plan: \{message}\n")
      @sys.exit(1)
    }
    error => {
      @stdio.stderr.write("lunanexa-capacity-plan: \{error}\n")
      @sys.exit(1)
    }
  }
}
