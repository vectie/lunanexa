///|
fn artifact_assignment_fixture(secret : String) -> @contracts.DesiredAssignment {
  let unsigned : @contracts.DesiredAssignment = {
    assignment_id: "assignment-artifact-gateway",
    deployment_id: "deployment-artifact-gateway",
    node_id: "node-a",
    artifact: {
      uri: "s3://models/model.bin",
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      size_bytes: 14L,
      signature_ref: "s3://models/model.bin.sig",
    },
    runtime: {
      name: "vllm",
      version: "1",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      capabilities: [TextGenerate],
      architectures: ["sm_121"],
      supports_batching: false,
      supports_multi_node: false,
    },
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 1024,
      cpu_millis: 1000,
      memory_mib: 2048,
    },
    devices: ["gpu-0"],
    network: {
      allow_controller: true,
      allow_artifact_store: true,
      allowed_egress: [],
    },
    health: {
      readiness_path: "/health",
      interval_ms: 1000,
      failure_threshold: 3,
      termination_grace_ms: 30000,
    },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    generation: 1L,
    lease_expires_unix_ms: 1900000000000L,
    controller_epoch: 1L,
    signature: "",
  }
  { ..unsigned, signature: @node.assignment_signature(unsigned, secret) }
}

///|
async test "artifact gateway binds node assignment object and durable grant" {
  let directory = @fs.tmpdir(prefix="lunanexa-artifact-gateway-")
  let durable = @store.FileStore::open("\{directory}/control.json")
  durable.fence_controller(1L)
  let technical = @technical_store.TechnicalStore::open(
    "\{directory}/technical.json",
  )
  let secret = "node-artifact-authority"
  let service = ApiService::new(
    durable,
    @runtimes.OpenAiTextRuntime::new(
      "http://127.0.0.1:1",
      "runtime-token",
      "test",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    ),
    "operator-token",
    "inference-token",
    secret,
    "test",
  ).with_technical_store(technical)
  let assignment = artifact_assignment_fixture(secret)
  durable.put_assignment(assignment)
  let headers : Map[String, String] = {
    "Authorization": "Node \{secret}",
    "X-LunaNexa-Node-Id": assignment.node_id,
    "X-LunaNexa-Assignment-Id": assignment.assignment_id,
    "X-LunaNexa-Deployment-Id": assignment.deployment_id,
    "X-LunaNexa-Model-Digest": assignment.artifact.digest,
  }
  assert_eq(
    service.artifact_assignment(headers, "models/model.bin", 1800000000000L),
    Some(assignment),
  )
  assert_eq(
    service.artifact_assignment(headers, "models/other.bin", 1800000000000L),
    None,
  )
  assert_true(
    service.consume_artifact_grant(
      assignment, "models/model.bin", 1800000000000L,
    )
    is Some(_),
  )
  assert_eq(
    service.consume_artifact_grant(
      assignment, "models/model.bin", 1800000000000L,
    ),
    None,
  )
  @fs.rmdir(directory, recursive=true)
}

///|
test "artifact paths and ranges fail closed" {
  assert_true(safe_artifact_key("models/team/model.bin"))
  for
    value in [
      "", "/absolute", "../escape", "models//model", "models/model%2fsecret", "models/model?token=secret",
      "models/model\nforged",
    ] {
    assert_false(safe_artifact_key(value))
  }
  assert_eq(range_start({}, 100L), Some(0L))
  assert_eq(range_start({ "Range": "bytes=40-" }, 100L), Some(40L))
  assert_eq(range_start({ "Range": "bytes=-40" }, 100L), None)
  assert_eq(range_start({ "Range": "bytes=100-" }, 100L), None)
}

///|
test "artifact key and range mutation fuzz stays lexical and bounded" {
  let hostile = ["\\", " ", "\n", "\r", "?", "#", "%", "<", ">"]
  for position in 0..<=64 {
    for mutation in hostile {
      let candidate = "a".repeat(position) +
        mutation +
        "b".repeat(64 - position)
      assert_false(safe_artifact_key(candidate))
    }
    let with_separator = "a".repeat(position) + "/" + "b".repeat(64 - position)
    assert_eq(safe_artifact_key(with_separator), position > 0 && position < 64)
  }
  for
    value in [
      "bytes=", "bytes=-", "bytes=0", "bytes=0-1", "bytes=+1-", "bytes= 1-", "bytes=1 -",
      "bytes=01-", "bytes=9223372036854775808-", "items=1-",
    ] {
    let parsed = range_start({ "Range": value }, 100L)
    assert_eq(parsed is Some(_), value == "bytes=01-")
  }
  for start in 0L..<100L {
    assert_eq(range_start({ "Range": "bytes=\{start}-" }, 100L), Some(start))
  }
}

///|
async test "artifact path resolution contains symlinks inside the model root" {
  let directory = @fs.tmpdir(prefix="lunanexa-artifact-root-")
  let root = "\{directory}/models"
  let outside = "\{directory}/outside"
  @fs.mkdir("\{root}/team", recursive=true)
  @fs.mkdir(outside, recursive=true)
  @fs.write_file(
    "\{root}/team/model.bin",
    "artifact-bytes",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{outside}/secret.bin",
    "outside-secret",
    create_mode=CreateOrTruncate,
  )
  @fs.symlink(target="\{outside}/secret.bin", "\{root}/team/escaped.bin")
  let expected = @fs.realpath("\{root}/team/model.bin")
  assert_eq(resolved_artifact_path(root, "team/model.bin"), Some(expected))
  assert_eq(resolved_artifact_path(root, "team/escaped.bin"), None)
  assert_eq(resolved_artifact_path("/", "etc/passwd"), None)
  assert_eq(resolved_artifact_path(root, "team"), None)
  @fs.rmdir(directory, recursive=true)
}

///|
test "artifact gateway enforces assigned model size and bounded signature size" {
  let assignment = artifact_assignment_fixture("assignment-secret")
  let signature_limit = 1048576L
  assert_true(
    artifact_size_allowed(assignment, "models/model.bin", 14L, signature_limit),
  )
  assert_false(
    artifact_size_allowed(assignment, "models/model.bin", 15L, signature_limit),
  )
  assert_true(
    artifact_size_allowed(
      assignment, "models/model.bin.sig", signature_limit, signature_limit,
    ),
  )
  assert_false(
    artifact_size_allowed(
      assignment,
      "models/model.bin.sig",
      signature_limit + 1L,
      signature_limit,
    ),
  )
  assert_false(
    artifact_size_allowed(assignment, "models/other.bin", 14L, signature_limit),
  )
}
