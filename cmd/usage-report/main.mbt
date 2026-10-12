///|
async fn read_input(path : String, maximum : Int64) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  if size > maximum {
    fail("input file exceeds the supported size")
  }
  let bytes = file.read_exactly(size.to_int())
  if file.read_some(max_len=1) is Some(_) {
    fail("input changed while reading")
  }
  @utf8.decode(bytes)
}

///|
async fn execute() -> Unit {
  let args = @env.args()
  if args.length() >= 2 &&
    (
      args[1] == "correlate-json" ||
      args[1] == "correlate-rows" ||
      args[1] == "correlate-summary"
    ) {
    guard args.length() == 5 else {
      fail(
        "usage: lunanexa-usage-report correlate-json|correlate-rows|correlate-summary SNAPSHOT.json QUERY.json LINKS.json; analyst-supplied opaque references, no live receipt or payment verification",
      )
    }
    let query = @commercial.import_usage_query(read_input(args[3], 16384L))
    let snapshot = @commercial.import_usage_snapshot(
      read_input(args[2], 16777216L),
    )
    let manifest = @commercial.import_usage_correlation_manifest(
      read_input(args[4], 1048576L),
    )
    let report = @commercial.correlate_usage(snapshot, query, manifest)
    @stdio.stdout.write(
      match args[1] {
        "correlate-rows" => report.rows_csv()
        "correlate-summary" => report.summary_csv()
        _ => report.json_text() + "\n"
      },
    )
    return
  }
  if args.length() >= 2 &&
    (args[1] == "timeline-json" || args[1] == "timeline-summary") {
    guard args.length() == 5 else {
      fail(
        "usage: lunanexa-usage-report timeline-json|timeline-summary SNAPSHOT.json QUERY.json BUCKET_MILLISECONDS; whole records assigned once by service start (prewindow starts clamp to first bucket), no proration",
      )
    }
    let width = @string.parse_int64(args[4])
    let query = @commercial.import_usage_query(read_input(args[3], 16384L))
    let snapshot = @commercial.import_usage_snapshot(
      read_input(args[2], 16777216L),
    )
    let report = @commercial.explore_usage_timeline(snapshot, query, width)
    @stdio.stdout.write(
      if args[1] == "timeline-json" {
        report.json_text() + "\n"
      } else {
        report.summary_csv()
      },
    )
    return
  }
  if args.length() >= 2 &&
    (
      args[1] == "combine-json" ||
      args[1] == "combine-summary" ||
      args[1] == "combine-rows"
    ) {
    guard args.length() >= 4 && args.length() <= 11 else {
      fail(
        "usage: lunanexa-usage-report combine-json|combine-summary|combine-rows QUERY.json SNAPSHOT.json [SNAPSHOT.json ...] (1 to 8 snapshots)",
      )
    }
    let query = @commercial.import_usage_query(read_input(args[2], 16384L))
    let snapshots : Array[@commercial.CommercialSnapshot] = []
    for index = 3; index < args.length(); index = index + 1 {
      snapshots.push(
        @commercial.import_usage_snapshot(read_input(args[index], 16777216L)),
      )
    }
    let combined = @commercial.consolidate_usage(snapshots, query)
    @stdio.stdout.write(
      match args[1] {
        "combine-summary" => combined.summary_csv()
        "combine-rows" => combined.rows_csv()
        _ => combined.json_text() + "\n"
      },
    )
    return
  }
  if args.length() >= 2 &&
    (args[1] == "changes-json" || args[1] == "changes-rows") {
    guard args.length() == 5 else {
      fail(
        "usage: lunanexa-usage-report changes-json|changes-rows BASELINE.json CANDIDATE.json QUERY.json",
      )
    }
    let query = @commercial.import_usage_query(read_input(args[4], 16384L))
    let baseline = @commercial.import_usage_snapshot(
      read_input(args[2], 16777216L),
    )
    let candidate = @commercial.import_usage_snapshot(
      read_input(args[3], 16777216L),
    )
    let changes = @commercial.compare_usage_snapshots(
      baseline, candidate, query,
    )
    @stdio.stdout.write(
      if args[1] == "changes-json" {
        changes.json_text() + "\n"
      } else {
        changes.rows_csv()
      },
    )
    return
  }
  let what_if = args.length() == 5 &&
    (
      args[1] == "price-summary" ||
      args[1] == "price-rows" ||
      args[1] == "price-json"
    )
  guard what_if ||
    (
      args.length() == 4 &&
      (args[1] == "summary" || args[1] == "rows" || args[1] == "json")
    ) else {
    fail(
      "usage: lunanexa-usage-report combine-json|combine-summary|combine-rows QUERY.json SNAPSHOT.json [SNAPSHOT.json ...]; or changes-json|changes-rows BASELINE.json CANDIDATE.json QUERY.json; or summary|rows|json SNAPSHOT.json QUERY.json; or price-summary|price-rows|price-json SNAPSHOT.json QUERY.json SCENARIO.json",
    )
  }
  let query = @commercial.import_usage_query(read_input(args[3], 16384L))
  let snapshot = @commercial.import_usage_snapshot(
    read_input(args[2], 16777216L),
  )
  let output = if what_if {
    let scenario = @commercial.import_usage_price_scenario(
      read_input(args[4], 262144L),
    )
    let report = @commercial.explore_usage_prices(snapshot, query, scenario)
    match args[1] {
      "price-summary" => report.summary_csv()
      "price-rows" => report.rows_csv()
      _ => report.json_text() + "\n"
    }
  } else {
    let report = @commercial.explore_usage(snapshot, query)
    match args[1] {
      "summary" => report.summary_csv()
      "rows" => report.rows_csv()
      _ => report.json_text() + "\n"
    }
  }
  @stdio.stdout.write(output)
}

///|
async fn main {
  execute() catch {
    @commercial.InvalidInput(message) => {
      @stdio.stderr.write("lunanexa-usage-report: \{message}\n")
      @sys.exit(1)
    }
    error => {
      @stdio.stderr.write("lunanexa-usage-report: \{error}\n")
      @sys.exit(1)
    }
  }
}
