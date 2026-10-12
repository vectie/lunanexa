///|
async fn read_input(path : String, maximum : Int64) -> (String, Int64) {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  if size > maximum {
    fail("input files exceed the supported size")
  }
  let bytes = file.read_exactly(size.to_int())
  if file.read_some(max_len=1) is Some(_) {
    fail("input changed while reading")
  }
  (@utf8.decode(bytes), size)
}

///|
fn source_path(manifest : String, source : String) -> String {
  if source.has_prefix("/") {
    return source
  }
  let parts = manifest.split("/").map(p => p.to_owned()).collect()
  let _ = parts.pop()
  if parts.is_empty() {
    source
  } else {
    parts.join("/") + "/" + source
  }
}

///|
async fn execute() -> Unit {
  let args = @env.args()
  guard args.length() == 4 && ["changes", "summary", "json"].contains(args[1]) else {
    fail(
      "usage: lunanexa-fleet-history changes|summary|json MANIFEST.json QUERY.json",
    )
  }
  let (query_text, _) = read_input(args[3], 16384L)
  let query = @fleet.import_history_query(query_text)
  let (manifest_text, _) = read_input(args[2], 65536L)
  let manifest = @fleet.import_history_manifest(manifest_text)
  let captures : Array[@fleet.HistoryCapture] = []
  let mut remaining_bytes = 33554432L
  for source in manifest.captures {
    let (text, size) = read_input(
      source_path(args[2], source.path),
      remaining_bytes.min(16777216L),
    )
    remaining_bytes -= size
    captures.push({
      capture_id: source.capture_id,
      captured_unix_ms: source.captured_unix_ms,
      nodes: @fleet.import_nodes(text),
    })
  }
  let report = @fleet.explore_history(captures, query)
  let output = match args[1] {
    "changes" => report.changes_csv()
    "summary" => report.summary_csv()
    _ => report.json_text() + "\n"
  }
  @stdio.stdout.write(output)
}

///|
async fn main {
  execute() catch {
    @fleet.InvalidInput(message) => {
      @stdio.stderr.write("lunanexa-fleet-history: \{message}\n")
      @sys.exit(1)
    }
    error => {
      @stdio.stderr.write("lunanexa-fleet-history: \{error}\n")
      @sys.exit(1)
    }
  }
}
