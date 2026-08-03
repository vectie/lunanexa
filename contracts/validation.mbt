///|
pub(all) suberror ContractError {
  UnsupportedVersion(String)
  MissingField(String)
  InvalidPolicy(String)
  InvalidDeadline
  InvalidResourceCeiling(String)
  PayloadTooLarge
} derive(Debug, Eq)

///|
pub fn valid_identifier(value : String, maximum_length? : Int = 256) -> Bool {
  value != "" &&
  value.length() <= maximum_length &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == ':'
  })
}

///|
pub fn valid_optional_identifier(
  value : String,
  maximum_length? : Int = 512,
) -> Bool {
  value == "" || valid_identifier(value, maximum_length~)
}

///|
pub fn valid_sha256_digest(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].all(character => {
    (character >= '0' && character <= '9') ||
    (character >= 'a' && character <= 'f') ||
    (character >= 'A' && character <= 'F')
  })
}

///|
pub fn validate_workload(
  request : WorkloadEnvelope,
) -> Unit raise ContractError {
  if request.version != contract_version {
    raise UnsupportedVersion(request.version)
  }
  if request.idempotency_key == "" {
    raise MissingField("idempotency_key")
  }
  if request.workload_id == "" {
    raise MissingField("workload_id")
  }
  if request.tenant_ref == "" {
    raise MissingField("tenant_ref")
  }
  if request.model_selector == "" {
    raise MissingField("model_selector")
  }
  if request.credential_scope == "" {
    raise MissingField("credential_scope")
  }
  if request.output_format == "" {
    raise MissingField("output_format")
  }
  if !valid_identifier(request.idempotency_key) ||
    !valid_identifier(request.workload_id) ||
    !valid_identifier(request.tenant_ref) ||
    !valid_identifier(request.credential_scope) ||
    !valid_identifier(request.model_selector) ||
    !valid_identifier(request.output_format) ||
    !valid_optional_identifier(request.trace_token) {
    raise InvalidPolicy(
      "identifier contains unsafe characters or exceeds its limit",
    )
  }
  if request.payload.stringify().length() > 1048576 {
    raise PayloadTooLarge
  }
  if request.deadline_unix_ms <= 0L {
    raise InvalidDeadline
  }
  let ceiling = request.resource_ceiling
  if ceiling.max_input_units <= 0 || ceiling.max_input_units > 10000000 {
    raise InvalidResourceCeiling("max_input_units")
  }
  if ceiling.max_output_units <= 0 || ceiling.max_output_units > 1000000 {
    raise InvalidResourceCeiling("max_output_units")
  }
  if ceiling.max_runtime_ms <= 0L || ceiling.max_runtime_ms > 86400000L {
    raise InvalidResourceCeiling("max_runtime_ms")
  }
  if ceiling.max_accelerator_memory_mib <= 0 ||
    ceiling.max_accelerator_memory_mib > 1048576 {
    raise InvalidResourceCeiling("max_accelerator_memory_mib")
  }
  if request.data_policy.retention is RetainUntil(expiry) && expiry <= 0L {
    raise InvalidPolicy("retention expiry must be positive")
  }
  if request.data_policy.retention is Ephemeral &&
    request.data_policy.allow_cache {
    raise InvalidPolicy("ephemeral payloads cannot be cached")
  }
  if request.data_policy.allow_training_reuse {
    match request.data_policy.retention {
      EvaluationCapture(consent_receipt="") =>
        raise InvalidPolicy("training reuse requires a consent receipt")
      EvaluationCapture(_) => ()
      _ => raise InvalidPolicy("training reuse requires evaluation capture")
    }
  }
}

///|
pub fn workload_transition_allowed(
  from : WorkloadState,
  to : WorkloadState,
) -> Bool {
  match (from, to) {
    (Submitted, Admitted | Rejected | Cancelled) => true
    (Admitted, Queued | Running | Rejected | Cancelled) => true
    (Queued, Running | Cancelled | Failed) => true
    (Running, Streaming | Succeeded | Failed | Cancelled) => true
    (Streaming, Succeeded | Failed | Cancelled) => true
    _ => false
  }
}

///|
pub fn deployment_transition_allowed(
  from : DeploymentState,
  to : DeploymentState,
) -> Bool {
  match (from, to) {
    (Pending, Preparing | Stopped | Failed) => true
    (Preparing, Starting | Failed | Stopped) => true
    (Starting, Ready | Failed | Stopped) => true
    (Ready, Draining | Degraded | Failed | Stopped) => true
    (Degraded, Ready | Draining | Failed | Stopped) => true
    (Draining, Stopped | Failed) => true
    (Failed, Pending | Stopped) => true
    _ => false
  }
}

///|
pub fn node_transition_allowed(from : NodeState, to : NodeState) -> Bool {
  match (from, to) {
    (Enrolling, Active | Retired) => true
    (Active, Cordoned | Draining | Unreachable | Retired) => true
    (Cordoned, Active | Draining | Unreachable | Retired) => true
    (Draining, Cordoned | Unreachable | Retired) => true
    (Unreachable, Active | Cordoned | Retired) => true
    _ => false
  }
}

///|
pub fn model_transition_allowed(from : ModelState, to : ModelState) -> Bool {
  match (from, to) {
    (Candidate, Verified | Revoked) => true
    (Verified, Evaluated | Revoked) => true
    (Evaluated, Approved | Revoked) => true
    (Approved, Deprecated | Revoked) => true
    (Deprecated, Approved | Revoked) => true
    _ => false
  }
}

///|
pub fn health(component : String, version : String) -> HealthResponse {
  { product: "LunaNexa", component, version, status: "ok" }
}

///|
pub fn decode_workload(json : String) -> WorkloadEnvelope raise {
  let value = @json.parse(json)
  let request : WorkloadEnvelope = @json.from_json(value)
  validate_workload(request)
  request
}
