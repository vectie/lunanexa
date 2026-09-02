///|
fn supervisor_assignment() -> @contracts.DesiredAssignment {
  {
    assignment_id: "assignment-materialize-1",
    deployment_id: "deployment-materialize-1",
    node_id: "node-a",
    artifact: {
      digest: "sha256:6521df166eb07efaf36eba5b6bedefd9d6a252e9c80bab1c99653700ec71473c",
      uri: "s3://models/model.bin",
      size_bytes: 14L,
      signature_ref: "s3://models/model.bin.sig",
    },
    runtime: {
      name: "registry.invalid/text-runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "runtime-v1",
      architectures: ["nvidia-gb10"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 8000,
      cpu_millis: 2000,
      memory_mib: 16000,
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
      termination_grace_ms: 5000,
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
    signature: "signed",
  }
}

///|
test "local Podman mode does not inject a remote engine socket" {
  let supervisor = OciRuntimeSupervisor::new(
    "/usr/bin/podman", "lunanexa-runtime", "local://",
  )
  assert_eq(supervisor.engine_environment().length(), 0)
}

///|
test "runtime arguments mount only the verified local model" {
  let assignment = supervisor_assignment()
  let artifact : MaterializedArtifact = {
    digest: assignment.artifact.digest,
    host_path: "/var/lib/lunanexa/models/sha256/model.model",
    size_bytes: assignment.artifact.size_bytes,
  }
  let arguments = runtime_run_arguments(
    assignment,
    artifact,
    "lunanexa-assignment-materialize-1",
    "registry.invalid/text-runtime@\{assignment.runtime.image_digest}",
    "lunanexa-runtime",
    512,
  )
  assert_true(
    arguments.any(value => {
      value ==
      "type=bind,src=/var/lib/lunanexa/models/sha256/model.model,dst=/var/lib/lunanexa/model/model,readonly"
    }),
  )
  assert_true(
    arguments.any(value => {
      value == "LUNANEXA_MODEL_PATH=/var/lib/lunanexa/model/model"
    }),
  )
  assert_false(arguments.any(value => value.contains("s3://")))
  assert_false(arguments.any(value => value.contains("artifact-token")))
  assert_false(arguments.any(value => value.contains("podman.sock")))
  assert_false(arguments.any(value => value == "--privileged"))
  assert_false(arguments.any(value => value == "host"))
  assert_true(arguments.any(value => value == "--pids-limit=512"))
  for
    required in [
      "--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges", "--pull=never",
      "--restart=no",
    ] {
    assert_true(arguments.any(value => value == required))
  }
}
