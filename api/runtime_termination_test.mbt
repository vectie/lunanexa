///|
async test "termination report endpoint rejects forged authority and stale send time" {
  let directory = @fs.tmpdir(prefix="lunanexa-termination-auth-")
  let store = @store.FileStore::open("\{directory}/control.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
    store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  )
  let unsigned : @contracts.RuntimeTerminationReport = {
    node_id: "node-a",
    timestamp_unix_ms: @async.now(),
    signature: "forged",
    records: [
      {
        assignment_id: "assignment-a",
        deployment_id: "deployment-a",
        generation: 1L,
        controller_epoch: 1L,
        instance_id: "a".repeat(64),
        artifact_digest: "sha256:" + "b".repeat(64),
        image_digest: "sha256:" + "c".repeat(64),
        observed_unix_ms: 1000L,
        original_assignment: None,
      },
    ],
  }
  let headers = {
    "Authorization": "Node node-token",
    "X-LunaNexa-Node-Id": "node-a",
  }
  let path = "/v1/nodes/runtime-terminations"
  assert_eq(
    service.handle(Post, path, headers, ToJson::to_json(unsigned).stringify()).status,
    401,
  )
  let signed = {
    ..unsigned,
    signature: @node.termination_report_signature(unsigned, "node-token"),
  }
  assert_eq(
    service.handle(
      Post,
      path,
      { "Authorization": "Bearer operator-token" },
      ToJson::to_json(signed).stringify(),
    ).status,
    401,
  )
  let stale = { ..unsigned, timestamp_unix_ms: 1L, }
  let stale = {
    ..stale,
    signature: @node.termination_report_signature(stale, "node-token"),
  }
  assert_eq(
    service.handle(Post, path, headers, ToJson::to_json(stale).stringify()).status,
    409,
  )
  assert_eq(
    service.handle(Post, path, headers, ToJson::to_json(signed).stringify()).status,
    503,
  )
  let jobs = @media_jobs.JobStore::restore(
    {
      schema_version: @media_jobs.schema_version,
      jobs: [],
      terminations: None,
    },
    _ => (),
  )
  let configured = service.with_media_jobs(jobs, [])
  let assignment = api_assignment()
  store.put_assignment(assignment)
  let evidence : @contracts.RuntimeTermination = {
    assignment_id: assignment.assignment_id,
    deployment_id: assignment.deployment_id,
    generation: assignment.generation,
    controller_epoch: assignment.controller_epoch,
    instance_id: "a".repeat(64),
    artifact_digest: assignment.artifact.digest,
    image_digest: assignment.runtime.image_digest,
    observed_unix_ms: @async.now(),
    original_assignment: None,
  }
  let valid = {
    ..unsigned,
    timestamp_unix_ms: @async.now(),
    records: [evidence],
  }
  let valid = {
    ..valid,
    signature: @node.termination_report_signature(valid, "node-token"),
  }
  assert_eq(
    configured.handle(Post, path, headers, ToJson::to_json(valid).stringify()).status,
    202,
  )
  assert_eq(
    configured.handle(Post, path, headers, ToJson::to_json(valid).stringify()).status,
    202,
  )
  assert_true(
    jobs.snapshot().terminations == Some([{ node_id: "node-a", evidence, }]),
  )
  let historical_service = configured.with_assignment_signing_secret(
    "controller-only-signing-key",
  )
  let historical = { ..assignment, assignment_id: "removed-assignment", }
  let historical = {
    ..historical,
    signature: @node.assignment_signature(
      historical, "controller-only-signing-key",
    ),
  }
  let late_evidence = {
    ..evidence,
    assignment_id: historical.assignment_id,
    instance_id: "d".repeat(64),
    original_assignment: Some(historical),
  }
  let late = { ..valid, records: [late_evidence], }
  let late = {
    ..late,
    signature: @node.termination_report_signature(late, "node-token"),
  }
  assert_eq(
    historical_service.handle(
      Post,
      path,
      headers,
      ToJson::to_json(late).stringify(),
    ).status,
    202,
  )
  let tampered = {
    ..late,
    records: [
      {
        ..late_evidence,
        instance_id: "e".repeat(64),
        original_assignment: Some({ ..historical, node_id: "node-b", }),
      },
    ],
  }
  let tampered = {
    ..tampered,
    signature: @node.termination_report_signature(tampered, "node-token"),
  }
  assert_eq(
    historical_service.handle(
      Post,
      path,
      headers,
      ToJson::to_json(tampered).stringify(),
    ).status,
    409,
  )
  let wrong = {
    ..valid,
    records: [{ ..evidence, generation: evidence.generation + 1L, }],
  }
  let wrong = {
    ..wrong,
    signature: @node.termination_report_signature(wrong, "node-token"),
  }
  assert_eq(
    configured.handle(Post, path, headers, ToJson::to_json(wrong).stringify()).status,
    409,
  )
  assert_eq(jobs.snapshot().terminations.unwrap().length(), 2)
}
