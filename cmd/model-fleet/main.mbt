///|
fn read_input(path : String, maximum : Int) -> String raise {
  // x/fs reads the selected file before checking this bound. This is not a
  // streaming acquisition limit; use only ordinary bounded local files.
  let bytes = @fs.read_file_to_bytes(path)
  if bytes.length() > maximum {
    fail("input exceeds supported byte size")
  }
  @utf8.decode(bytes)
}

///|
fn execute() -> String raise {
  let args = @env.args()
  guard args.length() == 6 &&
    ["json", "matrix"].contains(args[1]) &&
    ["registry", "draft"].contains(args[2]) else {
    fail(
      "usage: lunanexa-model-fleet json|matrix registry|draft MODELS.json NODES.json QUERY.json",
    )
  }
  let query = @model_fleet.import_query(read_input(args[5], 16384))
  let models = @model_fleet.import_models(
    read_input(args[3], 16777216),
    args[2],
  )
  let nodes = @fleet.import_nodes(read_input(args[4], 16777216))
  let report = @model_fleet.explore(models, nodes, query)
  if args[1] == "json" {
    report.json_text() + "\n"
  } else {
    report.matrix_csv()
  }
}

///|
/// The synchronous x/fs API has no standard-error writer. This borrowed-byte
/// adapter only writes a diagnostic to the process's existing stderr stream.
#borrow(bytes)
extern "C" fn write_diagnostic(bytes : Bytes) -> Unit = "lunanexa_model_fleet_diagnostic"

///|
fn main {
  let output = execute() catch {
    error => {
      write_diagnostic(@utf8.encode("lunanexa-model-fleet: \{error}\n"))
      @sys.exit(1)
      return
    }
  }
  // Both serializers end in LF; println supplies exactly that final byte.
  println(output[:output.length() - 1])
}
