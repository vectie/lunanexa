///|
fn template() -> @deployment.ModelServiceTemplate {
  {
    template_id: "text-small",
    version: "v1",
    display_name: "Text small",
    description: "Approved text service",
    model_selector: "text.default",
    model_id: "model.text",
    model_version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model.text/v1",
      size_bytes: 1L,
      signature_ref: "s3://models/model.text/v1.sig",
    },
    runtime: {
      name: "text-runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "runtime-v1",
      architectures: ["nvidia-gb10"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    capability: TextGenerate,
    architecture: "nvidia-gb10",
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 1000,
      cpu_millis: 1000,
      memory_mib: 2000,
    },
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
      classification: Internal,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    secret_refs: ["runtime-token"],
    rollout: {
      canary_replicas: 1,
      automatic_promotion: false,
      automatic_rollback: true,
      readiness_timeout_ms: 60000L,
    },
    approval_receipt: "catalog:text-small:v1",
    signature: "signed",
  }
}

///|
fn intent() -> @deployment.ModelServiceIntent {
  {
    version: @contracts.contract_version,
    idempotency_key: "deploy-text-small",
    deployment_id: "text-small-service",
    template: { template_id: "text-small", version: "v1", },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
    topology_profile: None,
  }
}

///|
test "approved template produces deterministic executable plan" {
  let catalog = template()
  let plan = @deployment.preflight([catalog], intent(), {
    registry: [
      {
        model_id: catalog.model_id,
        model_version: catalog.model_version,
        model_state: Approved,
        artifact_digest: catalog.artifact.digest,
        runtime_name: catalog.runtime.name,
        runtime_version: catalog.runtime.version,
        runtime_image_digest: catalog.runtime.image_digest,
        model_selector: catalog.model_selector,
        license_accepted: true,
        artifact_verified: true,
        runtime_verified: true,
        evaluation_passed: true,
        alias_points_to_model: true,
      },
    ],
    nodes: [
      {
        node_id: "node-a",
        state: Active,
        architecture: "nvidia-gb10",
        memory_free_mib: 8000,
        runtime_names: ["text-runtime"],
        device_ids: ["gpu-0"],
        allowed_data_classes: [Internal],
        cx7_peer: "",
        cx7_address: "",
      },
    ],
    available_secret_refs: ["runtime-token"],
  })
  assert_true(plan.executable)
  assert_eq(plan.plan_id, "plan:text-small-service:text-small:v1")
  assert_eq(plan.replicas[0].node_id, "node-a")
  let assignments = @deployment.desired_assignments(plan, 2L, 1L, 1000L)
  assert_eq(assignments[0].assignment_id, "text-small-service-r1")
  assert_eq(assignments[0].controller_epoch, 2L)
}

///|
test "preflight blocks missing evidence secrets and capacity" {
  let plan = @deployment.preflight([template()], intent(), {
    registry: [],
    nodes: [],
    available_secret_refs: [],
  })
  assert_false(plan.executable)
  assert_true(plan.findings.any(value => value.code == RuntimeNotRegistered))
  assert_true(plan.findings.any(value => value.code == MissingSecretReference))
  assert_true(
    plan.findings.any(value => value.message.contains("runtime-token")),
  )
  assert_true(plan.findings.any(value => value.code == NoCompatibleNode))
}

///|
test "dedicated preflight is pinned to the controller-reserved node" {
  let catalog = template()
  let evidence : @deployment.RegistryEvidence = {
    model_id: catalog.model_id,
    model_version: catalog.model_version,
    model_state: Approved,
    artifact_digest: catalog.artifact.digest,
    runtime_name: catalog.runtime.name,
    runtime_version: catalog.runtime.version,
    runtime_image_digest: catalog.runtime.image_digest,
    model_selector: catalog.model_selector,
    license_accepted: true,
    artifact_verified: true,
    runtime_verified: true,
    evaluation_passed: true,
    alias_points_to_model: true,
  }
  let node_a : @deployment.ManagementNode = {
    node_id: "node-a",
    state: Active,
    architecture: "nvidia-gb10",
    memory_free_mib: 8000,
    runtime_names: ["text-runtime"],
    device_ids: ["gpu-a"],
    allowed_data_classes: [Internal],
    cx7_peer: "",
    cx7_address: "",
  }
  let plan = @deployment.preflight_on_node(
    [catalog],
    intent(),
    {
      registry: [evidence],
      nodes: [node_a, { ..node_a, node_id: "node-b", device_ids: ["gpu-b"], }],
      available_secret_refs: ["runtime-token"],
    },
    "node-b",
  )
  assert_true(plan.executable)
  assert_eq(plan.replicas.length(), 1)
  assert_eq(plan.replicas[0].node_id, "node-b")
  let context : @deployment.PlanningContext = {
    registry: [evidence],
    nodes: [node_a, { ..node_a, node_id: "node-b", device_ids: ["gpu-b"], }],
    available_secret_refs: ["runtime-token"],
  }
  assert_eq(
    @deployment.preflight([catalog], intent(), context, preferred_node_ids=[
      "node-b",
    ]).replicas[0].node_id,
    "node-b",
  )
  assert_eq(
    @deployment.preflight(
      [catalog],
      intent(),
      {
        ..context,
        nodes: [node_a, { ..node_a, node_id: "node-b", state: Unreachable, }],
      },
      preferred_node_ids=["node-b", "foreign-node"],
    ).replicas[0].node_id,
    "node-a",
  )
}

///|
test "dedicated preflight cannot waive node eligibility" {
  let catalog = template()
  let blocked = @deployment.preflight_on_node(
    [catalog],
    intent(),
    {
      registry: [
        {
          model_id: catalog.model_id,
          model_version: catalog.model_version,
          model_state: Approved,
          artifact_digest: catalog.artifact.digest,
          runtime_name: catalog.runtime.name,
          runtime_version: catalog.runtime.version,
          runtime_image_digest: catalog.runtime.image_digest,
          model_selector: catalog.model_selector,
          license_accepted: true,
          artifact_verified: true,
          runtime_verified: true,
          evaluation_passed: true,
          alias_points_to_model: true,
        },
      ],
      nodes: [
        {
          node_id: "node-a",
          state: Active,
          architecture: "nvidia-gb10",
          memory_free_mib: 8000,
          runtime_names: ["text-runtime"],
          device_ids: ["gpu-a"],
          allowed_data_classes: [Internal],
          cx7_peer: "",
          cx7_address: "",
        },
      ],
      available_secret_refs: ["runtime-token"],
    },
    "node-missing",
  )
  assert_false(blocked.executable)
  assert_true(blocked.findings.any(value => value.code == NoCompatibleNode))
}

///|
test "one-click catalog rejects container-managed artifact downloads" {
  let unsupported = {
    ..template(),
    artifact: { ..template().artifact, uri: "oci://models/model.text:v1", },
  }
  try
    @deployment.validate_template(unsupported, require_signature=false)
  catch {
    InvalidTemplate(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a non-materializable template was accepted")
  }
  let plan = @deployment.preflight([unsupported], intent(), {
    registry: [],
    nodes: [],
    available_secret_refs: [],
  })
  assert_true(
    plan.findings.any(value => value.code == ArtifactMaterializationUnsupported),
  )
}

///|
fn cx7_evidence() -> @deployment.RegistryEvidence {
  let catalog = template()
  {
    model_id: catalog.model_id,
    model_version: catalog.model_version,
    model_state: Approved,
    artifact_digest: catalog.artifact.digest,
    runtime_name: catalog.runtime.name,
    runtime_version: catalog.runtime.version,
    runtime_image_digest: catalog.runtime.image_digest,
    model_selector: catalog.model_selector,
    license_accepted: true,
    artifact_verified: true,
    runtime_verified: true,
    evaluation_passed: true,
    alias_points_to_model: true,
  }
}

///|
fn cx7_node(
  node_id : String,
  peer : String,
  address : String,
) -> @deployment.ManagementNode {
  {
    node_id,
    state: Active,
    architecture: "nvidia-gb10",
    memory_free_mib: 8000,
    runtime_names: ["text-runtime"],
    device_ids: ["gpu-0"],
    allowed_data_classes: [Internal],
    cx7_peer: peer,
    cx7_address: address,
  }
}

///|
fn cx7_context(
  nodes : Array[@deployment.ManagementNode],
) -> @deployment.PlanningContext {
  {
    registry: [cx7_evidence()],
    nodes,
    available_secret_refs: ["runtime-token"],
  }
}

///|
fn cx7_pair_template() -> @deployment.ModelServiceTemplate {
  let pair : @contracts.RuntimeSpec = {
    ..template().runtime,
    supports_multi_node: true,
  }
  { ..template(), runtime: pair, }
}

///|
fn cx7_pair_intent() -> @deployment.ModelServiceIntent {
  { ..intent(), topology_profile: Some(@contracts.cx7_pair_topology_profile), }
}

///|
/// The geometry is a claim the intent makes and the template must honour. These
/// cases pin that neither alone can authorise a paired placement, and that a
/// pair is produced only from two compatible nodes that name each other and
/// both declare a fabric address.
test "a paired placement is gated on the intent and the runtime together" {
  let pair_template = cx7_pair_template()
  let pair_intent = cx7_pair_intent()

  // Runtime can pair, intent says nothing: the geometry was not declared.
  let undeclared = @deployment.preflight(
    [pair_template],
    intent(),
    cx7_context([]),
  )
  assert_true(
    undeclared.findings.any(value => value.code == GeometryNotDeclared),
  )

  // Intent names the pair but the runtime cannot: refused on the template side.
  let cannot = @deployment.preflight([template()], pair_intent, cx7_context([]))
  assert_true(cannot.findings.any(value => value.code == RuntimeCannotPair))

  // A profile other than the single admitted one is an invalid intent.
  let other = @deployment.preflight(
    [pair_template],
    { ..intent(), topology_profile: Some("any-two-nodes"), },
    cx7_context([]),
  )
  assert_true(other.findings.any(value => value.code == InvalidIntent))

  // Both claims hold and two compatible nodes name each other with an address
  // each: one logical instance, two ranked members.
  let planned = @deployment.preflight(
    [pair_template],
    pair_intent,
    cx7_context([
      cx7_node("node-a", "node-b", "10.0.22.1"),
      cx7_node("node-b", "node-a", "10.0.22.2"),
    ]),
  )
  assert_true(planned.executable)
  assert_eq(planned.replicas.length(), 2)
  assert_eq(planned.replicas[0].node_id, "node-a")
  assert_eq(planned.replicas[1].node_id, "node-b")
  let head = planned.replicas[0].group.unwrap()
  assert_eq(head.group_id, "text-small-service-pair")
  assert_eq(head.rank, 0)
  assert_eq(head.world_size, 2)
  assert_eq(head.peer_endpoint, "10.0.22.2")
  let worker = planned.replicas[1].group.unwrap()
  assert_eq(worker.rank, 1)
  assert_eq(worker.peer_endpoint, "10.0.22.1")
  let assignments = @deployment.desired_assignments(planned, 2L, 1L, 1000L)
  assert_eq(assignments.length(), 2)
  assert_eq(assignments[1].group.unwrap().rank, 1)
  assert_eq(assignments[1].group.unwrap().peer_endpoint, "10.0.22.1")

  // One-way naming is not a pair: nothing is half-placed.
  let one_way = @deployment.preflight(
    [pair_template],
    pair_intent,
    cx7_context([cx7_node("node-a", "node-b", "10.0.22.1")]),
  )
  assert_false(one_way.executable)
  assert_true(one_way.findings.any(value => value.code == NoCx7Pair))
  assert_eq(one_way.replicas.length(), 0)

  // Mutual naming without an address on the private fabric is refused too.
  let addressless = @deployment.preflight(
    [pair_template],
    pair_intent,
    cx7_context([
      cx7_node("node-a", "node-b", ""),
      cx7_node("node-b", "node-a", "10.0.22.2"),
    ]),
  )
  assert_false(addressless.executable)
  assert_true(addressless.findings.any(value => value.code == NoCx7Pair))
  assert_eq(addressless.replicas.length(), 0)

  // Three compatible nodes still yield one pair, never three.
  let triangle = @deployment.preflight(
    [pair_template],
    pair_intent,
    cx7_context([
      cx7_node("node-a", "node-b", "10.0.22.1"),
      cx7_node("node-b", "node-a", "10.0.22.2"),
      cx7_node("node-c", "node-a", "10.0.22.3"),
    ]),
  )
  assert_true(triangle.executable)
  assert_eq(triangle.replicas.length(), 2)
  assert_eq(triangle.replicas[0].node_id, "node-a")
  assert_eq(triangle.replicas[1].node_id, "node-b")
}

///|
/// A deployment document written before the geometry field existed must still
/// decode: clients are not forced to add a key to keep working.
test "an intent document without the geometry field still decodes" {
  let document =
    #|{"version":"lunanexa.v1","idempotency_key":"k","deployment_id":"d","template":{"template_id":"t","version":"v1"},"replicas":1,"data_class":"Confidential","lease_duration_ms":"1000","promote_when_ready":false}
  let decoded : @deployment.ModelServiceIntent? = try
    Some(@json.from_json(@json.parse(document)))
  catch {
    _ => None
  } noraise {
    value => value
  }
  assert_true(decoded is Some(_))
  match decoded {
    Some(value) => assert_eq(value.topology_profile, None)
    None => ()
  }
}

///|
/// The model store is a real transport for this platform's own verified
/// revisions: the artifact gateway serves them, the node materializes them,
/// and the signature subject is the revision's source manifest rather than a
/// detached object. A template that names one must be registrable.
test "a verified model-store revision is a materializable artifact" {
  let revision : @deployment.ModelServiceTemplate = {
    ..template(),
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "modelstore://owner/repo",
      size_bytes: 1L,
      signature_ref: "modelstore://owner/repo/lunanexa-source-manifest.json",
    },
  }
  @deployment.validate_template(revision)

  let plan = @deployment.preflight([revision], intent(), {
    registry: [],
    nodes: [],
    available_secret_refs: ["runtime-token"],
  })
  assert_false(
    plan.findings.any(value => value.code == ArtifactMaterializationUnsupported),
  )

  // A transport this platform cannot materialize is still refused, and so is a
  // revision whose signature subject is missing.
  for
    unusable in [
      {
        ..revision,
        artifact: { ..revision.artifact, uri: "oci://registry/repo", },
      },
      {
        ..revision,
        artifact: { ..revision.artifact, uri: "modelstore://owner/../etc", },
      },
      { ..revision, artifact: { ..revision.artifact, signature_ref: "", }, },
    ] {
    try @deployment.validate_template(unusable) catch {
      _ => continue
    } noraise {
      _ => fail("an unmaterializable artifact reference was accepted")
    }
  }
}
