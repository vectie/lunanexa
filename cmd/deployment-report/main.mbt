///|
async fn read_input(path : String, maximum : Int64) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  if size > maximum {
    fail("input file exceeds supported size")
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
  guard args.length() == 5 &&
    ["deployments", "placements", "json"].contains(args[1]) else {
    fail(
      "usage: lunanexa-deployment-report deployments|placements|json OPERATIONS.json NODES.json QUERY.json",
    )
  }
  let query = @deployment_report.import_query(read_input(args[4], 16384L))
  let operations = @deployment_report.import_operations(
    read_input(args[2], 16777216L),
  )
  let nodes = @deployment_report.import_nodes(read_input(args[3], 16777216L))
  let report = @deployment_report.explore(operations, nodes, query)
  let output = match args[1] {
    "deployments" => report.deployments_csv()
    "placements" => report.placements_csv()
    _ => report.json_text() + "\n"
  }
  @stdio.stdout.write(output)
}

///|
async fn main {
  execute() catch {
    @deployment_report.InvalidInput(message) => {
      @stdio.stderr.write("lunanexa-deployment-report: " + message + "\n")
      @sys.exit(1)
    }
    error => {
      @stdio.stderr.write("lunanexa-deployment-report: \{error}\n")
      @sys.exit(1)
    }
  }
}
