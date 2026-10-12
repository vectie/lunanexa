///|
test "editable export preserves every metadata field and displays all recorded states" {
  let original = draft().models[0]
  let models = [
    @contracts.Candidate,
    @contracts.Verified,
    @contracts.Evaluated,
    @contracts.Approved,
    @contracts.Deprecated,
    @contracts.Revoked,
  ].mapi((index, state) => {
    ..original,
    model_id: "model-" + index.to_string(),
    compatible_architectures: ["x86_64", "aarch64"],
    state,
  })
  let before = models.to_json()
  let mapping = @model_intake.default_mapping()
  let csv = @model_intake.export_registry_csv(models, mapping)
  for
    state in [
      "Candidate", "Verified", "Evaluated", "Approved", "Deprecated", "Revoked",
    ] {
    assert_true(csv.contains("\"" + state + "\""))
  }
  assert_true(csv.contains("\"lunanexa_registered_state\""))
  assert_true(csv.contains("\"9007199254740993\""))
  let imported = @model_intake.import_csv(csv, mapping)
  let result = @model_intake.review(imported, models)
  assert_eq(result.already_registered_count, 6)
  assert_eq(result.new_count, 0)
  assert_eq(result.conflict_count, 0)
  for index, model in imported.models {
    assert_eq(model, {
      ..models[index],
      compatible_architectures: ["aarch64", "x86_64"],
      state: @contracts.Candidate,
    })
  }
  assert_eq(models.to_json(), before)
  let reversed = Array::makei(models.length(), i => {
    models[models.length() - i - 1]
  })
  assert_eq(@model_intake.export_registry_csv(reversed, mapping), csv)
}

///|
test "custom column mapping quoted multiline Unicode and exact Int64 survive export import" {
  let mapping = @model_intake.default_mapping()
  let mapping = {
    ..mapping,
    columns: {
      ..mapping.columns,
      model_id: "模型, \"ID\"",
      provenance: "Source\nnotes",
    },
  }
  let source = draft().models[0]
  let model = {
    ..source,
    artifact: { ..source.artifact, size_bytes: 9223372036854775807L, },
    provenance: "  合成, \"declared\"\r\nsecond line 😀  ",
    state: @contracts.Approved,
  }
  let exported = @model_intake.export_registry_csv([model], mapping)
  let imported = @model_intake.import_csv(exported, mapping)
  assert_eq(imported.models[0], { ..model, state: @contracts.Candidate, })
  assert_eq(@model_intake.review(imported, [model]).already_registered_count, 1)
  assert_true(exported.has_suffix("\r\n"))
}

///|
test "an exported catalog becomes a successor Candidate only after explicit identity edit" {
  let model = { ..draft().models[0], state: @contracts.Approved, }
  let mapping = @model_intake.default_mapping()
  let csv = @model_intake.export_registry_csv([model], mapping)
  let unchanged = @model_intake.import_csv(csv, mapping)
  rejects(() => {
    @model_intake.registration_request(unchanged, [model], "model-a", "v1")
  })
  let edited = csv
    .replace_all(old="\"v1\"", new="\"v2\"")
    .replace_all(old="\"32768\"", new="\"65536\"")
  let candidate = @model_intake.import_csv(edited, mapping)
  let request = @model_intake.registration_request(
    candidate,
    [model],
    "model-a",
    "v2",
  )
  assert_eq(request, {
    ..model,
    version: "v2",
    minimum_memory_mib: 65536,
    state: @contracts.Candidate,
  })
  assert_true(@contracts.valid_candidate_model(request))
  // Changing the informational state cell never authorizes approval.
  let revoked_label = @model_intake.import_csv(
    edited.replace_all(old="Approved", new="Revoked"),
    mapping,
  )
  assert_eq(revoked_label.to_json(), candidate.to_json())
}

///|
test "editable export refuses formula-like text rather than silently changing metadata" {
  let model = draft().models[0]
  let mapping = @model_intake.default_mapping()
  for
    value in [
      "=1+1", "+1", "-note", "@formula", "  =cmd", "\ttext", "\rtext", "\ntext",
    ] {
    rejects(() => {
      @model_intake.export_registry_csv(
        [{ ..model, provenance: value, }],
        mapping,
      )
    })
  }
  rejects(() => {
    @model_intake.export_registry_csv(
      [{ ..model, model_id: "-model", }],
      mapping,
    )
  })
  rejects(() => {
    @model_intake.export_registry_csv(
      [
        {
          ..model,
          artifact: { ..model.artifact, signature_ref: "=signature", },
        },
      ],
      mapping,
    )
  })
  rejects(() => {
    @model_intake.export_registry_csv([model], {
      ..mapping,
      columns: { ..mapping.columns, model_id: "=Name", },
    })
  })
  rejects(() => {
    @model_intake.export_registry_csv(
      [
        {
          ..model,
          artifact: { ..model.artifact, signature_ref: " signature ", },
        },
      ],
      mapping,
    )
  })
  // Existing JSON review still supports these source values without altering them.
  let formula = { ..model, provenance: "=1+1", }
  assert_eq(
    @model_intake.review({ schema_version: 1, models: [formula], }, [formula]).already_registered_count,
    1,
  )
}

///|
test "empty bounds duplicate metadata and mapping behavior is explicit before CSV output" {
  let mapping = @model_intake.default_mapping()
  let empty = @model_intake.export_registry_csv([], mapping)
  assert_eq(empty.split("\r\n").count(), 2)
  rejects(() => @model_intake.import_csv(empty, mapping))
  let model = draft().models[0]
  rejects(() => @model_intake.export_registry_csv([model, model], mapping))
  rejects(() => {
    @model_intake.export_registry_csv(
      [{ ..model, minimum_memory_mib: 0, }],
      mapping,
    )
  })
  rejects(() => {
    @model_intake.export_registry_csv([model], { ..mapping, schema_version: 2, })
  })
  rejects(() => {
    @model_intake.export_registry_csv([model], {
      ..mapping,
      columns: { ..mapping.columns, model_id: "lunanexa_registered_state", },
    })
  })
  rejects(() => {
    @model_intake.export_registry_csv([model], {
      ..mapping,
      columns: { ..mapping.columns, model_id: "version", },
    })
  })
  let models = Array::makei(1001, index => {
    ..model,
    model_id: "model-" + index.to_string(),
  })
  rejects(() => @model_intake.export_registry_csv(models, mapping))
  let oversized = Array::makei(600, index => {
    ..model,
    model_id: "model-" + index.to_string(),
    provenance: "p".repeat(4096),
  })
  rejects(() => @model_intake.export_registry_csv(oversized, mapping))
}
