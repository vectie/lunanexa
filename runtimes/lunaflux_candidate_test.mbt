///|
fn digest(fill : Char) -> String {
  "sha256:" + fill.to_string().repeat(64)
}

///|
fn valid_candidate() -> @runtimes.LunaFluxCandidateManifest {
  {
    schema_version: "lunanexa.lunaflux.candidate.v1",
    runtime: {
      name: "lunaflux",
      version: "candidate-r17-serving",
      image_digest: digest('a'),
      architectures: ["nvidia-sm120"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    model_artifact_digest: digest('b'),
    launch_manifest_digest: digest('c'),
    kernel_manifest_digest: digest('d'),
    build_provenance_digest: "sha256:08b0139de9d5c2b9e70da27e3f8de2cc4fc2f91571458bdab889b4b824f65a9b",
    sbom_digest: digest('f'),
    license_manifest_digest: digest('1'),
    physical_serving_evidence_digest: "sha256:c236f1626fc958fe51f1a24eeaff635a1f3bce367999cca2bf330d6f5228da8b",
  }
}

///|
test "LunaFlux candidate is digest strict and cannot route traffic" {
  let candidate = valid_candidate()
  let decoded : @runtimes.LunaFluxCandidateManifest = @json.from_json(
    candidate.to_json(),
  )
  assert_eq(decoded, candidate)
  let report = @runtimes.inspect_lunaflux_candidate(candidate)
  assert_true(report.manifest_valid)
  assert_false(report.routable)
  assert_eq(report.blockers, [
    ApprovedOciImageMissing,
    PhysicalTargetApprovalMissing,
    ListenerContractUnapproved,
    HealthReadinessContractMissing,
    DrainContractUnapproved,
    InvocationContractUnapproved,
    PhysicalServingEvidenceUnapproved,
    BenchmarkComparisonMissing,
  ])
  let encoded = candidate.to_json().stringify()
  for
    forbidden in [
      "endpoint", "credential", "health_path", "readiness_path", "mount_path", "command",
    ] {
    assert_false(encoded.contains(forbidden))
  }
}

///|
test "LunaFlux candidate rejects hostile identity, claims, and evidence" {
  let candidate : @runtimes.LunaFluxCandidateManifest = {
    schema_version: "lunanexa.lunaflux.promoted.v1",
    runtime: {
      name: "registry.invalid/lunaflux",
      version: "bad version",
      image_digest: "sha256:aaaa",
      architectures: ["nvidia-sm120", "nvidia-sm120"],
      capabilities: [TextGenerate, ImageGenerate],
      supports_batching: true,
      supports_multi_node: true,
    },
    model_artifact_digest: "sha256:bbbb",
    launch_manifest_digest: "sha256:cccc",
    kernel_manifest_digest: "sha256:dddd",
    build_provenance_digest: "sha256:eeee",
    sbom_digest: "sha256:ffff",
    license_manifest_digest: "sha256:1111",
    physical_serving_evidence_digest: "sha256:2222",
  }
  let report = @runtimes.inspect_lunaflux_candidate(candidate)
  assert_false(report.manifest_valid)
  assert_false(report.routable)
  for
    blocker in [
      @runtimes.UnsupportedCandidateSchema,
      InvalidRuntimeIdentity,
      InvalidRuntimeVersion,
      InvalidRuntimeImageDigest,
      InvalidRuntimeArchitecture,
      UnsupportedRuntimeCapability,
      UnqualifiedBatchingClaim,
      UnqualifiedMultiNodeClaim,
      InvalidModelArtifactDigest,
      InvalidLaunchManifestDigest,
      InvalidKernelManifestDigest,
      InvalidBuildProvenanceDigest,
      InvalidSbomDigest,
      InvalidLicenseManifestDigest,
      InvalidPhysicalServingEvidenceDigest,
    ] {
    assert_true(report.blockers.contains(blocker))
  }
}
