///|
fn candidate(version : String) -> @contracts.ModelRecord {
  let digest = if version == "v1" {
    "sha256:9999999999999999999999999999999999999999999999999999999999999999"
  } else {
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
  {
    model_id: "model.text",
    version,
    artifact: {
      digest,
      uri: "s3://models/\{version}",
      size_bytes: 10L,
      signature_ref: "sig:\{version}",
    },
    license_id: "license.text",
    provenance: "provider:approved",
    compatible_architectures: ["nvidia-gb10"],
    minimum_memory_mib: 1000,
    state: Candidate,
  }
}

///|
fn benchmark(version : String) -> @registry.BenchmarkProfile {
  {
    profile_id: "bench:\{version}",
    model_id: "model.text",
    model_version: version,
    runtime_version: "runtime-1",
    hardware_profile: "dgx-spark",
    workload_profile: "text-short-v1",
    p50_ms: 10.0,
    p95_ms: 20.0,
    p99_ms: 30.0,
    throughput_per_second: 100.0,
    peak_memory_mib: 900,
  }
}

///|
fn make_approvable(
  registry : @registry.ModelRegistry,
  version : String,
) -> Unit raise {
  let model = candidate(version)
  registry.register_model(model)
  registry.record_license({
    license_id: "license.text",
    model_id: "model.text",
    status: Accepted,
    accepted_by: "operator",
    evidence_ref: "evidence:license",
    expires_unix_ms: None,
  })
  registry.record_verification({
    digest: model.artifact.digest,
    signature_verified: true,
    provenance_verified: true,
    verified_unix_ms: 1L,
    verifier: "verifier-v1",
  })
  assert_eq(registry.model("model.text", version).unwrap().state, Verified)
  registry.record_evaluation({
    evaluation_id: "eval:\{version}",
    model_id: "model.text",
    model_version: version,
    suite_version: "suite-v1",
    passed: true,
    score: 0.95,
    benchmark: benchmark(version),
    evidence_ref: "evidence:eval:\{version}",
  })
  assert_eq(registry.model("model.text", version).unwrap().state, Evaluated)
}

///|
test "unsafe artifact cannot deploy" {
  let registry = @registry.ModelRegistry::new()
  registry.register_model(candidate("v1"))
  try registry.approve("model.text", "v1", 1L) catch {
    @registry.RegistryError::LicenseNotAccepted(_) => ()
    err => fail("unexpected error: \{to_repr(err)}")
  } noraise {
    _ => fail("expected unsafe model rejection")
  }
}

///|
test "canary promotion and rollback are deterministic and durable" {
  let registry = @registry.ModelRegistry::new()
  make_approvable(registry, "v1")
  ignore(registry.approve("model.text", "v1", 2L))
  let first = registry.promote(
    "text.default",
    "model.text",
    "v1",
    Canary,
    "operator",
    3L,
  )
  assert_eq(first.generation, 1L)
  make_approvable(registry, "v2")
  ignore(registry.approve("model.text", "v2", 4L))
  let second = registry.promote(
    "text.default",
    "model.text",
    "v2",
    Stable,
    "operator",
    5L,
  )
  assert_eq(second.generation, 2L)
  let rollback = registry.rollback("text.default", "operator", 6L)
  assert_eq(rollback.to_version, "v1")
  assert_eq(registry.resolve_alias("text.default").unwrap().version, "v1")
  let restored = @registry.ModelRegistry::restore(registry.snapshot())
  assert_eq(restored.resolve_alias("text.default").unwrap().version, "v1")
  assert_eq(restored.receipts().length(), 3)
}

///|
async test "file registry survives restart with rollback history" {
  let directory = @fs.tmpdir(prefix="lunanexa-registry-test-")
  let path = "\{directory}/registry.json"
  let durable = @registry.FileRegistry::open(path)
  for version in ["v1", "v2"] {
    let model = candidate(version)
    durable.register_model(model)
    durable.record_license({
      license_id: "license.text",
      model_id: "model.text",
      status: Accepted,
      accepted_by: "operator",
      evidence_ref: "evidence:license",
      expires_unix_ms: None,
    })
    durable.record_verification({
      digest: model.artifact.digest,
      signature_verified: true,
      provenance_verified: true,
      verified_unix_ms: 1L,
      verifier: "verifier-v1",
    })
    durable.record_evaluation({
      evaluation_id: "eval:\{version}",
      model_id: "model.text",
      model_version: version,
      suite_version: "suite-v1",
      passed: true,
      score: 0.95,
      benchmark: benchmark(version),
      evidence_ref: "evidence:eval:\{version}",
    })
    ignore(durable.approve("model.text", version, 2L))
    ignore(
      durable.promote(
        "text.default",
        "model.text",
        version,
        if version == "v1" {
          Canary
        } else {
          Stable
        },
        "operator",
        3L,
      ),
    )
  }
  let reopened = @registry.FileRegistry::open(path)
  let receipt = reopened.rollback("text.default", "operator", 4L)
  assert_eq(receipt.to_version, "v1")
  assert_eq(reopened.snapshot().receipts.length(), 3)
  @fs.rmdir(directory, recursive=true)
}

///|
test "deployment requires an approved artifact and exact registered runtime" {
  let registry = @registry.ModelRegistry::new()
  make_approvable(registry, "v1")
  ignore(registry.approve("model.text", "v1", 2L))
  let runtime : @contracts.RuntimeSpec = {
    name: "registry.invalid/text-runtime",
    image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    version: "runtime-v1",
    architectures: ["nvidia-gb10"],
    capabilities: [TextGenerate],
    supports_batching: false,
    supports_multi_node: false,
  }
  assert_false(
    registry.deployment_allowed(
      "sha256:9999999999999999999999999999999999999999999999999999999999999999",
      runtime,
    ),
  )
  registry.register_runtime(runtime)
  assert_false(
    registry.deployment_allowed(
      "sha256:9999999999999999999999999999999999999999999999999999999999999999",
      runtime,
    ),
  )
  registry.record_verification({
    digest: runtime.image_digest,
    signature_verified: true,
    provenance_verified: true,
    verified_unix_ms: 2L,
    verifier: "cosign-key:test",
  })
  assert_true(
    registry.deployment_allowed(
      "sha256:9999999999999999999999999999999999999999999999999999999999999999",
      runtime,
    ),
  )
  assert_false(
    registry.deployment_allowed(
      "sha256:9999999999999999999999999999999999999999999999999999999999999999",
      {
        ..runtime,
        image_digest: "sha256:8888888888888888888888888888888888888888888888888888888888888888",
      },
    ),
  )
}
