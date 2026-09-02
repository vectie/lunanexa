///|
/// Legacy caller-claim subjects retained for structural inspection. They are
/// not the fixed trusted subjects of `LunaFluxPromotionCatalog`.
pub(all) enum LunaFluxApprovalSubject {
  RuntimeImage
  PhysicalTarget
  ListenerContract
  HealthReadinessContract
  DrainContract
  InvocationContract
  PhysicalServing
  BenchmarkComparison
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A decision asserted by untrusted promotion input. This is a claim, not
/// verifier-issued authority.
pub(all) enum LunaFluxClaimedDecision {
  Pending
  Rejected
  Approved
} derive(Debug, Eq, ToJson, FromJson)

///|
/// An untrusted claim that one subject digest has an independently retained
/// receipt. Callers can construct claims, but claims can never authorize
/// routing without a separately integrated trusted verifier.
pub(all) struct LunaFluxApprovalClaim {
  subject : LunaFluxApprovalSubject
  subject_digest : String
  approval_receipt_digest : String
  decision : LunaFluxClaimedDecision
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Only a qualified OpenAI Responses contract can use LunaNexa's existing
/// production text adapter. The native-framed LunaFlux diagnostic protocol is
/// intentionally represented as unqualified.
pub(all) enum LunaFluxInvocationProtocol {
  InvocationUnqualified
  OpenAiResponsesV1
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Readiness must be an independently reviewed HTTP contract. A TCP listener
/// accepting connections is not readiness evidence.
pub(all) enum LunaFluxHealthProtocol {
  HealthReadinessUnqualified
  HttpJsonReadinessV1
} derive(Debug, Eq, ToJson, FromJson)

///|
/// LunaNexa needs an authenticated external control operation translated by
/// deployment ownership into LunaFlux's inherited Unix-stream drain channel.
/// LunaFlux exposes no HTTP drain route.
pub(all) enum LunaFluxDrainProtocol {
  DrainUnqualified
  AuthenticatedInheritedDrainV1
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Exact deployment-facing facts that have to be proven together. This type
/// contains no credential; runtime credentials remain deployment-owned.
pub(all) struct LunaFluxServingContract {
  target_profile_digest : String
  target_architecture : String
  listener_contract_digest : String
  health_readiness_contract_digest : String
  drain_contract_digest : String
  invocation_contract_digest : String
  listener_origin : String
  listener_port : Int
  invocation_path : String
  health_path : String
  readiness_path : String
  drain_path : String
  invocation_protocol : LunaFluxInvocationProtocol
  health_protocol : LunaFluxHealthProtocol
  drain_protocol : LunaFluxDrainProtocol
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Untrusted promotion input is separate from candidate metadata. No claim,
/// endpoint, protocol, or benchmark fact is inferred from the candidate, and
/// structural inspection of this input never grants routing authority.
pub(all) struct LunaFluxPromotionSubmission {
  schema_version : String
  candidate : LunaFluxCandidateManifest
  serving : LunaFluxServingContract
  benchmark_evidence_digest : String
  approval_claims : Array[LunaFluxApprovalClaim]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Opaque routing authority produced only by an exact local promotion-catalog
/// match. There is deliberately no public constructor.
#warnings("-struct_never_constructed")
pub struct LunaFluxAdapterAuthority {
  runtime : @contracts.RuntimeSpec
  candidate_manifest_digest : String
  model_artifact_digest : String
  launch_manifest_digest : String
  build_provenance_digest : String
  sbom_digest : String
  license_manifest_digest : String
  kernel_manifest_digest : String
  listener_origin : String
  invocation_path : String
  health_path : String
  readiness_path : String
  drain_path : String
  target_profile_digest : String
  listener_contract_digest : String
  health_readiness_contract_digest : String
  drain_contract_digest : String
  invocation_contract_digest : String
  control_contract_digest : String
  physical_serving_evidence_digest : String
  benchmark_evidence_digest : String
  approval_catalog_digest : String
} derive(Debug, Eq)

///|
pub(all) enum LunaFluxPromotionBlocker {
  UnsupportedPromotionSchema
  CandidateManifestInvalid
  InvalidTargetProfileDigest
  InvalidTargetArchitecture
  TargetArchitectureMismatch
  InvalidListenerContractDigest
  InvalidHealthReadinessContractDigest
  InvalidDrainContractDigest
  InvalidInvocationContractDigest
  InvalidBenchmarkEvidenceDigest
  InvalidListenerOrigin
  InvalidListenerPort
  InvalidInvocationPath
  InvocationPathNotOpenAiResponses
  InvalidHealthPath
  HealthPathNotHealthz
  InvalidReadinessPath
  ReadinessPathNotReadyz
  InvalidDrainPath
  InvocationProtocolUnqualified
  HealthReadinessProtocolUnqualified
  DrainProtocolUnqualified
  MissingApprovalClaim(LunaFluxApprovalSubject)
  DuplicateApprovalClaim(LunaFluxApprovalSubject)
  PendingApprovalClaim(LunaFluxApprovalSubject)
  RejectedApprovalClaim(LunaFluxApprovalSubject)
  ApprovalClaimSubjectMismatch(LunaFluxApprovalSubject)
  InvalidApprovalClaimReceipt(LunaFluxApprovalSubject)
  ReusedApprovalClaimReceipt
  PromotionAuthorityMismatch(LunaFluxPromotionAuthoritySubject)
  PromotionVerifierClosed
  InvalidSignedPromotionReceiptCount(Int)
  MissingSignedPromotionReceipt(LunaFluxPromotionAuthoritySubject)
  DuplicateSignedPromotionReceipt(LunaFluxPromotionAuthoritySubject)
  InvalidSignedPromotionReceipt(LunaFluxPromotionAuthoritySubject)
  SignedPromotionReceiptPolicyMismatch(LunaFluxPromotionAuthoritySubject)
  ReusedSignedPromotionReceipt(LunaFluxPromotionAuthoritySubject)
  SignedPromotionReceiptAuthenticationFailed(LunaFluxPromotionAuthoritySubject)
  PromotionVerifierCatalogRejected
  PromotionVerifierUnavailable
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct LunaFluxPromotionReport {
  evidence_well_formed : Bool
  routable : Bool
  authority : LunaFluxAdapterAuthority?
  blockers : Array[LunaFluxPromotionBlocker]
} derive(Debug)

///|
fn promotion_subjects() -> Array[LunaFluxApprovalSubject] {
  [
    RuntimeImage,
    PhysicalTarget,
    ListenerContract,
    HealthReadinessContract,
    DrainContract,
    InvocationContract,
    PhysicalServing,
    BenchmarkComparison,
  ]
}

///|
fn expected_subject_digest(
  submission : LunaFluxPromotionSubmission,
  subject : LunaFluxApprovalSubject,
) -> String {
  match subject {
    RuntimeImage => submission.candidate.runtime.image_digest
    PhysicalTarget => submission.serving.target_profile_digest
    ListenerContract => submission.serving.listener_contract_digest
    HealthReadinessContract =>
      submission.serving.health_readiness_contract_digest
    DrainContract => submission.serving.drain_contract_digest
    InvocationContract => submission.serving.invocation_contract_digest
    PhysicalServing => submission.candidate.physical_serving_evidence_digest
    BenchmarkComparison => submission.benchmark_evidence_digest
  }
}

///|
fn valid_listener_origin(origin : String, port : Int) -> Bool {
  guard origin.has_prefix("https://") else { return false }
  let authority = origin["https://".length():]
  let port_suffix = ":\{port}"
  authority != "" &&
  authority.length() > port_suffix.length() &&
  authority.has_suffix(port_suffix) &&
  !authority.contains_char('/') &&
  !authority.contains_char('@') &&
  !authority.contains_char(' ') &&
  !authority.contains_char('\n') &&
  !authority.contains_char('\r') &&
  !authority.contains_char('?') &&
  !authority.contains_char('#')
}

///|
fn valid_contract_path(path : String) -> Bool {
  path.length() > 1 &&
  path.length() <= 256 &&
  path.has_prefix("/") &&
  !path.has_prefix("//") &&
  !path.contains_char(' ') &&
  !path.contains_char('\n') &&
  !path.contains_char('\r') &&
  !path.contains_char('?') &&
  !path.contains_char('#')
}

///|
fn inspect_approval_claim(
  submission : LunaFluxPromotionSubmission,
  subject : LunaFluxApprovalSubject,
  blockers : Array[LunaFluxPromotionBlocker],
) -> Unit {
  let matches = submission.approval_claims.filter(claim => {
    claim.subject == subject
  })
  if matches.length() == 0 {
    blockers.push(MissingApprovalClaim(subject))
    return
  }
  if matches.length() != 1 {
    blockers.push(DuplicateApprovalClaim(subject))
    return
  }
  let claim = matches[0]
  if claim.subject_digest != expected_subject_digest(submission, subject) {
    blockers.push(ApprovalClaimSubjectMismatch(subject))
  }
  if !@contracts.valid_sha256_digest(claim.approval_receipt_digest) {
    blockers.push(InvalidApprovalClaimReceipt(subject))
  }
  match claim.decision {
    Pending => blockers.push(PendingApprovalClaim(subject))
    Rejected => blockers.push(RejectedApprovalClaim(subject))
    Approved => ()
  }
}

///|
fn inspect_lunaflux_promotion_facts(
  schema_version : String,
  candidate : LunaFluxCandidateManifest,
  serving : LunaFluxServingContract,
  benchmark_evidence_digest : String,
  blockers : Array[LunaFluxPromotionBlocker],
) -> Unit {
  if schema_version != "lunanexa.lunaflux.promotion.v1" {
    blockers.push(UnsupportedPromotionSchema)
  }
  if !inspect_lunaflux_candidate(candidate).manifest_valid {
    blockers.push(CandidateManifestInvalid)
  }
  let digest_checks : Array[(String, LunaFluxPromotionBlocker)] = [
    (serving.target_profile_digest, InvalidTargetProfileDigest),
    (serving.listener_contract_digest, InvalidListenerContractDigest),
    (
      serving.health_readiness_contract_digest,
      InvalidHealthReadinessContractDigest,
    ),
    (serving.drain_contract_digest, InvalidDrainContractDigest),
    (serving.invocation_contract_digest, InvalidInvocationContractDigest),
    (benchmark_evidence_digest, InvalidBenchmarkEvidenceDigest),
  ]
  for entry in digest_checks {
    let (digest, blocker) = entry
    if !@contracts.valid_sha256_digest(digest) {
      blockers.push(blocker)
    }
  }
  if !@contracts.valid_identifier(
      serving.target_architecture,
      maximum_length=128,
    ) {
    blockers.push(InvalidTargetArchitecture)
  } else if !candidate.runtime.architectures.contains(
      serving.target_architecture,
    ) {
    blockers.push(TargetArchitectureMismatch)
  }
  if serving.listener_port < 1 || serving.listener_port > 65535 {
    blockers.push(InvalidListenerPort)
  }
  if !valid_listener_origin(serving.listener_origin, serving.listener_port) {
    blockers.push(InvalidListenerOrigin)
  }
  if !valid_contract_path(serving.invocation_path) {
    blockers.push(InvalidInvocationPath)
  } else if serving.invocation_path != "/v1/responses" {
    blockers.push(InvocationPathNotOpenAiResponses)
  }
  if !valid_contract_path(serving.health_path) {
    blockers.push(InvalidHealthPath)
  } else if serving.health_path != "/healthz" {
    blockers.push(HealthPathNotHealthz)
  }
  if !valid_contract_path(serving.readiness_path) ||
    serving.readiness_path == serving.invocation_path ||
    serving.readiness_path == serving.health_path {
    blockers.push(InvalidReadinessPath)
  } else if serving.readiness_path != "/readyz" {
    blockers.push(ReadinessPathNotReadyz)
  }
  if !valid_contract_path(serving.drain_path) ||
    serving.drain_path == serving.invocation_path ||
    serving.drain_path == serving.health_path ||
    serving.drain_path == serving.readiness_path {
    blockers.push(InvalidDrainPath)
  }
  if serving.invocation_protocol != OpenAiResponsesV1 {
    blockers.push(InvocationProtocolUnqualified)
  }
  if serving.health_protocol != HttpJsonReadinessV1 {
    blockers.push(HealthReadinessProtocolUnqualified)
  }
  if serving.drain_protocol != AuthenticatedInheritedDrainV1 {
    blockers.push(DrainProtocolUnqualified)
  }
}

///|
/// Performs structural inspection of untrusted promotion input. Even perfectly
/// formed claims remain non-routable because LunaNexa does not yet have a
/// trusted verifier that can authenticate and issue opaque approvals.
pub fn inspect_lunaflux_promotion(
  submission : LunaFluxPromotionSubmission,
) -> LunaFluxPromotionReport {
  let blockers : Array[LunaFluxPromotionBlocker] = []
  inspect_lunaflux_promotion_facts(
    submission.schema_version,
    submission.candidate,
    submission.serving,
    submission.benchmark_evidence_digest,
    blockers,
  )
  for subject in promotion_subjects() {
    inspect_approval_claim(submission, subject, blockers)
  }
  for index, claim in submission.approval_claims {
    if @contracts.valid_sha256_digest(claim.approval_receipt_digest) &&
      submission.approval_claims[:index].any(previous => {
        previous.approval_receipt_digest == claim.approval_receipt_digest
      }) {
      blockers.push(ReusedApprovalClaimReceipt)
      break
    }
  }
  let evidence_well_formed = blockers.length() == 0
  blockers.push(PromotionVerifierUnavailable)
  { evidence_well_formed, routable: false, authority: None, blockers }
}

///|
pub fn LunaFluxAdapterAuthority::readiness_path(
  self : LunaFluxAdapterAuthority,
) -> String {
  self.readiness_path
}

///|
pub fn LunaFluxAdapterAuthority::drain_path(
  self : LunaFluxAdapterAuthority,
) -> String {
  self.drain_path
}

///|
/// Constructs the existing OpenAI Responses adapter only from validated
/// promotion authority. The credential value is supplied at runtime and is
/// never retained in promotion evidence.
pub fn LunaFluxAdapterAuthority::openai_text_runtime(
  self : LunaFluxAdapterAuthority,
  credential_value : String,
) -> OpenAiTextRuntime raise RemoteRuntimeError {
  if credential_value.trim() == "" ||
    credential_value.contains_char(' ') ||
    credential_value.contains_char('\t') ||
    credential_value.contains_char('\n') ||
    credential_value.contains_char('\r') {
    raise InvalidUpstreamResponse(
      "deployment bearer credential must be non-empty and contain no whitespace",
    )
  }
  OpenAiTextRuntime::new(
    self.listener_origin + self.invocation_path,
    credential_value,
    self.runtime.version,
    self.runtime.image_digest,
    self.model_artifact_digest,
  )
}
