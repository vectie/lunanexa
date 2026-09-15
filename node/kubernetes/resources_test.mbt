///|
fn runtime_settings() -> @kubernetes.RuntimeSettings {
  {
    namespace_name: "runtime",
    node_name: "compute-1",
    node_id: "node-1",
    model_cache_root: "/var/lib/lunanexa/models",
    runtime_port: 8080,
    run_as_user: 1000,
    device_class_name: "gpu.nvidia.com",
    controller_addresses: ["192.168.2.175"],
  }
}

///|
fn runtime_assignment() -> @contracts.DesiredAssignment {
  {
    assignment_id: "assignment-1",
    deployment_id: "deployment-1",
    node_id: "node-1",
    artifact: {
      digest: identity().artifact_digest,
      uri: "s3://models/fixture",
      size_bytes: 5L,
      signature_ref: "s3://models/fixture.sig",
    },
    runtime: {
      name: "registry/runtime",
      image_digest: identity().image_digest,
      version: "v1",
      architectures: ["nvidia-sm120"],
      capabilities: [VideoGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 100,
      cpu_millis: 100,
      memory_mib: 256,
    },
    devices: ["GPU-50c44f23-00cd-8871-b4c7-0c5a62d3e7f6"],
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
    controller_epoch: 1L,
    lease_expires_unix_ms: 60000L,
    signature: "fixture-only-already-verified-by-caller",
  }
}

///|
test "runtime rendering binds exact GPU UUID through DRA without bypassing scheduling" {
  let assignment = runtime_assignment()
  let resources = @kubernetes.render_runtime(
    runtime_settings(),
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    1000L,
  )
  assert_true(
    resources.claim_template
    is Some(
      {
        "spec": {
          "spec": {
            "devices": {
              "requests": [
                {
                  "exactly": {
                    "count": 1,
                    "allocationMode": "ExactCount",
                    "selectors": [
                      { "cel": { "expression": String(expression), .. }, .. },
                    ],
                    ..
                  },
                  ..
                },
              ],
              ..
            },
            ..
          },
          ..
        },
        ..
      }
    ) &&
    expression.contains(assignment.devices[0]),
  )
  assert_false(resources.pod.stringify().contains("NVIDIA_VISIBLE_DEVICES"))
  assert_false(resources.pod.stringify().contains("nodeName"))
  assert_false(resources.pod.stringify().contains("s3://"))
  assert_false(resources.pod.stringify().contains("signature"))
  assert_true(
    resources.pod
    is {
      "spec": {
        "automountServiceAccountToken": false,
        "restartPolicy": "Never",
        "containers": [
          {
            "securityContext": {
              "readOnlyRootFilesystem": true,
              "allowPrivilegeEscalation": false,
              ..
            },
            "volumeMounts": [{ "readOnly": true, .. }],
            ..
          },
        ],
        "volumes": [
          {
            "hostPath": {
              "path": "/var/lib/lunanexa/models/model",
              "type": "File",
              ..
            },
            ..
          },
        ],
        ..
      },
      ..
    },
  )
  assert_true(resources.network_policy is { "spec": { "egress": [], .. }, .. })
  assert_eq(
    resources,
    @kubernetes.render_runtime(
      runtime_settings(),
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      1000L,
    ),
  )
}

///|
test "honest CPU fixture has no GPU resource claims" {
  let original = runtime_assignment()
  let assignment = {
    ..original,
    devices: [],
    resources: {
      ..original.resources,
      accelerator_count: 0,
      accelerator_memory_mib: 0,
    },
  }
  let resources = @kubernetes.render_runtime(
    runtime_settings(),
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    1000L,
  )
  assert_eq(resources.claim_template, None)
  assert_true(
    resources.pod
    is {
      "spec": {
        "resourceClaims": [],
        "containers": [{ "resources": { "claims": [], .. }, .. }],
        ..
      },
      ..
    },
  )
}

///|
test "expired mismatched and duplicate GPU assignments fail before resource creation" {
  let original = runtime_assignment()
  for
    assignment in [
      { ..original, lease_expires_unix_ms: 1000L, },
      { ..original, node_id: "other", },
      { ..original, signature: "", },
      { ..original, devices: ["fake-spark"], },
      {
        ..original,
        devices: [original.devices[0], original.devices[0]],
        resources: { ..original.resources, accelerator_count: 2, },
      },
    ] {
    try
      @kubernetes.render_runtime(
        runtime_settings(),
        assignment,
        "/var/lib/lunanexa/models/model",
        assignment.artifact.digest,
        5L,
        1000L,
      )
    catch {
      @kubernetes.InvalidResource => ()
      _ => fail("wrong validation failure")
    } noraise {
      _ => fail("invalid assignment accepted")
    }
  }
}

///|
test "model mounts cannot escape the verified cache and ingress cannot become public" {
  let assignment = runtime_assignment()
  for
    path in [
      "/etc/shadow", "/var/lib/lunanexa/models/../shadow", "/var/lib/lunanexa/models2/blob",
      "/var/lib/lunanexa/models",
    ] {
    try
      @kubernetes.render_runtime(
        runtime_settings(),
        assignment,
        path,
        assignment.artifact.digest,
        5L,
        1000L,
      )
    catch {
      @kubernetes.InvalidResource => ()
      _ => fail("wrong validation failure")
    } noraise {
      _ => fail("unsafe mount accepted")
    }
  }
  for
    address in [
      "0.0.0.0/0", "8.8.8.8", "10.1.2.3/8", "192.168.999.1", "127.0.0.1",
    ] {
    try
      @kubernetes.render_runtime(
        { ..runtime_settings(), controller_addresses: [address], },
        assignment,
        "/var/lib/lunanexa/models/model",
        assignment.artifact.digest,
        5L,
        1000L,
      )
    catch {
      @kubernetes.InvalidResource => ()
      _ => fail("wrong validation failure")
    } noraise {
      _ => fail("unsafe ingress accepted")
    }
  }
}
