///|
fn new_local_draft(
  state : @workbench.WorkbenchState,
  name : String,
) -> @workbench.WorkbenchState {
  state
  .update(NewDraft)
  .update(DraftNameChanged(name))
  .update(DraftLanguageChanged("Text"))
  .update(SaveDraft)
}

///|
test "empty create edit duplicate rename retains exact text order and authority" {
  let base = { ..@workbench.demo_state(), files: [], active_path: "", }
  let created = new_local_draft(base, "../草稿🌙.txt")
  assert_eq(created.files.length(), 1)
  assert_eq(created.files[0].content, "")
  assert_eq(created.files[0].language, "Text")
  assert_eq(created.active_path, "../草稿🌙.txt")
  let text = "\r\n月亮🌙\n\"quoted\"\\\t</textarea><script>bad()</script>\n"
  let edited = created.update(DraftChanged(text))
  let copy = edited
    .update(DuplicateDraft)
    .update(DraftNameChanged("copy\".txt"))
    .update(SaveDraft)
  assert_eq(copy.files.length(), 2)
  assert_eq(copy.files[0], edited.files[0])
  assert_eq(copy.files[1].content, text)
  assert_eq(copy.files[1].language, "Text")
  assert_eq(copy.active_path, "copy\".txt")
  let renamed = copy
    .update(RenameDraft)
    .update(DraftNameChanged("https://invalid.test/<script>🌙"))
    .update(SaveDraft)
  assert_eq(renamed.files.length(), 2)
  assert_eq(renamed.files[0], edited.files[0])
  assert_eq(renamed.files[1].content, text)
  assert_eq(renamed.files[1].language, "Text")
  assert_eq(renamed.files[1].path, renamed.active_path)
  assert_eq(renamed.lease, base.lease)
  assert_eq(renamed.model_selector, base.model_selector)
  assert_eq(renamed.allowed_models, base.allowed_models)
  assert_eq(renamed.usage, base.usage)
  assert_eq(renamed.instruction, base.instruction)
  assert_eq(renamed.integrations, base.integrations)
  assert_false(renamed.loading)
  assert_false(@workbench.render(renamed).contains("<script>bad()</script>"))
}

///|
test "opening cancel repeated saves and navigation never create accidental files" {
  let base = {
    ..@workbench.demo_state(),
    output_text: "prior output",
    receipt: "prior receipt",
  }
  for
    begin in [
      @workbench.WorkbenchMessage::NewDraft,
      DuplicateDraft,
      RenameDraft,
    ] {
    let staged = base.update(begin).update(DraftNameChanged("new label"))
    assert_true(staged.update(begin) == staged)
    assert_eq(staged.files, base.files)
    assert_eq(staged.active_path, base.active_path)
    let cancelled = staged.update(CancelDraftEdit).update(SaveDraft)
    assert_eq(cancelled.files, base.files)
    assert_eq(cancelled.active_path, base.active_path)
    assert_eq(cancelled.output_text, base.output_text)
    assert_eq(cancelled.receipt, base.receipt)
    let saved = staged.update(SaveDraft)
    assert_true(saved.update(SaveDraft) == saved)
    let navigated = staged.update(SelectFile("README.mbt.md"))
    assert_true(navigated.draft_edit is None)
    assert_eq(navigated.update(SaveDraft).files, base.files)
    assert_eq(navigated.active_path, "README.mbt.md")
  }
}

///|
test "blank duplicate and bounded metadata failures are atomic and correctable" {
  let base = @workbench.demo_state()
  for
    begin in [
      @workbench.WorkbenchMessage::NewDraft,
      DuplicateDraft,
      RenameDraft,
    ] {
    for name in ["", " \t\n", "README.mbt.md", "x".repeat(513)] {
      let failed = base
        .update(begin)
        .update(DraftNameChanged(name))
        .update(SaveDraft)
      assert_eq(failed.files, base.files)
      assert_eq(failed.active_path, base.active_path)
      assert_eq(failed.draft_revision, base.draft_revision)
      assert_true(failed.draft_edit is Some({ error: Some(_), .. }))
      let corrected = failed.update(DraftNameChanged("valid")).update(SaveDraft)
      assert_eq(corrected.active_path, "valid")
    }
  }
  for language in ["", " \t", "x".repeat(65)] {
    let failed = base
      .update(NewDraft)
      .update(DraftNameChanged("valid"))
      .update(DraftLanguageChanged(language))
      .update(SaveDraft)
    assert_eq(failed.files, base.files)
    assert_true(failed.draft_edit is Some({ error: Some(_), .. }))
  }
  let max = base
    .update(NewDraft)
    .update(DraftNameChanged("x".repeat(512)))
    .update(DraftLanguageChanged("y".repeat(64)))
    .update(SaveDraft)
  assert_eq(max.files.length(), 3)
  // Rename to the same exact label is allowed and never duplicates the file.
  let same = base.update(RenameDraft).update(SaveDraft)
  assert_eq(same.files, base.files)
  assert_eq(same.active_path, base.active_path)
}

///|
test "file count content total text and export escaping bounds fail before mutation" {
  let base = @workbench.demo_state()
  let full = {
    ..base,
    files: [
      for i in 0..<64 => { path: i.to_string(), language: "T", content: "", }
    ],
    active_path: "0",
  }
  for begin in [@workbench.WorkbenchMessage::NewDraft, DuplicateDraft] {
    let rejected = full
      .update(begin)
      .update(DraftNameChanged("extra"))
      .update(SaveDraft)
    assert_eq(rejected.files, full.files)
    assert_eq(rejected.active_path, full.active_path)
    assert_true(rejected.draft_edit is Some({ error: Some(_), .. }))
  }
  let at_limit = base.update(DraftChanged("x".repeat(1048576)))
  assert_eq(at_limit.files[0].content.length(), 1048576)
  let too_large = at_limit.update(DraftChanged("x".repeat(1048577)))
  assert_eq(too_large.files, at_limit.files)
  assert_eq(too_large.draft_revision, at_limit.draft_revision)
  assert_true(too_large.error_message is Some(_))
  let near_total = {
    ..base,
    files: [
      for i in 0..<3 => {
        { path: i.to_string(), language: "T", content: "x".repeat(1048576), }
      }
    ],
    active_path: "0",
  }
  let rejected = near_total
    .update(DuplicateDraft)
    .update(DraftNameChanged("fourth"))
    .update(SaveDraft)
  assert_eq(rejected.files, near_total.files)
  let escaped = base.update(DraftChanged("\u0001".repeat(700000)))
  assert_eq(escaped.files, base.files)
  assert_true(escaped.error_message is Some(_))
}

///|
test "file management cancels import and input revisions fence changed work" {
  let base = @workbench.demo_state()
  let reading = base.update(ReadDraftFile)
  let callback = @workbench.WorkbenchMessage::DraftFileRead(
    reading.draft_import_generation,
    Ok(base.files),
  )
  for
    begin in [
      @workbench.WorkbenchMessage::NewDraft,
      DuplicateDraft,
      RenameDraft,
    ] {
    let opened = reading.update(begin)
    assert_true(opened.update(callback) == opened)
    assert_true(opened.draft_import_preview is None)
    let preview = reading.update(callback).update(begin)
    assert_true(preview.update(ReplaceDrafts) == preview)
    let saved = opened.update(DraftNameChanged("new")).update(SaveDraft)
    assert_true(saved.draft_revision > base.draft_revision)
  }
  let busy = { ..base, loading: true, output_text: "stale", receipt: "stale", }
  for
    changed in [
      busy.update(DraftChanged("edited")),
      busy.update(SelectFile("README.mbt.md")),
      busy.update(InstructionChanged("new instruction")),
      busy.update(ModelChanged("text.other")),
      new_local_draft(busy, "new"),
      busy
      .update(DuplicateDraft)
      .update(DraftNameChanged("copy"))
      .update(SaveDraft),
      busy
      .update(RenameDraft)
      .update(DraftNameChanged("renamed"))
      .update(SaveDraft),
    ] {
    assert_true(changed.loading)
    assert_eq(changed.output_text, "")
    assert_eq(changed.receipt, "")
    assert_true(changed.draft_revision > busy.draft_revision)
    assert_false(@workbench.can_send(changed))
    assert_eq(changed.usage, busy.usage)
  }
}

///|
test "empty file-management controls and bilingual staged form are accessible" {
  let empty = { ..@workbench.demo_state(), files: [], active_path: "", }
  let html = @workbench.render(empty)
  assert_true(html.contains("New draft"))
  assert_true(html.contains("Duplicate"))
  assert_true(html.contains("Rename"))
  assert_true(empty.update(DuplicateDraft).error_message is Some(_))
  assert_true(empty.update(RenameDraft).error_message is Some(_))
  assert_true(empty.update(DraftChanged("ignored")).files.is_empty())
  let form = @workbench.render(empty.update(NewDraft).update(SaveDraft))
  assert_true(form.contains("for=\"draft-name\""))
  assert_true(form.contains("id=\"draft-language\""))
  assert_true(form.contains("role=\"alert\""))
  assert_true(form.contains("Save draft"))
  assert_true(form.contains("Cancel"))
  let chinese = @workbench.render(
    empty.update(LocaleChanged(ChineseSimplified)).update(NewDraft),
  )
  assert_true(chinese.contains("新建草稿"))
  assert_true(chinese.contains("保存草稿"))
  assert_true(chinese.contains("取消"))
}
