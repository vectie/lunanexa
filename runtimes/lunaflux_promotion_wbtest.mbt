///|
fn verifier_only_authority_fixture() -> LunaFluxAdapterAuthority {
  {
    runtime: {
      name: "lunaflux",
      version: "promotion-fixture",
      image_digest: "sha256:" + "a".repeat(64),
      architectures: ["nvidia-sm120"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    candidate_manifest_digest: "sha256:" + "4".repeat(64),
    model_artifact_digest: "sha256:" + "b".repeat(64),
    launch_manifest_digest: "sha256:" + "a".repeat(64),
    build_provenance_digest: "sha256:" + "5".repeat(64),
    sbom_digest: "sha256:" + "6".repeat(64),
    license_manifest_digest: "sha256:" + "7".repeat(64),
    kernel_manifest_digest: "sha256:" + "8".repeat(64),
    listener_origin: "https://lunaflux.runtime.invalid:8443",
    invocation_path: "/v1/responses",
    health_path: "/healthz",
    readiness_path: "/readyz",
    drain_path: "/v1/drain",
    target_profile_digest: "sha256:" + "c".repeat(64),
    listener_contract_digest: "sha256:" + "d".repeat(64),
    health_readiness_contract_digest: "sha256:" + "e".repeat(64),
    drain_contract_digest: "sha256:" + "f".repeat(64),
    invocation_contract_digest: "sha256:" + "1".repeat(64),
    control_contract_digest: "sha256:" + "9".repeat(64),
    physical_serving_evidence_digest: "sha256:" + "2".repeat(64),
    benchmark_evidence_digest: "sha256:" + "3".repeat(64),
    approval_catalog_digest: "sha256:" + "0".repeat(64),
  }
}

///|
test "opaque LunaFlux authority rejects empty deployment bearer credentials" {
  let authority = verifier_only_authority_fixture()
  for credential in ["", " ", "token with space", "token\nheader"] {
    try authority.openai_text_runtime(credential) catch {
      InvalidUpstreamResponse(message) =>
        assert_eq(
          message, "deployment bearer credential must be non-empty and contain no whitespace",
        )
      _ => fail("unexpected credential error")
    } noraise {
      _ => fail("invalid bearer credential was accepted")
    }
  }
}

///|
test "opaque LunaFlux authority accepts a non-empty deployment bearer token" {
  let authority = verifier_only_authority_fixture()
  let runtime = authority.openai_text_runtime("deployment-token")
  assert_eq(runtime.image_digest(), "sha256:" + "a".repeat(64))
  assert_eq(runtime.artifact_digest(), "sha256:" + "b".repeat(64))
  assert_eq(authority.health_path(), "/healthz")
  assert_eq(authority.readiness_path(), "/readyz")
  assert_eq(authority.drain_path(), "/v1/drain")
}
