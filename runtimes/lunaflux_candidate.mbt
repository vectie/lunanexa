///|
/// An inert, digest-only description of a LunaFlux rollout candidate.
///
/// This type deliberately has no endpoint, credential, health path, command,
/// mount path, or adapter conversion. Those fields may be introduced only by
/// a later promoted contract whose physical serving evidence has been
/// accepted by LunaNexa.
pub(all) struct LunaFluxCandidateManifest {
  schema_version : String
  runtime : @contracts.RuntimeSpec
  model_artifact_digest : String
  launch_manifest_digest : String
  kernel_manifest_digest : String
  build_provenance_digest : String
  sbom_digest : String
  license_manifest_digest : String
  physical_serving_evidence_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Stable, payload-free reasons why a LunaFlux candidate cannot be promoted.
pub(all) enum LunaFluxCandidateBlocker {
  UnsupportedCandidateSchema
  InvalidRuntimeIdentity
  InvalidRuntimeVersion
  InvalidRuntimeImageDigest
  InvalidRuntimeArchitecture
  UnsupportedRuntimeCapability
  UnqualifiedBatchingClaim
  UnqualifiedMultiNodeClaim
  InvalidModelArtifactDigest
  InvalidLaunchManifestDigest
  InvalidKernelManifestDigest
  InvalidBuildProvenanceDigest
  InvalidSbomDigest
  InvalidLicenseManifestDigest
  InvalidPhysicalServingEvidenceDigest
  ApprovedOciImageMissing
  PhysicalTargetApprovalMissing
  ListenerContractUnapproved
  HealthReadinessContractMissing
  DrainContractUnapproved
  InvocationContractUnapproved
  PhysicalServingEvidenceUnapproved
  BenchmarkComparisonMissing
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A candidate report is intentionally not an adapter admission. Even a
/// syntactically valid candidate remains unroutable while the promoted runtime
/// contract and its external evidence are absent.
pub(all) struct LunaFluxCandidateReport {
  manifest_valid : Bool
  routable : Bool
  blockers : Array[LunaFluxCandidateBlocker]
} derive(Debug, Eq, ToJson, FromJson)

///|
fn unique_architectures(values : Array[String]) -> Bool {
  for index, value in values {
    if values[:index].any(previous => previous == value) {
      return false
    }
  }
  true
}

///|
/// Validates only the stable digest and capability envelope, then appends the
/// exact external promotion blockers. It never produces routing authority.
pub fn inspect_lunaflux_candidate(
  candidate : LunaFluxCandidateManifest,
) -> LunaFluxCandidateReport {
  let blockers : Array[LunaFluxCandidateBlocker] = []
  let mut manifest_valid = true
  let reject = fn(blocker : LunaFluxCandidateBlocker) {
    manifest_valid = false
    blockers.push(blocker)
  }
  if candidate.schema_version != "lunanexa.lunaflux.candidate.v1" {
    reject(UnsupportedCandidateSchema)
  }
  if candidate.runtime.name != "lunaflux" {
    reject(InvalidRuntimeIdentity)
  }
  if !@contracts.valid_identifier(candidate.runtime.version, maximum_length=128) {
    reject(InvalidRuntimeVersion)
  }
  if !@contracts.valid_sha256_digest(candidate.runtime.image_digest) {
    reject(InvalidRuntimeImageDigest)
  }
  if candidate.runtime.architectures.length() == 0 ||
    candidate.runtime.architectures.length() > 64 ||
    !candidate.runtime.architectures.all(value => {
      @contracts.valid_identifier(value, maximum_length=128)
    }) ||
    !unique_architectures(candidate.runtime.architectures) {
    reject(InvalidRuntimeArchitecture)
  }
  if candidate.runtime.capabilities != [TextGenerate] {
    reject(UnsupportedRuntimeCapability)
  }
  if candidate.runtime.supports_batching {
    reject(UnqualifiedBatchingClaim)
  }
  if candidate.runtime.supports_multi_node {
    reject(UnqualifiedMultiNodeClaim)
  }
  if !@contracts.valid_sha256_digest(candidate.model_artifact_digest) {
    reject(InvalidModelArtifactDigest)
  }
  if !@contracts.valid_sha256_digest(candidate.launch_manifest_digest) {
    reject(InvalidLaunchManifestDigest)
  }
  if !@contracts.valid_sha256_digest(candidate.kernel_manifest_digest) {
    reject(InvalidKernelManifestDigest)
  }
  if !@contracts.valid_sha256_digest(candidate.build_provenance_digest) {
    reject(InvalidBuildProvenanceDigest)
  }
  if !@contracts.valid_sha256_digest(candidate.sbom_digest) {
    reject(InvalidSbomDigest)
  }
  if !@contracts.valid_sha256_digest(candidate.license_manifest_digest) {
    reject(InvalidLicenseManifestDigest)
  }
  if !@contracts.valid_sha256_digest(candidate.physical_serving_evidence_digest) {
    reject(InvalidPhysicalServingEvidenceDigest)
  }
  blockers.push(ApprovedOciImageMissing)
  blockers.push(PhysicalTargetApprovalMissing)
  blockers.push(ListenerContractUnapproved)
  blockers.push(HealthReadinessContractMissing)
  blockers.push(DrainContractUnapproved)
  blockers.push(InvocationContractUnapproved)
  blockers.push(PhysicalServingEvidenceUnapproved)
  blockers.push(BenchmarkComparisonMissing)
  { manifest_valid, routable: false, blockers }
}
