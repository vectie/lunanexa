///|
fn local_metadata() -> @model_intake.ArtifactMetadata {
  {
    schema_version: "lunanexa.local-artifact.v1",
    model_id: "local-model",
    version: "v1",
    artifact_uri: "modelstore://synthetic/local-model.bin",
    signature_ref: "declared-signature-ref",
    license_id: "declared-license",
    provenance: "  Declared source, \"unverified\"\n本地模型 😀  ",
    compatible_architectures: ["x86_64", "aarch64"],
    minimum_memory_mib: 8192,
    maximum_artifact_bytes: 1048576L,
  }
}

///|
test "local declarations and observed bytes produce a reopenable existing Candidate draft" {
  let metadata = local_metadata()
  let original = metadata.to_json()
  let imported = @model_intake.import_artifact_metadata(original.stringify())
  let digest = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  let draft = @model_intake.artifact_draft(imported, digest, 3L)
  let reopened = @model_intake.import_draft(draft.to_json().stringify())
  assert_eq(reopened.to_json(), draft.to_json())
  let model = draft.models[0]
  assert_eq(model.artifact.digest, digest)
  assert_eq(model.artifact.size_bytes, 3L)
  assert_eq(model.provenance, metadata.provenance)
  assert_eq(model.compatible_architectures, ["aarch64", "x86_64"])
  assert_eq(model.state, @contracts.Candidate)
  assert_true(@contracts.valid_candidate_model(model))
  assert_eq(metadata.to_json(), original)
  assert_eq(@model_intake.review(draft, []).new_count, 1)
  assert_eq(
    @model_intake.registration_request(draft, [], "local-model", "v1"),
    model,
  )
  let registered = { ..model, state: @contracts.Approved, }
  assert_eq(
    @model_intake.review(draft, [registered]).already_registered_count,
    1,
  )
  rejects(() => {
    @model_intake.registration_request(draft, [registered], "local-model", "v1")
  })
}

///|
test "local artifact content changes surface in existing review without upgrading state" {
  let metadata = local_metadata()
  let previous = @model_intake.artifact_draft(
    metadata,
    "sha256:" + "a".repeat(64),
    3L,
  )
  let changed = @model_intake.artifact_draft(
    metadata,
    "sha256:" + "b".repeat(64),
    4L,
  )
  let review = @model_intake.review(changed, previous.models)
  assert_eq(review.conflict_count, 1)
  assert_eq(review.rows[0].differences.length(), 2)
  let successor = @model_intake.artifact_draft(
    { ..metadata, version: "v2", },
    "sha256:" + "b".repeat(64),
    4L,
  )
  assert_eq(@model_intake.review(successor, previous.models).new_count, 1)
  assert_eq(successor.models[0].state, @contracts.Candidate)
}

///|
test "local metadata rejects authority computed fields unknown fields and version errors" {
  let original = local_metadata().to_json()
  guard original is Object(fields) else { fail("object") }
  for
    (name, value) in [
      ("state", Json::string("Approved")),
      ("artifact_digest", Json::string("sha256:" + "a".repeat(64))),
      ("artifact_size_bytes", Json::string("3")),
      ("path", Json::string("/not-inferred")),
      ("typo", (true : Json)),
      ("schema_version", Json::string("lunanexa.local-artifact.v2")),
      ("maximum_artifact_bytes", Json::number(100)),
    ] {
    let fields = fields.copy()
    fields[name] = value
    rejects(() => {
      @model_intake.import_artifact_metadata(Json::object(fields).stringify())
    })
  }
  let fields = fields.copy()
  fields.remove("signature_ref")
  rejects(() => {
    @model_intake.import_artifact_metadata(Json::object(fields).stringify())
  })
  rejects(() => @model_intake.import_artifact_metadata(" ".repeat(16385)))
}

///|
test "local metadata uses current registration constraints before artifact acquisition" {
  let valid = local_metadata()
  for
    metadata in [
      { ..valid, model_id: "bad id", },
      { ..valid, artifact_uri: "file:///not-a-managed-reference", },
      { ..valid, signature_ref: "", },
      { ..valid, license_id: "", },
      { ..valid, provenance: " ", },
      { ..valid, compatible_architectures: [], },
      { ..valid, compatible_architectures: ["x86_64", "x86_64"], },
      { ..valid, minimum_memory_mib: 0, },
      { ..valid, maximum_artifact_bytes: 0L, },
      { ..valid, maximum_artifact_bytes: 1099511627777L, },
    ] {
    rejects(() => {
      @model_intake.import_artifact_metadata(metadata.to_json().stringify())
    })
  }
}

///|
test "local artifact exact size limits and invalid digests fail without rounding" {
  let metadata = { ..local_metadata(), maximum_artifact_bytes: 1099511627776L, }
  let digest = "sha256:" + "a".repeat(64)
  let draft = @model_intake.artifact_draft(metadata, digest, 1099511627776L)
  assert_eq(draft.models[0].artifact.size_bytes.to_string(), "1099511627776")
  for size in [-1L, 0L, 1099511627777L] {
    rejects(() => @model_intake.artifact_draft(metadata, digest, size))
  }
  rejects(() => @model_intake.artifact_draft(metadata, "sha256:bad", 1L))
}
