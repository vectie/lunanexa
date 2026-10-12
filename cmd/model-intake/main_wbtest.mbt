///|
async fn invoke(args : Array[String]) -> (Int, String, String) {
  let executable = @env.get_env_var("MODEL_INTAKE_EXE").unwrap_or("")
  if executable == "" {
    fail("Set MODEL_INTAKE_EXE to the built native model-intake executable")
  }
  let (code, out, err) = @process.collect_output(executable, args)
  (code, out.text(), err.text())
}

///|
async fn save(path : String, data : &@io.Data) -> Unit {
  @fs.write_file(path, data, create_mode=CreateOrTruncate)
}

///|
async test "actual CSV edit import reopen review and exact existing-contract request" {
  let fixtures = @env.get_env_var("MODEL_INTAKE_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("MODEL_INTAKE_EVIDENCE").unwrap_or("")
  if fixtures == "" || evidence == "" {
    fail("Set MODEL_INTAKE_FIXTURES and MODEL_INTAKE_EVIDENCE")
  }
  let csv = fixtures + "/model-catalog.synthetic.csv"
  let mapping = fixtures + "/model-catalog-mapping.v1.json"
  let registry = fixtures + "/model-registry.synthetic.json"
  let originals = [
    @fs.read_file(csv).text(),
    @fs.read_file(mapping).text(),
    @fs.read_file(registry).text(),
  ]
  let (mapping_code, default_mapping, mapping_error) = invoke(["mapping"])
  assert_eq(mapping_code, 0)
  assert_eq(mapping_error, "")
  assert_eq(
    @model_intake.import_mapping(default_mapping).to_json(),
    @model_intake.default_mapping().to_json(),
  )
  save(evidence + "/default-mapping.json", default_mapping)
  let (import_code, draft_text, import_error) = invoke(["import", csv, mapping])
  assert_eq(import_code, 0)
  assert_eq(import_error, "")
  let draft = evidence + "/draft.json"
  save(draft, draft_text)
  let loaded = @model_intake.import_draft(@fs.read_file(draft).text())
  assert_eq(loaded.models.length(), 3)
  for model in loaded.models {
    assert_eq(model.state, @contracts.Candidate)
  }
  let (_, repeated, _) = invoke(["import", csv, mapping])
  assert_eq(repeated, draft_text)
  let (review_code, review_text, review_error) = invoke([
    "review", draft, registry,
  ])
  assert_eq(review_code, 0)
  assert_eq(review_error, "")
  guard @json.parse(review_text)
    is {
      "new_count": 1,
      "already_registered_count": 1,
      "conflict_count": 1,
      "rows": Array(rows),
      ..
    } else {
    fail("review counts")
  }
  guard rows[0]
    is {
      "status": "conflict",
      "registered_state": "Revoked",
      "differences": Array(differences),
      ..
    } else {
    fail("conflict state")
  }
  assert_eq(differences.length(), 2)
  guard rows[1]
    is { "status": "already-registered", "registered_state": "Approved", .. } else {
    fail("approved identity remains existing")
  }
  save(evidence + "/review.json", review_text)
  let (request_code, request_text, request_error) = invoke([
    "request", draft, registry, "model-new", "v1",
  ])
  assert_eq(request_code, 0)
  assert_eq(request_error, "")
  save(evidence + "/register-model.json", request_text)
  let model : @contracts.ModelRecord = @json.from_json(
    @json.parse(@fs.read_file(evidence + "/register-model.json").text()),
  )
  assert_eq(model.artifact.size_bytes.to_string(), "9007199254740993")
  // Use the exact shared predicate called by ModelRegistry::register_model.
  assert_true(@contracts.valid_candidate_model(model))
  assert_eq(model.state, @contracts.Candidate)
  let refreshed = evidence + "/refreshed-registry.json"
  save(
    refreshed,
    (
      { "schema_version": "lunanexa.registry.v1", "models": [model.to_json()] } :
      Json).stringify(),
  )
  let (repeat_code, repeat_output, _) = invoke([
    "request", draft, refreshed, "model-new", "v1",
  ])
  assert_true(repeat_code != 0)
  assert_eq(repeat_output, "")
  // Edit the source sheet, re-import, and prove only the intended draft metadata changes.
  let edited = evidence + "/edited-catalog.csv"
  save(edited, originals[0].replace_all(old="32768", new="65536"))
  let (edit_code, edited_text, _) = invoke(["import", edited, mapping])
  assert_eq(edit_code, 0)
  let edited_draft = @model_intake.import_draft(edited_text)
  let new_model = @model_intake.registration_request(
    edited_draft,
    [],
    "model-new",
    "v1",
  )
  assert_eq(new_model.minimum_memory_mib, 65536)
  assert_eq({ ..new_model, minimum_memory_mib: 32768, }, model)
  save(evidence + "/edited-draft.json", edited_text)
  let malformed = evidence + "/malformed.json"
  save(malformed, "{")
  let invalid_utf8 = evidence + "/invalid-utf8.csv"
  save(invalid_utf8, b"\xff")
  let duplicate = evidence + "/duplicate-catalog.csv"
  save(
    duplicate,
    originals[0] + originals[0].split("\n").collect()[3].to_owned() + "\n",
  )
  let approved = evidence + "/approved-draft.json"
  save(approved, draft_text.replace_all(old="Candidate", new="Approved"))
  let del_uri = evidence + "/del-uri-draft.json"
  save(
    del_uri,
    draft_text.replace_all(
      old="s3://synthetic-models/new",
      new="s3://synthetic-models/\\u007fnew",
    ),
  )
  let del_signature = evidence + "/del-signature-draft.json"
  save(
    del_signature,
    draft_text.replace_all(
      old="synthetic-signature-new",
      new="synthetic-signature-\\u007fnew",
    ),
  )
  let cases = [
    ["send", draft, registry],
    ["import", csv],
    ["import", csv, malformed],
    ["import", invalid_utf8, mapping],
    ["import", duplicate, mapping],
    ["review", malformed, registry],
    ["review", draft, malformed],
    ["review", approved, registry],
    ["request", draft, registry, "model-existing", "v1"],
    ["request", draft, registry, "model-conflict", "v1"],
    ["request", draft, registry, "missing", "v1"],
    ["import", evidence + "/missing.csv", mapping],
    ["request", del_uri, registry, "model-new", "v1"],
    ["request", del_signature, registry, "model-new", "v1"],
  ]
  for i, args in cases {
    let (code, output, error) = invoke(args)
    assert_true(code != 0)
    assert_eq(output, "")
    assert_true(error.contains("lunanexa-model-intake:"))
    save(evidence + "/invalid-" + i.to_string() + ".stderr", error)
  }
  assert_eq(@fs.read_file(csv).text(), originals[0])
  assert_eq(@fs.read_file(mapping).text(), originals[1])
  assert_eq(@fs.read_file(registry).text(), originals[2])
  save(
    evidence + "/CLI_WORKFLOW.json",
    (
      {
        "passed": true,
        "synthetic_only": true,
        "imported_candidates": 3,
        "new": 1,
        "already_registered": 1,
        "conflicts": 1,
        "exact_shared_registration_predicate_passed": true,
        "large_integer_exact": true,
        "csv_edit_reimport": true,
        "deterministic": true,
        "inputs_unchanged": true,
        "invalid_cases": 14,
        "failure_stdout_empty": true,
        "live_registry_mutations": false,
        "approval_or_artifact_verification": false,
      } : Json).stringify(indent=2),
  )
}
