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
  let usage = "usage: lunanexa-model-intake mapping | local-artifact ARTIFACT METADATA.json | export REGISTRY.json MAPPING.json | import CSV MAPPING.json | review DRAFT.json REGISTRY.json | request DRAFT.json REGISTRY.json MODEL_ID VERSION"
  if args.length() < 2 {
    fail(usage)
  }
  if args[1] == "export" {
    guard args.length() == 4 else { fail(usage) }
    let mapping = @model_intake.import_mapping(read_input(args[3], 65536L))
    let registered = @model_intake.import_registry(
      read_input(args[2], 16777216L),
    )
    @stdio.stdout.write(@model_intake.export_registry_csv(registered, mapping))
    return
  }
  let output : Json = match args[1] {
    "mapping" if args.length() == 2 => @model_intake.default_mapping().to_json()
    "local-artifact" if args.length() == 4 => {
      let metadata = @model_intake.import_artifact_metadata(
        read_input(args[3], 65536L),
      )
      read_local_artifact(args[2], metadata).to_json()
    }
    "import" if args.length() == 4 => {
      let mapping = @model_intake.import_mapping(read_input(args[3], 65536L))
      @model_intake.import_csv(read_input(args[2], 8388608L), mapping).to_json()
    }
    "review" | "request" if args.length() ==
      (if args[1] == "review" { 4 } else { 6 }) => {
      let draft = @model_intake.import_draft(read_input(args[2], 16777216L))
      let registered = @model_intake.import_registry(
        read_input(args[3], 16777216L),
      )
      if args[1] == "review" {
        @model_intake.review(draft, registered).to_json()
      } else {
        @model_intake.registration_request(draft, registered, args[4], args[5]).to_json()
      }
    }
    _ => fail(usage)
  }
  let text = output.stringify(indent=2)
  if text.length() > 8388608 {
    fail("output exceeds 8 Mi characters")
  }
  @stdio.stdout.write(text + "\n")
}

///|
async fn main {
  execute() catch {
    @model_intake.InvalidInput(message) => {
      @stdio.stderr.write("lunanexa-model-intake: " + message + "\n")
      @sys.exit(1)
    }
    error => {
      @stdio.stderr.write("lunanexa-model-intake: \{error}\n")
      @sys.exit(1)
    }
  }
}
