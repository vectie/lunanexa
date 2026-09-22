///|
async test "media replicas balance new requests but pin retries to original execution" {
  let profile : @media_provider.Profile = {
    model: "video.h3",
    provider_model: "H3",
    widths: [512],
    heights: [512],
    maximum_frames: 25,
    maximum_fps: 24,
    maximum_steps: 30,
    sound_supported: false,
  }
  let first : MediaBinding = {
    deployment_id: "delivery-1",
    deployment_generation: 1L,
    node_id: "spark-a",
    origin: "http://127.0.0.1:8101",
    bearer: None,
    profile,
    instance_id: Some(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
  }
  let second : MediaBinding = {
    ..first,
    node_id: "spark-b",
    origin: "http://127.0.0.1:8102",
    instance_id: Some(
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
  }
  let owner : @media_jobs.Owner = {
    tenant_ref: "tenant-a",
    subject_ref: "subject-a",
    organization_id: "org-a",
    project_id: "project-a",
    authority: PrivateWorkspace("lease-a"),
  }
  let jobs = @media_jobs.JobStore::restore(
    {
      schema_version: @media_jobs.schema_version,
      jobs: [],
      terminations: None,
    },
    _ => (),
  )
  let (existing, _) = jobs.reserve(
    owner,
    "request-a",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    profile.model,
    first.identity(),
    1L,
    1000L,
    2000L,
    execution_context=first.execution_context(),
  )
  let snapshot = jobs.snapshot().jobs
  assert_true(
    select_media_replica([first, second], snapshot, owner, "request-a")
    is MediaSelected(binding) &&
    binding.identity() == first.identity(),
  )
  assert_true(
    select_media_replica([first, second], snapshot, owner, "request-b")
    is MediaSelected(binding) &&
    binding.identity() == second.identity(),
  )
  assert_true(
    select_media_replica([second], snapshot, owner, "request-a")
    is MediaUnavailable,
  )
  assert_true(
    select_media_replica(
      [{ ..first, deployment_generation: 2L, }, second],
      snapshot,
      owner,
      "request-a",
    )
    is MediaUnavailable,
  )
  assert_true(
    select_media_replica(
      [first, { ..second, deployment_id: "other-delivery", }],
      [],
      owner,
      "request-b",
    )
    is MediaAmbiguous,
  )
  assert_true(
    select_media_replica(
      [first, { ..second, profile: { ..profile, maximum_steps: 40, }, }],
      [],
      owner,
      "request-b",
    )
    is MediaAmbiguous,
  )
  assert_true(
    select_media_replica(
      [first, { ..first, origin: "http://127.0.0.1:8103", }],
      [],
      owner,
      "request-b",
    )
    is MediaAmbiguous,
  )
  assert_true(
    select_media_replica(
      [second],
      snapshot,
      { ..owner, subject_ref: "subject-b", },
      "request-a",
    )
    is MediaSelected(_),
  )
  assert_eq(existing.execution_context, Some(first.execution_context()))
}
