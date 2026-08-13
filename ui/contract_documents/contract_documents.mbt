///|
pub(all) enum ContractDocumentConfirmation {
  ConfirmInformation(String, Int64)
  RequestGeneration(String, Int64, String)
} derive(Debug, Eq)

///|
pub(all) struct ContractDocumentsState {
  locale : @i18n.Locale
  manifest : @contractdoc.ContractTemplateManifest?
  packets : Array[@contractdoc.ContractPacket]
  selected_packet_id : String?
  selected_form : @contractdoc.ContractFormKind?
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
pub fn default_state(locale : @i18n.Locale) -> ContractDocumentsState {
  {
    locale,
    manifest: None,
    packets: [],
    selected_packet_id: None,
    selected_form: None,
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
        confirmation: None,
      }
    }
    SelectForm(form) => { ..self, selected_form: Some(form) }
    FieldChanged(field_id, value) =>
      {
        ..self,
        draft_values: upsert_value(self.draft_values, field_id, value),
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
fn missing_count(
  manifest : @contractdoc.ContractTemplateManifest,
  form : @contractdoc.ContractFormDefinition,
  values : Array[@contractdoc.ContractFieldValue],
) -> Int {
  let mut missing = 0
  for field_id in form.field_ids {
    match manifest.field(field_id) {
      Some(field) if field.required &&
        draft_value(values, field_id).trim() == "" => missing += 1
      _ => ()
    }
  }
  missing
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
  @html.section(class="contract-workspace", [
    @html.div(class="contract-progress", [
      @html.strong(state_label(state.locale, packet.state)),
      @html.span(
        copy(
          state.locale,
          "Source packet: 7 forms · 14 pages",
          "源合同包：7 份表单 · 14 页",
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
          ) => {
            let count = missing_count(manifest, definition, state.draft_values)
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
                @html.p(
                  class="eyebrow",
                  copy(state.locale, "SOURCE FORM", "源文件表单"),
                ),
                @html.h2(form_title(state.locale, definition)),
                @html.p(
                  copy(
                    state.locale,
                    "Labels and choices below come directly from the supplied contract. The system does not add legal wording or calculate missing amounts.",
                    "以下字段与选项均直接来自所提供合同。系统不会增加法律条款，也不会代填或推算金额。",
                  ),
                ),
              ]),
              {
                let fields : Array[@rabbita.Html] = []
                for field_id in definition.field_ids {
                  match manifest.field(field_id) {
                    Some(field) => fields.push(input_for(state, emit, field))
                    None => ()
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
                state.draft_values.copy(),
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
