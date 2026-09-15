///|
async test "file-backed media intents survive restart without resubmission" {
  let root = @fs.tmpdir(prefix="lunanexa-media-store-")
  defer @fs.rmdir(root, recursive=true)
  let path = root + "/jobs.json"
  let owner : @jobs.Owner = {
    tenant_ref: "t",
    subject_ref: "s",
    organization_id: "o",
    project_id: "p",
    authority: DedicatedOrder("order"),
  }
  let store = @store.open_file(path)
  let (job, created) = store.reserve(
    owner,
    "request",
    "sha256:" + "a".repeat(64),
    "video.h3",
    "deployment",
    1000L,
    2000L,
    5000L,
  )
  assert_true(created)
  ignore(store.begin_submission(job.job_id, owner, 1001L))
  let restored = @store.open_file(path)
  assert_eq(restored.get(job.job_id, owner).state, SubmissionUnknown)
  let again = @store.open_file(path)
  assert_eq(again.get(job.job_id, owner).state, SubmissionUnknown)
}

///|
async test "PostgreSQL private media intents retain ownership and ambiguous submission across restart" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  defer database.close()
  database.save_opaque_snapshot(
    "media_jobs",
    @jobs.schema_version,
    ToJson::to_json(@jobs.Snapshot::{
      schema_version: @jobs.schema_version,
      jobs: [],
      terminations: None,
    }).stringify(),
  )
  let owner : @jobs.Owner = {
    tenant_ref: "t",
    subject_ref: "s",
    organization_id: "o",
    project_id: "p",
    authority: PrivateWorkspace("workspace-lease"),
  }
  let store = @store.open_postgres(database)
  let (job, created) = store.reserve(
    owner,
    "postgres-request",
    "sha256:" + "b".repeat(64),
    "video.h3",
    "deployment",
    1000L,
    2000L,
    5000L,
  )
  assert_true(created)
  ignore(store.begin_submission(job.job_id, owner, 1001L))
  let restored = @store.open_postgres(database)
  assert_eq(restored.get(job.job_id, owner).state, SubmissionUnknown)
  let again = @store.open_postgres(database)
  assert_true(again.get(job.job_id, owner).owner == owner)
  assert_eq(again.get(job.job_id, owner).state, SubmissionUnknown)
}
