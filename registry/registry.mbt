///|
pub(all) struct Alias {
  name : String
  model_id : String
  version : String
  generation : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum LicenseStatus {
  Pending
  Accepted
  Expired
  Revoked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct LicenseRecord {
  license_id : String
  model_id : String
  status : LicenseStatus
  accepted_by : String
  evidence_ref : String
  expires_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ArtifactVerification {
  digest : String
  signature_verified : Bool
  provenance_verified : Bool
  verified_unix_ms : Int64
  verifier : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BenchmarkProfile {
  profile_id : String
  model_id : String
  model_version : String
  runtime_version : String
  hardware_profile : String
  workload_profile : String
  p50_ms : Double
  p95_ms : Double
  p99_ms : Double
  throughput_per_second : Double
  peak_memory_mib : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EvaluationRecord {
  evaluation_id : String
  model_id : String
  model_version : String
  suite_version : String
  passed : Bool
  score : Double
  benchmark : BenchmarkProfile
  evidence_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum RolloutStage {
  Canary
  Stable
  RolledBack
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PromotionReceipt {
  receipt_id : String
  alias_name : String
  from_version : String?
  to_version : String
  stage : RolloutStage
  actor : String
  evaluation_id : String
  generation : Int64
  timestamp_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror RegistryError {
  ModelNotFound(String)
  LicenseNotAccepted(String)
  ArtifactNotVerified(String)
  EvaluationNotPassed(String)
  ModelNotApproved(String)
  AliasNotFound(String)
  NoRollbackTarget(String)
  InvalidMetadata(String)
} derive(Debug, Eq)

///|
pub(all) struct RegistrySnapshot {
  schema_version : String
  models : Array[@contracts.ModelRecord]
  licenses : Array[LicenseRecord]
  verifications : Array[ArtifactVerification]
  evaluations : Array[EvaluationRecord]
  aliases : Array[Alias]
  receipts : Array[PromotionReceipt]
  alias_history : Array[AliasHistory]
  runtimes : Array[@contracts.RuntimeSpec]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AliasHistory {
  name : String
  values : Array[Alias]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SchedulingTarget {
  model_key : String
  model : @contracts.ModelRecord
  runtime : @contracts.RuntimeSpec
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct ModelRegistry {
  models : Map[String, @contracts.ModelRecord]
  licenses : Map[String, LicenseRecord]
  verifications : Map[String, ArtifactVerification]
  evaluations : Map[String, EvaluationRecord]
  aliases : Map[String, Alias]
  alias_history : Map[String, Array[Alias]]
  receipts : Array[PromotionReceipt]
  runtimes : Map[String, @contracts.RuntimeSpec]
}

///|
fn model_key(model_id : String, version : String) -> String {
  "\{model_id}@\{version}"
}

///|
pub fn ModelRegistry::new() -> ModelRegistry {
  {
    models: Map([]),
    licenses: Map([]),
    verifications: Map([]),
    evaluations: Map([]),
    aliases: Map([]),
    alias_history: Map([]),
    receipts: [],
    runtimes: Map([]),
  }
}

///|
pub fn ModelRegistry::register_runtime(
  self : ModelRegistry,
  runtime : @contracts.RuntimeSpec,
) -> Unit raise RegistryError {
  if runtime.name == "" ||
    runtime.name.length() > 256 ||
    runtime.name.contains("..") ||
    runtime.name.contains_char('@') ||
    runtime.name.contains_char(' ') ||
    runtime.name.contains_char('\n') ||
    runtime.name.contains_char('\r') ||
    !@contracts.valid_identifier(runtime.version, maximum_length=128) ||
    !@contracts.valid_sha256_digest(runtime.image_digest) ||
    runtime.capabilities.length() == 0 ||
    runtime.architectures.length() == 0 ||
    !runtime.architectures.all(value => {
      @contracts.valid_identifier(value, maximum_length=128)
    }) {
    raise InvalidMetadata(runtime.name)
  }
  self.runtimes[model_key(runtime.name, runtime.version)] = runtime
}

///|
pub fn ModelRegistry::deployment_allowed(
  self : ModelRegistry,
  artifact_digest : String,
  runtime : @contracts.RuntimeSpec,
) -> Bool {
  let approved = self.models
    .values()
    .any(model => {
      model.state == Approved && model.artifact.digest == artifact_digest
    })
  let runtime_verified = self.verifications
    .get(runtime.image_digest)
    .map(verification => {
      verification.signature_verified && verification.provenance_verified
    })
    .unwrap_or(false)
  approved &&
  runtime_verified &&
  self.runtimes.get(model_key(runtime.name, runtime.version)) == Some(runtime)
}

///|
pub fn ModelRegistry::verification_valid(
  self : ModelRegistry,
  digest : String,
) -> Bool {
  self.verifications
  .get(digest)
  .map(verification => {
    verification.signature_verified && verification.provenance_verified
  })
  .unwrap_or(false)
}

///|
pub fn ModelRegistry::register_model(
  self : ModelRegistry,
  model : @contracts.ModelRecord,
) -> Unit raise RegistryError {
  if !@contracts.valid_identifier(model.model_id, maximum_length=128) ||
    !@contracts.valid_identifier(model.version, maximum_length=128) ||
    model.artifact.uri.contains("../") ||
    model.artifact.uri.contains("file://") ||
    model.artifact.uri.contains("<script") ||
    model.artifact.uri.contains_char('\n') ||
    !(model.artifact.uri.has_prefix("s3://") ||
    model.artifact.uri.has_prefix("oci://")) ||
    !@contracts.valid_sha256_digest(model.artifact.digest) ||
    model.artifact.size_bytes <= 0L ||
    model.artifact.signature_ref == "" ||
    model.artifact.signature_ref.contains_char('\n') ||
    !@contracts.valid_identifier(model.license_id, maximum_length=128) ||
    model.provenance == "" ||
    model.compatible_architectures.length() == 0 ||
    !model.compatible_architectures.all(value => {
      @contracts.valid_identifier(value, maximum_length=128)
    }) ||
    model.minimum_memory_mib <= 0 ||
    model.state != Candidate {
    raise InvalidMetadata(model.model_id)
  }
  self.models[model_key(model.model_id, model.version)] = model
}

///|
pub fn ModelRegistry::record_license(
  self : ModelRegistry,
  license : LicenseRecord,
) -> Unit raise RegistryError {
  if !@contracts.valid_identifier(license.license_id, maximum_length=128) ||
    !@contracts.valid_identifier(license.model_id, maximum_length=128) ||
    license.evidence_ref == "" ||
    (license.status == Accepted && license.accepted_by == "") ||
    (license.expires_unix_ms is Some(expiry) && expiry <= 0L) {
    raise InvalidMetadata(license.license_id)
  }
  self.licenses[license.license_id] = license
}

///|
pub fn ModelRegistry::record_verification(
  self : ModelRegistry,
  verification : ArtifactVerification,
) -> Unit raise RegistryError {
  if !@contracts.valid_sha256_digest(verification.digest) ||
    verification.verified_unix_ms <= 0L ||
    verification.verifier == "" ||
    verification.verifier.contains_char('\n') {
    raise InvalidMetadata(verification.digest)
  }
  self.verifications[verification.digest] = verification
  if verification.signature_verified && verification.provenance_verified {
    for key, model in self.models {
      if model.artifact.digest == verification.digest &&
        model.state == Candidate {
        self.models[key] = { ..model, state: Verified }
      }
    }
  }
}

///|
pub fn ModelRegistry::record_evaluation(
  self : ModelRegistry,
  evaluation : EvaluationRecord,
) -> Unit raise RegistryError {
  let key = model_key(evaluation.model_id, evaluation.model_version)
  guard self.models.get(key) is Some(model) else { raise ModelNotFound(key) }
  if !@contracts.valid_identifier(evaluation.evaluation_id, maximum_length=128) ||
    !@contracts.valid_identifier(evaluation.model_id, maximum_length=128) ||
    !@contracts.valid_identifier(evaluation.model_version, maximum_length=128) ||
    evaluation.evidence_ref == "" ||
    evaluation.benchmark.model_id != evaluation.model_id ||
    evaluation.benchmark.model_version != evaluation.model_version ||
    evaluation.benchmark.profile_id == "" ||
    evaluation.benchmark.runtime_version == "" ||
    evaluation.benchmark.hardware_profile == "" ||
    evaluation.benchmark.workload_profile == "" ||
    evaluation.benchmark.p50_ms < 0.0 ||
    evaluation.benchmark.p95_ms < 0.0 ||
    evaluation.benchmark.p99_ms < 0.0 ||
    evaluation.benchmark.throughput_per_second < 0.0 ||
    evaluation.benchmark.peak_memory_mib <= 0 {
    raise InvalidMetadata(evaluation.evaluation_id)
  }
  self.evaluations[model_key(evaluation.model_id, evaluation.model_version)] = evaluation
  if evaluation.passed && model.state == Verified {
    self.models[key] = { ..model, state: Evaluated }
  }
}

///|
pub fn ModelRegistry::model(
  self : ModelRegistry,
  model_id : String,
  version : String,
) -> @contracts.ModelRecord? {
  self.models.get(model_key(model_id, version))
}

///|
pub fn ModelRegistry::approve(
  self : ModelRegistry,
  model_id : String,
  version : String,
  now_unix_ms : Int64,
) -> @contracts.ModelRecord raise RegistryError {
  let key = model_key(model_id, version)
  guard self.models.get(key) is Some(model) else { raise ModelNotFound(key) }
  guard self.licenses.get(model.license_id) is Some(license) &&
    license.model_id == model.model_id &&
    license.status == Accepted &&
    (
      license.expires_unix_ms is None ||
      (license.expires_unix_ms is Some(expiry) && expiry > now_unix_ms)
    ) else {
    raise LicenseNotAccepted(model.license_id)
  }
  guard self.verifications.get(model.artifact.digest) is Some(verification) &&
    verification.signature_verified &&
    verification.provenance_verified else {
    raise ArtifactNotVerified(model.artifact.digest)
  }
  guard self.evaluations.get(key) is Some(evaluation) && evaluation.passed else {
    raise EvaluationNotPassed(key)
  }
  if model.state != Evaluated {
    raise EvaluationNotPassed(key)
  }
  let approved : @contracts.ModelRecord = { ..model, state: Approved }
  self.models[key] = approved
  approved
}

///|
pub fn ModelRegistry::promote(
  self : ModelRegistry,
  alias_name : String,
  model_id : String,
  version : String,
  stage : RolloutStage,
  actor : String,
  now_unix_ms : Int64,
) -> PromotionReceipt raise RegistryError {
  if !@contracts.valid_identifier(alias_name, maximum_length=128) ||
    !@contracts.valid_identifier(model_id, maximum_length=128) ||
    !@contracts.valid_identifier(version, maximum_length=128) {
    raise InvalidMetadata(alias_name)
  }
  let key = model_key(model_id, version)
  guard self.models.get(key) is Some(model) else { raise ModelNotFound(key) }
  if model.state != Approved {
    raise ModelNotApproved(key)
  }
  guard self.evaluations.get(key) is Some(evaluation) && evaluation.passed else {
    raise EvaluationNotPassed(key)
  }
  let prior = self.aliases.get(alias_name)
  let generation = match prior {
    Some(value) => value.generation + 1L
    None => 1L
  }
  if prior is Some(value) {
    let history = self.alias_history.get(alias_name).unwrap_or([])
    history.push(value)
    self.alias_history[alias_name] = history
  }
  let alias_record : Alias = { name: alias_name, model_id, version, generation }
  self.aliases[alias_name] = alias_record
  let receipt : PromotionReceipt = {
    receipt_id: "promotion:\{alias_name}:\{generation}",
    alias_name,
    from_version: prior.map(value => value.version),
    to_version: version,
    stage,
    actor,
    evaluation_id: evaluation.evaluation_id,
    generation,
    timestamp_unix_ms: now_unix_ms,
  }
  self.receipts.push(receipt)
  receipt
}

///|
pub fn ModelRegistry::rollback(
  self : ModelRegistry,
  alias_name : String,
  actor : String,
  now_unix_ms : Int64,
) -> PromotionReceipt raise RegistryError {
  guard self.aliases.get(alias_name) is Some(current) else {
    raise AliasNotFound(alias_name)
  }
  guard self.alias_history.get(alias_name) is Some(history) &&
    history.length() > 0 else {
    raise NoRollbackTarget(alias_name)
  }
  let previous = history.pop().unwrap()
  self.alias_history[alias_name] = history
  let generation = current.generation + 1L
  self.aliases[alias_name] = { ..previous, generation, }
  let receipt : PromotionReceipt = {
    receipt_id: "rollback:\{alias_name}:\{generation}",
    alias_name,
    from_version: Some(current.version),
    to_version: previous.version,
    stage: RolledBack,
    actor,
    evaluation_id: "rollback-of:\{current.version}",
    generation,
    timestamp_unix_ms: now_unix_ms,
  }
  self.receipts.push(receipt)
  receipt
}

///|
pub fn ModelRegistry::resolve_alias(
  self : ModelRegistry,
  name : String,
) -> Alias? {
  self.aliases.get(name)
}

///|
pub fn ModelRegistry::scheduling_target(
  self : ModelRegistry,
  selector : String,
  capability : @contracts.Capability,
) -> SchedulingTarget? {
  guard self.aliases.get(selector) is Some(alias_record) else { return None }
  guard self.models.get(model_key(alias_record.model_id, alias_record.version))
    is Some(model) &&
    model.state == Approved else {
    return None
  }
  let runtimes = [
    for _, runtime in self.runtimes if runtime.capabilities.any(value => {
      value == capability
    }) &&
    runtime.architectures.any(architecture => {
      model.compatible_architectures.any(value => value == architecture)
    }) => runtime
  ]
  runtimes.sort_by((left, right) => {
    let by_name = left.name.compare(right.name)
    if by_name != 0 {
      by_name
    } else {
      left.version.compare(right.version)
    }
  })
  runtimes
  .get(0)
  .map(runtime => {
    model_key: model_key(model.model_id, model.version),
    model,
    runtime,
  })
}

///|
pub fn ModelRegistry::receipts(self : ModelRegistry) -> Array[PromotionReceipt] {
  self.receipts.copy()
}

///|
pub fn ModelRegistry::snapshot(self : ModelRegistry) -> String {
  let value : RegistrySnapshot = {
    schema_version: "lunanexa.registry.v1",
    models: [
      for _, model in self.models => model
    ],
    licenses: [
      for _, license in self.licenses => license
    ],
    verifications: [
      for _, verification in self.verifications => verification
    ],
    evaluations: [
      for _, evaluation in self.evaluations => evaluation
    ],
    aliases: [
      for _, alias_record in self.aliases => alias_record
    ],
    receipts: self.receipts(),
    alias_history: [
      for name, values in self.alias_history => { name, values: values.copy() }
    ],
    runtimes: [
      for _, runtime in self.runtimes => runtime
    ],
  }
  value.to_json().stringify()
}

///|
pub fn ModelRegistry::restore(json : String) -> ModelRegistry raise {
  let snapshot : RegistrySnapshot = @json.from_json(@json.parse(json))
  if snapshot.schema_version != "lunanexa.registry.v1" {
    raise Failure::Failure("unsupported registry schema")
  }
  let registry = ModelRegistry::new()
  for model in snapshot.models {
    registry.register_model({ ..model, state: Candidate })
  }
  for license in snapshot.licenses {
    registry.record_license(license)
  }
  for verification in snapshot.verifications {
    registry.record_verification(verification)
  }
  for evaluation in snapshot.evaluations {
    registry.record_evaluation(evaluation)
  }
  for model in snapshot.models {
    registry.models[model_key(model.model_id, model.version)] = model
  }
  for alias_record in snapshot.aliases {
    registry.aliases[alias_record.name] = alias_record
  }
  for receipt in snapshot.receipts {
    registry.receipts.push(receipt)
  }
  for runtime in snapshot.runtimes {
    registry.register_runtime(runtime)
  }
  for history in snapshot.alias_history {
    registry.alias_history[history.name] = history.values.copy()
  }
  registry
}
