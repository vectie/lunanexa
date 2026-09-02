///|
fn catalog_test_digest(fill : Char) -> String {
  "sha256:" + fill.to_string().repeat(64)
}

///|
fn promotion_verification_request() -> LunaFluxPromotionVerificationRequest {
  {
    schema_version: "lunanexa.lunaflux.promotion.v1",
    candidate: {
      schema_version: "lunanexa.lunaflux.candidate.v1",
      runtime: {
        name: "lunaflux",
        version: "promotion-fixture",
        image_digest: catalog_test_digest('a'),
        architectures: ["nvidia-sm120"],
        capabilities: [TextGenerate],
        supports_batching: false,
        supports_multi_node: false,
      },
      model_artifact_digest: catalog_test_digest('b'),
      launch_manifest_digest: catalog_test_digest('c'),
      kernel_manifest_digest: catalog_test_digest('d'),
      build_provenance_digest: catalog_test_digest('e'),
      sbom_digest: catalog_test_digest('f'),
      license_manifest_digest: catalog_test_digest('1'),
      physical_serving_evidence_digest: catalog_test_digest('2'),
    },
    serving: {
      target_profile_digest: catalog_test_digest('3'),
      target_architecture: "nvidia-sm120",
      listener_contract_digest: catalog_test_digest('4'),
      health_readiness_contract_digest: catalog_test_digest('5'),
      drain_contract_digest: catalog_test_digest('6'),
      invocation_contract_digest: catalog_test_digest('7'),
      listener_origin: "https://lunaflux.runtime.invalid:8443",
      listener_port: 8443,
      invocation_path: "/v1/responses",
      health_path: "/healthz",
      readiness_path: "/readyz",
      drain_path: "/v1/drain",
      invocation_protocol: OpenAiResponsesV1,
      health_protocol: HttpJsonReadinessV1,
      drain_protocol: AuthenticatedInheritedDrainV1,
    },
    benchmark_evidence_digest: catalog_test_digest('8'),
  }
}

///|
fn trusted_approval(
  evidence_digest : String,
  receipt_fill : Char,
  authority_id : String,
) -> LunaFluxEvidenceApproval {
  {
    evidence_digest,
    approval_receipt_digest: catalog_test_digest(receipt_fill),
    authority_id,
  }
}

///|
fn complete_promotion_authority(
  request : LunaFluxPromotionVerificationRequest,
) -> LunaFluxPromotionAuthorityInput {
  {
    schema_version: "lunanexa.lunaflux.promotion-authority.v1",
    candidate_manifest: trusted_approval(
      lunaflux_candidate_manifest_digest(request.candidate),
      '0',
      "release-review",
    ),
    oci_image: trusted_approval(
      request.candidate.runtime.image_digest,
      '1',
      "image-review",
    ),
    sbom: trusted_approval(
      request.candidate.sbom_digest,
      '2',
      "security-review",
    ),
    build_provenance: trusted_approval(
      request.candidate.build_provenance_digest,
      '3',
      "build-review",
    ),
    license: trusted_approval(
      request.candidate.license_manifest_digest,
      '4',
      "license-review",
    ),
    kernel: trusted_approval(
      request.candidate.kernel_manifest_digest,
      '5',
      "kernel-review",
    ),
    physical_serving: trusted_approval(
      lunaflux_physical_serving_approval_digest(
        request.candidate,
        request.serving,
      ),
      '6',
      "physical-review",
    ),
    benchmark: trusted_approval(
      lunaflux_benchmark_approval_digest(
        request.candidate,
        request.serving,
        request.benchmark_evidence_digest,
      ),
      '7',
      "performance-review",
    ),
    control_contract: trusted_approval(
      lunaflux_control_contract_digest(request.serving),
      '8',
      "operations-review",
    ),
    invocation_contract: trusted_approval(
      lunaflux_invocation_approval_digest(request.candidate, request.serving),
      '9',
      "api-review",
    ),
  }
}

///|
fn promotion_authority_subject_fixture() -> Array[
  LunaFluxPromotionAuthoritySubject,
] {
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
fn mismatch_promotion_authority(
  input : LunaFluxPromotionAuthorityInput,
  subject : LunaFluxPromotionAuthoritySubject,
) -> LunaFluxPromotionAuthorityInput {
  let wrong = catalog_test_digest('0')
  match subject {
    CandidateManifestAuthority =>
      {
        ..input,
        candidate_manifest: {
          ..input.candidate_manifest,
          evidence_digest: wrong,
        },
      }
    OciImageAuthority =>
      { ..input, oci_image: { ..input.oci_image, evidence_digest: wrong } }
    SbomAuthority => { ..input, sbom: { ..input.sbom, evidence_digest: wrong } }
    BuildProvenanceAuthority =>
      {
        ..input,
        build_provenance: { ..input.build_provenance, evidence_digest: wrong },
      }
    LicenseAuthority =>
      { ..input, license: { ..input.license, evidence_digest: wrong } }
    KernelAuthority =>
      { ..input, kernel: { ..input.kernel, evidence_digest: wrong } }
    PhysicalServingAuthority =>
      {
        ..input,
        physical_serving: { ..input.physical_serving, evidence_digest: wrong },
      }
    BenchmarkAuthority =>
      { ..input, benchmark: { ..input.benchmark, evidence_digest: wrong } }
    ControlContractAuthority =>
      {
        ..input,
        control_contract: { ..input.control_contract, evidence_digest: wrong },
      }
    InvocationContractAuthority =>
      {
        ..input,
        invocation_contract: {
          ..input.invocation_contract,
          evidence_digest: wrong,
        },
      }
  }
}

///|
test "complete local LunaFlux authority catalog admits one exact rollout" {
  let request = promotion_verification_request()
  let catalog = prepare_lunaflux_promotion_catalog(
    complete_promotion_authority(request),
  )
  let report = catalog.verify(request)
  assert_true(report.evidence_well_formed)
  assert_true(report.routable)
  assert_eq(report.blockers, [])
  guard report.authority is Some(authority) else {
    fail("complete promotion did not produce opaque adapter authority")
  }
  assert_eq(authority.health_path(), "/healthz")
  assert_eq(authority.readiness_path(), "/readyz")
  assert_eq(authority.drain_path(), "/v1/drain")
  assert_eq(authority.approval_catalog_digest(), catalog.digest())
  assert_true(@contracts.valid_sha256_digest(catalog.digest()))
}

///|
test "every local LunaFlux approval authority is independently required" {
  let request = promotion_verification_request()
  let input = complete_promotion_authority(request)
  for subject in promotion_authority_subject_fixture() {
    let catalog = prepare_lunaflux_promotion_catalog(
      mismatch_promotion_authority(input, subject),
    )
    let report = catalog.verify(request)
    assert_false(report.evidence_well_formed)
    assert_false(report.routable)
    assert_eq(report.authority, None)
    assert_true(report.blockers.contains(PromotionAuthorityMismatch(subject)))
  }
}

///|
test "promotion catalog rejects malformed authority and receipt replay" {
  let request = promotion_verification_request()
  let input = complete_promotion_authority(request)
  try
    prepare_lunaflux_promotion_catalog({
      ..input,
      schema_version: "lunanexa.lunaflux.promotion-authority.v2",
    })
  catch {
    UnsupportedPromotionAuthoritySchema => ()
    _ => fail("unsupported authority schema returned the wrong rule")
  } noraise {
    _ => fail("unsupported authority schema was admitted")
  }
  try
    prepare_lunaflux_promotion_catalog({
      ..input,
      sbom: { ..input.sbom, approval_receipt_digest: "sha256:short" },
    })
  catch {
    InvalidPromotionAuthority(SbomAuthority) => ()
    _ => fail("malformed SBOM approval returned the wrong rule")
  } noraise {
    _ => fail("malformed SBOM approval was admitted")
  }
  try
    prepare_lunaflux_promotion_catalog({
      ..input,
      license: { ..input.license, authority_id: "not an authority id" },
    })
  catch {
    InvalidPromotionAuthority(LicenseAuthority) => ()
    _ => fail("malformed license authority returned the wrong rule")
  } noraise {
    _ => fail("malformed license authority was admitted")
  }
  try
    prepare_lunaflux_promotion_catalog({
      ..input,
      oci_image: {
        ..input.oci_image,
        approval_receipt_digest: input.candidate_manifest.approval_receipt_digest,
      },
    })
  catch {
    ReusedPromotionAuthorityReceipt(OciImageAuthority) => ()
    _ => fail("replayed promotion receipt returned the wrong rule")
  } noraise {
    _ => fail("replayed promotion receipt was admitted")
  }
}

///|
test "catalog rejects candidate control and invocation substitution" {
  let request = promotion_verification_request()
  let catalog = prepare_lunaflux_promotion_catalog(
    complete_promotion_authority(request),
  )
  let candidate_substitution = catalog.verify({
    ..request,
    candidate: {
      ..request.candidate,
      runtime: { ..request.candidate.runtime, version: "substituted-v2" },
    },
  })
  assert_false(candidate_substitution.routable)
  assert_true(
    candidate_substitution.blockers.contains(
      PromotionAuthorityMismatch(CandidateManifestAuthority),
    ),
  )
  let control_substitution = catalog.verify({
    ..request,
    serving: {
      ..request.serving,
      listener_origin: "https://replacement.runtime.invalid:8443",
    },
  })
  assert_false(control_substitution.routable)
  assert_true(
    control_substitution.blockers.contains(
      PromotionAuthorityMismatch(ControlContractAuthority),
    ),
  )
  let invocation_substitution = catalog.verify({
    ..request,
    serving: {
      ..request.serving,
      invocation_contract_digest: catalog_test_digest('0'),
    },
  })
  assert_false(invocation_substitution.routable)
  assert_true(
    invocation_substitution.blockers.contains(
      PromotionAuthorityMismatch(InvocationContractAuthority),
    ),
  )
}
