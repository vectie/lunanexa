///|
fn csv() -> String {
  let value =
    #|model_id,version,artifact_digest,artifact_uri,artifact_size_bytes,signature_ref,license_id,provenance,compatible_architectures,minimum_memory_mib,extra
    #|model-a,v1,sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,s3://synthetic/a,9007199254740993,sig-a,license-a,"合成, ""declared""
    #|second line",x86_64; aarch64,32768,excluded
  value
}

///|
fn[T] rejects(call : () -> T raise) -> Unit raise {
  try call() catch {
    _ => ()
  } noraise {
    _ => fail("expected input rejection")
  }
}

///|
fn draft() -> @model_intake.Draft raise {
  @model_intake.import_csv(csv(), @model_intake.default_mapping())
}

///|
test "CSV intake retains explicit context exact bytes and Candidate state" {
  let d = draft()
  assert_eq(d.models.length(), 1)
  let m = d.models[0]
  assert_eq(m.model_id, "model-a")
  assert_eq(m.artifact.size_bytes.to_string(), "9007199254740993")
  assert_eq(m.provenance, "合成, \"declared\"\nsecond line")
  assert_eq(m.compatible_architectures, ["aarch64", "x86_64"])
  assert_eq(m.state, Candidate)
  assert_false(d.to_json().stringify().contains("excluded"))
  assert_eq(
    @model_intake.import_draft(d.to_json().stringify()).to_json(),
    d.to_json(),
  )
}

///|
test "mapping is explicit exact distinct and strict" {
  let mapping = @model_intake.default_mapping()
  let customized = {
    ..mapping,
    columns: { ..mapping.columns, model_id: "Name", },
  }
  let data = csv().replace_all(old="model_id,", new="Name,")
  assert_eq(
    @model_intake.import_csv(data, customized).to_json(),
    draft().to_json(),
  )
  rejects(() => @model_intake.import_csv(data, mapping))
  rejects(() => {
    @model_intake.import_csv(csv(), {
      ..mapping,
      columns: { ..mapping.columns, version: "model_id", },
    })
  })
  rejects(() => {
    @model_intake.import_mapping(
      mapping
      .to_json()
      .stringify()
      .replace_all(old="schema_version", new="typo"),
    )
  })
  let unknown = mapping
    .to_json()
    .stringify()
    .replace_all(old="\"columns\":", new="\"extra\":true,\"columns\":")
  rejects(() => @model_intake.import_mapping(unknown))
  rejects(() => {
    @model_intake.import_csv(csv(), { ..mapping, schema_version: 2, })
  })
}

///|
test "CSV quote record header and integer mistakes reject the complete input" {
  for
    data in [
      csv().replace_all(old="model_id,version", new="model_id,model_id"),
      csv().replace_all(old="model_id,version", new="model_id,"),
      csv() + "\n\n",
      csv() + "\nbroken,row",
      csv().replace_all(old="excluded", new="\"unterminated"),
      csv().replace_all(old="32768", new="3.5"),
      csv().replace_all(old="32768", new="2147483648"),
      csv().replace_all(old="32768", new="0"),
      csv().replace_all(old="9007199254740993", new="9223372036854775808"),
      csv().replace_all(old="9007199254740993", new="-1"),
      csv().replace_all(old="9007199254740993", new="1e4"),
    ] {
    rejects(() => {
      @model_intake.import_csv(data, @model_intake.default_mapping())
    })
  }
  let unix = draft().to_json()
  assert_eq(
    @model_intake.import_csv(
      "\uFEFF" + csv().replace_all(old="\n", new="\r\n") + "\r\n",
      @model_intake.default_mapping(),
    ).models[0].provenance,
    "合成, \"declared\"\r\nsecond line",
  )
  assert_eq(
    @model_intake.import_csv(csv() + "\n", @model_intake.default_mapping()).to_json(),
    unix,
  )
}

///|
test "model metadata never gains verification approval or guessed requirements" {
  for
    data in [
      csv().replace_all(old="model-a", new="bad/id"),
      csv().replace_all(
        old="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        new="sha256:short",
      ),
      csv().replace_all(old="s3://synthetic/a", new="https://example.invalid/a"),
      csv().replace_all(old="s3://synthetic/a", new="s3://"),
      csv().replace_all(old="s3://synthetic/a", new="s3://synthetic/../a"),
      csv().replace_all(old="sig-a", new=""),
      csv().replace_all(old="license-a", new=""),
      csv().replace_all(old="x86_64; aarch64", new="aarch64; aarch64"),
      csv().replace_all(old="x86_64; aarch64", new=""),
    ] {
    rejects(() => {
      @model_intake.import_csv(data, @model_intake.default_mapping())
    })
  }
  let d = draft()
  for state in ["Approved", "Verified", "Revoked"] {
    rejects(() => {
      @model_intake.import_draft(
        d.to_json().stringify().replace_all(old="Candidate", new=state),
      )
    })
  }
  rejects(() => {
    @model_intake.import_draft(
      d
      .to_json()
      .stringify()
      .replace_all(old="\"artifact\":", new="\"verified\":true,\"artifact\":"),
    )
  })
}

///|
test "ASCII DEL is rejected in both artifact references on every intake path" {
  let d = draft()
  let m = d.models[0]
  for
    artifact in [
      { ..m.artifact, uri: "s3://synthetic/\u007Fa", },
      { ..m.artifact, signature_ref: "sig\u007Fa", },
    ] {
    let model = { ..m, artifact, }
    // The extraction did not change historical registry admission semantics.
    assert_true(@contracts.valid_candidate_model(model))
    let changed = { ..d, models: [model], }
    rejects(() => @model_intake.import_draft(changed.to_json().stringify()))
    rejects(() => {
      @model_intake.registration_request(changed, [], "model-a", "v1")
    })
    let source : Json = {
      "schema_version": "lunanexa.registry.v1",
      "models": [model.to_json()],
    }
    rejects(() => @model_intake.import_registry(source.stringify()))
  }
  for
    data in [
      csv().replace_all(old="s3://synthetic/a", new="s3://synthetic/\u007Fa"),
      csv().replace_all(old="sig-a", new="sig\u007Fa"),
    ] {
    rejects(() => {
      @model_intake.import_csv(data, @model_intake.default_mapping())
    })
  }
}

///|
test "review distinguishes new equal metadata and conflicts without resetting state" {
  let d = draft()
  let m = d.models[0]
  let existing = {
    ..m,
    state: Approved,
    compatible_architectures: ["x86_64", "aarch64"],
  }
  let same = @model_intake.review(d, [existing])
  assert_eq(same.already_registered_count, 1)
  assert_eq(same.rows[0].registered_state, Some(Approved))
  assert_eq(same.rows[0].differences.length(), 0)
  rejects(() => {
    @model_intake.registration_request(d, [existing], "model-a", "v1")
  })
  let conflicting = { ..existing, state: Revoked, minimum_memory_mib: 16384, }
  let result = @model_intake.review(d, [conflicting])
  assert_eq(result.conflict_count, 1)
  assert_eq(result.rows[0].differences.length(), 1)
  assert_eq(result.rows[0].differences[0].field, "minimum_memory_mib")
  assert_eq(result.rows[0].differences[0].candidate, Json::number(32768))
  assert_eq(result.rows[0].differences[0].registered, Json::number(16384))
  rejects(() => {
    @model_intake.registration_request(d, [conflicting], "model-a", "v1")
  })
  let request = @model_intake.registration_request(d, [], "model-a", "v1")
  assert_eq(request, m)
  assert_eq(@model_intake.review(d, []).new_count, 1)
  rejects(() => @model_intake.registration_request(d, [], "model-a", "v2"))
  assert_eq(existing.compatible_architectures, ["x86_64", "aarch64"])
}

///|
test "duplicate identities are rejected while model versions and colon identities remain independent" {
  let d = draft()
  let m = d.models[0]
  rejects(() => @model_intake.review({ ..d, models: [m, m], }, []))
  rejects(() => @model_intake.review(d, [m, m]))
  let a = { ..m, model_id: "a:b", version: "c", }
  let b = { ..m, model_id: "a", version: "b:c", }
  let c = { ..m, version: "v2", }
  let many = { ..d, models: [c, b, m, a], }
  assert_eq(@model_intake.review(many, [a]).new_count, 3)
  assert_eq(@model_intake.registration_request(many, [a], "a", "b:c"), b)
  let reverse = { ..many, models: [a, m, b, c], }
  assert_eq(
    @model_intake.review(many, [a]).to_json(),
    @model_intake.review(reverse, [a]).to_json(),
  )
}

///|
test "saved registry shape is explicit and unrelated domains are not imported" {
  let m = draft().models[0]
  let source : Json = {
    "schema_version": "lunanexa.registry.v1",
    "models": [m.to_json()],
    "licenses": ["not validated"],
  }
  assert_eq(@model_intake.import_registry(source.stringify()), [m])
  rejects(() => @model_intake.import_registry("[]"))
  rejects(() => {
    @model_intake.import_registry(
      source.stringify().replace_all(old="lunanexa.registry.v1", new="v2"),
    )
  })
  let duplicate : Json = {
    "schema_version": "lunanexa.registry.v1",
    "models": [m.to_json(), m.to_json()],
  }
  rejects(() => @model_intake.import_registry(duplicate.stringify()))
  let unknown = source
    .stringify()
    .replace_all(old="\"artifact\":", new="\"unexpected\":1,\"artifact\":")
  rejects(() => @model_intake.import_registry(unknown))
}

///|
test "empty draft and bounded model collection have explicit behavior" {
  let empty = @model_intake.import_draft("{\"schema_version\":1,\"models\":[]}")
  assert_eq(@model_intake.review(empty, []).rows.length(), 0)
  rejects(() => @model_intake.registration_request(empty, [], "a", "v1"))
  let m = draft().models[0]
  let models = Array::makei(1001, i => {
    ..m,
    model_id: "model-" + i.to_string(),
  })
  rejects(() => @model_intake.review({ schema_version: 1, models, }, []))
  rejects(() => {
    @model_intake.import_csv(
      "a".repeat(2097153),
      @model_intake.default_mapping(),
    )
  })
}
