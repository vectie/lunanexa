///|
fn safe_runtime_name(value : String) -> Bool {
  value != "" &&
  value.length() <= 256 &&
  !value.contains("..") &&
  !value.contains_char('@') &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == ':' ||
    character == '/'
  })
}

///|
fn safe_s3_reference(value : String) -> Bool {
  guard value.has_prefix("s3://") else { return false }
  let object = value[5:].to_owned()
  object != "" &&
  object.length() <= 2048 &&
  object.contains_char('/') &&
  !object.has_prefix("/") &&
  !object.has_suffix("/") &&
  !object.contains("..") &&
  !object.contains("//") &&
  object.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == '/'
  })
}

///|
fn safe_signature_reference(value : String) -> Bool {
  safe_s3_reference(value) ||
  @contracts.valid_identifier(value, maximum_length=256)
}

///|
fn unique_strings(values : Array[String]) -> Bool {
  for index, value in values {
    if values[:index].any(previous => previous == value) {
      return false
    }
  }
  true
}

///|
fn safe_readiness_path(value : String) -> Bool {
  value.has_prefix("/") &&
  value.length() <= 256 &&
  !value.contains("..") &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == '/'
  })
}

///|
pub fn validate_template(
  template : ModelServiceTemplate,
  require_signature? : Bool = true,
) -> Unit raise DeploymentError {
  if !@contracts.valid_identifier(template.template_id, maximum_length=128) ||
    !@contracts.valid_identifier(template.version, maximum_length=128) ||
    template.display_name.trim() == "" ||
    template.display_name.length() > 256 ||
    template.description.length() > 2048 ||
    !@contracts.valid_identifier(template.model_selector, maximum_length=128) ||
    !@contracts.valid_identifier(template.model_id, maximum_length=128) ||
    !@contracts.valid_identifier(template.model_version, maximum_length=128) ||
    !@contracts.valid_identifier(template.architecture, maximum_length=128) ||
    !@contracts.valid_sha256_digest(template.artifact.digest) ||
    template.artifact.size_bytes <= 0L ||
    template.artifact.size_bytes > 1099511627776L ||
    !safe_s3_reference(template.artifact.uri) ||
    !safe_signature_reference(template.artifact.signature_ref) ||
    !template.network.allow_artifact_store ||
    !template.network.allow_controller ||
    template.network.allowed_egress.length() > 0 ||
    !safe_runtime_name(template.runtime.name) ||
    !@contracts.valid_identifier(template.runtime.version, maximum_length=128) ||
    !@contracts.valid_sha256_digest(template.runtime.image_digest) ||
    template.runtime.architectures.length() == 0 ||
    template.runtime.architectures.length() > 64 ||
    !template.runtime.architectures.all(value => {
      @contracts.valid_identifier(value, maximum_length=128)
    }) ||
    !unique_strings(template.runtime.architectures) ||
    !template.runtime.architectures.any(value => value == template.architecture) ||
    template.runtime.capabilities.length() == 0 ||
    template.runtime.capabilities.length() > 16 ||
    !template.runtime.capabilities.any(value => value == template.capability) ||
    template.resources.accelerator_count <= 0 ||
    template.resources.accelerator_count > 64 ||
    template.resources.accelerator_memory_mib <= 0 ||
    template.resources.accelerator_memory_mib > 1048576 ||
    template.resources.cpu_millis <= 0 ||
    template.resources.cpu_millis > 1000000 ||
    template.resources.memory_mib <= 0 ||
    template.resources.memory_mib > 1048576 ||
    !safe_readiness_path(template.health.readiness_path) ||
    template.health.interval_ms <= 0 ||
    template.health.interval_ms > 3600000 ||
    template.health.failure_threshold <= 0 ||
    template.health.failure_threshold > 100 ||
    template.health.termination_grace_ms <= 0 ||
    template.health.termination_grace_ms > 3600000 ||
    template.rollout.canary_replicas <= 0 ||
    template.rollout.canary_replicas > 64 ||
    template.rollout.readiness_timeout_ms <= 0L ||
    template.rollout.readiness_timeout_ms > 86400000L ||
    template.secret_refs.length() > 64 ||
    template.secret_refs.any(value => {
      !@contracts.valid_identifier(value, maximum_length=256)
    }) ||
    !unique_strings(template.secret_refs) ||
    (
      require_signature &&
      (template.approval_receipt == "" || template.signature == "")
    ) {
    raise InvalidTemplate(template.template_id)
  }
}

///|
pub fn validate_intent(
  intent : ModelServiceIntent,
) -> Unit raise DeploymentError {
  if intent.version != @contracts.contract_version ||
    !@contracts.valid_identifier(intent.idempotency_key, maximum_length=256) ||
    !@contracts.valid_identifier(intent.deployment_id, maximum_length=128) ||
    !@contracts.valid_identifier(
      intent.template.template_id,
      maximum_length=128,
    ) ||
    !@contracts.valid_identifier(intent.template.version, maximum_length=128) ||
    intent.replicas <= 0 ||
    intent.replicas > 64 ||
    intent.lease_duration_ms <= 0L ||
    intent.lease_duration_ms > 2592000000L {
    raise InvalidIntent(intent.deployment_id)
  }
}

///|
fn finding(
  code : FindingCode,
  severity : FindingSeverity,
  message : String,
) -> PreflightFinding {
  { code, severity, message }
}

///|
fn template_for(
  templates : Array[ModelServiceTemplate],
  reference : TemplateRef,
) -> ModelServiceTemplate? {
  templates
  .iter()
  .find_first(template => {
    template.template_id == reference.template_id &&
    template.version == reference.version
  })
}

///|
fn evidence_for(
  context : PlanningContext,
  template : ModelServiceTemplate,
) -> RegistryEvidence? {
  context.registry
  .iter()
  .find_first(evidence => {
    evidence.model_id == template.model_id &&
    evidence.model_version == template.model_version &&
    evidence.artifact_digest == template.artifact.digest &&
    evidence.runtime_name == template.runtime.name &&
    evidence.runtime_version == template.runtime.version &&
    evidence.runtime_image_digest == template.runtime.image_digest &&
    evidence.model_selector == template.model_selector
  })
}

///|
fn compatible_nodes(
  context : PlanningContext,
  template : ModelServiceTemplate,
  intent : ModelServiceIntent,
) -> Array[ManagementNode] {
  let nodes : Array[ManagementNode] = []
  for node in context.nodes {
    if node.state == Active &&
      @contracts.valid_identifier(node.node_id, maximum_length=96) &&
      node.architecture == template.architecture &&
      node.memory_free_mib >= template.resources.accelerator_memory_mib &&
      node.runtime_names.any(value => value == template.runtime.name) &&
      node.device_ids.length() >= template.resources.accelerator_count &&
      node.device_ids.all(value => {
        @contracts.valid_identifier(value, maximum_length=96)
      }) &&
      unique_strings(node.device_ids) &&
      node.allowed_data_classes.any(value => value == intent.data_class) &&
      !nodes.any(existing => existing.node_id == node.node_id) {
      nodes.push(node)
    }
  }
  nodes.sort_by_key(node => node.node_id)
  nodes
}

///|
pub fn preflight(
  templates : Array[ModelServiceTemplate],
  intent : ModelServiceIntent,
  context : PlanningContext,
) -> DeploymentPlan {
  let findings : Array[PreflightFinding] = []
  try validate_intent(intent) catch {
    _ =>
      findings.push(
        finding(InvalidIntent, Blocking, "deployment intent is invalid"),
      )
  } noraise {
    _ => ()
  }
  let selected_template = template_for(templates, intent.template)
  guard selected_template is Some(template) else {
    findings.push(
      finding(
        TemplateNotFound,
        Blocking,
        "the requested catalog template was not found",
      ),
    )
    return {
      plan_id: "plan:\{intent.deployment_id}:\{intent.template.template_id}:\{intent.template.version}",
      intent,
      template: None,
      replicas: [],
      findings,
      executable: false,
      endpoint: None,
    }
  }
  try validate_template(template) catch {
    _ =>
      findings.push(
        finding(
          TemplateNotApproved,
          Blocking,
          "the catalog template is not controller-approved",
        ),
      )
  } noraise {
    _ => ()
  }
  if !template.artifact.uri.has_prefix("s3://") ||
    template.artifact.signature_ref == "" ||
    !template.network.allow_artifact_store {
    findings.push(
      finding(
        ArtifactMaterializationUnsupported,
        Blocking,
        "the model blob and detached signature must be materializable from the artifact store",
      ),
    )
  }
  match evidence_for(context, template) {
    None =>
      findings.push(
        finding(
          RuntimeNotRegistered,
          Blocking,
          "the exact model and runtime profile is not registered",
        ),
      )
    Some(evidence) => {
      if evidence.model_state != Approved {
        findings.push(
          finding(ModelNotApproved, Blocking, "the model is not approved"),
        )
      }
      if !evidence.license_accepted {
        findings.push(
          finding(
            LicenseNotAccepted,
            Blocking,
            "the model license is not accepted or has expired",
          ),
        )
      }
      if !evidence.artifact_verified {
        findings.push(
          finding(
            ArtifactNotVerified,
            Blocking,
            "the model artifact is not verified",
          ),
        )
      }
      if !evidence.runtime_verified {
        findings.push(
          finding(
            RuntimeNotVerified,
            Blocking,
            "the runtime image is not verified",
          ),
        )
      }
      if !evidence.evaluation_passed {
        findings.push(
          finding(
            EvaluationNotPassed,
            Blocking,
            "the required model evaluation has not passed",
          ),
        )
      }
      if !evidence.alias_points_to_model {
        findings.push(
          finding(
            AliasNotApproved,
            Blocking,
            "the model selector does not point to this approved version",
          ),
        )
      }
    }
  }
  for secret_ref in template.secret_refs {
    if !context.available_secret_refs.any(value => value == secret_ref) {
      findings.push(
        finding(
          MissingSecretReference,
          Blocking,
          "required secret reference \{secret_ref} is unavailable",
        ),
      )
    }
  }
  if intent.promote_when_ready && !template.rollout.automatic_promotion {
    findings.push(
      finding(
        AutomaticPromotionDenied,
        Blocking,
        "this template requires an explicit promotion decision",
      ),
    )
  }
  let nodes = compatible_nodes(context, template, intent)
  if nodes.length() == 0 {
    findings.push(
      finding(
        NoCompatibleNode,
        Blocking,
        "no active node satisfies runtime, architecture, memory, device and data-class policy",
      ),
    )
  } else if nodes.length() < intent.replicas {
    findings.push(
      finding(
        InsufficientCapacity,
        Blocking,
        "requested replicas exceed compatible node capacity",
      ),
    )
  }
  let replicas : Array[PlannedReplica] = []
  if nodes.length() >= intent.replicas {
    for index in 0..<intent.replicas {
      let node = nodes[index]
      replicas.push({
        replica_id: "\{intent.deployment_id}-r\{index + 1}",
        node_id: node.node_id,
        devices: node.device_ids[:template.resources.accelerator_count].to_owned(),
      })
    }
  }
  let executable = !findings.any(value => value.severity == Blocking)
  {
    plan_id: "plan:\{intent.deployment_id}:\{intent.template.template_id}:\{intent.template.version}",
    intent,
    template: Some(template),
    replicas,
    findings,
    executable,
    endpoint: if executable {
      Some({
        canonical_path: "/v1/workloads",
        model_selector: template.model_selector,
      })
    } else {
      None
    },
  }
}

///|
pub fn desired_assignments(
  plan : DeploymentPlan,
  controller_epoch : Int64,
  generation : Int64,
  now_unix_ms : Int64,
) -> Array[@contracts.DesiredAssignment] raise DeploymentError {
  if !plan.executable ||
    controller_epoch <= 0L ||
    generation <= 0L ||
    plan.template is None {
    raise InvalidState(plan.plan_id)
  }
  let template = plan.template.unwrap()
  [
    for replica in plan.replicas => {
      {
        assignment_id: replica.replica_id,
        deployment_id: plan.intent.deployment_id,
        node_id: replica.node_id,
        artifact: template.artifact,
        runtime: template.runtime,
        resources: template.resources,
        devices: replica.devices,
        network: template.network,
        health: template.health,
        data_policy: {
          ..template.data_policy,
          classification: plan.intent.data_class,
        },
        generation,
        lease_expires_unix_ms: now_unix_ms + plan.intent.lease_duration_ms,
        controller_epoch,
        signature: "",
      }
    }
  ]
}

///|
pub fn operation_transition_allowed(
  from : DeploymentOperationState,
  to : DeploymentOperationState,
) -> Bool {
  match (from, to) {
    (Submitted, Blocked | Planned | Failed) => true
    (Blocked, Planned | RollingBack | Failed | Deleted) => true
    (Planned, Reconciling | RollingBack | Failed | Deleted) => true
    (Reconciling, Ready | Degraded | Failed | RollingBack | Deleted) => true
    (Ready, Degraded | RollingBack | Deleted) => true
    (Degraded, Reconciling | Ready | RollingBack | Failed | Deleted) => true
    (Failed, Planned | RollingBack | Deleted) => true
    (RollingBack, RolledBack | Failed | Deleted) => true
    (RolledBack, Planned | Deleted) => true
    _ => false
  }
}
