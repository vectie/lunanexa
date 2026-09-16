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
async fn verify_postgres_termination_recovery(
  again : @jobs.JobStore,
  job : @jobs.StoredJob,
  owner : @jobs.Owner,
  url : String,
) -> Unit {
  let context : @jobs.ExecutionContext = {
    deployment_id: "deployment",
    generation: 1L,
    node_id: "test-node",
    instance_id: Some("c".repeat(64)),
  }
  again.remember_execution(job.deployment_id, context)
  let recovered_database = @database.PostgresDatabase::open(url)
  defer recovered_database.close()
  let recovered = @store.open_postgres(recovered_database)
  try
    recovered.reserve(
      owner,
      "must-stay-busy",
      "sha256:" + "d".repeat(64),
      "video.h3",
      "deployment",
      1002L,
      2000L,
      5000L,
      maximum_active=1,
    )
  catch {
    @jobs.JobError::Busy => ()
    error => raise error
  } noraise {
    _ => fail("ambiguous submission released capacity after database recovery")
  }
  try
    recovered.acknowledge_instance_termination(
      job.job_id,
      owner,
      job.deployment_id,
      { ..context, instance_id: Some("d".repeat(64)), },
      "test-only-wrong-instance",
      1003L,
      1004L,
    )
  catch {
    @jobs.JobError::Conflict => ()
    error => raise error
  } noraise {
    _ => fail("replacement instance cannot terminate original execution")
  }
  assert_false(recovered.get(job.job_id, owner).execution_terminal)
  let terminal = recovered.acknowledge_instance_termination(
    job.job_id,
    owner,
    job.deployment_id,
    context,
    "test-only-original-instance-exit",
    1003L,
    1004L,
  )
  assert_true(terminal.execution_terminal)
  let final_database = @database.PostgresDatabase::open(url)
  defer final_database.close()
  let final_store = @store.open_postgres(final_database)
  assert_true(final_store.get(job.job_id, owner) == terminal)
  assert_true(
    final_store.acknowledge_instance_termination(
      job.job_id,
      owner,
      job.deployment_id,
      context,
      "test-only-original-instance-exit",
      1003L,
      1005L,
    ) ==
    terminal,
  )
  let (_, created_after_exit) = final_store.reserve(
    owner,
    "capacity-after-evidenced-exit",
    "sha256:" + "e".repeat(64),
    "video.h3",
    "deployment",
    1006L,
    2000L,
    5000L,
    maximum_active=1,
  )
  assert_true(created_after_exit)
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
  verify_postgres_termination_recovery(again, job, owner, url)
}
