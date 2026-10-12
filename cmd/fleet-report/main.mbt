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
  guard args.length() == 4 &&
    (
      args[1] == "summary" ||
      args[1] == "nodes" ||
      args[1] == "devices" ||
      args[1] == "json"
    ) else {
    fail(
      "usage: lunanexa-fleet-report summary|nodes|devices|json SNAPSHOT.json QUERY.json",
    )
  }
  let query = @fleet.import_query(read_input(args[3], 16384L))
  let snapshot = @fleet.import_nodes(read_input(args[2], 16777216L))
  let report = @fleet.explore(snapshot, query)
  let output = match args[1] {
    "summary" => report.summary_csv()
    "nodes" => report.nodes_csv()
    "devices" => report.devices_csv()
    _ => report.json_text() + "\n"
  }
  @stdio.stdout.write(output)
}

///|
async fn main {
  execute() catch {
    @fleet.InvalidInput(message) => {
      @stdio.stderr.write("lunanexa-fleet-report: \{message}\n")
      @sys.exit(1)
    }
    error => {
      @stdio.stderr.write("lunanexa-fleet-report: \{error}\n")
      @sys.exit(1)
    }
  }
}
