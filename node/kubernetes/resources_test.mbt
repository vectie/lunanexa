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
    device_plugin_resource: None,
    runtime_class_name: None,
    controller_namespace: None,
    runtime_secrets: None,
    fabric_address: None,
  }
}

///|
test "runtime quantities match Kubernetes canonical serialization" {
  let base = runtime_assignment()
  for
    sample in [
      (100, 256, "100m", "256Mi"),
      (1000, 2048, "1", "2Gi"),
      (1500, 1536, "1500m", "1536Mi"),
      (2000, 1048576, "2", "1Ti"),
      (1, 1073741824, "1m", "1Pi"),
    ] {
    let (cpu, memory, expected_cpu, expected_memory) = sample
    let assignment = {
      ..base,
      resources: { ..base.resources, cpu_millis: cpu, memory_mib: memory, },
    }
    let rendered = @kubernetes.render_runtime(
      runtime_settings(),
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      1000L,
    )
    guard rendered.pod
      is {
        "spec": {
          "containers": [
            { "resources": { "requests": requests, "limits": limits, .. }, .. },
          ],
          ..
        },
        ..
      } else {
      fail("runtime resource bounds missing")
    }
    assert_eq(requests, limits)
    guard requests
      is { "cpu": String(actual_cpu), "memory": String(actual_memory), .. } else {
      fail("quantity strings missing")
    }
    assert_eq(actual_cpu, expected_cpu)
    assert_eq(actual_memory, expected_memory)
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
    group: None,
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
      InvalidResource => ()
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
      InvalidResource => ()
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
      InvalidResource => ()
      _ => fail("wrong validation failure")
    } noraise {
      _ => fail("unsafe ingress accepted")
    }
  }
}

///|
fn paired_assignment(rank : Int, peer : String) -> @contracts.DesiredAssignment {
  {
    ..runtime_assignment(),
    group: Some({
      group_id: "deployment-1-pair",
      rank,
      world_size: 2,
      peer_endpoint: peer,
    }),
  }
}

///|
fn pod_environment(pod : Json) -> Array[Json] {
  guard pod
    is { "spec": { "containers": [{ "env": Array(environment), .. }], .. }, .. } else {
    abort("rendered pod carries no container environment")
  }
  environment
}

///|
fn environment_value(environment : Array[Json], name : String) -> String? {
  for entry in environment {
    if entry is { "name": String(observed), "value": String(value), .. } &&
      observed == name {
      return Some(value)
    }
  }
  None
}

///|
/// A member of a pair is rendered only when both the assignment and the node
/// name the fabric address this member answers on, and the rendered pod says
/// which rank it is and takes its isolated network away in favour of the host
/// fabric. Nothing here is guessed from the peer's side.
test "a paired runtime renders rank identity, fabric passthrough and a named peer" {
  let head = paired_assignment(0, "192.168.2.179")
  let settings = {
    ..runtime_settings(),
    fabric_address: Some("192.168.2.178"),
  }
  let resources = @kubernetes.render_runtime(
    settings,
    head,
    "/var/lib/lunanexa/models/model",
    head.artifact.digest,
    5L,
    1000L,
  )
  assert_true(
    resources.pod
    is {
      "spec": {
        "hostNetwork": true,
        "dnsPolicy": "ClusterFirstWithHostNet",
        "volumes": [
          { "name": "model", .. },
          { "name": "infiniband", .. },
          { "name": "shm", .. },
        ],
        "containers": [
          {
            "securityContext": {
              "capabilities": { "add": ["IPC_LOCK"], .. },
              ..
            },
            "volumeMounts": [
              { "name": "model", .. },
              { "name": "infiniband", .. },
              { "name": "shm", .. },
            ],
            ..
          },
        ],
        ..
      },
      ..
    },
  )
  let environment = pod_environment(resources.pod)
  assert_eq(environment_value(environment, "LUNANEXA_RANK"), Some("0"))
  assert_eq(environment_value(environment, "LUNANEXA_WORLD_SIZE"), Some("2"))
  assert_eq(
    environment_value(environment, "LUNANEXA_PEER_ENDPOINT"),
    Some("192.168.2.179"),
  )
  assert_eq(
    environment_value(environment, "LUNANEXA_HEAD_ENDPOINT"),
    Some("192.168.2.178"),
  )
  assert_true(
    resources.network_policy
    is {
      "spec": {
        "ingress": [
          {
            "from": [
              { "ipBlock": { "cidr": "192.168.2.175/32", .. }, .. },
              { "ipBlock": { "cidr": "192.168.2.179/32", .. }, .. },
            ],
            ..
          },
        ],
        "egress": [
          { "to": [{ "ipBlock": { "cidr": "192.168.2.179/32", .. }, .. }], .. },
        ],
        ..
      },
      ..
    },
  )

  // The peer takes its rendezvous point from the head, not from itself.
  let worker = @kubernetes.render_runtime(
    { ..settings, fabric_address: Some("192.168.2.179"), },
    paired_assignment(1, "192.168.2.178"),
    "/var/lib/lunanexa/models/model",
    head.artifact.digest,
    5L,
    1000L,
  )
  assert_eq(
    environment_value(pod_environment(worker.pod), "LUNANEXA_RANK"),
    Some("1"),
  )
  assert_eq(
    environment_value(pod_environment(worker.pod), "LUNANEXA_HEAD_ENDPOINT"),
    Some("192.168.2.178"),
  )

  // A node that declares no fabric address cannot host half a pair: the two
  // containers would never find each other, so nothing is rendered.
  for
    unusable in [
      { ..settings, fabric_address: None, },
      { ..settings, fabric_address: Some(""), },
      { ..settings, fabric_address: Some("10.1.2.3/8"), },
      { ..settings, fabric_address: Some("192.168.2.179"), },
    ] {
    try
      ignore(
        @kubernetes.render_runtime(
          unusable,
          head,
          "/var/lib/lunanexa/models/model",
          head.artifact.digest,
          5L,
          1000L,
        ),
      )
    catch {
      InvalidResource => ()
      _ => fail("wrong validation failure")
    } noraise {
      _ => fail("paired runtime accepted without a usable fabric address")
    }
  }
  for
    broken in [
      { ..head, group: Some({ ..head.group.unwrap(), rank: 2, }), },
      { ..head, group: Some({ ..head.group.unwrap(), world_size: 3, }), },
      {
        ..head,
        group: Some({ ..head.group.unwrap(), peer_endpoint: "127.0.0.1", }),
      },
      { ..head, group: Some({ ..head.group.unwrap(), peer_endpoint: "", }), },
      {
        ..head,
        group: Some({ ..head.group.unwrap(), group_id: "Deployment Pairs", }),
      },
    ] {
    try
      ignore(
        @kubernetes.render_runtime(
          settings,
          broken,
          "/var/lib/lunanexa/models/model",
          head.artifact.digest,
          5L,
          1000L,
        ),
      )
    catch {
      InvalidResource => ()
      _ => fail("wrong validation failure")
    } noraise {
      _ => fail("invalid pair accepted")
    }
  }

  // A single-machine assignment is untouched: same pod, no fence opened.
  let single = @kubernetes.render_runtime(
    settings,
    runtime_assignment(),
    "/var/lib/lunanexa/models/model",
    head.artifact.digest,
    5L,
    1000L,
  )
  assert_false(single.pod.stringify().contains("hostNetwork\":true"))
  assert_false(single.pod.stringify().contains("LUNANEXA_RANK"))
  assert_true(single.network_policy is { "spec": { "egress": [], .. }, .. })
}

///|
/// A cluster that exposes its GPUs through the device plugin cannot be given a
/// DRA claim: nothing would allocate it. The same assignment is therefore
/// rendered as a counted extended resource, with the exact devices the
/// signature pinned kept in the variable the GPU runtime reads.
test "a device-plugin cluster renders a counted resource and keeps the exact devices" {
  let assignment = runtime_assignment()
  let settings : @kubernetes.RuntimeSettings = {
    ..runtime_settings(),
    device_plugin_resource: Some("nvidia.com/gpu"),
    runtime_class_name: Some("nvidia"),
  }
  let resources = @kubernetes.render_runtime(
    settings,
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
        "runtimeClassName": "nvidia",
        "resourceClaims": [],
        "containers": [
          {
            "resources": {
              "requests": { "nvidia.com/gpu": 1, .. },
              "limits": { "nvidia.com/gpu": 1, .. },
              "claims": [],
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
  let environment = pod_environment(resources.pod)
  assert_false(
    environment.any(value => value is { "name": "LUNANEXA_RANK", .. }),
  )
  assert_eq(
    environment_value(environment, "NVIDIA_VISIBLE_DEVICES"),
    Some(assignment.devices[0]),
  )

  // A CPU-only assignment asks for no GPU either way.
  let cpu_only = {
    ..assignment,
    devices: [],
    resources: { ..assignment.resources, accelerator_count: 0, },
  }
  let resources = @kubernetes.render_runtime(
    settings,
    cpu_only,
    "/var/lib/lunanexa/models/model",
    cpu_only.artifact.digest,
    5L,
    1000L,
  )
  assert_false(resources.pod.stringify().contains("nvidia.com/gpu"))
  assert_false(resources.pod.stringify().contains("NVIDIA_VISIBLE_DEVICES"))

  for
    unusable in [
      { ..settings, device_plugin_resource: Some("nvidia.com"), },
      { ..settings, device_plugin_resource: Some("not a resource"), },
      { ..settings, device_plugin_resource: Some("nvidia.com/"), },
      { ..settings, runtime_class_name: Some("Nvidia Class"), },
    ] {
    try
      ignore(
        @kubernetes.render_runtime(
          unusable,
          assignment,
          "/var/lib/lunanexa/models/model",
          assignment.artifact.digest,
          5L,
          1000L,
        ),
      )
    catch {
      InvalidResource => ()
      _ => fail("wrong validation failure")
    } noraise {
      _ => fail("invalid device-plugin configuration accepted")
    }
  }
}

///|
/// The controller's pod address changes whenever the pod is replaced, so a
/// policy that names it goes stale. Naming the namespace instead keeps the
/// runtime reachable without re-deriving anything, and an address may still be
/// listed alongside it for a controller outside the cluster.
test "the runtime accepts its controller by namespace rather than by address" {
  let assignment = runtime_assignment()
  let by_namespace : @kubernetes.RuntimeSettings = {
    ..runtime_settings(),
    controller_addresses: [],
    controller_namespace: Some("lunanexa"),
  }
  let resources = @kubernetes.render_runtime(
    by_namespace,
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    1000L,
  )
  assert_true(
    resources.network_policy
    is {
      "spec": {
        "ingress": [
          {
            "from": [
              {
                "namespaceSelector": {
                  "matchLabels": {
                    "kubernetes.io/metadata.name": "lunanexa",
                    ..
                  },
                  ..
                },
                ..
              },
            ],
            ..
          },
        ],
        ..
      },
      ..
    },
  )

  let both = @kubernetes.render_runtime(
    { ..runtime_settings(), controller_namespace: Some("lunanexa"), },
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    1000L,
  )
  assert_true(
    both.network_policy
    is {
      "spec": {
        "ingress": [
          {
            "from": [
              { .. },
              { "ipBlock": { "cidr": "192.168.2.175/32", .. }, .. },
            ],
            ..
          },
        ],
        ..
      },
      ..
    },
  )

  // Neither a namespace nor an address would leave the runtime with no
  // controller that is allowed to reach it, which is not a usable state.
  try
    ignore(
      @kubernetes.render_runtime(
        {
          ..runtime_settings(),
          controller_addresses: [],
          controller_namespace: Some("Not A Namespace"),
        },
        assignment,
        "/var/lib/lunanexa/models/model",
        assignment.artifact.digest,
        5L,
        1000L,
      ),
    )
  catch {
    InvalidResource => ()
    _ => fail("wrong validation failure")
  } noraise {
    _ => fail("an unreachable runtime was rendered")
  }
}
