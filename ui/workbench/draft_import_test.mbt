///|
fn packet(files : Array[Json]) -> Json {
  { "format": "lunanexa.browser-drafts.v1", "files": files }
}

///|
fn draft(path : String, content : String) -> Json {
  { "path": path, "language": "MoonBit", "content": content }
}

///|
fn imported() -> Array[@workbench.DraftFile] {
  [
    {
      path: "../../草稿🌙\".mbt",
      language: "MoonBit",
      content: "line 1\r\n\"月亮🌙\"\\\n\t</pre><script>bad()</script>\n",
    },
  ]
}

///|
fn preview(state : @workbench.WorkbenchState) -> @workbench.WorkbenchState {
  let reading = state.update(ReadDraftFile)
  reading.update(DraftFileRead(reading.draft_import_generation, Ok(imported())))
}

///|
test "draft decode preserves exact unicode quotes newlines and inert names" {
  let files = imported()
  let file = files[0]
  assert_eq(
    @workbench.decode_drafts(packet([draft(file.path, file.content)])),
    Ok(files),
  )
  for
    path in [
      "/etc/passwd", "../secret", "https://example.invalid/", "<img src=x onerror=bad()>",
      "C:\\draft\\a.mbt",
    ] {
    guard @workbench.decode_drafts(packet([draft(path, "")])) is Ok(decoded) else {
      fail("inert name rejected")
    }
    assert_eq(decoded[0].path, path)
    assert_eq(decoded[0].content, "")
  }
}

///|
test "malformed unsupported duplicate empty and authority bearing packets reject" {
  for
    value in [
      Json::null(),
      Json::array([]),
      { "format": "lunanexa.browser-drafts.v2", "files": [draft("a", "")] },
      { "format": 1, "files": [draft("a", "")] },
      { "format": "lunanexa.browser-drafts.v1", "files": "text" },
      {
        "format": "lunanexa.browser-drafts.v1",
        "files": [draft("a", "")],
        "lease": "forged",
      },
      packet([]),
      packet([draft("", "")]),
      packet([draft("  ", "")]),
      packet([draft("same", "first"), draft("same", "second")]),
      packet([{ "path": "a", "language": "", "content": "" }]),
      packet([{ "path": "a", "language": "MoonBit", "content": 3 }]),
      packet([{ "path": "a", "language": "MoonBit" }]),
      packet([
        { "path": "a", "language": "MoonBit", "content": "", "token": "forged" },
      ]),
    ] {
    assert_true(@workbench.decode_drafts(value) is Err(_))
  }
}

///|
test "draft limits are enforced at count names language per file and total boundaries" {
  let max_name = "x".repeat(512)
  let max_language = "x".repeat(64)
  let max_content = "x".repeat(1048576)
  assert_true(
    @workbench.decode_drafts(
      packet([
        { "path": max_name, "language": max_language, "content": max_content },
      ]),
    )
    is Ok(_),
  )
  assert_true(
    @workbench.decode_drafts(
      packet([ for i in 0..<64 => draft(i.to_string(), "") ]),
    )
    is Ok(_),
  )
  for
    value in [
      packet([draft(max_name + "x", "")]),
      packet([{ "path": "a", "language": max_language + "x", "content": "" }]),
      packet([draft("a", max_content + "x")]),
      packet([ for i in 0..<65 => draft(i.to_string(), "") ]),
      packet([ for i in 0..<4 => draft(i.to_string(), max_content) ]),
    ] {
    assert_true(@workbench.decode_drafts(value) is Err(LimitExceeded))
  }
}

///|
test "preview waits for explicit replacement and retains current authority" {
  let base = {
    ..@workbench.demo_state(),
    output_text: "old-output",
    receipt: "old-receipt",
    instruction: "keep-instruction",
  }
  let loaded = preview(base)
  assert_eq(loaded.files, base.files)
  assert_eq(loaded.output_text, "old-output")
  assert_eq(loaded.receipt, "old-receipt")
  assert_true(loaded.draft_import_preview is Some(_))
  let replaced = loaded.update(ReplaceDrafts)
  assert_eq(replaced.files, imported())
  assert_eq(replaced.active_path, imported()[0].path)
  assert_eq(replaced.output_text, "")
  assert_eq(replaced.receipt, "")
  assert_eq(replaced.lease, base.lease)
  assert_eq(replaced.model_selector, base.model_selector)
  assert_eq(replaced.allowed_models, base.allowed_models)
  assert_eq(replaced.usage, base.usage)
  assert_eq(replaced.instruction, base.instruction)
  assert_eq(replaced.integrations, base.integrations)
  assert_false(replaced.loading)
  assert_true(replaced.draft_import_preview is None)
  assert_true(replaced.update(ReplaceDrafts) == replaced)
  assert_eq(
    replaced.update(DraftChanged("continued\n月亮🌙\n")).files[0].content,
    "continued\n月亮🌙\n",
  )
}

///|
test "cancel error duplicate callback and late reads preserve all authored changes" {
  let base = @workbench.demo_state().update(DraftChanged("do not lose\n"))
  let reading = base.update(ReadDraftFile)
  let response = @workbench.WorkbenchMessage::DraftFileRead(
    reading.draft_import_generation,
    Ok(imported()),
  )
  for
    changed in [
      reading.update(CancelDraftImport),
      reading.update(DraftChanged("newest edit")),
      reading.update(SelectFile("README.mbt.md")),
      reading.update(SelectEditor(VSCode)),
      reading.update(SelectIntegration(Trae)),
      reading.update(ReadDraftFile),
      reading.update(SendRequest),
    ] {
    assert_true(changed.update(response) == changed)
    assert_true(changed.update(ReplaceDrafts) == changed)
  }
  let loaded = reading.update(response)
  assert_true(loaded.update(response) == loaded)
  let replaced = loaded.update(ReplaceDrafts)
  assert_true(replaced.update(response) == replaced)
  for
    error in [
      @workbench.DraftImportError::ReadFailed,
      InvalidPacket,
      ReadCancelled,
    ] {
    let failed = reading.update(
      DraftFileRead(reading.draft_import_generation, Err(error)),
    )
    assert_eq(failed.files, base.files)
    assert_true(failed.draft_import_preview is None)
    assert_false(failed.draft_import_pending)
  }
}

///|
test "editing or navigating after preview cancels replacement and loading blocks reopen" {
  let base = preview(@workbench.demo_state())
  for
    changed in [
      base.update(DraftChanged("newer")),
      base.update(SelectFile("README.mbt.md")),
      base.update(CancelDraftImport),
    ] {
    assert_true(changed.draft_import_preview is None)
    assert_true(changed.update(ReplaceDrafts) == changed)
  }
  let busy = { ..base, loading: true, }
  assert_true(busy.update(ReadDraftFile) == busy)
  assert_true(busy.update(ReplaceDrafts) == busy)
}

///|
test "preview renders hostile content as text with bilingual explicit controls" {
  let base = preview(@workbench.demo_state())
  let html = @workbench.render(base)
  assert_true(html.contains("workbench-draft-file"))
  assert_true(html.contains("type=\"file\""))
  assert_true(html.contains("Preview imported drafts"))
  assert_true(html.contains("Replace current drafts"))
  assert_true(html.contains("Cancel reopen"))
  assert_true(html.contains("&lt;script&gt;bad()&lt;/script&gt;"))
  assert_false(html.contains("<script>bad()</script>"))
  assert_true(html.contains("Generated output and receipt will be cleared"))
  let chinese = @workbench.render(base.update(LocaleChanged(ChineseSimplified)))
  assert_true(chinese.contains("重新打开导出的草稿"))
  assert_true(chinese.contains("替换当前草稿"))
  assert_true(chinese.contains("取消重新打开"))
}

///|
test "import never grants readiness to an absent expired or revoked lease" {
  let base = @workbench.demo_state()
  guard base.lease is Some(lease) else { fail("fixture lease") }
  for
    state in [
      { ..base, lease: None, },
      { ..base, lease: Some({ ..lease, state: Revoked, }), },
      { ..base, now_unix_ms: lease.expires_unix_ms, },
    ] {
    let restored = preview(state).update(ReplaceDrafts)
    assert_eq(restored.lease, state.lease)
    assert_false(@workbench.can_send(restored))
  }
}
