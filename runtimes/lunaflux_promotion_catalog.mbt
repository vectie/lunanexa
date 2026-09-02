///|
/// Fixed approval subjects accepted by the local LunaFlux promotion catalog.
/// Subject position, rather than caller-provided labels, binds each approval
/// to its evidence class.
pub(all) enum LunaFluxPromotionAuthoritySubject {
  CandidateManifestAuthority
  OciImageAuthority
  SbomAuthority
  BuildProvenanceAuthority
  LicenseAuthority
  KernelAuthority
  PhysicalServingAuthority
  BenchmarkAuthority
  ControlContractAuthority
  InvocationContractAuthority
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Private fixture shape for approval authenticated by a future embedding
/// controller. It is not constructible through the production interface and
/// does not claim that LunaNexa verified an external signature.
#warnings("-struct_never_constructed")
priv struct LunaFluxEvidenceApproval {
  evidence_digest : String
  approval_receipt_digest : String
  authority_id : String
}

///|
/// Private fixed-field verifier join. The production package exposes no
/// constructor until a deployment-owned controller verification bridge exists.
#warnings("-struct_never_constructed")
priv struct LunaFluxPromotionAuthorityInput {
  schema_version : String
  candidate_manifest : LunaFluxEvidenceApproval
  oci_image : LunaFluxEvidenceApproval
  sbom : LunaFluxEvidenceApproval
  build_provenance : LunaFluxEvidenceApproval
  license : LunaFluxEvidenceApproval
  kernel : LunaFluxEvidenceApproval
  physical_serving : LunaFluxEvidenceApproval
  benchmark : LunaFluxEvidenceApproval
  control_contract : LunaFluxEvidenceApproval
  invocation_contract : LunaFluxEvidenceApproval
}

///|
/// Untrusted facts checked against one immutable local authority catalog.
/// Unlike `LunaFluxPromotionSubmission`, this type carries no caller claims.
pub(all) struct LunaFluxPromotionVerificationRequest {
  schema_version : String
  candidate : LunaFluxCandidateManifest
  serving : LunaFluxServingContract
  benchmark_evidence_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror LunaFluxPromotionCatalogError {
  UnsupportedPromotionAuthoritySchema
  InvalidPromotionAuthority(LunaFluxPromotionAuthoritySubject)
  ReusedPromotionAuthorityReceipt(LunaFluxPromotionAuthoritySubject)
} derive(Debug, Eq)

///|
/// Immutable one-rollout approval catalog. Its public API exposes verification,
/// not mutation or a constructor for `LunaFluxAdapterAuthority`.
pub struct LunaFluxPromotionCatalog {
  priv authority : LunaFluxPromotionAuthorityInput
  priv digest : String
}

///|
priv struct LunaFluxControlDigestMaterial {
  target_profile_digest : String
  target_architecture : String
  listener_contract_digest : String
  health_readiness_contract_digest : String
  drain_contract_digest : String
  listener_origin : String
  listener_port : Int
  health_path : String
  readiness_path : String
  drain_path : String
  health_protocol : LunaFluxHealthProtocol
  drain_protocol : LunaFluxDrainProtocol
} derive(ToJson)

///|
fn lunaflux_promotion_sha256(domain : String, material : String) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode("\{domain}|\{material}")))}"
}

///|
/// Canonical digest that binds the complete candidate manifest, including all
/// artifact and evidence digests. This is a local content digest, not a
/// signature or external approval.
pub fn lunaflux_candidate_manifest_digest(
  candidate : LunaFluxCandidateManifest,
) -> String {
  lunaflux_promotion_sha256(
    "lunanexa.lunaflux.candidate-manifest.v1",
    candidate.to_json().stringify(),
  )
}

///|
/// Canonical digest of the deployment-facing target, TLS origin, observation,
/// and authenticated inherited-drain bridge contract. Invocation is approved
/// independently.
pub fn lunaflux_control_contract_digest(
  serving : LunaFluxServingContract,
) -> String {
  let material : LunaFluxControlDigestMaterial = {
    target_profile_digest: serving.target_profile_digest,
    target_architecture: serving.target_architecture,
    listener_contract_digest: serving.listener_contract_digest,
    health_readiness_contract_digest: serving.health_readiness_contract_digest,
    drain_contract_digest: serving.drain_contract_digest,
    listener_origin: serving.listener_origin,
    listener_port: serving.listener_port,
    health_path: serving.health_path,
    readiness_path: serving.readiness_path,
    drain_path: serving.drain_path,
    health_protocol: serving.health_protocol,
    drain_protocol: serving.drain_protocol,
  }
  lunaflux_promotion_sha256(
    "lunanexa.lunaflux.control-contract.v1",
    ToJson::to_json(material).stringify(),
  )
}

///|
/// Approval subject digest joining physical-serving evidence to the exact
/// candidate and target profile that were exercised.
pub fn lunaflux_physical_serving_approval_digest(
  candidate : LunaFluxCandidateManifest,
  serving : LunaFluxServingContract,
) -> String {
  lunaflux_promotion_sha256(
    "lunanexa.lunaflux.physical-serving-approval.v1",
    "\{lunaflux_candidate_manifest_digest(candidate)}|\{serving.target_profile_digest}|\{serving.target_architecture}|\{candidate.physical_serving_evidence_digest}",
  )
}

///|
/// Approval subject digest joining comparative benchmark evidence to the
/// exact candidate and deployment-facing control contract.
pub fn lunaflux_benchmark_approval_digest(
  candidate : LunaFluxCandidateManifest,
  serving : LunaFluxServingContract,
  benchmark_evidence_digest : String,
) -> String {
  lunaflux_promotion_sha256(
    "lunanexa.lunaflux.benchmark-approval.v1",
    "\{lunaflux_candidate_manifest_digest(candidate)}|\{lunaflux_control_contract_digest(serving)}|\{benchmark_evidence_digest}",
  )
}

///|
/// Approval subject digest joining the invocation contract to the exact
/// candidate and control contract. This prevents an independently valid API
/// contract from being substituted across rollout units.
pub fn lunaflux_invocation_approval_digest(
  candidate : LunaFluxCandidateManifest,
  serving : LunaFluxServingContract,
) -> String {
  lunaflux_promotion_sha256(
    "lunanexa.lunaflux.invocation-approval.v1",
    "\{lunaflux_candidate_manifest_digest(candidate)}|\{lunaflux_control_contract_digest(serving)}|\{serving.invocation_contract_digest}",
  )
}

///|
fn promotion_authority_subjects() -> Array[LunaFluxPromotionAuthoritySubject] {
  [
    CandidateManifestAuthority,
    OciImageAuthority,
    SbomAuthority,
    BuildProvenanceAuthority,
    LicenseAuthority,
    KernelAuthority,
    PhysicalServingAuthority,
    BenchmarkAuthority,
    ControlContractAuthority,
    InvocationContractAuthority,
  ]
}

///|
fn promotion_approval_for(
  input : LunaFluxPromotionAuthorityInput,
  subject : LunaFluxPromotionAuthoritySubject,
) -> LunaFluxEvidenceApproval {
  match subject {
    CandidateManifestAuthority => input.candidate_manifest
    OciImageAuthority => input.oci_image
    SbomAuthority => input.sbom
    BuildProvenanceAuthority => input.build_provenance
    LicenseAuthority => input.license
    KernelAuthority => input.kernel
    PhysicalServingAuthority => input.physical_serving
    BenchmarkAuthority => input.benchmark
    ControlContractAuthority => input.control_contract
    InvocationContractAuthority => input.invocation_contract
  }
}

///|
fn promotion_authority_subject_label(
  subject : LunaFluxPromotionAuthoritySubject,
) -> String {
  match subject {
    CandidateManifestAuthority => "candidate_manifest"
    OciImageAuthority => "oci_image"
    SbomAuthority => "sbom"
    BuildProvenanceAuthority => "build_provenance"
    LicenseAuthority => "license"
    KernelAuthority => "kernel"
    PhysicalServingAuthority => "physical_serving"
    BenchmarkAuthority => "benchmark"
    ControlContractAuthority => "control_contract"
    InvocationContractAuthority => "invocation_contract"
  }
}

///|
fn promotion_authority_catalog_digest(
  input : LunaFluxPromotionAuthorityInput,
) -> String {
  let builder = StringBuilder()
  builder.write_string(input.schema_version)
  for subject in promotion_authority_subjects() {
    let approval = promotion_approval_for(input, subject)
    builder.write_char('|')
    builder.write_string(promotion_authority_subject_label(subject))
    builder.write_char('|')
    builder.write_string(approval.evidence_digest)
    builder.write_char('|')
    builder.write_string(approval.approval_receipt_digest)
    builder.write_char('|')
    builder.write_string(approval.authority_id)
  }
  lunaflux_promotion_sha256(
    "lunanexa.lunaflux.promotion-authority-catalog.v1",
    builder.to_string(),
  )
}

///|
/// Admits one fixed local approval catalog. This validates identifiers,
/// content-addressed evidence and unique receipt references; it does not call
/// or impersonate an external signature service.
#warnings("-unused_value")
fn prepare_lunaflux_promotion_catalog(
  input : LunaFluxPromotionAuthorityInput,
) -> LunaFluxPromotionCatalog raise LunaFluxPromotionCatalogError {
  if input.schema_version != "lunanexa.lunaflux.promotion-authority.v1" {
    raise UnsupportedPromotionAuthoritySchema
  }
  let receipts : Array[String] = []
  for subject in promotion_authority_subjects() {
    let approval = promotion_approval_for(input, subject)
    if !@contracts.valid_sha256_digest(approval.evidence_digest) ||
      !@contracts.valid_sha256_digest(approval.approval_receipt_digest) ||
      !@contracts.valid_identifier(approval.authority_id, maximum_length=128) {
      raise InvalidPromotionAuthority(subject)
    }
    if receipts.contains(approval.approval_receipt_digest) {
      raise ReusedPromotionAuthorityReceipt(subject)
    }
    receipts.push(approval.approval_receipt_digest)
  }
  { authority: input, digest: promotion_authority_catalog_digest(input) }
}

///|
fn expected_promotion_authority_digest(
  request : LunaFluxPromotionVerificationRequest,
  subject : LunaFluxPromotionAuthoritySubject,
) -> String {
  match subject {
    CandidateManifestAuthority =>
      lunaflux_candidate_manifest_digest(request.candidate)
    OciImageAuthority => request.candidate.runtime.image_digest
    SbomAuthority => request.candidate.sbom_digest
    BuildProvenanceAuthority => request.candidate.build_provenance_digest
    LicenseAuthority => request.candidate.license_manifest_digest
    KernelAuthority => request.candidate.kernel_manifest_digest
    PhysicalServingAuthority =>
      lunaflux_physical_serving_approval_digest(
        request.candidate,
        request.serving,
      )
    BenchmarkAuthority =>
      lunaflux_benchmark_approval_digest(
        request.candidate,
        request.serving,
        request.benchmark_evidence_digest,
      )
    ControlContractAuthority =>
      lunaflux_control_contract_digest(request.serving)
    InvocationContractAuthority =>
      lunaflux_invocation_approval_digest(request.candidate, request.serving)
  }
}

///|
/// Verifies untrusted rollout facts against every fixed local approval. Only a
/// complete exact match produces the opaque adapter authority and routability.
pub fn LunaFluxPromotionCatalog::verify(
  self : LunaFluxPromotionCatalog,
  request : LunaFluxPromotionVerificationRequest,
) -> LunaFluxPromotionReport {
  let blockers : Array[LunaFluxPromotionBlocker] = []
  inspect_lunaflux_promotion_facts(
    request.schema_version,
    request.candidate,
    request.serving,
    request.benchmark_evidence_digest,
    blockers,
  )
  for subject in promotion_authority_subjects() {
    let approval = promotion_approval_for(self.authority, subject)
    if approval.evidence_digest !=
      expected_promotion_authority_digest(request, subject) {
      blockers.push(PromotionAuthorityMismatch(subject))
    }
  }
  if blockers.length() != 0 {
    return {
      evidence_well_formed: false,
      routable: false,
      authority: None,
      blockers,
    }
  }
  let candidate = request.candidate
  let serving = request.serving
  let authority : LunaFluxAdapterAuthority = {
    runtime: candidate.runtime,
    candidate_manifest_digest: lunaflux_candidate_manifest_digest(candidate),
    model_artifact_digest: candidate.model_artifact_digest,
    launch_manifest_digest: candidate.launch_manifest_digest,
    build_provenance_digest: candidate.build_provenance_digest,
    sbom_digest: candidate.sbom_digest,
    license_manifest_digest: candidate.license_manifest_digest,
    kernel_manifest_digest: candidate.kernel_manifest_digest,
    listener_origin: serving.listener_origin,
    invocation_path: serving.invocation_path,
    health_path: serving.health_path,
    readiness_path: serving.readiness_path,
    drain_path: serving.drain_path,
    target_profile_digest: serving.target_profile_digest,
    listener_contract_digest: serving.listener_contract_digest,
    health_readiness_contract_digest: serving.health_readiness_contract_digest,
    drain_contract_digest: serving.drain_contract_digest,
    invocation_contract_digest: serving.invocation_contract_digest,
    control_contract_digest: lunaflux_control_contract_digest(serving),
    physical_serving_evidence_digest: candidate.physical_serving_evidence_digest,
    benchmark_evidence_digest: request.benchmark_evidence_digest,
    approval_catalog_digest: self.digest,
  }
  {
    evidence_well_formed: true,
    routable: true,
    authority: Some(authority),
    blockers: [],
  }
}

///|
pub fn LunaFluxPromotionCatalog::digest(
  self : LunaFluxPromotionCatalog,
) -> String {
  self.digest
}

///|
pub fn LunaFluxAdapterAuthority::approval_catalog_digest(
  self : LunaFluxAdapterAuthority,
) -> String {
  self.approval_catalog_digest
}

///|
pub fn LunaFluxAdapterAuthority::health_path(
  self : LunaFluxAdapterAuthority,
) -> String {
  self.health_path
}
