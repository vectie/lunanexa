///|
test "shared registration predicate preserves existing candidate metadata rules" {
  let model : @contracts.ModelRecord = {
    model_id: "model-a",
    version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://synthetic/a",
      size_bytes: 42L,
      signature_ref: "declared-signature",
    },
    license_id: "license-a",
    provenance: "operator-declared",
    compatible_architectures: ["aarch64"],
    minimum_memory_mib: 1024,
    state: Candidate,
  }
  assert_true(@contracts.valid_candidate_model(model))
  for
    candidate in [
      { ..model, model_id: "", },
      { ..model, version: "bad/version", },
      { ..model, artifact: { ..model.artifact, uri: "s3://bucket/../a", }, },
      { ..model, artifact: { ..model.artifact, uri: "file://model", }, },
      { ..model, artifact: { ..model.artifact, uri: "s3://bucket/<script", }, },
      { ..model, artifact: { ..model.artifact, uri: "s3://bucket/a\n", }, },
      { ..model, artifact: { ..model.artifact, uri: "https://synthetic/a", }, },
      { ..model, artifact: { ..model.artifact, digest: "sha256:bad", }, },
      { ..model, artifact: { ..model.artifact, size_bytes: 0L, }, },
      { ..model, artifact: { ..model.artifact, signature_ref: "", }, },
      { ..model, artifact: { ..model.artifact, signature_ref: "sig\n", }, },
      { ..model, license_id: "bad/license", },
      { ..model, provenance: "", },
      { ..model, compatible_architectures: [], },
      { ..model, compatible_architectures: ["bad/arch"], },
      { ..model, minimum_memory_mib: 0, },
      { ..model, state: Approved, },
      { ..model, state: Verified, },
      { ..model, state: Revoked, },
    ] {
    assert_false(@contracts.valid_candidate_model(candidate))
  }
  // Preserve historical registry semantics. The offline intake's bounded
  // spreadsheet profile separately rejects these under-specified records.
  assert_true(
    @contracts.valid_candidate_model({
      ..model,
      artifact: { ..model.artifact, uri: "s3://", },
    }),
  )
  assert_true(@contracts.valid_candidate_model({ ..model, provenance: " ", }))
  assert_true(
    @contracts.valid_candidate_model({
      ..model,
      compatible_architectures: ["aarch64", "aarch64"],
    }),
  )
}
