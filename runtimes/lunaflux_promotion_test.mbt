///|
fn promotion_digest(fill : Char) -> String {
  "sha256:" + fill.to_string().repeat(64)
}

///|
fn promotion_candidate() -> @runtimes.LunaFluxCandidateManifest {
  {
    schema_version: "lunanexa.lunaflux.candidate.v1",
    runtime: {
      name: "lunaflux",
      version: "promotion-fixture",
      image_digest: promotion_digest('a'),
      architectures: ["nvidia-sm120"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    model_artifact_digest: promotion_digest('b'),
    launch_manifest_digest: promotion_digest('c'),
    kernel_manifest_digest: promotion_digest('d'),
    build_provenance_digest: promotion_digest('e'),
    sbom_digest: promotion_digest('f'),
    license_manifest_digest: promotion_digest('1'),
    physical_serving_evidence_digest: promotion_digest('2'),
  }
}

///|
fn approval_claim(
  subject : @runtimes.LunaFluxApprovalSubject,
  subject_digest : String,
  receipt_fill : Char,
) -> @runtimes.LunaFluxApprovalClaim {
  {
    subject,
    subject_digest,
    approval_receipt_digest: promotion_digest(receipt_fill),
    decision: Approved,
  }
}

///|
fn forged_promotion_submission() -> @runtimes.LunaFluxPromotionSubmission {
  let candidate = promotion_candidate()
  let serving : @runtimes.LunaFluxServingContract = {
    target_profile_digest: promotion_digest('3'),
    target_architecture: "nvidia-sm120",
    listener_contract_digest: promotion_digest('4'),
    health_readiness_contract_digest: promotion_digest('5'),
    drain_contract_digest: promotion_digest('6'),
    invocation_contract_digest: promotion_digest('7'),
    listener_origin: "https://lunaflux.runtime.invalid:8443",
    listener_port: 8443,
    invocation_path: "/v1/responses",
    health_path: "/healthz",
    readiness_path: "/readyz",
    drain_path: "/v1/drain",
    invocation_protocol: OpenAiResponsesV1,
    health_protocol: HttpJsonReadinessV1,
    drain_protocol: AuthenticatedInheritedDrainV1,
  }
  let benchmark_evidence_digest = promotion_digest('8')
  {
    schema_version: "lunanexa.lunaflux.promotion.v1",
    candidate,
    serving,
    benchmark_evidence_digest,
    approval_claims: [
      approval_claim(RuntimeImage, candidate.runtime.image_digest, '9'),
      approval_claim(PhysicalTarget, serving.target_profile_digest, 'a'),
      approval_claim(ListenerContract, serving.listener_contract_digest, 'b'),
      approval_claim(
        HealthReadinessContract,
        serving.health_readiness_contract_digest,
        'c',
      ),
      approval_claim(DrainContract, serving.drain_contract_digest, 'd'),
      approval_claim(
        InvocationContract,
        serving.invocation_contract_digest,
        'e',
      ),
      approval_claim(
        PhysicalServing,
        candidate.physical_serving_evidence_digest,
        'f',
      ),
      approval_claim(BenchmarkComparison, benchmark_evidence_digest, '0'),
    ],
  }
}

///|
test "eight caller-forged claims cannot mint LunaFlux routing authority" {
  let report = @runtimes.inspect_lunaflux_promotion(
    forged_promotion_submission(),
  )
  assert_true(report.evidence_well_formed)
  assert_false(report.routable)
  assert_eq(report.authority, None)
  assert_eq(report.blockers, [PromotionVerifierUnavailable])
}

///|
test "native-framed candidate remains explicitly non-routable" {
  let evidence = forged_promotion_submission()
  let report = @runtimes.inspect_lunaflux_promotion({
    ..evidence,
    serving: {
      ..evidence.serving,
      invocation_protocol: InvocationUnqualified,
      health_protocol: HealthReadinessUnqualified,
      drain_protocol: DrainUnqualified,
    },
    approval_claims: [],
  })
  assert_false(report.evidence_well_formed)
  assert_false(report.routable)
  assert_eq(report.authority, None)
  assert_true(report.blockers.contains(InvocationProtocolUnqualified))
  assert_true(report.blockers.contains(HealthReadinessProtocolUnqualified))
  assert_true(report.blockers.contains(DrainProtocolUnqualified))
  for
    subject in [
      @runtimes.RuntimeImage,
      PhysicalTarget,
      ListenerContract,
      HealthReadinessContract,
      DrainContract,
      InvocationContract,
      PhysicalServing,
      BenchmarkComparison,
    ] {
    assert_true(report.blockers.contains(MissingApprovalClaim(subject)))
  }
}

///|
test "pending, mismatched, duplicated, and reused claims fail closed" {
  let evidence = forged_promotion_submission()
  let approval_claims = evidence.approval_claims.copy()
  approval_claims[0] = { ..approval_claims[0], decision: Pending }
  approval_claims[1] = {
    ..approval_claims[1],
    subject_digest: promotion_digest('f'),
    approval_receipt_digest: approval_claims[0].approval_receipt_digest,
  }
  approval_claims.push(approval_claims[2])
  let report = @runtimes.inspect_lunaflux_promotion({
    ..evidence,
    approval_claims,
  })
  assert_false(report.evidence_well_formed)
  assert_false(report.routable)
  assert_eq(report.authority, None)
  assert_true(report.blockers.contains(PendingApprovalClaim(RuntimeImage)))
  assert_true(
    report.blockers.contains(ApprovalClaimSubjectMismatch(PhysicalTarget)),
  )
  assert_true(
    report.blockers.contains(DuplicateApprovalClaim(ListenerContract)),
  )
  assert_true(report.blockers.contains(ReusedApprovalClaimReceipt))
}

///|
test "malformed serving facts and rejected evidence cannot authorize routing" {
  let evidence = forged_promotion_submission()
  let approval_claims = evidence.approval_claims.copy()
  approval_claims[7] = {
    ..approval_claims[7],
    approval_receipt_digest: "sha256:short",
    decision: Rejected,
  }
  let report = @runtimes.inspect_lunaflux_promotion({
    ..evidence,
    schema_version: "lunanexa.lunaflux.promotion.future",
    benchmark_evidence_digest: "sha256:short",
    serving: {
      ..evidence.serving,
      listener_origin: "http://127.0.0.1:8443",
      listener_port: 70000,
      target_architecture: "nvidia-sm999",
      invocation_path: "/not-responses",
      health_path: "/health",
      readiness_path: "//ready",
      drain_path: "/v1/drain?force=1",
    },
    approval_claims,
  })
  assert_false(report.evidence_well_formed)
  assert_false(report.routable)
  for
    blocker in [
      @runtimes.UnsupportedPromotionSchema,
      InvalidBenchmarkEvidenceDigest,
      InvalidListenerOrigin,
      InvalidListenerPort,
      TargetArchitectureMismatch,
      InvocationPathNotOpenAiResponses,
      HealthPathNotHealthz,
      InvalidReadinessPath,
      InvalidDrainPath,
      ApprovalClaimSubjectMismatch(BenchmarkComparison),
      InvalidApprovalClaimReceipt(BenchmarkComparison),
      RejectedApprovalClaim(BenchmarkComparison),
      PromotionVerifierUnavailable,
    ] {
    assert_true(report.blockers.contains(blocker))
  }
}
