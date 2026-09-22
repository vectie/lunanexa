///|
fn group_assignment(
  group : @contracts.AssignmentGroup?,
) -> @contracts.DesiredAssignment {
  {
    assignment_id: "assignment-group-1",
    deployment_id: "deployment-group-1",
    node_id: "node-a",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "modelstore://qwen3635ba3bfp8",
      size_bytes: 14L,
      signature_ref: "modelstore://qwen3635ba3bfp8/lunanexa-source-manifest.json",
    },
    runtime: {
      name: "registry.invalid/text-runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "runtime-v1",
      architectures: ["nvidia-gb10"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: true,
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
    group,
    reservation: None,
    signature: "",
  }
}

///|
/// The compatibility invariant behind the group field: a single-machine
/// assignment must serialize exactly as it did before pairs existed. If an
/// absent group were written as `null` instead of omitted, every signature
/// would change and a node running the previous build would reject live
/// assignments during a rolling update.
test "an absent group is omitted from the wire form, not written as null" {
  let alone = group_assignment(None)
  let json = alone.to_json().stringify()
  assert_false(json.contains("\"group\""))
  assert_false(json.contains("null"))
  assert_true(json.contains("\"controller_epoch\""))

  let paired = group_assignment(
    Some({
      group_id: "group-abc",
      rank: 1,
      world_size: 2,
      peer_endpoint: "10.0.22.1",
    }),
  )
  let paired_json = paired.to_json().stringify()
  assert_true(paired_json.contains("\"group\""))
  assert_true(paired_json.contains("\"world_size\":2"))
  assert_true(paired_json.contains("\"peer_endpoint\":\"10.0.22.1\""))

  // The MAC covers the group, so a pair cannot be downgraded into a lone
  // member: the same assignment with and without it signs differently.
  let secret = "assignment-secret"
  assert_true(
    @node.assignment_signature(alone, secret) !=
    @node.assignment_signature(paired, secret),
  )
}

///|
test "reservation ownership is omitted for legacy assignments and authenticated when present" {
  let legacy = group_assignment(None)
  assert_false(legacy.to_json().stringify().contains("reservation"))
  let decoded : @contracts.DesiredAssignment = @json.from_json(legacy.to_json())
  assert_eq(decoded.reservation, None)
  let secret = "reservation-signature-fixture"
  assert_eq(
    @node.assignment_signature(decoded, secret),
    @node.assignment_signature(legacy, secret),
  )
  let owned = {
    ..legacy,
    reservation: Some({
      reservation_id: "reservation-a",
      tenant_ref: "tenant-a",
    }),
  }
  let signed = {
    ..owned,
    signature: @node.assignment_signature(owned, secret),
  }
  let verifier = @node.SharedSecretAssignmentVerifier::new(secret)
  assert_true(verifier.verify(signed))
  assert_false(verifier.verify({ ..signed, reservation: None, }))
  assert_false(
    verifier.verify({
      ..signed,
      reservation: Some({
        reservation_id: "reservation-b",
        tenant_ref: "tenant-a",
      }),
    }),
  )
  assert_false(
    verifier.verify({
      ..signed,
      reservation: Some({
        reservation_id: "reservation-a",
        tenant_ref: "tenant-b",
      }),
    }),
  )
}
