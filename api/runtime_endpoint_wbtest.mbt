///|
async fn exercise_runtime_route_discovery(
  service : ApiService,
  operation : @deployment.DeploymentOperation,
  binding : MediaBinding,
  owner : @media_jobs.Owner,
) -> Unit {
  let heartbeat = service.store
    .heartbeats()
    .filter(value => value.node_id == binding.node_id)[0]
  let assignment = service.store
    .assignments()
    .filter(value => operation.assignment_ids.contains(value.assignment_id))[0]
  let now = @async.now()
  let endpoint : @contracts.RuntimeEndpoint = {
    assignment_id: assignment.assignment_id,
    deployment_id: assignment.deployment_id,
    generation: assignment.generation,
    controller_epoch: assignment.controller_epoch,
    instance_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    address: "10.42.1.99",
    port: 5885,
    artifact_digest: assignment.artifact.digest,
    image_digest: assignment.runtime.image_digest,
    observed_unix_ms: now,
  }
  let current : @contracts.NodeHeartbeat = {
    ..heartbeat,
    timestamp_unix_ms: now,
    runtime_endpoints: Some([endpoint]),
  }
  let template : MediaTemplateBinding = {
    template_id: operation.plan.template.unwrap().template_id,
    template_version: operation.plan.template.unwrap().version,
    node_id: binding.node_id,
    origin: "",
    bearer: binding.bearer,
    profile: binding.profile,
    runtime_route: Some({ network: "10.42.1.0", prefix_length: 24, port: 5885, }),
  }
  assert_true(service.heartbeat_runtime_endpoints_valid(current, now))
  for
    invalid in [
      { ..template, origin: "http://10.42.1.99:5885", },
      {
        ..template,
        runtime_route: Some({
          network: "8.8.8.0",
          prefix_length: 24,
          port: 5885,
        }),
      },
    ] {
    let jobs = @media_jobs.JobStore::restore(
      { schema_version: @media_jobs.schema_version, jobs: [], },
      _ => (),
    )
    try service.with_media_templates(jobs, [invalid]) catch {
      _ => ()
    } noraise {
      _ => fail("unsafe managed route profile accepted")
    }
  }
  for
    bad in [
      { ..endpoint, address: "169.254.169.254", },
      { ..endpoint, deployment_id: "foreign-deployment", },
      { ..endpoint, generation: endpoint.generation + 1L, },
      { ..endpoint, observed_unix_ms: now + 1L, },
      { ..endpoint, observed_unix_ms: now - 15001L, },
    ] {
    assert_false(
      service.heartbeat_runtime_endpoints_valid(
        { ..current, runtime_endpoints: Some([bad]), },
        now,
      ),
    )
  }
  assert_false(
    service.heartbeat_runtime_endpoints_valid(
      { ..current, runtime_endpoints: Some([endpoint, endpoint]), },
      now,
    ),
  )
  assert_false(
    service.heartbeat_runtime_endpoints_valid(
      { ..current, node_id: "foreign-node", },
      now,
    ),
  )
  service.store.put_heartbeat(current)
  let discovered = service.media_all_bindings([], [template])
  assert_eq(discovered.length(), 1)
  assert_eq(discovered[0].origin, "http://10.42.1.99:5885")
  let original_identity = discovered[0].identity()
  let jobs = @media_jobs.JobStore::restore(
    { schema_version: @media_jobs.schema_version, jobs: [], },
    _ => (),
  )
  let job = jobs.reserve(
      owner,
      "endpoint-outage",
      "sha256:" + digest_hex("fixture-request"),
      binding.profile.model,
      original_identity,
      now,
      now + 3600000L,
      now + 7200000L,
    ).0
  let configured = service.with_media_templates(jobs, [template])
  let context = configured.media_execution_context(
    jobs,
    [],
    [template],
    original_identity,
  )
  assert_eq(jobs.get(job.job_id, owner).execution_context, Some(context))
  let jobs = @media_jobs.JobStore::restore(jobs.snapshot(), _ => ())
  let configured = service.with_media_templates(jobs, [template])
  service.store.put_heartbeat({ ..current, runtime_endpoints: None, })
  // Lost discovery is not lost ownership. An unsubmitted intent can still be
  // inspected, but no provider address is invented or taken from stored data.
  assert_eq(
    configured.media.unwrap().runtime.get(job.job_id, owner).state,
    Intent,
  )
  ignore(jobs.begin_submission(job.job_id, owner, now + 1L))
  ignore(
    jobs.attach_provider(job.job_id, owner, "fixture-old-instance", now + 2L),
  )
  assert_eq(configured.media.unwrap().runtime.reconcile(), (0, 1))
  assert_eq(jobs.get(job.job_id, owner).state, Queued)
  service.store.put_heartbeat({
    ..current,
    runtime_endpoints: Some([
      {
        ..endpoint,
        instance_id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      },
    ]),
  })
  let replacement = service.media_all_bindings([], [template])
  assert_eq(replacement.length(), 1)
  assert_true(replacement[0].identity() != original_identity)
  // Even after a replacement becomes available, the old job stays attached to
  // its original incarnation. Resolving it fails before any HTTP request.
  assert_eq(configured.media.unwrap().runtime.reconcile(), (0, 1))
  assert_eq(jobs.get(job.job_id, owner).state, Queued)
  for
    bad in [
      { ..endpoint, address: "10.42.2.99", },
      { ..endpoint, port: 5886, },
      { ..endpoint, observed_unix_ms: now - 15001L, },
    ] {
    service.store.put_heartbeat({ ..current, runtime_endpoints: Some([bad]), })
    assert_eq(service.media_all_bindings([], [template]).length(), 0)
  }
  service.store.put_heartbeat({ ..heartbeat, timestamp_unix_ms: @async.now(), })
  assert_eq(service.media_all_bindings([], [template]).length(), 0)
  let unavailable = { ..service, reconciliation_only: true, }.with_media_templates(
    jobs,
    [template],
  )
  assert_eq(unavailable.media.unwrap().runtime.reconcile(), (0, 1))
  assert_eq(jobs.get(job.job_id, owner).state, Queued)
  let revoked = { ..service, account_store: None, }.with_media_templates(jobs, [
    template,
  ])
  assert_eq(revoked.media.unwrap().runtime.reconcile(), (0, 1))
  assert_eq(jobs.get(job.job_id, owner).state, Cancelling)
  assert_false(jobs.get(job.job_id, owner).execution_terminal)
}
