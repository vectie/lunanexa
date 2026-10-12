///|
async test "actual local binary intake save reopen review request and successor draft" {
  let fixtures = @env.get_env_var("MODEL_INTAKE_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("MODEL_INTAKE_EVIDENCE").unwrap_or("")
  if fixtures == "" || evidence == "" {
    fail("Set MODEL_INTAKE_FIXTURES and MODEL_INTAKE_EVIDENCE")
  }
  let artifact = fixtures + "/local-artifact.synthetic.bin"
  let metadata = fixtures + "/local-artifact-metadata.synthetic.json"
  let bytes = @fs.read_file(artifact).binary()
  let declarations = @fs.read_file(metadata).text()
  let (code, output, error) = invoke(["local-artifact", artifact, metadata])
  assert_eq(code, 0)
  assert_eq(error, "")
  let draft_path = evidence + "/local-draft.json"
  save(draft_path, output)
  let draft = @model_intake.import_draft(@fs.read_file(draft_path).text())
  assert_eq(draft.models.length(), 1)
  let model = draft.models[0]
  assert_eq(model.artifact.size_bytes, 131335L)
  assert_eq(
    model.artifact.digest,
    "sha256:f9bee7fdb821357e6b4a03658df896a5bb056360b1e6645dfbeacc1018130056",
  )
  assert_eq(model.state, @contracts.Candidate)
  assert_true(@contracts.valid_candidate_model(model))
  assert_false(output.contains(artifact))
  let (again_code, again, again_error) = invoke([
    "local-artifact", artifact, metadata,
  ])
  assert_eq(again_code, 0)
  assert_eq(again_error, "")
  assert_eq(again, output)
  let registry = evidence + "/local-empty-registry.json"
  save(registry, "{\"schema_version\":\"lunanexa.registry.v1\",\"models\":[]}")
  let (review_code, review, review_error) = invoke([
    "review", draft_path, registry,
  ])
  assert_eq(review_code, 0)
  assert_eq(review_error, "")
  guard @json.parse(review) is { "new_count": 1, .. } else {
    fail("new local candidate")
  }
  save(evidence + "/local-review.json", review)
  let (request_code, request, request_error) = invoke([
    "request", draft_path, registry, "local-model", "v1",
  ])
  assert_eq(request_code, 0)
  assert_eq(request_error, "")
  let decoded : @contracts.ModelRecord = @json.from_json(@json.parse(request))
  assert_eq(decoded, model)
  save(evidence + "/local-register-request.json", request)
  let existing_registry = evidence + "/local-recorded-registry.json"
  save(
    existing_registry,
    (
      {
        "schema_version": "lunanexa.registry.v1",
        "models": [{ ..model, state: @contracts.Approved, }.to_json()],
      } : Json).stringify(),
  )
  let (blocked, no_request, _) = invoke([
    "request", draft_path, existing_registry, "local-model", "v1",
  ])
  assert_true(blocked != 0)
  assert_eq(no_request, "")
  // Edit a private copy of the artifact, then review the changed byte identity.
  let changed = evidence + "/local-changed.bin"
  save(changed, b"abc")
  let (changed_code, changed_draft, changed_error) = invoke([
    "local-artifact", changed, metadata,
  ])
  assert_eq(changed_code, 0)
  assert_eq(changed_error, "")
  let changed_path = evidence + "/local-changed-draft.json"
  save(changed_path, changed_draft)
  assert_eq(
    @model_intake.import_draft(changed_draft).models[0].artifact.digest,
    "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  let (conflict_code, conflict, _) = invoke([
    "review", changed_path, existing_registry,
  ])
  assert_eq(conflict_code, 0)
  guard @json.parse(conflict) is { "conflict_count": 1, .. } else {
    fail("changed bytes must conflict")
  }
  save(evidence + "/local-conflict-review.json", conflict)
  let successor_metadata = evidence + "/local-successor-metadata.json"
  let declared = @model_intake.import_artifact_metadata(declarations)
  save(successor_metadata, { ..declared, version: "v2", }.to_json().stringify())
  let (successor_code, successor, _) = invoke([
    "local-artifact", changed, successor_metadata,
  ])
  assert_eq(successor_code, 0)
  let successor_path = evidence + "/local-successor-draft.json"
  save(successor_path, successor)
  let (new_code, successor_review, _) = invoke([
    "review", successor_path, existing_registry,
  ])
  assert_eq(new_code, 0)
  guard @json.parse(successor_review) is { "new_count": 1, .. } else {
    fail("successor is new")
  }
  save(evidence + "/local-successor-review.json", successor_review)
  assert_eq(@fs.read_file(artifact).binary(), bytes)
  assert_eq(@fs.read_file(metadata).text(), declarations)
}

///|
async test "local artifact CLI rejects unsupported inputs with empty stdout" {
  let fixtures = @env.get_env_var("MODEL_INTAKE_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("MODEL_INTAKE_EVIDENCE").unwrap_or("")
  if fixtures == "" || evidence == "" {
    fail("Set model intake paths")
  }
  let artifact = fixtures + "/local-artifact.synthetic.bin"
  let metadata = fixtures + "/local-artifact-metadata.synthetic.json"
  let declaration = @model_intake.import_artifact_metadata(
    @fs.read_file(metadata).text(),
  )
  let bounded = evidence + "/local-too-small-limit.json"
  save(
    bounded,
    { ..declaration, maximum_artifact_bytes: 131334L, }.to_json().stringify(),
  )
  let empty = evidence + "/local-empty.bin"
  save(empty, b"")
  let bad_utf8 = evidence + "/local-invalid-metadata.json"
  save(bad_utf8, b"\xff")
  let bad_json = evidence + "/local-malformed-metadata.json"
  save(bad_json, "{")
  let bad_fields = evidence + "/local-unsupported-metadata.json"
  guard declaration.to_json() is Object(fields) else { fail("metadata object") }
  fields["artifact_digest"] = Json::string("sha256:" + "a".repeat(64))
  save(bad_fields, Json::object(fields).stringify())
  for
    index, args in [
      ["local-artifact"],
      ["local-artifact", artifact, metadata, "extra"],
      ["local-artifact", evidence + "/does-not-exist.bin", metadata],
      ["local-artifact", evidence, metadata],
      ["local-artifact", empty, metadata],
      ["local-artifact", artifact, bounded],
      ["local-artifact", artifact, bad_utf8],
      ["local-artifact", artifact, bad_json],
      ["local-artifact", artifact, bad_fields],
      ["local-artifact", artifact, evidence + "/missing-metadata.json"],
    ] {
    let (code, output, error) = invoke(args)
    assert_true(code != 0)
    assert_eq(output, "")
    assert_true(error.contains("lunanexa-model-intake:"))
    save(evidence + "/local-invalid-" + index.to_string() + ".stderr", error)
  }
  let boundary = evidence + "/local-exact-limit.json"
  save(
    boundary,
    { ..declaration, maximum_artifact_bytes: 131335L, }.to_json().stringify(),
  )
  let (code, output, error) = invoke(["local-artifact", artifact, boundary])
  assert_eq(code, 0)
  assert_eq(error, "")
  assert_eq(
    @model_intake.import_draft(output).models[0].artifact.size_bytes,
    131335L,
  )
  save(evidence + "/local-exact-limit-draft.json", output)
}
