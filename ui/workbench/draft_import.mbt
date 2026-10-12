///|
/// Local packet validation errors never contain the chosen file's private text.
pub(all) enum DraftImportError {
  ReadCancelled
  ReadFailed
  InvalidPacket
  UnsupportedFormat
  InvalidFiles
  DuplicatePath
  LimitExceeded
} derive(Eq, Debug)

///|
pub extend DraftImportError with Eq::{not_equal, equal}

///|
pub extend DraftImportError with Debug::{to_repr}

///|
/// Decode only v1 authored draft fields. Names are inert browser labels, never
/// filesystem paths, URLs, credentials, model choices or lease authority.
pub fn decode_drafts(
  packet : Json,
) -> Result[Array[DraftFile], DraftImportError] {
  guard packet is Object(root) && root.length() == 2 else {
    return Err(InvalidPacket)
  }
  guard packet is { "format": String(format), "files": Array(files), .. } else {
    return Err(InvalidPacket)
  }
  if format != "lunanexa.browser-drafts.v1" {
    return Err(UnsupportedFormat)
  }
  if files.is_empty() {
    return Err(InvalidFiles)
  }
  if files.length() > 64 {
    return Err(LimitExceeded)
  }
  let drafts : Array[DraftFile] = []
  for file in files {
    guard file is Object(fields) && fields.length() == 3 else {
      return Err(InvalidFiles)
    }
    guard file
      is {
        "path": String(path),
        "language": String(language),
        "content": String(content),
        ..
      } else {
      return Err(InvalidFiles)
    }
    drafts.push({ path, language, content, })
  }
  validate_draft_files(drafts)
}

///|
/// One set of authored-field bounds for import and local file management.
fn validate_draft_files(
  files : Array[DraftFile],
) -> Result[Array[DraftFile], DraftImportError] {
  if files.is_empty() {
    return Err(InvalidFiles)
  }
  if files.length() > 64 {
    return Err(LimitExceeded)
  }
  let paths : Map[String, Bool] = Map([])
  let mut total = 0
  for { path, language, content, } in files {
    if path.trim() == "" || language.trim() == "" {
      return Err(InvalidFiles)
    }
    if path.length() > 512 ||
      language.length() > 64 ||
      content.length() > 1048576 {
      return Err(LimitExceeded)
    }
    total += path.length() + language.length() + content.length()
    if total > 4194304 {
      return Err(LimitExceeded)
    }
    if paths.contains(path) {
      return Err(DuplicatePath)
    }
    paths[path] = true
  }
  Ok(files)
}

///|
fn draft_import_error(
  locale : @i18n.Locale,
  error : DraftImportError,
) -> String {
  let detail = match error {
    ReadCancelled =>
      @i18n.copy(locale, "Reopen cancelled.", "已取消重新打开。")
    ReadFailed =>
      @i18n.copy(
        locale, "Could not read a UTF-8 JSON file.", "无法读取 UTF-8 JSON 文件。",
      )
    InvalidPacket =>
      @i18n.copy(
        locale, "The draft packet is malformed or has unexpected fields.", "草稿包格式有误或含有非预期字段。",
      )
    UnsupportedFormat =>
      @i18n.copy(
        locale, "Only lunanexa.browser-drafts.v1 is supported.", "仅支持 lunanexa.browser-drafts.v1 格式。",
      )
    InvalidFiles =>
      @i18n.copy(
        locale, "Include 1–64 files with nonempty names and languages and text content.",
        "请包含 1–64 个文件，名称和语言不能为空，内容须为文本。",
      )
    DuplicatePath =>
      @i18n.copy(
        locale, "Draft names must be unique.", "草稿名称不能重复。",
      )
    LimitExceeded =>
      @i18n.copy(
        locale, "The draft packet exceeds the displayed import limits.", "草稿包超出了显示的导入限制。",
      )
  }
  detail +
  @i18n.copy(
    locale, " Current drafts are unchanged.", " 当前草稿未更改。",
  )
}

///|
fn cancel_draft_import(state : WorkbenchState) -> WorkbenchState {
  if !state.draft_import_pending && state.draft_import_preview is None {
    return state
  }
  {
    ..state,
    draft_import_generation: state.draft_import_generation + 1L,
    draft_import_pending: false,
    draft_import_preview: None,
  }
}

///|
fn update_draft_import(
  state : WorkbenchState,
  message : WorkbenchMessage,
) -> WorkbenchState {
  match message {
    ReadDraftFile =>
      if state.loading {
        state
      } else {
        {
          ..state,
          draft_import_generation: state.draft_import_generation + 1L,
          draft_import_pending: true,
          draft_import_preview: None,
          draft_edit: None,
          error_message: None,
          success_message: None,
        }
      }
    DraftFileRead(generation, result) => {
      if !state.draft_import_pending ||
        state.draft_import_generation != generation {
        return state
      }
      match result {
        Err(ReadCancelled) => cancel_draft_import(state)
        Ok(files) => {
          // Revalidate even typed messages before offering destructive replacement.
          let packet : Json = {
            "format": "lunanexa.browser-drafts.v1",
            "files": [
              for file in files => {
                {
                  "path": file.path,
                  "language": file.language,
                  "content": file.content,
                }
              }
            ],
          }
          match decode_drafts(packet) {
            Ok(preview) =>
              {
                ..state,
                draft_import_pending: false,
                draft_import_preview: Some(preview),
                error_message: None,
              }
            Err(error) =>
              {
                ..cancel_draft_import(state),
                error_message: Some(draft_import_error(state.locale, error)),
              }
          }
        }
        Err(error) =>
          {
            ..cancel_draft_import(state),
            error_message: Some(draft_import_error(state.locale, error)),
          }
      }
    }
    CancelDraftImport => cancel_draft_import(state)
    ReplaceDrafts => {
      if state.loading {
        return state
      }
      guard state.draft_import_preview is Some(files) &&
        files.get(0) is Some(first) else {
        return state
      }
      {
        ..cancel_draft_import(state),
        files,
        active_path: first.path,
        draft_edit: None,
        draft_revision: state.draft_revision + 1L,
        output_text: "",
        receipt: "",
        error_message: None,
        success_message: Some(
          @i18n.copy(
            state.locale,
            "Drafts replaced locally. Continue editing, then export to save your changes.",
            "已在本地替换草稿。请继续编辑，完成后导出以保存更改。",
          ),
        ),
      }
    }
    _ => state
  }
}

///|
fn draft_import_view(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage]?,
) -> @rabbita.Html {
  @html.section(class="draft-import", [
    @html.label(
      for_="workbench-draft-file",
      @i18n.copy(
        state.locale,
        "Reopen exported drafts",
        "重新打开导出的草稿",
      ),
    ),
    @html.input(
      id="workbench-draft-file",
      input_type=File,
      accept="application/json,.json",
      attrs=@html.Attrs::build().disabled(state.loading),
      on_change=text_command(emit, _ => ReadDraftFile),
    ),
    @html.p(
      class="privacy-copy",
      @i18n.copy(
        state.locale,
        "Read locally, preview, then confirm replacement. Nothing is uploaded or run. UTF-8 JSON: 16 MiB, 4 Mi characters; 1–64 files; name 512, language 64, content 1 Mi characters per file. Names remain virtual labels.",
        "在本地读取并预览，确认后再替换。不会上传或运行任何内容。UTF-8 JSON：16 MiB、4 Mi 字符；1–64 个文件；每个文件名称 512、语言 64、内容 1 Mi 字符。名称仅为虚拟标签。",
      ),
    ),
    if state.draft_import_pending {
      @html.p(
        attrs=@html.Attrs::build().role("status"),
        @i18n.copy(
          state.locale,
          "Reading local draft file…",
          "正在读取本地草稿文件…",
        ),
      )
    } else {
      @html.nothing
    },
    if state.draft_import_preview is Some(files) {
      @html.div(class="draft-import-preview", [
        @html.h3(
          @i18n.copy(
            state.locale,
            "Preview imported drafts",
            "预览导入草稿",
          ),
        ),
        @html.p(
          @i18n.copy(
            state.locale,
            "Replace all current drafts? Export first if you need them. Generated output and receipt will be cleared. Editing or switching drafts cancels this preview.",
            "是否替换全部当前草稿？如需保留，请先导出。生成的输出和回执将被清除。编辑或切换草稿会取消此次预览。",
          ),
        ),
        @html.div(
          [
            for file in files => {
              @html.details([
                @html.summary(file.path + " · " + file.language),
                @html.pre(class="draft-import-content", file.content),
              ])
            }
          ],
        ),
        @html.button(
          type_="button",
          class="primary-action",
          disabled=state.loading,
          on_click=command(emit, ReplaceDrafts),
          @i18n.copy(
            state.locale,
            "Replace current drafts",
            "替换当前草稿",
          ),
        ),
      ])
    } else {
      @html.nothing
    },
    if state.draft_import_pending || state.draft_import_preview is Some(_) {
      @html.button(
        type_="button",
        class="secondary-action",
        on_click=command(emit, CancelDraftImport),
        @i18n.copy(state.locale, "Cancel reopen", "取消重新打开"),
      )
    } else {
      @html.nothing
    },
  ])
}
