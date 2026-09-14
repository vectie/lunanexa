///|
fn empty() -> @jobs.Snapshot {
  { schema_version: @jobs.schema_version, jobs: [], }
}

///|
fn decode(value : String) -> @jobs.Snapshot raise @jobs.JobError {
  @json.from_json(@json.parse(value)) catch {
    _ => raise InvalidSnapshot
  }
}

///|
/// A file driver for a single fenced controller or isolated acceptance tests.
/// Production deployments should use the controller's PostgreSQL connection.
pub async fn open_file(path : String) -> @jobs.JobStore {
  if !path.has_prefix("/") || path.has_suffix("/") {
    raise @jobs.JobError::InvalidInput
  }
  let saved = if @fs.exists(path) {
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    if file.size() > 67108864L {
      raise @jobs.JobError::InvalidSnapshot
    }
    decode(@io.Reader::read_all(file).text())
  } else {
    empty()
  }
  let persist = async fn(value : @jobs.Snapshot) -> Unit {
    let encoded = ToJson::to_json(value).stringify()
    if encoded.length() > 67108864 {
      raise @jobs.JobError::CapacityExceeded
    }
    let pending = path + ".next"
    @fs.write_file(
      pending,
      encoded,
      create_mode=CreateOrTruncate,
      permission=0o600,
      sync=Full,
    )
    @fs.rename(pending, path, replace=true)
  }
  let store = @jobs.JobStore::restore(saved, persist)
  if !@fs.exists(path) {
    persist(empty())
  }
  store
}

///|
pub async fn open_postgres(
  database : @database.PostgresDatabase,
) -> @jobs.JobStore {
  let saved = match database.load_snapshot("media_jobs", @jobs.schema_version) {
    Some(payload) => decode(payload)
    None => empty()
  }
  @jobs.JobStore::restore(saved, value => {
    database.save_opaque_snapshot(
      "media_jobs",
      @jobs.schema_version,
      ToJson::to_json(value).stringify(),
    )
  })
}
