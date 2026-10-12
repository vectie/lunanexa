///|
/// A synthetic host around the compiled production bridges. No physical
/// browser or download directory is claimed by these tests.
extern "js" fn install_draft_host(text : String, mode : String) -> Unit =
  #| (text, mode) => {
  #|   const prior = {document:globalThis.document, fetch:globalThis.fetch, create:URL.createObjectURL, revoke:URL.revokeObjectURL, timeout:globalThis.setTimeout};
  #|   const fixture = {prior, reads:0, downloads:0, uploads:0, removed:0, revoked:0, type:"", filename:"", blob:null, complete:null};
  #|   const bytes = mode === "utf8" ? new Uint8Array([255]) : new TextEncoder().encode(text);
  #|   const file = new File([bytes], "../../never-a-filesystem-path.json", {type:"application/json"});
  #|   if (mode === "oversized") Object.defineProperty(file, "size", {value:16777217});
  #|   file.arrayBuffer = () => {
  #|     fixture.reads++;
  #|     if (mode === "reject") return Promise.reject(new Error("private raw error must not escape"));
  #|     if (mode === "late") return new Promise(resolve => fixture.complete = () => resolve(bytes.buffer));
  #|     return Promise.resolve(bytes.buffer);
  #|   };
  #|   fixture.input = {value:"selected", files:mode === "cancel" ? [] : [file]};
  #|   globalThis.__lunaDraftReopenFixture = fixture;
  #|   globalThis.document = {
  #|     getElementById:id => id === "workbench-draft-file" ? fixture.input : null,
  #|     createElement:tag => { if (tag !== "a") throw new Error("unexpected element"); return {click() { fixture.downloads++; fixture.filename=this.download; }, remove() { fixture.removed++; }}; },
  #|     body:{appendChild:() => {}}
  #|   };
  #|   URL.createObjectURL = blob => { fixture.blob=blob; fixture.type=blob.type; return "blob:synthetic-draft"; };
  #|   URL.revokeObjectURL = () => fixture.revoked++;
  #|   globalThis.setTimeout = callback => { callback(); return 0; };
  #|   globalThis.fetch = () => { fixture.uploads++; throw new Error("unexpected network"); };
  #| }

///|
extern "js" fn restore_draft_host() -> Unit =
  #| () => {
  #|   const fixture = globalThis.__lunaDraftReopenFixture;
  #|   globalThis.document=fixture.prior.document;
  #|   globalThis.fetch=fixture.prior.fetch;
  #|   URL.createObjectURL=fixture.prior.create;
  #|   URL.revokeObjectURL=fixture.prior.revoke;
  #|   globalThis.setTimeout=fixture.prior.timeout;
  #|   delete globalThis.__lunaDraftReopenFixture;
  #| }

///|
extern "js" fn draft_host_json() -> String =
  #| () => {
  #|   const f=globalThis.__lunaDraftReopenFixture;
  #|   return JSON.stringify({reads:f.reads,downloads:f.downloads,uploads:f.uploads,removed:f.removed,revoked:f.revoked,type:f.type,filename:f.filename,value:f.input.value});
  #| }

///|
extern "js" fn downloaded_draft_text() -> @js.Promise =
  #| () => globalThis.__lunaDraftReopenFixture.blob.text()

///|
extern "js" fn finish_draft_read() -> Unit =
  #| () => globalThis.__lunaDraftReopenFixture.complete()

///|
fn draft_test_model() -> AppModel {
  {
    endpoint: "https://controller.invalid",
    scoped_token: "PRIVATE-CREDENTIAL-FIXTURE",
    subject_ref: "subject-fixture",
    demo_mode: true,
    connecting: false,
    clock_generation: 3L,
    global_policy_generation: 8L,
    global_max_output_units: 1024,
    workbench: {
      ..@workbench_ui.demo_state(),
      output_text: "PRIVATE-OUTPUT",
      receipt: "PRIVATE-RECEIPT",
    },
  }
}

///|
async fn verify_draft_roundtrip() -> Unit {
  let fixture = {
    ..@workbench_ui.default_state(0L),
    files: [
      {
        path: "../../草稿🌙\".mbt",
        language: "MoonBit",
        content: "初稿\r\n\"quotes\"\\\t🌙\n</script><script>bad()</script>",
      },
    ],
  }
  let wire = @workbench_ui.export_drafts(fixture)
  install_draft_host(wire, "normal")
  defer restore_draft_host()
  let text : String = read_drafts_promise().wait().cast()
  assert_eq(text, wire)
  let base = draft_test_model()
  let started = { ..base, workbench: base.workbench.update(ReadDraftFile), }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (preview, _) = update(
    started,
    Workbench(
      DraftFileRead(
        started.workbench.draft_import_generation,
        decode_draft_text(text),
      ),
    ),
    emit,
  )
  assert_eq(preview.workbench.files, base.workbench.files)
  assert_eq(preview.workbench.output_text, "PRIVATE-OUTPUT")
  assert_true(preview.workbench.draft_import_preview is Some(_))
  let (restored, _) = update(preview, Workbench(ReplaceDrafts), emit)
  assert_eq(restored.workbench.files, fixture.files)
  assert_eq(restored.workbench.output_text, "")
  assert_eq(restored.workbench.receipt, "")
  assert_eq(restored.scoped_token, base.scoped_token)
  assert_eq(restored.subject_ref, base.subject_ref)
  assert_eq(restored.endpoint, base.endpoint)
  assert_eq(restored.global_policy_generation, base.global_policy_generation)
  assert_eq(restored.workbench.lease, base.workbench.lease)
  assert_eq(restored.workbench.usage, base.workbench.usage)
  let (edited, _) = update(
    restored,
    Workbench(DraftChanged("编辑\r\n\"exact\"\\🌙\n")),
    emit,
  )
  let exported = @workbench_ui.export_drafts(edited.workbench)
  ignore(export_drafts_promise(exported).wait())
  let downloaded : String = downloaded_draft_text().wait().cast()
  assert_eq(downloaded, exported)
  assert_eq(decode_draft_text(downloaded), Ok(edited.workbench.files))
  assert_eq(
    @workbench_ui.export_drafts({
      ..edited.workbench,
      files: decode_draft_text(downloaded).unwrap(),
    }),
    downloaded,
  )
  for
    excluded in [
      "PRIVATE-CREDENTIAL-FIXTURE", "PRIVATE-OUTPUT", "PRIVATE-RECEIPT", "lease-demo-01",
      "requests_used", "model_selector", "subject_ref",
    ] {
    assert_false(downloaded.contains(excluded))
  }
  let host = @json.parse(draft_host_json())
  assert_true(
    host
    is {
      "reads": Number(1, ..),
      "downloads": Number(1, ..),
      "uploads": Number(0, ..),
      "removed": Number(1, ..),
      "revoked": Number(1, ..),
      "value": String(""),
      "filename": String("lunanexa-browser-drafts.json"),
      "type": String("application/json;charset=utf-8"),
      ..
    },
  )
  // Resetting the native input allows selecting the same File again.
  let again : String = read_drafts_promise().wait().cast()
  assert_eq(again, wire)
}

///|
async fn verify_draft_read_errors() -> Unit {
  for mode in ["utf8", "oversized", "reject"] {
    install_draft_host("{}", mode)
    defer restore_draft_host()
    try ignore(read_drafts_promise().wait()) catch {
      _ => ()
    } noraise {
      _ => fail("invalid local file accepted")
    }
    if mode == "oversized" {
      assert_true(
        @json.parse(draft_host_json()) is { "reads": Number(0, ..), .. },
      )
    }
  }
  install_draft_host("{}", "cancel")
  defer restore_draft_host()
  assert_true(read_drafts_promise().wait().is_null())
}

///|
async fn verify_delayed_draft_read() -> Unit {
  let wire = @workbench_ui.export_drafts(@workbench_ui.default_state(0L))
  install_draft_host(wire, "late")
  defer restore_draft_host()
  let base = draft_test_model()
  let started = { ..base, workbench: base.workbench.update(ReadDraftFile), }
  let promise = read_drafts_promise()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let messages : Array[AppMessage] = [
    Workbench(DraftChanged("latest text")),
    Workbench(SelectFile("README.mbt.md")),
    Workbench(CancelDraftImport),
    EndpointChanged("https://other.invalid"),
    TokenChanged("replacement-fixture"),
    SubjectChanged("other-subject"),
  ]
  let changed = [
    for message in messages => {
      let (next, _) = update(started, message, emit)
      next
    }
  ]
  finish_draft_read()
  let text : String = promise.wait().cast()
  for model in changed {
    let (late, _) = update(
      model,
      Workbench(
        DraftFileRead(
          started.workbench.draft_import_generation,
          decode_draft_text(text),
        ),
      ),
      emit,
    )
    assert_eq(late.workbench.files, model.workbench.files)
    assert_eq(late.workbench.active_path, model.workbench.active_path)
    assert_true(late.workbench.draft_import_preview is None)
    assert_eq(late.scoped_token, model.scoped_token)
    assert_eq(late.workbench.output_text, model.workbench.output_text)
  }
}

///|
test "compiled local file effects roundtrip errors cancellation repeats and delayed navigation" {
  // Rabbita's supplied JS runner propagates any async assertion failure as a
  // failing process. One sequential operation avoids overlapping global hosts.
  @js.async_test(() => {
    verify_draft_roundtrip()
    verify_draft_read_errors()
    verify_delayed_draft_read()
    verify_created_drafts_file_boundary()
  })
}

///|
test "JSON text decode rejects malformed deep duplicate escaped names and unwanted authority" {
  for
    text in [
      "", "not-json", "{} trailing", "{", "[[[[[[[[[[]]]]]]]]]]", "{\"format\":\"lunanexa.browser-drafts.v1\",\"files\":[{\"path\":\"a\",\"language\":\"MoonBit\",\"content\":\"\"},{\"path\":\"\\u0061\",\"language\":\"MoonBit\",\"content\":\"\"}]}",
    ] {
    assert_true(decode_draft_text(text) is Err(_))
  }
  assert_true(decode_draft_text(" ".repeat(4194305)) is Err(LimitExceeded))
}

///|
test "replacement fences an old request result and failure even after reconnection" {
  let base = draft_test_model()
  let reading = base.workbench.update(ReadDraftFile)
  let prepared = reading.update(
    DraftFileRead(
      reading.draft_import_generation,
      decode_draft_text(@workbench_ui.export_drafts(base.workbench)),
    ),
  )
  let replaced = { ..base, workbench: prepared.update(ReplaceDrafts), }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let old_generation = base.workbench.draft_import_generation
  for
    outcome in [
      RequestCompleted({
        output_text: Some("old late output"),
        receipt: "old late receipt",
        usage: {
          input_units: 1,
          output_units: 2,
          accelerator_ms: 3L,
          queue_ms: 0L,
        },
      }),
      PublicFailure(WorkloadResponseInvalid, "old failed receipt", false),
    ] {
    let (late, _) = update(
      replaced,
      Outcome(DraftBoundOutcome(old_generation, outcome)),
      emit,
    )
    assert_true(late == replaced)
  }
  // Import generation is separate from input revision; ordinary edits must
  // still allow in-flight usage/loading to settle without showing stale output.
  let edited = base.workbench.update(DraftChanged("an ordinary edit"))
  assert_eq(edited.draft_import_generation, old_generation)
}
