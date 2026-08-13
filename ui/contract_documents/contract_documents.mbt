///|
pub(all) enum ContractDocumentConfirmation {
  ConfirmInformation(String, Int64)
  RequestGeneration(String, Int64, String)
} derive(Debug, Eq)

///|
pub(all) struct ContractDocumentsState {
  locale : @i18n.Locale
  actor_owner : @contractdoc.ContractFieldOwner
  manifest : @contractdoc.ContractTemplateManifest?
  packets : Array[@contractdoc.ContractPacket]
  selected_packet_id : String?
  selected_form : @contractdoc.ContractFormKind?
  preview : @contractdoc.ContractPreviewDocument?
  preview_loading : Bool
  draft_values : Array[@contractdoc.ContractFieldValue]
  confirmation : ContractDocumentConfirmation?
  loading : Bool
  success_message : String?
  error_message : String?
} derive(Eq)

///|
pub(all) enum ContractDocumentsMessage {
  SelectPacket(String)
  SelectForm(@contractdoc.ContractFormKind)
  RequestPreview(
    String,
    Int64,
    @contractdoc.ContractFormKind,
    Array[@contractdoc.ContractFieldValue]
  )
  PreviewLoaded(@contractdoc.ContractPreviewDocument)
  PreviewFailed(String)
  FieldChanged(String, String)
  SaveInformation(String, Int64, Array[@contractdoc.ContractFieldValue])
  BeginConfirmInformation(String, Int64)
  BeginRequestGeneration(String, Int64, String)
  DismissConfirmation
  ConfirmAction(ContractDocumentConfirmation)
  Refresh
  ClearNotice
} derive(Eq)

///|
fn copy(locale : @i18n.Locale, en : String, zh : String) -> String {
  if locale.is_chinese() {
    zh
  } else {
    en
  }
}

///|
pub fn default_state(
  locale : @i18n.Locale,
  actor_owner? : @contractdoc.ContractFieldOwner = CustomerMessenger,
) -> ContractDocumentsState {
  {
    locale,
    actor_owner,
    manifest: None,
    packets: [],
    selected_packet_id: None,
    selected_form: None,
    preview: None,
    preview_loading: false,
    draft_values: [],
    confirmation: None,
    loading: false,
    success_message: None,
    error_message: None,
  }
}

///|
fn draft_value(
  values : Array[@contractdoc.ContractFieldValue],
  field_id : String,
) -> String {
  match values.search_by(item => item.field_id == field_id) {
    Some(index) => values[index].value
    None => ""
  }
}

///|
fn upsert_value(
  values : Array[@contractdoc.ContractFieldValue],
  field_id : String,
  value : String,
) -> Array[@contractdoc.ContractFieldValue] {
  let updated = values.copy()
  match updated.search_by(item => item.field_id == field_id) {
    Some(index) => updated[index] = { field_id, value }
    None => updated.push({ field_id, value })
  }
  updated.sort_by((left, right) => left.field_id.compare(right.field_id))
  updated
}

///|
fn find_packet(
  packets : Array[@contractdoc.ContractPacket],
  packet_id : String,
) -> @contractdoc.ContractPacket? {
  match packets.search_by(item => item.packet_id == packet_id) {
    Some(index) => packets.get(index)
    None => None
  }
}

///|
fn find_form(
  forms : Array[@contractdoc.ContractFormDefinition],
  kind : @contractdoc.ContractFormKind,
) -> @contractdoc.ContractFormDefinition? {
  match forms.search_by(item => item.form == kind) {
    Some(index) => forms.get(index)
    None => None
  }
}

///|
pub fn ContractDocumentsState::update(
  self : ContractDocumentsState,
  message : ContractDocumentsMessage,
) -> ContractDocumentsState {
  match message {
    SelectPacket(packet_id) => {
      let packet = find_packet(self.packets, packet_id)
      {
        ..self,
        selected_packet_id: Some(packet_id),
        selected_form: match packet {
          Some(item) => item.active_forms.get(0)
          None => None
        },
        draft_values: match packet {
          Some(item) => item.values.copy()
          None => []
        },
        preview: None,
        preview_loading: false,
        confirmation: None,
      }
    }
    SelectForm(form) => { ..self, selected_form: Some(form), preview: None }
    RequestPreview(_, _, _, _) =>
      { ..self, preview_loading: true, error_message: None }
    PreviewLoaded(preview) =>
      {
        ..self,
        preview: Some(preview),
        preview_loading: false,
        error_message: None,
      }
    PreviewFailed(message) =>
      { ..self, preview_loading: false, error_message: Some(message) }
    FieldChanged(field_id, value) =>
      {
        ..self,
        draft_values: upsert_value(self.draft_values, field_id, value),
        preview: None,
        success_message: None,
        error_message: None,
      }
    SaveInformation(_, _, _) =>
      { ..self, loading: true, success_message: None, error_message: None }
    BeginConfirmInformation(packet_id, revision) =>
      { ..self, confirmation: Some(ConfirmInformation(packet_id, revision)) }
    BeginRequestGeneration(packet_id, revision, digest) =>
      {
        ..self,
        confirmation: Some(RequestGeneration(packet_id, revision, digest)),
      }
    DismissConfirmation => { ..self, confirmation: None }
    ConfirmAction(_) =>
      {
        ..self,
        confirmation: None,
        loading: true,
        success_message: None,
        error_message: None,
      }
    Refresh => { ..self, loading: true, error_message: None }
    ClearNotice => { ..self, success_message: None, error_message: None }
  }
}

///|
fn command(
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  message : ContractDocumentsMessage,
) -> @rabbita.Cmd {
  match emit {
    Some(send) => send(message)
    None => @rabbita.none
  }
}

///|
fn text_command(
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  wrap : (String) -> ContractDocumentsMessage,
) -> @rabbita.Emit[String] {
  match emit {
    Some(send) => send.map(wrap)
    None => Emit(_ => @rabbita.none)
  }
}

///|
fn state_label(
  locale : @i18n.Locale,
  state : @contractdoc.ContractPacketState,
) -> String {
  match state {
    InformationDraft => copy(locale, "Information draft", "资料填写中")
    ReadyForConfirmation => copy(locale, "Ready to review", "待确认")
    InformationConfirmed =>
      copy(locale, "Information confirmed", "资料已确认")
    GenerationRequested =>
      copy(locale, "Generating exact documents", "正在生成原格式文件")
    Generated =>
      copy(locale, "DOCX and PDF generated", "DOCX 与 PDF 已生成")
    Superseded => copy(locale, "Superseded", "已替代")
  }
}

///|
fn form_title(
  locale : @i18n.Locale,
  form : @contractdoc.ContractFormDefinition,
) -> String {
  if locale.is_chinese() {
    form.title_zh_cn
  } else {
    form.title_en
  }
}

///|
fn field_label(
  locale : @i18n.Locale,
  field : @contractdoc.ContractFieldDefinition,
) -> String {
  if locale.is_chinese() {
    field.label_zh_cn
  } else {
    field.label_en
  }
}

///|
fn preview_font_stack(font : String) -> String {
  if font.contains("黑体") || font.contains("Hei") {
    "'\{font}','Heiti SC','STHeiti','Noto Sans CJK SC','Source Han Sans SC',sans-serif"
  } else if font.contains("仿宋") || font.contains("FangSong") {
    "'\{font}','FangSong','STFangsong','Songti SC','STSong','Noto Serif CJK SC','Source Han Serif SC',serif"
  } else {
    "'\{font}','Songti SC','STSong','Noto Serif CJK SC','Source Han Serif SC',serif"
  }
}

///|
/// Scale a source DOCX half-point measurement against its 595.25pt page.
fn half_points_cqw(value : Int) -> String {
  "\{value.to_double() * 1000.0 / 11905.0}cqw"
}

///| Scale source twips against the physical page width. Using container query

///| units keeps typography, spacing and indents proportional in a narrow

///|
/// side-by-side preview instead of clipping an unscaled desktop page.
fn twips_cqw(value : Int) -> String {
  "\{value.to_double() * 100.0 / 11905.0}cqw"
}

///|
fn preview_runs(runs : Array[@contractdoc.ContractPreviewRun]) -> @rabbita.Html {
  @html.span(
    [
      for run in runs => {
        let classes = [
            if run.bold {
              "is-bold"
            } else {
              ""
            },
            if run.italic {
              "is-italic"
            } else {
              ""
            },
            if run.underline {
              "is-underline"
            } else {
              ""
            },
          ]
          .filter(value => value != "")
          .join(" ")
        let attrs = @html.Attrs::build()
        match run.font_size_half_points {
          Some(size) => ignore(attrs.style("font-size", half_points_cqw(size)))
          None => ()
        }
        match run.color {
          Some(color) if color.length() == 6 =>
            ignore(attrs.style("color", "#\{color}"))
          _ => ()
        }
        match run.font_east_asia {
          Some(font) if font.trim() != "" =>
            ignore(attrs.style("font-family", preview_font_stack(font)))
          _ => ()
        }
        @html.span(class=classes, attrs~, run.text)
      }
    ],
  )
}

///|
fn preview_block(block : @contractdoc.ContractPreviewBlock) -> @rabbita.Html {
  let attrs = @html.Attrs::build()
  match block.alignment {
    Some("center") => ignore(attrs.style("text-align", "center"))
    Some("right") | Some("end") => ignore(attrs.style("text-align", "right"))
    Some("both") | Some("distribute") =>
      ignore(attrs.style("text-align", "justify"))
    _ => ()
  }
  match block.spacing_before_twips {
    Some(value) => ignore(attrs.style("margin-top", twips_cqw(value)))
    None => ()
  }
  match block.spacing_after_twips {
    Some(value) => ignore(attrs.style("margin-bottom", twips_cqw(value)))
    None => ()
  }
  match block.line_twips {
    Some(value) if value > 0 =>
      ignore(attrs.style("line-height", twips_cqw(value)))
    _ => ()
  }
  match block.left_indent_twips {
    Some(value) => ignore(attrs.style("margin-left", twips_cqw(value)))
    None => ()
  }
  match block.right_indent_twips {
    Some(value) => ignore(attrs.style("margin-right", twips_cqw(value)))
    None => ()
  }
  match block.first_line_twips {
    Some(value) => ignore(attrs.style("text-indent", twips_cqw(value)))
    None => ()
  }
  match block.kind {
    "table" => {
      let total = block.grid_widths_twips.fold(init=0, (sum, value) => {
        sum + value
      })
      @html.table(class="moonleaf-table", attrs~, [
        if total > 0 {
          @html.colgroup(
            [
              for width in block.grid_widths_twips => {
                let column = @html.Attrs::build()
                ignore(
                  column.style(
                    "width",
                    "\{width.to_double() * 100.0 / total.to_double()}%",
                  ),
                )
                @html.col(attrs=column)
              }
            ],
          )
        } else {
          @html.nothing
        },
        @html.tbody(
          [
            for row in block.rows => {
              @html.tr([ for cell in row => @html.td(cell) ])
            }
          ],
        ),
      ])
    }
    "heading" =>
      @html.div(class="moonleaf-heading", attrs~, preview_runs(block.runs))
    "list-item" =>
      @html.div(class="moonleaf-list-item", attrs~, [
        @html.span(if block.ordered { "1." } else { "•" }),
        preview_runs(block.runs),
      ])
    _ => @html.p(class="moonleaf-paragraph", attrs~, preview_runs(block.runs))
  }
}

///|
fn preview_panel(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  manifest : @contractdoc.ContractTemplateManifest,
  packet : @contractdoc.ContractPacket,
  form : @contractdoc.ContractFormDefinition?,
) -> @rabbita.Html {
  let active_form = form.map(item => item.form)
  @html.aside(class="contract-preview", [
    @html.div(class="contract-preview-heading", [
      @html.div([
        @html.p(class="eyebrow", "MOONLEAF LIVE PREVIEW"),
        @html.h2(
          copy(state.locale, "What will be generated", "将要生成的文件"),
        ),
      ]),
      @html.span(
        class="contract-preview-revision",
        "MoonLeaf · r\{packet.revision}",
      ),
    ]),
    @html.div(class="contract-preview-toolbar", [
      @html.button(
        type_="button",
        class="primary-button",
        disabled=state.preview_loading || active_form is None,
        on_click=match active_form {
          Some(kind) =>
            command(
              emit,
              RequestPreview(
                packet.packet_id,
                packet.revision,
                kind,
                editable_draft_values(state, manifest),
              ),
            )
          None => @rabbita.none
        },
        if state.preview_loading {
          copy(state.locale, "Rendering…", "渲染中…")
        } else {
          copy(state.locale, "Render current draft", "渲染当前草稿")
        },
      ),
      match state.preview {
        Some(preview) if active_form == Some(preview.form) =>
          @html.span(
            class="contract-page-count",
            copy(
              state.locale,
              "\{preview.pages.length()} physical pages",
              "\{preview.pages.length()} 个物理页面",
            ),
          )
        _ => @html.nothing
      },
    ]),
    @html.div(class="contract-paper-stage", [
      @html.div(class="contract-paper-viewport", [
        match state.preview {
          Some(preview) if active_form == Some(preview.form) => {
            let pages = preview.pages
            @html.div(
              class="moonleaf-pages",
              [
                for index, page in pages => {
                  let paper = @html.Attrs::build().aria_label(
                    copy(
                      state.locale,
                      "Contract page \{index + 1} of \{pages.length()}",
                      "合同第 \{index + 1} 页，共 \{pages.length()} 页",
                    ),
                  )
                  ignore(paper.style("aspect-ratio", "11905 / 16840"))
                  @html.article(
                    class="contract-paper moonleaf-document",
                    attrs=paper,
                    [
                      for block in page => preview_block(block)
                    ],
                  )
                }
              ],
            )
          }
          _ =>
            @html.div(class="contract-paper moonleaf-empty", [
              @html.strong(
                copy(
                  state.locale,
                  "Render the role-scoped draft with MoonLeaf",
                  "使用 MoonLeaf 渲染当前角色草稿",
                ),
              ),
              @html.p(
                copy(
                  state.locale,
                  "The preview is created from the authoritative DOCX. No screenshot or alternate template is used.",
                  "预览直接从权威 DOCX 生成，不使用截图或另一份模板。",
                ),
              ),
            ])
        },
      ]),
    ]),
    @html.p(
      class="contract-preview-note",
      copy(
        state.locale,
        "MoonLeaf lays out this preview from the generated DOCX using its physical paginator. Final PDF release still requires matching MoonLeaf render evidence.",
        "MoonLeaf 使用物理分页器从生成后的 DOCX 排版此预览；最终 PDF 发布仍需匹配的 MoonLeaf 渲染证据。",
      ),
    ),
  ])
}

///|
fn editable_draft_values(
  state : ContractDocumentsState,
  manifest : @contractdoc.ContractTemplateManifest,
) -> Array[@contractdoc.ContractFieldValue] {
  state.draft_values.filter(item => {
    manifest
    .field(item.field_id)
    .map_or(false, field => field.owner.can_edit(state.actor_owner))
  })
}

///|
fn input_for(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  field : @contractdoc.ContractFieldDefinition,
) -> @rabbita.Html {
  let id = "contract-field-\{field.field_id}"
  let value = draft_value(state.draft_values, field.field_id)
  if field.collection_policy == CompleteOffline {
    return @html.div(class="contract-offline-field", [
      @html.strong(field_label(state.locale, field)),
      @html.p(
        copy(
          state.locale,
          "Complete this item only on the printed or approved signing copy. It is never collected online.",
          "此项仅在线下打印件或获批签署件中填写，系统不在线收集。",
        ),
      ),
    ])
  }
  let control = if field.allowed_values.length() > 0 {
    let options = [
      @html.option(
        value="",
        selected=value == "",
        copy(state.locale, "Select one", "请选择"),
      ),
    ]
    for option in field.allowed_values {
      options.push(@html.option(value=option, selected=value == option, option))
    }
    @html.select(
      id~,
      on_change=text_command(emit, next => FieldChanged(field.field_id, next)),
      options,
    )
  } else if field.kind == MultilineText {
    @html.textarea(
      id~,
      maxlength=field.maximum_characters,
      value~,
      on_input=text_command(emit, next => FieldChanged(field.field_id, next)),
      "",
    )
  } else {
    @html.input(
      id~,
      value~,
      maxlength=field.maximum_characters,
      on_input=text_command(emit, next => FieldChanged(field.field_id, next)),
    )
  }
  @html.div(class="contract-field", [
    @html.label(for_=id, [
      @html.span(field_label(state.locale, field)),
      if field.required {
        @html.small(copy(state.locale, "Required", "必填"))
      } else {
        @html.small(copy(state.locale, "Optional", "选填"))
      },
    ]),
    control,
  ])
}

///|
fn visible_to_actor(
  actor : @contractdoc.ContractFieldOwner,
  field : @contractdoc.ContractFieldDefinition,
) -> Bool {
  field.owner.can_edit(actor)
}

///|
fn role_missing_count(
  manifest : @contractdoc.ContractTemplateManifest,
  form : @contractdoc.ContractFormDefinition,
  values : Array[@contractdoc.ContractFieldValue],
  actor : @contractdoc.ContractFieldOwner,
) -> Int {
  let mut missing = 0
  for field_id in form.field_ids {
    match manifest.field(field_id) {
      Some(field) if visible_to_actor(actor, field) &&
        field.required &&
        draft_value(values, field_id).trim() == "" => missing += 1
      _ => ()
    }
  }
  missing
}

///|
fn form_has_actor_fields(
  manifest : @contractdoc.ContractTemplateManifest,
  form : @contractdoc.ContractFormDefinition,
  actor : @contractdoc.ContractFieldOwner,
) -> Bool {
  form.field_ids.any(field_id => {
    manifest
    .field(field_id)
    .map_or(false, field => visible_to_actor(actor, field))
  })
}

///|
fn packet_editor(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  manifest : @contractdoc.ContractTemplateManifest,
  packet : @contractdoc.ContractPacket,
) -> @rabbita.Html {
  let active_form = match state.selected_form {
    Some(value) => Some(value)
    None => packet.active_forms.get(0)
  }
  let form = match active_form {
    Some(kind) => find_form(manifest.forms, kind)
    None => None
  }
  let editable = packet.state == InformationDraft ||
    packet.state == ReadyForConfirmation ||
    packet.state == InformationConfirmed
  let actor_title = if state.actor_owner == CustomerMessenger {
    copy(state.locale, "Your customer information", "填写乙方资料")
  } else {
    copy(
      state.locale,
      "Your operator information",
      "填写甲方及运营资料",
    )
  }
  @html.section(class="contract-workspace", [
    @html.div(class="contract-progress", [
      @html.strong(state_label(state.locale, packet.state)),
      @html.span(
        copy(
          state.locale,
          "Source packet: 7 forms · 18 pages",
          "源合同包：7 份表单 · 18 页",
        ),
      ),
      @html.span("Revision \{packet.revision}"),
    ]),
    @html.div(class="contract-editor-layout", [
      @html.nav(
        class="contract-form-nav",
        attrs=@html.Attrs::build().aria_label(
          copy(state.locale, "Contract forms", "合同表单"),
        ),
        [
          for definition in manifest.forms if packet.active_forms.contains(
            definition.form,
          ) &&
          form_has_actor_fields(manifest, definition, state.actor_owner) => {
            let count = role_missing_count(
              manifest,
              definition,
              state.draft_values,
              state.actor_owner,
            )
            @html.button(
              type_="button",
              class=if active_form == Some(definition.form) {
                "contract-form-tab is-active"
              } else {
                "contract-form-tab"
              },
              on_click=command(emit, SelectForm(definition.form)),
              [
                @html.span(form_title(state.locale, definition)),
                @html.small(
                  if count == 0 {
                    copy(state.locale, "Complete", "已完成")
                  } else {
                    copy(
                      state.locale,
                      "\{count} required",
                      "\{count} 项必填",
                    )
                  },
                ),
              ],
            )
          }
        ],
      ),
      @html.div(class="contract-form-panel", [
        match form {
          Some(definition) =>
            @html.div([
              @html.div(class="contract-form-heading", [
                @html.p(class="eyebrow", actor_title),
                @html.h2(form_title(state.locale, definition)),
                @html.p(
                  copy(
                    state.locale,
                    "Only the fields assigned to your side are shown. Labels and choices come directly from the supplied contract.",
                    "这里只显示由您这一方填写的字段；标签与选项均直接来自所提供合同。",
                  ),
                ),
              ]),
              {
                let fields : Array[@rabbita.Html] = []
                for field_id in definition.field_ids {
                  match manifest.field(field_id) {
                    Some(field) if visible_to_actor(state.actor_owner, field) =>
                      fields.push(input_for(state, emit, field))
                    None => ()
                    _ => ()
                  }
                }
                @html.div(class="contract-field-grid", fields)
              },
            ])
          None =>
            @html.div(
              class="empty-state",
              copy(state.locale, "Select a form.", "请选择表单。"),
            )
        },
        @html.div(class="contract-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            disabled=!editable || state.loading,
            on_click=command(
              emit,
              SaveInformation(
                packet.packet_id,
                packet.revision,
                editable_draft_values(state, manifest),
              ),
            ),
            copy(state.locale, "Save information", "保存资料"),
          ),
          if packet.state == ReadyForConfirmation {
            @html.button(
              type_="button",
              class="primary-button",
              disabled=state.loading,
              on_click=command(
                emit,
                BeginConfirmInformation(packet.packet_id, packet.revision),
              ),
              copy(state.locale, "Review and confirm", "审阅并确认"),
            )
          } else if packet.state == InformationConfirmed &&
            packet.values_sha256 is Some(digest) {
            @html.button(
              type_="button",
              class="primary-button",
              disabled=state.loading,
              on_click=command(
                emit,
                BeginRequestGeneration(
                  packet.packet_id,
                  packet.revision,
                  digest,
                ),
              ),
              copy(
                state.locale,
                "Generate exact DOCX + PDF",
                "生成原格式 DOCX + PDF",
              ),
            )
          } else {
            @html.span("")
          },
        ]),
      ]),
      preview_panel(state, emit, manifest, packet, form),
    ]),
  ])
}

///|
fn confirmation(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
) -> @rabbita.Html {
  match state.confirmation {
    None => @html.span("")
    Some(action) => {
      let generating = action is RequestGeneration(_, _, _)
      @html.div(class="modal-backdrop", [
        @html.section(
          class="confirmation-dialog",
          attrs=@html.Attrs::build().role("alertdialog").aria_modal("true"),
          [
            @html.h2(
              if generating {
                copy(
                  state.locale,
                  "Generate from the confirmed values?",
                  "按已确认资料生成文件？",
                )
              } else {
                copy(
                  state.locale,
                  "Confirm the information is exact?",
                  "确认资料准确无误？",
                )
              },
            ),
            @html.p(
              if generating {
                copy(
                  state.locale,
                  "The generator may only replace declared blanks. It must preserve the supplied wording, layout, pagination, headers, footers, tables, and styles; otherwise the job fails.",
                  "生成器仅可替换已声明的空白项；必须保留源文件的文字、布局、分页、页眉页脚、表格与样式，否则任务失败。",
                )
              } else {
                copy(
                  state.locale,
                  "Names, dates, amounts, and Chinese uppercase amounts are recorded exactly as entered. The system does not infer or correct them.",
                  "姓名、日期、金额及金额大写将按输入原样记录；系统不会推断或更正。",
                )
              },
            ),
            @html.div(class="dialog-actions", [
              @html.button(
                type_="button",
                class="quiet-button",
                on_click=command(emit, DismissConfirmation),
                copy(state.locale, "Go back", "返回检查"),
              ),
              @html.button(
                type_="button",
                class="primary-button",
                on_click=command(emit, ConfirmAction(action)),
                if generating {
                  copy(state.locale, "Request generation", "申请生成")
                } else {
                  copy(state.locale, "Confirm information", "确认资料")
                },
              ),
            ]),
          ],
        ),
      ])
    }
  }
}

///|
fn contract_documents_view(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
) -> @rabbita.Html {
  let selected = match state.selected_packet_id {
    Some(packet_id) => find_packet(state.packets, packet_id)
    None => state.packets.get(0)
  }
  @html.div(class="contract-documents", [
    @html.style_tag(contract_styles()),
    @html.header(class="contract-documents-header", [
      @html.div([
        @html.p(
          class="eyebrow",
          copy(
            state.locale,
            "EXACT SOURCE CONTRACT",
            "源合同原格式生成",
          ),
        ),
        @html.h1(
          copy(
            state.locale,
            "Contract information and documents",
            "合同资料与文件",
          ),
        ),
        @html.p(
          copy(
            state.locale,
            "Complete only the blanks found in the supplied youth-policy contract packet. Signatures and seals remain offline.",
            "仅填写青年政策合同包中已有的空白项；签字与盖章仍在线下完成。",
          ),
        ),
      ]),
      @html.button(
        type_="button",
        class="quiet-button",
        disabled=state.loading,
        on_click=command(emit, Refresh),
        copy(state.locale, "Refresh", "刷新"),
      ),
    ]),
    match (state.manifest, selected) {
      (Some(manifest), Some(packet)) =>
        packet_editor(state, emit, manifest, packet)
      (None, _) =>
        @html.div(class="empty-state", [
          @html.h2(
            copy(
              state.locale,
              "Contract template unavailable",
              "合同模板不可用",
            ),
          ),
          @html.p(
            copy(
              state.locale,
              "The verified template manifest must load before information can be collected.",
              "必须先加载已验证的模板清单，才能收集资料。",
            ),
          ),
        ])
      (_, None) =>
        @html.div(class="empty-state", [
          @html.h2(
            copy(
              state.locale,
              "No contract packet yet",
              "暂无合同资料包",
            ),
          ),
          @html.p(
            copy(
              state.locale,
              "A packet is created from an approved order; no blank or invented contract is generated.",
              "合同资料包由已批准订单创建；系统不会生成空白或虚构合同。",
            ),
          ),
        ])
    },
    match state.error_message {
      Some(value) =>
        @html.div(
          class="notice error",
          attrs=@html.Attrs::build().role("alert"),
          value,
        )
      None => @html.span("")
    },
    match state.success_message {
      Some(value) =>
        @html.div(
          class="notice success",
          attrs=@html.Attrs::build().role("status"),
          value,
        )
      None => @html.span("")
    },
    confirmation(state, emit),
  ])
}

///|
fn contract_styles() -> String {
  (
    #|.contract-editor-layout{display:grid;grid-template-columns:minmax(10rem,.18fr) minmax(18rem,.58fr) minmax(30rem,1fr)!important}.contract-form-nav{min-width:0;padding:.8rem;border-right:1px solid var(--line,#223743);display:grid;align-content:start;gap:.4rem}.contract-form-tab{min-height:3.2rem;padding:.6rem .75rem;border:1px solid transparent;border-radius:.5rem;background:transparent;color:inherit;font:inherit;text-align:left;display:flex;flex-direction:column;cursor:pointer}.contract-form-tab small{color:var(--muted,#91a7ad)}.contract-form-tab.is-active{border-color:rgba(126,224,189,.35);background:rgba(126,224,189,.08)}.contract-form-panel{min-width:0;padding:1.25rem}.contract-form-heading h2{margin:.15rem 0}.contract-form-heading p:last-child{color:var(--muted,#91a7ad)}.contract-field-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.9rem;margin:1.2rem 0}.contract-field label{display:flex;justify-content:space-between;gap:.5rem;margin-bottom:.35rem;font-weight:750}.contract-field label small{color:var(--muted,#91a7ad);font-weight:500}.contract-field input,.contract-field select,.contract-field textarea{width:100%;min-height:44px;padding:.65rem .75rem;border:1px solid #35505f;border-radius:.5rem;background:#09151c;color:#ecf5f2;font:inherit}.contract-field textarea{min-height:7rem;resize:vertical}.contract-actions{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:.65rem;padding-top:1rem;border-top:1px solid var(--line,#223743)}.contract-preview{min-width:0;padding:1.25rem;border-left:1px solid var(--line,#223743);background:var(--panel2,#111f29);color:var(--ink,#ecf5f2)}.contract-preview-heading,.contract-preview-toolbar{display:flex;justify-content:space-between;align-items:center;gap:.75rem;flex-wrap:wrap}.contract-preview-heading h2{margin:.1rem 0}.contract-preview-revision,.contract-page-count{color:var(--muted,#91a7ad);font-family:ui-monospace,SFMono-Regular,Menlo,monospace}.contract-preview-toolbar{margin:.8rem 0}.contract-paper-stage{display:grid;grid-template-columns:minmax(0,1fr);gap:.75rem}.contract-paper-viewport{height:min(76vh,64rem);padding:1rem;overflow:auto;border:1px solid var(--line,#223743);border-radius:.55rem;background:#273138}.moonleaf-pages{display:grid;gap:1.5rem}.contract-paper{container-type:inline-size;display:block;box-sizing:border-box;width:100%;min-height:0;padding:12.1%;overflow:hidden;background:white;color:#111;box-shadow:0 .8rem 2rem rgba(0,0,0,.35);font-family:"Songti SC","STSong","Noto Serif CJK SC","Source Han Serif SC",serif;font-size:0;line-height:normal}.moonleaf-document{overflow-wrap:anywhere}.moonleaf-paragraph,.moonleaf-heading,.moonleaf-list-item{font-size:2.688cqw;line-height:4.704cqw}.moonleaf-paragraph{min-height:0;margin:0;text-indent:0}.moonleaf-heading{margin:0;text-align:center;font-weight:700}.moonleaf-list-item{display:flex;gap:.5rem;margin:0}.moonleaf-table{width:100%;margin:0;border-collapse:collapse;table-layout:fixed;font-size:2.15cqw;line-height:3.25cqw}.moonleaf-table td{padding:.2cqw .3cqw;border:1px solid #555;vertical-align:top;white-space:pre-wrap;overflow-wrap:anywhere}.is-bold{font-weight:700}.is-italic{font-style:italic}.is-underline{text-decoration:underline}.moonleaf-empty{display:grid;place-content:center;gap:.5rem;text-align:center;color:#3c4850}.moonleaf-empty p{max-width:34rem}.contract-preview-note{color:var(--muted,#91a7ad);font-size:.72rem}@media(max-width:78rem){.contract-editor-layout{grid-template-columns:12rem minmax(0,1fr)!important}.contract-preview{grid-column:1/-1;border-left:0;border-top:1px solid var(--line,#223743)}.contract-paper{max-width:52rem;margin:0 auto}}@media(max-width:52rem){.contract-editor-layout{grid-template-columns:1fr!important}.contract-form-nav{border-right:0;border-bottom:1px solid var(--line,#223743)}.contract-field-grid{grid-template-columns:1fr}.contract-preview-heading{align-items:flex-start;flex-direction:column}.contract-preview-toolbar{position:sticky;top:0;z-index:2;padding:.5rem;background:var(--panel2,#111f29)}.contract-paper-viewport{height:auto;max-height:45rem;padding:.5rem}}
  )
}

///|
pub fn view(state : ContractDocumentsState) -> @rabbita.Html {
  contract_documents_view(state, None)
}

///|
pub fn interactive_view(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage],
) -> @rabbita.Html {
  contract_documents_view(state, Some(emit))
}

///|
#warnings("-alert_unstable")
pub fn render(state : ContractDocumentsState) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(view(state)))
}
