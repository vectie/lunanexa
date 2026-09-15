///|
async test "public placement API survives a serialized store restart" {
  let store = @jobs.JobStore::restore(
    { schema_version: @jobs.schema_version, jobs: [], },
    _ => (),
  )
  let owner : @jobs.Owner = {
    tenant_ref: "tenant",
    subject_ref: "subject",
    organization_id: "org",
    project_id: "project",
    authority: PrivateWorkspace("workspace-lease"),
  }
  let context : @jobs.ExecutionContext = {
    deployment_id: "deployment",
    generation: 1L,
    node_id: "node",
  }
  let job = store.reserve(
      owner,
      "request",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "video.model",
      "immutable-binding",
      1000L,
      2000L,
      3000L,
      execution_context=context,
    ).0
  let restored = @jobs.JobStore::restore(store.snapshot(), _ => ())
  assert_eq(restored.context_for_binding(job.deployment_id), Some(context))
  restored.remember_execution(job.deployment_id, context)
  assert_eq(restored.get(job.job_id, owner).execution_context, Some(context))
}
