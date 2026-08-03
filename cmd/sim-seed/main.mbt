///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required simulator environment is missing: \{name}")
  }
  value
}

///|
async fn main {
  if @env.get_env_var("LUNANEXA_SIMULATION_ONLY") != Some("1") {
    raise Failure::Failure(
      "simulated registry evidence requires explicit simulation-only mode",
    )
  }
  let registry = @registry.FileRegistry::open(
    required_environment("LUNANEXA_REGISTRY_PATH"),
  )
  let artifact_digest = required_environment("LUNANEXA_MODEL_ARTIFACT_DIGEST")
  let image_digest = required_environment("LUNANEXA_RUNTIME_IMAGE_DIGEST")
  let runtime : @contracts.RuntimeSpec = {
    name: "text-runtime",
    image_digest,
    version: "sim-runtime-v1",
    architectures: ["nvidia-gb10"],
    capabilities: [TextGenerate],
    supports_batching: false,
    supports_multi_node: false,
  }
  let model : @contracts.ModelRecord = {
    model_id: "model.text",
    version: "v1",
    artifact: {
      digest: artifact_digest,
      uri: "s3://simulator/model.text/v1",
      size_bytes: 1024L,
      signature_ref: "simulator-evidence:model.text:v1",
    },
    license_id: "license.text",
    provenance: "simulator-fixture:v1",
    compatible_architectures: ["nvidia-gb10"],
    minimum_memory_mib: 8192,
    state: Candidate,
  }
  registry.register_model(model)
  registry.register_runtime(runtime)
  registry.record_license({
    license_id: "license.text",
    model_id: "model.text",
    status: Accepted,
    accepted_by: "simulator",
    evidence_ref: "simulator-evidence:license",
    expires_unix_ms: None,
  })
  for digest in [artifact_digest, image_digest] {
    registry.record_verification({
      digest,
      signature_verified: true,
      provenance_verified: true,
      verified_unix_ms: @async.now(),
      verifier: "simulator-only",
    })
  }
  registry.record_evaluation({
    evaluation_id: "evaluation-sim-v1",
    model_id: "model.text",
    model_version: "v1",
    suite_version: "simulator-suite-v1",
    passed: true,
    score: 1.0,
    benchmark: {
      profile_id: "simulated-dgx-functional-v1",
      model_id: "model.text",
      model_version: "v1",
      runtime_version: "sim-runtime-v1",
      hardware_profile: "simulated-dgx-spark",
      workload_profile: "functional-only",
      p50_ms: 0.0,
      p95_ms: 0.0,
      p99_ms: 0.0,
      throughput_per_second: 0.0,
      peak_memory_mib: 8192,
    },
    evidence_ref: "simulator-evidence:evaluation",
  })
  ignore(registry.approve("model.text", "v1", @async.now()))
  ignore(
    registry.promote(
      "text.default",
      "model.text",
      "v1",
      Stable,
      "simulator",
      @async.now(),
    ),
  )
  println("seeded simulator-only approved registry state")
}
