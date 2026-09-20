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
    LicenseNotAccepted(_) => ()
    err => fail("unexpected error: \{Repr(err)}")
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
async test "failed registry persistence never publishes a model and permits retry" {
  let directory = @fs.tmpdir(prefix="lunanexa-registry-write-failure-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/registry.json"
  let durable = @registry.FileRegistry::open(path)
  let before = durable.snapshot()
  let disk = @fs.read_file(path).text()
  @fs.mkdir(path + ".next")
  try durable.register_model(candidate("v1")) catch {
    _ => ()
  } noraise {
    _ => fail("expected persistence failure")
  }
  @async.with_timeout(1000, () => {
    assert_eq(durable.snapshot(), before)
    assert_eq(@fs.read_file(path).text(), disk)
    assert_eq(@registry.FileRegistry::open(path).snapshot(), before)
  })
  @fs.rmdir(path + ".next")
  @async.with_timeout(1000, () => {
    durable.register_model(candidate("v1"))
    assert_eq(durable.snapshot().models, [candidate("v1")])
    assert_eq(@registry.FileRegistry::open(path).snapshot(), durable.snapshot())
  })
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
    let before_approval = durable.snapshot()
    @fs.mkdir(path + ".next")
    try durable.approve("model.text", version, 2L) catch {
      _ => ()
    } noraise {
      _ => fail("approval succeeded despite failed persistence")
    }
    @async.with_timeout(1000, () => {
      assert_eq(durable.snapshot(), before_approval)
      assert_eq(@registry.FileRegistry::open(path).snapshot(), before_approval)
    })
    @fs.rmdir(path + ".next")
    ignore(durable.approve("model.text", version, 2L))
    let before_promotion = durable.snapshot()
    @fs.mkdir(path + ".next")
    try
      durable.promote(
        "text.default",
        "model.text",
        version,
        Stable,
        "operator",
        3L,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("promotion succeeded despite failed persistence")
    }
    @async.with_timeout(1000, () => {
      assert_eq(durable.snapshot(), before_promotion)
      assert_eq(@registry.FileRegistry::open(path).snapshot(), before_promotion)
    })
    @fs.rmdir(path + ".next")
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
async test "verified import adoption persists model and pending license atomically" {
  let directory = @fs.tmpdir(prefix="lunanexa-registry-adopt-test-")
  let path = "\{directory}/registry.json"
  let durable = @registry.FileRegistry::open(path)
  let model = candidate("v1")
  let license : @registry.LicenseRecord = {
    license_id: model.license_id,
    model_id: model.model_id,
    status: Pending,
    accepted_by: "",
    evidence_ref: "modelscope-license:apache-2.0",
    expires_unix_ms: None,
  }
  durable.adopt_import(model, license)
  let adopted = @registry.FileRegistry::open(path).snapshot()
  assert_eq(adopted.models, [model])
  assert_eq(adopted.licenses, [license])
  let before_replay = durable.snapshot()
  durable.adopt_import(model, license)
  assert_eq(durable.snapshot(), before_replay)
  let mut conflicted = false
  ignore(
    durable.adopt_import(model, {
      ..license,
      evidence_ref: "modelscope-license:conflicting",
    }),
  ) catch {
    _ => conflicted = true
  }
  assert_true(conflicted)
  assert_eq(durable.snapshot(), before_replay)
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

///|
test "scheduling binds the promoted model to its evaluated runtime" {
  let registry = @registry.ModelRegistry::new()
  make_approvable(registry, "v1")
  ignore(registry.approve("model.text", "v1", 2L))
  ignore(
    registry.promote("text.default", "model.text", "v1", Stable, "operator", 3L),
  )
  let stale_runtime : @contracts.RuntimeSpec = {
    name: "text-runtime",
    image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    version: "runtime-0",
    architectures: ["nvidia-gb10"],
    capabilities: [TextGenerate],
    supports_batching: false,
    supports_multi_node: false,
  }
  let evaluated_runtime : @contracts.RuntimeSpec = {
    ..stale_runtime,
    image_digest: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    version: "runtime-1",
  }
  registry.register_runtime(stale_runtime)
  registry.register_runtime(evaluated_runtime)
  for digest in [stale_runtime.image_digest, evaluated_runtime.image_digest] {
    registry.record_verification({
      digest,
      signature_verified: true,
      provenance_verified: true,
      verified_unix_ms: 4L,
      verifier: "cosign-key:test",
    })
  }
  guard registry.scheduling_target("text.default", TextGenerate) is Some(target) else {
    fail("expected an evaluated scheduling target")
  }
  assert_eq(target.runtime, evaluated_runtime)
}

///|
/// A deployment that has shelved evaluation says so at open time. The model
/// still has to have been verified for real -- a candidate is never approvable
/// -- and the promotion receipt records that no evaluation took part, so the
/// absence is visible in the audit trail rather than implied by it.
test "a shelved evaluation still requires verification and is recorded as absent" {
  let registry = @registry.ModelRegistry::new()
  let model = candidate("v-shelved")
  registry.register_model(model)
  registry.record_license({
    license_id: "license.text",
    model_id: "model.text",
    status: Accepted,
    accepted_by: "operator",
    evidence_ref: "modelstore://owner/repo/LICENSE#sha256=abc",
    expires_unix_ms: None,
  })

  // Verified but unevaluated: refused while evaluation is required.
  registry.record_verification({
    digest: model.artifact.digest,
    signature_verified: true,
    provenance_verified: true,
    verified_unix_ms: 1L,
    verifier: "modelstore-manifest:modelstore://owner/repo",
  })
  try
    ignore(registry.approve("model.text", "v-shelved", 1000L))
  catch {
    @registry.RegistryError::EvaluationNotPassed(_) => ()
    _ => fail("wrong refusal: a missing evaluation was not the reason")
  } noraise {
    _ => fail("an unevaluated model was approved while evaluation was required")
  }

  // Shelved: approvable from Verified, and the receipt says no evaluation ran.
  let approved = registry.approve(
    "model.text", "v-shelved", 1000L, require_evaluation=false,
  )
  assert_eq(approved.state, Approved)
  let receipt = registry.promote(
    "text.default",
    "model.text",
    "v-shelved",
    @registry.RolloutStage::Canary,
    "operator",
    1000L,
    require_evaluation=false,
  )
  assert_eq(receipt.evaluation_id, "")
  assert_eq(registry.model("model.text", "v-shelved").unwrap().state, Approved)
}

///|
/// The shelved policy is not a way in for an unverified artifact: that gate is
/// untouched and still refuses.
test "a shelved evaluation does not admit an unverified artifact" {
  let registry = @registry.ModelRegistry::new()
  registry.register_model(candidate("v-unverified"))
  registry.record_license({
    license_id: "license.text",
    model_id: "model.text",
    status: Accepted,
    accepted_by: "operator",
    evidence_ref: "evidence:license",
    expires_unix_ms: None,
  })
  try
    ignore(registry.approve("model.text", "v-unverified", 1000L, require_evaluation=false))
  catch {
    @registry.RegistryError::ArtifactNotVerified(_) => ()
    _ => fail("wrong refusal: verification was not the reason")
  } noraise {
    _ => fail("an unverified model was approved")
  }
}
