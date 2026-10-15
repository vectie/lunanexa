///|
async test "actual saved registry export edit successor import review and Candidate request" {
  let fixtures = @env.get_env_var("MODEL_INTAKE_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("MODEL_INTAKE_EVIDENCE").unwrap_or("")
  if fixtures == "" || evidence == "" {
    fail("Set MODEL_INTAKE_FIXTURES and MODEL_INTAKE_EVIDENCE")
  }
  let registry = fixtures + "/model-registry-edit.synthetic.json"
  let mapping = fixtures + "/model-catalog-mapping.v1.json"
  let original = @fs.read_file(registry).text()
  let original_mapping = @fs.read_file(mapping).text()
  let (code, exported, error) = invoke(["export", registry, mapping])
  assert_eq(code, 0)
  assert_eq(error, "")
  let catalog = evidence + "/exported-catalog.csv"
  save(catalog, exported)
  let (again_code, repeated, again_error) = invoke(["export", registry, mapping])
  assert_eq(again_code, 0)
  assert_eq(again_error, "")
  assert_eq(repeated, exported)
  let table = @csv.parse(@fs.read_file(catalog).text())
  assert_eq(table.rows.length(), 3)
  assert_eq(table.rows[0][0], "Model")
  assert_eq(table.rows[0][10], "lunanexa_registered_state")
  assert_eq(table.rows[1][10], "Revoked")
  assert_eq(table.rows[2][10], "Approved")
  assert_eq(table.rows[2][4], "9007199254740993")
  let (import_code, imported, import_error) = invoke([
    "import", catalog, mapping,
  ])
  assert_eq(import_code, 0)
  assert_eq(import_error, "")
  let draft_path = evidence + "/exported-draft.json"
  save(draft_path, imported)
  let (review_code, review_text, review_error) = invoke([
    "review", draft_path, registry,
  ])
  assert_eq(review_code, 0)
  assert_eq(review_error, "")
  guard @json.parse(review_text)
    is {
      "already_registered_count": 2,
      "new_count": 0,
      "conflict_count": 0,
      ..
    } else {
    fail("unchanged exported models should exactly match recorded metadata")
  }
  save(evidence + "/exported-review.json", review_text)
  // An ordinary CSV editor changes the selected row, leaving the other record intact.
  let edited = table
    .set_cell_text(3, 2, "v2")
    .set_cell_text(
      3, 3, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    )
    .set_cell_text(3, 4, "s3://synthetic-models/successor")
    .set_cell_text(3, 6, "synthetic-signature-successor")
    .set_cell_text(
      3, 8, "Synthetic successor declaration; no verified model evidence",
    )
    .set_cell_text(3, 10, "16384")
  let edited_path = evidence + "/successor-catalog.csv"
  save(edited_path, edited.serialize_quoted())
  let (edited_code, successor, edited_error) = invoke([
    "import", edited_path, mapping,
  ])
  assert_eq(edited_code, 0)
  assert_eq(edited_error, "")
  let successor_path = evidence + "/successor-draft.json"
  save(successor_path, successor)
  let (successor_code, successor_review, successor_error) = invoke([
    "review", successor_path, registry,
  ])
  assert_eq(successor_code, 0)
  assert_eq(successor_error, "")
  guard @json.parse(successor_review)
    is {
      "already_registered_count": 1,
      "new_count": 1,
      "conflict_count": 0,
      ..
    } else {
    fail(
      "edited successor must be new while the untouched model stays existing",
    )
  }
  save(evidence + "/successor-review.json", successor_review)
  let (request_code, request_text, request_error) = invoke([
    "request", successor_path, registry, "model-existing", "v2",
  ])
  assert_eq(request_code, 0)
  assert_eq(request_error, "")
  let request : @contracts.ModelRecord = @json.from_json(
    @json.parse(request_text),
  )
  assert_eq(request.state, Candidate)
  assert_eq(request.version, "v2")
  assert_eq(request.minimum_memory_mib, 16384)
  assert_eq(request.artifact.size_bytes, 9007199254740993L)
  assert_eq(request.artifact.uri, "s3://synthetic-models/successor")
  assert_true(@contracts.valid_candidate_model(request))
  save(evidence + "/successor-register-model.json", request_text)
  // Invalid exports and unchanged-identity extraction produce no partial output.
  let malformed = evidence + "/export-malformed.json"
  save(malformed, "{")
  let bad_utf8 = evidence + "/export-invalid-utf8.json"
  save(bad_utf8, b"\xff")
  let formula = evidence + "/export-formula.json"
  save(
    formula,
    original.replace_all(old="Synthetic prior metadata", new="=1+1"),
  )
  let empty_path = evidence + "/export-empty.json"
  save(
    empty_path, "{\"schema_version\":\"lunanexa.registry.v1\",\"models\":[]}",
  )
  let (empty_code, empty_output, empty_error) = invoke([
    "export", empty_path, mapping,
  ])
  assert_eq(empty_code, 0)
  assert_eq(empty_error, "")
  assert_eq(@csv.parse(empty_output).rows.length(), 1)
  save(evidence + "/empty-catalog.csv", empty_output)
  let cases = [
    ["export", registry],
    ["export", registry, mapping, "extra"],
    ["export", malformed, mapping],
    ["export", registry, malformed],
    ["export", bad_utf8, mapping],
    ["export", formula, mapping],
    ["export", evidence + "/missing-registry.json", mapping],
    ["request", draft_path, registry, "model-existing", "v1"],
    ["request", draft_path, registry, "model-conflict", "v1"],
  ]
  for index, args in cases {
    let (failed_code, output, message) = invoke(args)
    assert_true(failed_code != 0)
    assert_eq(output, "")
    assert_true(message.contains("lunanexa-model-intake:"))
    save(evidence + "/export-invalid-" + index.to_string() + ".stderr", message)
  }
  assert_eq(@fs.read_file(registry).text(), original)
  assert_eq(@fs.read_file(mapping).text(), original_mapping)
  assert_eq(@fs.read_file(catalog).text(), exported)
  save(
    evidence + "/EXPORT_WORKFLOW.json",
    (
      {
        "passed": true,
        "synthetic_only": true,
        "exported_models": 2,
        "unchanged_roundtrip_matches": 2,
        "successor_candidates": 1,
        "untouched_existing_models": 1,
        "candidate_contract_passed": true,
        "large_integer_exact": true,
        "recorded_states_visible": true,
        "existing_identity_request_blocked": true,
        "inputs_unchanged": true,
        "invalid_cases": 9,
        "failure_stdout_empty": true,
        "registry_mutations_or_approvals": false,
      } : Json).stringify(indent=2),
  )
}
