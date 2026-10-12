///|
extern "js" fn local_command_is_none(
  cmd : @rabbita.Cmd,
  none : @rabbita.Cmd,
) -> Bool =
  #| (cmd, none) => cmd === none

///|
extern "js" fn choose_downloaded_packet(text : String) -> Unit =
  #| text => {
  #|   const f = globalThis.__lunaDraftReopenFixture;
  #|   const file = new File([text], "../../inert-export.json", {type:"application/json"});
  #|   const read = file.arrayBuffer.bind(file);
  #|   file.arrayBuffer = () => { f.reads++; return read(); };
  #|   f.input.files = [file]; f.input.value = "selected";
  #| }

///|
fn local_step(
  model : AppModel,
  message : @workbench_ui.WorkbenchMessage,
) -> AppModel raise {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (next, cmd) = update(model, Workbench(message), emit)
  assert_true(
    local_command_is_none(cmd, @rabbita.none),
    msg="local draft operation emitted an effect",
  )
  next
}

///|
async fn verify_created_drafts_file_boundary() -> Unit {
  let base = draft_test_model()
  install_draft_host("", "normal")
  defer restore_draft_host()
  let mut model = {
    ..base,
    workbench: { ..base.workbench, files: [], active_path: "", },
  }
  for
    message in [
      @workbench_ui.WorkbenchMessage::NewDraft,
      DraftNameChanged("../新草稿🌙.txt"),
      DraftLanguageChanged("Plain text"),
      SaveDraft,
      SaveDraft,
    ] {
    model = local_step(model, message)
  }
  assert_eq(model.workbench.files.length(), 1)
  assert_eq(model.workbench.files[0].content, "")
  let exact = "\r\n🌙 第一行\n\"quotes\"\\\t</script><script>bad()</script>\n"
  model = local_step(model, DraftChanged(exact))
  for
    message in [
      @workbench_ui.WorkbenchMessage::DuplicateDraft,
      DraftNameChanged("copy"),
      SaveDraft,
      SaveDraft,
      RenameDraft,
      DraftNameChanged("https://inert.invalid/<script>"),
      SaveDraft,
    ] {
    model = local_step(model, message)
  }
  assert_eq(model.workbench.files.length(), 2)
  assert_eq(model.workbench.files[0].content, exact)
  assert_eq(model.workbench.files[1].content, exact)
  assert_eq(model.workbench.files[1].language, "Plain text")
  let wire = @workbench_ui.export_drafts(model.workbench)
  ignore(export_drafts_promise(wire).wait())
  let downloaded : String = downloaded_draft_text().wait().cast()
  assert_eq(downloaded, wire)
  choose_downloaded_packet(downloaded)
  let reread : String = read_drafts_promise().wait().cast()
  assert_eq(reread, downloaded)
  let selected = local_step(model, SelectFile(model.workbench.files[0].path))
  let reading = {
    ..selected,
    workbench: selected.workbench.update(ReadDraftFile),
  }
  let previewed = local_step(
    reading,
    DraftFileRead(
      reading.workbench.draft_import_generation,
      decode_draft_text(reread),
    ),
  )
  assert_eq(previewed.workbench.files, model.workbench.files)
  let reopened = local_step(previewed, ReplaceDrafts)
  assert_eq(reopened.workbench.files, model.workbench.files)
  assert_eq(@workbench_ui.export_drafts(reopened.workbench), wire)
  assert_eq(reopened.scoped_token, base.scoped_token)
  assert_eq(reopened.subject_ref, base.subject_ref)
  assert_eq(reopened.endpoint, base.endpoint)
  assert_eq(reopened.global_policy_generation, base.global_policy_generation)
  assert_eq(reopened.workbench.lease, base.workbench.lease)
  assert_eq(reopened.workbench.usage, base.workbench.usage)
  for
    excluded in [
      "PRIVATE-CREDENTIAL-FIXTURE", "PRIVATE-OUTPUT", "PRIVATE-RECEIPT", "lease-demo-01",
      "subject_ref", "requests_used", "model_selector",
    ] {
    assert_false(downloaded.contains(excluded))
  }
  assert_true(
    @json.parse(draft_host_json())
    is {
      "reads": Number(1, ..),
      "downloads": Number(1, ..),
      "uploads": Number(0, ..),
      "removed": Number(1, ..),
      "revoked": Number(1, ..),
      "value": String(""),
      ..
    },
  )
}

///|
test "late request completion settles usage but never relabels output after editing or navigation" {
  let base = draft_test_model()
  let sending = { ..base, workbench: base.workbench.update(SendRequest), }
  let result = RequestCompleted({
    output_text: Some("OLD INPUT OUTPUT"),
    receipt: "OLD INPUT RECEIPT",
    usage: {
      input_units: 3,
      output_units: 4,
      accelerator_ms: 5L,
      queue_ms: 0L,
    },
  })
  let response = AppMessage::Outcome(
    DraftBoundOutcome(
      sending.workbench.draft_import_generation,
      InputBoundOutcome(sending.workbench.draft_revision, result),
    ),
  )
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let copy = sending.workbench
    .update(DuplicateDraft)
    .update(DraftNameChanged("copy"))
    .update(SaveDraft)
  let renamed = sending.workbench
    .update(RenameDraft)
    .update(DraftNameChanged("renamed"))
    .update(SaveDraft)
  let created = sending.workbench
    .update(NewDraft)
    .update(DraftNameChanged("new"))
    .update(SaveDraft)
  for
    changed in [
      sending.workbench.update(DraftChanged("new input")),
      sending.workbench.update(SelectFile("README.mbt.md")),
      copy,
      renamed,
      created,
      sending.workbench.update(InstructionChanged("new instruction")),
      sending.workbench.update(ModelChanged("text.new")),
    ] {
    let current = { ..sending, workbench: changed, }
    let (settled, cmd) = update(current, response, emit)
    assert_true(local_command_is_none(cmd, @rabbita.none))
    assert_eq(settled.workbench.files, current.workbench.files)
    assert_eq(settled.workbench.active_path, current.workbench.active_path)
    assert_eq(settled.workbench.output_text, "")
    assert_eq(settled.workbench.receipt, "")
    assert_false(settled.workbench.loading)
    assert_eq(
      settled.workbench.usage.requests_used,
      base.workbench.usage.requests_used + 1,
    )
    assert_eq(
      settled.workbench.usage.input_units,
      base.workbench.usage.input_units + 3,
    )
    assert_eq(settled.workbench.lease, base.workbench.lease)
    assert_true(
      settled.workbench.success_message.unwrap().contains("earlier request"),
    )
    let (repeated, _) = update(settled, response, emit)
    assert_true(repeated == settled)
  }
  let (current, _) = update(sending, response, emit)
  assert_eq(current.workbench.output_text, "OLD INPUT OUTPUT")
  assert_eq(current.workbench.receipt, "OLD INPUT RECEIPT")
  let next_request = {
    ..current,
    workbench: current.workbench.update(SendRequest),
  }
  let (old_during_next, _) = update(next_request, response, emit)
  assert_true(old_during_next == next_request)
  let (repeated_send, cmd) = update(sending, Workbench(SendRequest), emit)
  assert_true(repeated_send == sending)
  assert_true(local_command_is_none(cmd, @rabbita.none))
}

///|
test "stale-input failures preserve authorization safety and local forms cancel on identity or reopen" {
  let base = draft_test_model()
  let sending = { ..base, workbench: base.workbench.update(SendRequest), }
  let edited = local_step(sending, DraftChanged("new input"))
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (failed, _) = update(
    edited,
    Outcome(
      DraftBoundOutcome(
        sending.workbench.draft_import_generation,
        InputBoundOutcome(
          sending.workbench.draft_revision,
          PublicFailure(
            PublicDetail("Unauthorized", "", false),
            "old failure receipt",
            true,
          ),
        ),
      ),
    ),
    emit,
  )
  assert_true(failed.workbench.lease is None)
  assert_false(failed.workbench.loading)
  assert_eq(failed.workbench.receipt, "")
  assert_eq(failed.workbench.usage, base.workbench.usage)
  assert_true(
    failed.workbench.error_message
    .unwrap()
    .contains("authorization was invalidated"),
  )
  let staged = local_step(base, NewDraft)
  for
    message in [
      AppMessage::EndpointChanged("https://new.invalid"),
      TokenChanged("different-fixture"),
      SubjectChanged("subject-other"),
    ] {
    let (changed, cmd) = update(staged, message, emit)
    assert_true(changed.workbench.draft_edit is None)
    assert_eq(changed.workbench.files, base.workbench.files)
    assert_true(local_command_is_none(cmd, @rabbita.none))
    assert_eq(
      local_step(changed, SaveDraft).workbench.files,
      base.workbench.files,
    )
  }
  let reading = staged.workbench.update(ReadDraftFile)
  assert_true(reading.draft_edit is None)
  assert_true(reading.update(SaveDraft) == reading)
}
