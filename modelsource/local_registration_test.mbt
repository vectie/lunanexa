///|
test "local directories are validated as store-relative keys" {
  assert_true(@modelsource.valid_local_directory("stepfun"))
  assert_true(
    @modelsource.valid_local_directory("models/modelscope/ms-0123456789abcdef"),
  )
  assert_false(@modelsource.valid_local_directory(""))
  assert_false(@modelsource.valid_local_directory("/data/models/stepfun"))
  assert_false(@modelsource.valid_local_directory("stepfun/"))
  assert_false(@modelsource.valid_local_directory("../stepfun"))
  assert_false(@modelsource.valid_local_directory("stepfun/.."))
  assert_false(@modelsource.valid_local_directory("step fun"))
  assert_false(@modelsource.valid_local_directory("stepfun//weights"))
  assert_eq(
    @modelsource.local_artifact_uri("stepfun"),
    "modelstore://stepfun",
  )
  let escape_rejected = try {
    ignore(@modelsource.local_artifact_uri("../stepfun"))
    false
  } catch {
    @modelsource.ModelSourceError::InvalidRepositoryPath => true
    _ => false
  } noraise {
    value => value
  }
  assert_true(escape_rejected)
}

///|
/// The same document a pre-`local_directory` build wrote: every option absent,
/// every Int64 already rendered as a JSON string.
fn legacy_snapshot() -> String {
  Json::object({
    "schema_version": Json::number(1.0),
    "operations": Json::array([
      Json::object({
        "import_id": Json::string("ms-legacy"),
        "source": Json::string("modelscope"),
        "model_id": Json::string("OpenBMB/MiniCPM5-1B"),
        "revision": Json::string("master"),
        "state": Json::string("Verified"),
        "files_total": Json::number(11.0),
        "files_completed": Json::number(11.0),
        "bytes_total": Json::string("2171355326"),
        "bytes_completed": Json::string("2171355326"),
        "manifest_digest": Json::string("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        "artifact_uri": Json::string("modelstore://modelscope/ms-legacy"),
        "license": Json::string("apache-2.0"),
        "error_code": Json::string(""),
        "cancel_requested": Json::boolean(false),
        "created_unix_ms": Json::string("1000"),
        "updated_unix_ms": Json::string("1100"),
      }),
    ]),
  }).stringify()
}

///|
async test "a local revision is verified before it is believed" {
  let directory = @fs.tmpdir(prefix="lunanexa-modelsource-local-")
  let path = "\{directory}/imports.json"
  let store = @modelsource.FileImportStore::open(path)
  let created = store.create_local(
    { model_id: "stepfun-ai/Step-3.5-Flash", revision: "master" },
    "apache-2.0",
    "stepfun",
    1000L,
  )
  assert_eq(created.state, Queued)
  assert_eq(created.local_directory, "stepfun")
  assert_eq(created.artifact_uri, "")
  guard store.next_queued() is Some(claimed) else {
    fail("expected the local registration to be claimed")
  }
  // Re-deriving a directory is verifying, never downloading.
  assert_eq(claimed.state, Verifying)
  assert_eq(claimed.local_directory, "stepfun")

  let rejected = try {
    ignore(
      store.create_local(
        { model_id: "stepfun-ai/Step-3.5-Flash", revision: "main" },
        "apache-2.0",
        "../escape",
        1100L,
      ),
    )
    false
  } catch {
    @modelsource.ModelSourceError::InvalidRepositoryPath => true
    _ => false
  } noraise {
    value => value
  }
  assert_true(rejected)
  assert_eq(store.list().length(), 1)
}

///|
async test "a version 1 snapshot keeps its imports when the schema grows" {
  let directory = @fs.tmpdir(prefix="lunanexa-modelsource-migrate-")
  let path = "\{directory}/imports.json"
  @fs.write_file(
    path,
    legacy_snapshot(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let store = @modelsource.FileImportStore::open(path)
  guard store.get("ms-legacy") is Some(restored) else {
    fail("expected the pre-upgrade import to survive")
  }
  assert_eq(restored.state, Verified)
  assert_eq(restored.local_directory, "")
  assert_eq(restored.bytes_completed, 2171355326L)

  // The upgrade is written back as the current schema.
  assert_true(
    @fs.read_file(path).text().contains("\"schema_version\":2"),
  )
}

///|
/// The console decodes this listing with an `Int64` field. A bare JSON number
/// here answers 200 with the right bytes and still makes the console report
/// that the model store could not be read, so the wire form is pinned.
test "a store-directory entry keeps byte counts on the Int64 wire form" {
  let entry = @modelsource.local_directory_entry(
    "stepfun", 59, 398779649344L, false,
  )
  guard entry is Object(fields) else {
    fail("a store-directory entry is a JSON object")
  }
  assert_eq(fields.get("directory"), Some(Json::string("stepfun")))
  assert_eq(fields.get("bytes"), Some(Json::string("398779649344")))
  assert_eq(fields.get("files"), Some(Json::number(59.0)))
  assert_eq(fields.get("registered"), Some(Json::boolean(false)))
  let escaped = try {
    ignore(@modelsource.local_directory_entry("../escape", 1, 1L, false))
    false
  } catch {
    @modelsource.ModelSourceError::InvalidRepositoryPath => true
    _ => false
  } noraise {
    value => value
  }
  assert_true(escaped)
}
