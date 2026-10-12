///|
pub(all) enum DraftOperation {
  Create
  Duplicate(String)
  Rename(String)
} derive(Eq, Debug)

///|
pub extend DraftOperation with Eq::{not_equal, equal}

///|
pub extend DraftOperation with Debug::{to_repr}

///|
pub(all) struct DraftEdit {
  operation : DraftOperation
  name : String
  language : String
  error : String?
} derive(Eq, Debug)

///|
pub extend DraftEdit with Eq::{not_equal, equal}

///|
pub extend DraftEdit with Debug::{to_repr}

///|
/// Results belong to an exact input revision. Keep loading and usage intact:
/// local editing does not cancel, retry or issue a provider request.
fn draft_input_changed(state : WorkbenchState) -> WorkbenchState {
  {
    ..state,
    draft_revision: state.draft_revision + 1L,
    output_text: "",
    receipt: "",
    success_message: None,
  }
}

///|
fn local_draft_error(locale : @i18n.Locale, error : DraftImportError) -> String {
  match error {
    InvalidFiles =>
      @i18n.copy(
        locale, "Enter a draft name and language. Whitespace alone is not a name or language.",
        "请输入草稿名称和语言，不能仅包含空白。",
      )
    DuplicatePath =>
      @i18n.copy(
        locale, "That draft name already exists. Choose a unique name.", "该草稿名称已存在，请选择不同的名称。",
      )
    _ =>
      @i18n.copy(
        locale, "Draft limits exceeded: 64 files; name 512, language 64, content 1 Mi characters; exported JSON 4 Mi characters. Shorten the text or export a smaller set.",
        "草稿超出限制：64 个文件；名称 512、语言 64、内容 1 Mi 字符；导出的 JSON 4 Mi 字符。请缩短文本或使用更小的草稿集。",
      )
  }
}

///|
fn validated_local_drafts(
  state : WorkbenchState,
  files : Array[DraftFile],
) -> Result[Array[DraftFile], DraftImportError] {
  match validate_draft_files(files) {
    Err(error) => Err(error)
    Ok(files) =>
      // JSON escaping and pretty-print overhead also count at the File boundary.
      // A successful edit must still export to a packet the v1 reader can reopen.
      if export_drafts({ ..state, files, }).length() > 4194304 {
        Err(LimitExceeded)
      } else {
        Ok(files)
      }
  }
}

///|
fn update_draft_management(
  state : WorkbenchState,
  message : WorkbenchMessage,
) -> WorkbenchState {
  match message {
    NewDraft | DuplicateDraft | RenameDraft => {
      // Repeated opening clicks never overwrite a form or create a file.
      if state.draft_edit is Some(_) {
        return state
      }
      let edit : DraftEdit = match message {
        NewDraft =>
          { operation: Create, name: "", language: "MoonBit", error: None, }
        _ => {
          guard active_file(state) is Some(file) else {
            return {
              ..state,
              error_message: Some(
                @i18n.copy(
                  state.locale,
                  "Select a draft to duplicate or rename, or create a new draft.",
                  "请选择要复制或重命名的草稿，或新建草稿。",
                ),
              ),
            }
          }
          {
            operation: if message == DuplicateDraft {
              Duplicate(file.path)
            } else {
              Rename(file.path)
            },
            name: if message == DuplicateDraft {
              ""
            } else {
              file.path
            },
            language: file.language,
            error: None,
          }
        }
      }
      {
        ..cancel_draft_import(state),
        draft_edit: Some(edit),
        error_message: None,
        success_message: None,
      }
    }
    DraftNameChanged(name) =>
      match state.draft_edit {
        Some(edit) =>
          { ..state, draft_edit: Some({ ..edit, name, error: None, }), }
        None => state
      }
    DraftLanguageChanged(language) =>
      match state.draft_edit {
        Some(edit) if edit.operation == Create =>
          { ..state, draft_edit: Some({ ..edit, language, error: None, }), }
        _ => state
      }
    CancelDraftEdit => { ..state, draft_edit: None, }
    SaveDraft => {
      guard state.draft_edit is Some(edit) else { return state }
      let files = state.files.copy()
      match edit.operation {
        Create =>
          files.push({ path: edit.name, language: edit.language, content: "", })
        Duplicate(source) | Rename(source) => {
          guard active_file({ ..state, active_path: source, }) is Some(file) else {
            return {
              ..state,
              draft_edit: None,
              error_message: Some(
                @i18n.copy(
                  state.locale,
                  "The source draft is no longer available. Select a current draft.",
                  "来源草稿已不可用，请选择当前草稿。",
                ),
              ),
            }
          }
          match edit.operation {
            Duplicate(_) => files.push({ ..file, path: edit.name, })
            _ =>
              for i in 0..<files.length() {
                if files[i].path == source {
                  files[i] = { ..file, path: edit.name, }
                }
              }
          }
        }
      }
      match validated_local_drafts(state, files) {
        Err(error) =>
          {
            ..state,
            draft_edit: Some({
              ..edit,
              error: Some(local_draft_error(state.locale, error)),
            }),
          }
        Ok(files) =>
          {
            ..draft_input_changed(cancel_draft_import(state)),
            files,
            active_path: edit.name,
            draft_edit: None,
            error_message: None,
            success_message: Some(
              @i18n.copy(
                state.locale,
                "Draft saved in this page. Export to keep your changes.",
                "草稿已保存在当前页面中，请导出以保留更改。",
              ),
            ),
          }
      }
    }
    DraftChanged(content) => {
      guard active_file(state) is Some(current) else {
        return {
          ..state,
          error_message: Some(
            @i18n.copy(
              state.locale,
              "Create or select a draft before editing.",
              "请先新建或选择草稿再进行编辑。",
            ),
          ),
        }
      }
      let state = cancel_draft_import(state)
      if current.content == content {
        return state
      }
      let files = [
        for file in state.files => {
          if file.path == state.active_path {
            { ..file, content, }
          } else {
            file
          }
        }
      ]
      match validated_local_drafts(state, files) {
        Err(error) =>
          {
            ..state,
            error_message: Some(local_draft_error(state.locale, error)),
          }
        Ok(files) =>
          { ..draft_input_changed(state), files, error_message: None, }
      }
    }
    _ => state
  }
}

///|
fn draft_management_view(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage]?,
) -> @rabbita.Html {
  let locale = state.locale
  @html.section(class="draft-management", [
    @html.div(class="draft-actions", [
      @html.button(
        type_="button",
        disabled=state.draft_edit is Some(_),
        on_click=command(emit, NewDraft),
        @i18n.copy(locale, "New draft", "新建草稿"),
      ),
      @html.button(
        type_="button",
        disabled=state.draft_edit is Some(_) || active_file(state) is None,
        on_click=command(emit, DuplicateDraft),
        @i18n.copy(locale, "Duplicate", "复制"),
      ),
      @html.button(
        type_="button",
        disabled=state.draft_edit is Some(_) || active_file(state) is None,
        on_click=command(emit, RenameDraft),
        @i18n.copy(locale, "Rename", "重命名"),
      ),
    ]),
    match state.draft_edit {
      None => @html.nothing
      Some(edit) =>
        @html.div(class="draft-form", [
          @html.h3(
            match edit.operation {
              Create =>
                @i18n.copy(
                  locale, "Create an empty draft", "新建空白草稿",
                )
              Duplicate(_) =>
                @i18n.copy(
                  locale, "Duplicate selected draft", "复制选中的草稿",
                )
              Rename(_) =>
                @i18n.copy(
                  locale, "Rename selected draft", "重命名选中的草稿",
                )
            },
          ),
          @html.label(
            for_="draft-name",
            @i18n.copy(locale, "Draft name", "草稿名称"),
          ),
          @html.input(
            id="draft-name",
            value=edit.name,
            on_input=text_command(emit, value => DraftNameChanged(value)),
          ),
          if edit.operation == Create {
            @html.div([
              @html.label(
                for_="draft-language",
                @i18n.copy(locale, "Draft language", "草稿语言"),
              ),
              @html.input(
                id="draft-language",
                value=edit.language,
                on_input=text_command(emit, value => DraftLanguageChanged(value)),
              ),
            ])
          } else {
            @html.p(edit.language)
          },
          @html.p(
            class="privacy-copy",
            @i18n.copy(
              locale, "Names are browser labels only. Up to 64 drafts, name 512 and language 64 characters. Save opens the draft; Cancel keeps current files and selection.",
              "名称仅为浏览器标签。最多 64 个草稿，名称 512、语言 64 字符。保存后打开草稿；取消将保留当前文件和选择。",
            ),
          ),
          match edit.error {
            None => @html.nothing
            Some(error) =>
              @html.p(
                class="error-state",
                attrs=@html.Attrs::build().role("alert"),
                error,
              )
          },
          @html.div(class="draft-actions", [
            @html.button(
              type_="button",
              on_click=command(emit, SaveDraft),
              @i18n.copy(locale, "Save draft", "保存草稿"),
            ),
            @html.button(
              type_="button",
              on_click=command(emit, CancelDraftEdit),
              @i18n.copy(locale, "Cancel", "取消"),
            ),
          ]),
        ])
    },
  ])
}
