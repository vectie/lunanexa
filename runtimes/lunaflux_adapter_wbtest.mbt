///|
test "opaque LunaFlux adapter retains the exact approved rollout" {
  let adapter = verifier_only_authority_fixture().opaque_adapter()
  assert_eq(adapter.runtime().name, "lunaflux")
  assert_eq(adapter.runtime().image_digest, "sha256:" + "a".repeat(64))
  assert_eq(adapter.model_artifact_digest(), "sha256:" + "b".repeat(64))
  assert_eq(adapter.launch_manifest_digest(), "sha256:" + "a".repeat(64))
  assert_eq(adapter.target_profile_digest(), "sha256:" + "c".repeat(64))
  assert_eq(
    adapter.health_url(),
    "https://lunaflux.runtime.invalid:8443/healthz",
  )
  assert_eq(
    adapter.readiness_url(),
    "https://lunaflux.runtime.invalid:8443/readyz",
  )
  assert_eq(adapter.inherited_drain_path(), "/v1/drain")
  assert_true(@contracts.valid_sha256_digest(adapter.contract_digest()))
}

///|
test "opaque LunaFlux adapter identity binds every authority envelope" {
  let authority = verifier_only_authority_fixture()
  let exact = authority.opaque_adapter().contract_digest()
  let variants = [
    { ..authority, candidate_manifest_digest: "sha256:" + "1".repeat(64) },
    { ..authority, launch_manifest_digest: "sha256:" + "5".repeat(64) },
    { ..authority, control_contract_digest: "sha256:" + "2".repeat(64) },
    { ..authority, invocation_contract_digest: "sha256:" + "3".repeat(64) },
    { ..authority, approval_catalog_digest: "sha256:" + "4".repeat(64) },
  ]
  for variant in variants {
    assert_not_eq(variant.opaque_adapter().contract_digest(), exact)
  }
}

///|
test "launch manifest substitution cannot produce opaque adapter authority" {
  let request = promotion_verification_request()
  let catalog = prepare_lunaflux_promotion_catalog(
    complete_promotion_authority(request),
  )
  let report = catalog.verify({
    ..request,
    candidate: {
      ..request.candidate,
      launch_manifest_digest: "sha256:" + "0".repeat(64),
    },
  })
  assert_false(report.routable)
  assert_eq(report.authority, None)
  assert_true(
    report.blockers.contains(
      PromotionAuthorityMismatch(CandidateManifestAuthority),
    ),
  )
}

///|
test "opaque LunaFlux adapter never retains an invalid bearer credential" {
  let adapter = verifier_only_authority_fixture().opaque_adapter()
  for credential in ["", "token with space", "token\nheader"] {
    try adapter.openai_text_runtime(credential) catch {
      InvalidUpstreamResponse(_) => ()
      _ => fail("unexpected credential error")
    } noraise {
      _ => fail("invalid bearer credential was accepted")
    }
  }
}
