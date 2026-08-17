///|
pub(all) enum ContractDocumentConfirmation {
  ConfirmInformation(String, Int64)
  RequestGeneration(String, Int64, String)
  RegisterExecution(String, Int64, String, String)
  ClosePacket(String, Int64, @contractdoc.ContractClosureKind, String)
  SupersedePacket(String, Int64, String, String)
  RequestRenewal(String)
  RejectApproval(String, String)
} derive(Debug, Eq)

///|
/// The actions a packet offers to a given role in its current state. The
/// action bar renders exactly this list, so both browser surfaces stay
/// consistent with the lifecycle rules by construction.
pub(all) enum ContractPacketCapability {
  SaveInformation
  ConfirmInformation
  RequestGeneration
  RetryGeneration
  RegisterExecution
  ClosePacket
  SupersedePacket
  RequestRenewal
} derive(Debug, Eq)

///|
pub fn contract_packet_capabilities(
  packet : @contractdoc.ContractPacket,
  actor_owner : @contractdoc.ContractFieldOwner,
) -> Array[ContractPacketCapability] {
  let capabilities : Array[ContractPacketCapability] = []
  let editable = packet.state == InformationDraft ||
    packet.state == ReadyForConfirmation ||
    packet.state == InformationConfirmed
  if editable {
    capabilities.push(SaveInformation)
  }
  // Renewal is offered to both roles from an effective packet: the customer
  // initiates it in the portal, the operator prepares it in the console.
  if packet.state == Effective {
    capabilities.push(RequestRenewal)
  }
  // Confirmation and generation requests are the customer's attestation; the
  // backend exposes the matching routes only on the customer side.
  if actor_owner == CustomerMessenger {
    if packet.state == ReadyForConfirmation {
      capabilities.push(ConfirmInformation)
    }
    if packet.state == InformationConfirmed && packet.values_sha256 is Some(_) {
      capabilities.push(RequestGeneration)
    }
    if packet.state == GenerationFailed && packet.values_sha256 is Some(_) {
      capabilities.push(RetryGeneration)
    }
  }
  if actor_owner == ManagerOperator {
    if packet.state == Generated {
      capabilities.push(RegisterExecution)
    }
    if packet.state == Effective {
      capabilities.push(ClosePacket)
    }
    if packet.state != Effective &&
      packet.state != Closed &&
      packet.state != Superseded {
      capabilities.push(SupersedePacket)
    }
  }
  capabilities
}

///|
pub(all) struct ContractDocumentsState {
  locale : @i18n.Locale
  actor_owner : @contractdoc.ContractFieldOwner
  manifest : @contractdoc.ContractTemplateManifest?
  packets : Array[@contractdoc.ContractPacket]
  approvals : Array[@contractdoc.ContractApproval]
  governance_dashboard : @contractdoc.ContractGovernanceDashboard?
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
  BeginRegisterExecution(String, Int64)
  BeginClosePacket(String, Int64)
  BeginSupersedePacket(String, Int64)
  BeginRequestRenewal(String)
  ApproveApproval(String)
  BeginRejectApproval(String)
  ConfirmationInputChanged(ContractConfirmationField, String)
  DismissConfirmation
  ConfirmAction(ContractDocumentConfirmation)
  Refresh
  ClearNotice
} derive(Eq)

///|
/// The editable inputs of the operator action dialogs. Values are kept inside
/// the pending confirmation so `ConfirmAction` always carries the complete,
/// typed payload the shell needs for its HTTP call.
pub(all) enum ContractConfirmationField {
  EvidenceDigest
  SignedOn
  ClosureKind
  ClosureReason
  SuccessorReference
  SupersessionReason
  RejectionReason
} derive(Debug, Eq)

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
    approvals: [],
    governance_dashboard: None,
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
    RequestPreview(_, _, form, _) =>
      {
        ..self,
        selected_form: Some(form),
        preview_loading: true,
        error_message: None,
      }
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
    BeginRegisterExecution(packet_id, revision) =>
      {
        ..self,
        confirmation: Some(RegisterExecution(packet_id, revision, "", "")),
      }
    BeginClosePacket(packet_id, revision) =>
      {
        ..self,
        confirmation: Some(ClosePacket(packet_id, revision, Expired, "")),
      }
    BeginSupersedePacket(packet_id, revision) =>
      {
        ..self,
        confirmation: Some(SupersedePacket(packet_id, revision, "", "")),
      }
    BeginRequestRenewal(packet_id) =>
      { ..self, confirmation: Some(RequestRenewal(packet_id)) }
    ApproveApproval(_) =>
      { ..self, loading: true, success_message: None, error_message: None }
    BeginRejectApproval(approval_id) =>
      { ..self, confirmation: Some(RejectApproval(approval_id, "")) }
    ConfirmationInputChanged(field, value) =>
      {
        ..self,
        confirmation: self.confirmation.map(action => {
          match (action, field) {
            (RegisterExecution(id, revision, _, signed_on), EvidenceDigest) =>
              RegisterExecution(id, revision, value, signed_on)
            (RegisterExecution(id, revision, digest, _), SignedOn) =>
              RegisterExecution(id, revision, digest, value)
            (ClosePacket(id, revision, _, reason), ClosureKind) =>
              ClosePacket(id, revision, closure_kind_from(value), reason)
            (ClosePacket(id, revision, kind, _), ClosureReason) =>
              ClosePacket(id, revision, kind, value)
            (SupersedePacket(id, revision, _, reason), SuccessorReference) =>
              SupersedePacket(id, revision, value, reason)
            (SupersedePacket(id, revision, successor, _), SupersessionReason) =>
              SupersedePacket(id, revision, successor, value)
            (RejectApproval(id, _), RejectionReason) =>
              RejectApproval(id, value)
            (current, _) => current
          }
        }),
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
/// Build the current role-scoped preview request from the selected packet,
/// form, and draft. Browser shells use this for reactive preview scheduling.
pub fn ContractDocumentsState::preview_request(
  self : ContractDocumentsState,
) -> ContractDocumentsMessage? {
  guard self.manifest is Some(manifest) && self.selected_form is Some(form) else {
    return None
  }
  let packet = match self.selected_packet_id {
    Some(packet_id) => find_packet(self.packets, packet_id)
    None => self.packets.get(0)
  }
  match packet {
    Some(value) =>
      Some(
        RequestPreview(
          value.packet_id,
          value.revision,
          form,
          editable_draft_values(self, manifest),
        ),
      )
    None => None
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
fn closure_kind_from(value : String) -> @contractdoc.ContractClosureKind {
  match value {
    "EarlyTermination" => EarlyTermination
    "Settled" => Settled
    _ => Expired
  }
}

///|
fn closure_kinds() -> Array[@contractdoc.ContractClosureKind] {
  [Expired, EarlyTermination, Settled]
}

///|
fn closure_kind_label(
  locale : @i18n.Locale,
  kind : @contractdoc.ContractClosureKind,
) -> String {
  match kind {
    Expired => copy(locale, "Expired", "到期")
    EarlyTermination => copy(locale, "Early termination", "提前退租")
    Settled => copy(locale, "Settled", "已结算")
  }
}

///|
fn short_digest(digest : String) -> String {
  let prefix = if digest.has_prefix("sha256:") {
    digest[7:].to_owned()
  } else {
    digest
  }
  if prefix.length() > 12 {
    "\{prefix[:12]}…"
  } else {
    prefix
  }
}

///|
/// Lifecycle steps for the progress bar. Terminal states that sit outside the
/// happy path (superseded) are rendered as a badge instead of a step.
priv enum ContractStep {
  FillInformation
  ReviewConfirm
  GenerateDocuments
  SignedEffective
  ClosedArchived
} derive(Eq)

///|
fn step_index(state : @contractdoc.ContractPacketState) -> Int {
  match state {
    InformationDraft | ReadyForConfirmation => 0
    InformationConfirmed => 1
    GenerationRequested | Generated | GenerationFailed => 2
    Effective => 3
    Closed | Superseded => 4
  }
}

///|
fn step_label(locale : @i18n.Locale, step : ContractStep) -> String {
  match step {
    FillInformation => copy(locale, "Fill information", "填写资料")
    ReviewConfirm => copy(locale, "Review and confirm", "审阅确认")
    GenerateDocuments => copy(locale, "Generate documents", "生成文件")
    SignedEffective => copy(locale, "Signed and effective", "签署生效")
    ClosedArchived => copy(locale, "Closed and archived", "关闭归档")
  }
}

///|
fn step_bar(
  locale : @i18n.Locale,
  packet : @contractdoc.ContractPacket,
) -> @rabbita.Html {
  if packet.state == Superseded {
    return @html.div(class="contract-steps-terminal", [
      @html.span(
        class="contract-step-badge is-superseded",
        copy(locale, "Superseded packet", "已替代的资料包"),
      ),
      @html.span(
        copy(
          locale,
          "Replaced by \{packet.supersession.map_or("", item => item.successor_ref)}",
          "由 \{packet.supersession.map_or("", item => item.successor_ref)} 替代",
        ),
      ),
    ])
  }
  let steps = [
    FillInformation,
    ReviewConfirm,
    GenerateDocuments,
    SignedEffective,
    ClosedArchived,
  ]
  let current = step_index(packet.state)
  @html.ol(
    class="contract-steps",
    [
      for index, step in steps => {
        let tone = if packet.state == GenerationFailed &&
          step == GenerateDocuments {
          "contract-step is-failed"
        } else if index < current {
          "contract-step is-done"
        } else if index == current {
          "contract-step is-current"
        } else {
          "contract-step"
        }
        @html.li(class=tone, [
          @html.span(class="contract-step-marker", "\{index + 1}"),
          @html.span(step_label(locale, step)),
        ])
      }
    ],
  )
}

///|
/// Per-state guidance: what this state means and what happens next. Terminal
/// states surface their recorded evidence, closure, or supersession facts.
fn state_guidance(
  locale : @i18n.Locale,
  packet : @contractdoc.ContractPacket,
  actor_owner : @contractdoc.ContractFieldOwner,
) -> String {
  match packet.state {
    InformationDraft =>
      copy(
        locale, "Fill in the fields assigned to your side, then save. Nothing is generated from blank or invented values.",
        "填写贵方负责的字段并保存；系统不会用空白或虚构内容生成合同。",
      )
    ReadyForConfirmation =>
      copy(
        locale, "All required fields are complete. Review the preview against the source wording, then confirm.",
        "必填字段已齐全。请对照源合同文字审阅预览，然后确认。",
      )
    InformationConfirmed =>
      copy(
        locale, "Information is confirmed. Request generation to produce the exact DOCX and PDF pair.",
        "资料已确认。申请生成以产出原格式 DOCX 与 PDF。",
      )
    GenerationRequested =>
      copy(
        locale, "The renderer is producing the DOCX and PDF pair with a fidelity gate. No edits are accepted meanwhile.",
        "渲染器正在带保真校验地生成 DOCX 与 PDF；期间不接受修改。",
      )
    GenerationFailed =>
      copy(
        locale,
        "Generation failed: \{packet.generation_failure.unwrap_or("unknown reason")}. The confirmed values are unchanged; you can retry generation.",
        "生成失败：\{packet.generation_failure.unwrap_or("未知原因")}。已确认资料未变，可重试生成。",
      )
    Generated =>
      if actor_owner == ManagerOperator {
        copy(
          locale, "Documents are generated. After the offline signing and stamping, register the evidence digest to make the packet effective.",
          "文件已生成。线下签署盖章完成后，登记证据摘要以使合同生效。",
        )
      } else {
        copy(
          locale, "Documents are generated. Signing and stamping happen offline; the operator will register the signed evidence.",
          "文件已生成。签署盖章在线下完成，由运营方登记签署证据。",
        )
      }
    Effective => {
      let base = copy(
        locale,
        "Signed on \{packet.execution.map_or("", item => item.signed_on)}; evidence digest \{packet.execution.map_or("", item => short_digest(item.evidence_sha256))}. The packet is effective and read-only.",
        "已于 \{packet.execution.map_or("", item => item.signed_on)} 签署生效，证据摘要 \{packet.execution.map_or("", item => short_digest(item.evidence_sha256))}。资料包只读。",
      )
      let windowed = match effective_window(packet) {
        Some((start_date, end_date)) =>
          base +
          copy(
            locale,
            " Recorded effective window: \{start_date} to \{end_date}.",
            " 已记录生效租期：\{start_date} 至 \{end_date}。",
          )
        None => base
      }
      windowed +
      copy(
        locale, " Renewal is available: request it to open a draft packet that carries this information forward.",
        " 可发起续约：新建草稿资料包并带入本资料包的资料。",
      )
    }
    Closed =>
      copy(
        locale,
        "Closed (\{packet.closure.map_or("", item => closure_kind_label(locale, item.kind))}): \{packet.closure.map_or("", item => item.reason)}",
        "已关闭（\{packet.closure.map_or("", item => closure_kind_label(locale, item.kind))}）：\{packet.closure.map_or("", item => item.reason)}",
      )
    Superseded =>
      copy(
        locale,
        "Superseded by \{packet.supersession.map_or("", item => item.successor_ref)}: \{packet.supersession.map_or("", item => item.reason)}. Continue in the successor packet.",
        "已被 \{packet.supersession.map_or("", item => item.successor_ref)} 替代：\{packet.supersession.map_or("", item => item.reason)}。请在后续资料包中继续。",
      )
  }
}

///|
/// The recorded lease window of an Effective packet, read back from the
/// submitted form values. MasterLease packets record `lease.*_date`;
/// ReservationApplication packets record `reservation.*_date`. Other form
/// kinds carry no window and render nothing extra.
fn effective_window(packet : @contractdoc.ContractPacket) -> (String, String)? {
  match (packet.value("lease.start_date"), packet.value("lease.end_date")) {
    (Some(start_date), Some(end_date)) => Some((start_date, end_date))
    _ =>
      match
        (
          packet.value("reservation.start_date"),
          packet.value("reservation.end_date"),
        ) {
        (Some(start_date), Some(end_date)) => Some((start_date, end_date))
        _ => None
      }
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
    GenerationFailed =>
      copy(
        locale, "Generation failed, retry available", "生成失败，可重试",
      )
    Effective => copy(locale, "Signed and effective", "已签署生效")
    Closed => copy(locale, "Closed", "已关闭")
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
  if font.contains("方正小标宋") || font.contains("XiaoBiaoSong") {
    "'LunaNexa FZ XiaoBiaoSong','\{font}','Songti SC','STSong',serif"
  } else if font.contains("黑体") || font.contains("Hei") {
    "'LunaNexa SimHei','\{font}','Heiti SC','STHeiti','Noto Sans CJK SC','Source Han Sans SC',sans-serif"
  } else if font.contains("仿宋") || font.contains("FangSong") {
    "'LunaNexa FangSong GB2312','\{font}','FangSong','STFangsong','Songti SC','STSong','Noto Serif CJK SC','Source Han Serif SC',serif"
  } else {
    "'\{font}','Songti SC','STSong','Noto Serif CJK SC','Source Han Serif SC',serif"
  }
}

///|
/// Scale a source DOCX half-point measurement against MoonLeaf's effective
/// content box. Container query units resolve against the paper's content box,
/// not the outer physical page.
fn half_points_cqw(value : Int, content_width_twips : Int) -> String {
  "\{value.to_double() * 1000.0 / content_width_twips.to_double()}cqw"
}

///| Scale source twips against the physical page width. Using container query

///| units keeps typography, spacing and indents proportional in a narrow

///|
/// side-by-side preview instead of clipping an unscaled desktop page.
fn twips_cqw(value : Int, content_width_twips : Int) -> String {
  "\{value.to_double() * 100.0 / content_width_twips.to_double()}cqw"
}

///|
fn preview_runs(
  runs : Array[@contractdoc.ContractPreviewRun],
  content_width_twips : Int,
) -> @rabbita.Html {
  if runs.is_empty() {
    return @html.span(" ")
  }
  if runs.all(run => run.text.is_empty()) {
    let spacer = @html.Attrs::build()
    let source = runs[0]
    match source.font_size_half_points {
      Some(size) =>
        ignore(
          spacer.style("font-size", half_points_cqw(size, content_width_twips)),
        )
      None => ()
    }
    match source.font_east_asia {
      Some(font) if font.trim() != "" =>
        ignore(spacer.style("font-family", preview_font_stack(font)))
      _ => ()
    }
    return @html.span(attrs=spacer, " ")
  }
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
          Some(size) =>
            ignore(
              attrs.style(
                "font-size",
                half_points_cqw(size, content_width_twips),
              ),
            )
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
fn apply_paragraph_layout(
  attrs : @html.Attrs,
  alignment : String?,
  spacing_before_twips : Int?,
  spacing_after_twips : Int?,
  line_twips : Int?,
  line_rule : String?,
  left_indent_twips : Int?,
  right_indent_twips : Int?,
  first_line_twips : Int?,
  content_width_twips : Int,
) -> Unit {
  match alignment {
    Some("center") => ignore(attrs.style("text-align", "center"))
    Some("right") | Some("end") => ignore(attrs.style("text-align", "right"))
    Some("both") | Some("distribute") =>
      ignore(attrs.style("text-align", "justify"))
    _ => ()
  }
  match spacing_before_twips {
    Some(value) =>
      ignore(attrs.style("margin-top", twips_cqw(value, content_width_twips)))
    None => ()
  }
  match spacing_after_twips {
    Some(value) =>
      ignore(
        attrs.style("margin-bottom", twips_cqw(value, content_width_twips)),
      )
    None => ()
  }
  match line_twips {
    Some(value) if value > 0 && line_rule == Some("exact") =>
      ignore(attrs.style("line-height", twips_cqw(value, content_width_twips)))
    Some(value) if value > 0 =>
      ignore(
        attrs.style("line-height", (value.to_double() / 240.0).to_string()),
      )
    _ => ()
  }
  match left_indent_twips {
    Some(value) =>
      ignore(attrs.style("margin-left", twips_cqw(value, content_width_twips)))
    None => ()
  }
  match right_indent_twips {
    Some(value) =>
      ignore(attrs.style("margin-right", twips_cqw(value, content_width_twips)))
    None => ()
  }
  match first_line_twips {
    Some(value) =>
      ignore(attrs.style("text-indent", twips_cqw(value, content_width_twips)))
    None => ()
  }
}

///|
fn preview_cell_paragraph(
  paragraph : @contractdoc.ContractPreviewParagraph,
  content_width_twips : Int,
) -> @rabbita.Html {
  let attrs = @html.Attrs::build()
  apply_paragraph_layout(
    attrs,
    paragraph.alignment,
    paragraph.spacing_before_twips,
    paragraph.spacing_after_twips,
    paragraph.line_twips,
    paragraph.line_rule,
    paragraph.left_indent_twips,
    paragraph.right_indent_twips,
    paragraph.first_line_twips,
    content_width_twips,
  )
  @html.p(
    class="moonleaf-cell-paragraph",
    attrs~,
    preview_runs(paragraph.runs, content_width_twips),
  )
}

///|
fn cell_grid_start(row : @contractdoc.ContractPreviewRow, index : Int) -> Int {
  let start = Ref(0)
  for cell_index = 0; cell_index < index; cell_index = cell_index + 1 {
    start.val = start.val + row.cells[cell_index].grid_span.max(1)
  }
  start.val
}

///|
fn continuation_at(
  row : @contractdoc.ContractPreviewRow,
  grid_start : Int,
) -> Bool {
  let cursor = Ref(0)
  for cell in row.cells {
    if cursor.val == grid_start {
      return cell.vertical_merge == Some("continue")
    }
    cursor.val = cursor.val + cell.grid_span.max(1)
  }
  false
}

///|
fn cell_rowspan(
  rows : Array[@contractdoc.ContractPreviewRow],
  row_index : Int,
  cell_index : Int,
) -> Int {
  if rows[row_index].cells[cell_index].vertical_merge != Some("restart") {
    return 1
  }
  let grid_start = cell_grid_start(rows[row_index], cell_index)
  let span = Ref(1)
  for next = row_index + 1; next < rows.length(); next = next + 1 {
    if continuation_at(rows[next], grid_start) {
      span.val = span.val + 1
    } else {
      break
    }
  }
  span.val
}

///|
fn preview_block(
  block : @contractdoc.ContractPreviewBlock,
  content_width_twips : Int,
) -> @rabbita.Html {
  let attrs = @html.Attrs::build()
  apply_paragraph_layout(
    attrs,
    block.alignment,
    block.spacing_before_twips,
    block.spacing_after_twips,
    block.line_twips,
    block.line_rule,
    block.left_indent_twips,
    block.right_indent_twips,
    block.first_line_twips,
    content_width_twips,
  )
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
            for row_index, row in block.rows => {
              let row_attrs = @html.Attrs::build()
              match row.height_twips {
                Some(value) =>
                  ignore(
                    row_attrs.style(
                      "height",
                      twips_cqw(value, content_width_twips),
                    ),
                  )
                None =>
                  ignore(
                    row_attrs.style(
                      "height",
                      twips_cqw(720, content_width_twips),
                    ),
                  )
              }
              @html.tr(
                attrs=row_attrs,
                [
                  for cell_index, cell in row.cells => {
                    if cell.vertical_merge == Some("continue") {
                      @html.nothing
                    } else {
                      let cell_attrs = @html.Attrs::build()
                      ignore(
                        cell_attrs.style(
                          "padding-top",
                          twips_cqw(
                            cell.margin_top_twips.unwrap_or(60),
                            content_width_twips,
                          ),
                        ),
                      )
                      ignore(
                        cell_attrs.style(
                          "padding-right",
                          twips_cqw(
                            cell.margin_right_twips.unwrap_or(120),
                            content_width_twips,
                          ),
                        ),
                      )
                      ignore(
                        cell_attrs.style(
                          "padding-bottom",
                          twips_cqw(
                            cell.margin_bottom_twips.unwrap_or(30),
                            content_width_twips,
                          ),
                        ),
                      )
                      ignore(
                        cell_attrs.style(
                          "padding-left",
                          twips_cqw(
                            cell.margin_left_twips.unwrap_or(120),
                            content_width_twips,
                          ),
                        ),
                      )
                      match cell.vertical_alignment {
                        Some("center") =>
                          ignore(cell_attrs.style("vertical-align", "middle"))
                        Some("bottom") =>
                          ignore(cell_attrs.style("vertical-align", "bottom"))
                        _ => ignore(cell_attrs.style("vertical-align", "top"))
                      }
                      @html.td(
                        colspan=cell.grid_span.max(1),
                        rowspan=cell_rowspan(block.rows, row_index, cell_index),
                        attrs=cell_attrs,
                        if cell.paragraphs.is_empty() {
                          [@html.span(cell.text)]
                        } else {
                          [
                            for paragraph in cell.paragraphs => {
                              preview_cell_paragraph(
                                paragraph, content_width_twips,
                              )
                            }
                          ]
                        },
                      )
                    }
                  }
                ],
              )
            }
          ],
        ),
      ])
    }
    "heading" =>
      @html.div(
        class="moonleaf-heading",
        attrs~,
        preview_runs(block.runs, content_width_twips),
      )
    "list-item" =>
      @html.div(class="moonleaf-list-item", attrs~, [
        @html.span(if block.ordered { "1." } else { "•" }),
        preview_runs(block.runs, content_width_twips),
      ])
    _ =>
      @html.p(
        class="moonleaf-paragraph",
        attrs~,
        preview_runs(block.runs, content_width_twips),
      )
  }
}

///|
fn page_percent(value_twips : Int, page_width_twips : Int) -> String {
  "\{value_twips.to_double() * 100.0 / page_width_twips.to_double()}%"
}

///|
fn preview_panel(
  state : ContractDocumentsState,
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
      @html.span(
        class=if state.preview_loading {
          "contract-preview-sync is-loading"
        } else {
          "contract-preview-sync"
        },
        attrs=@html.Attrs::build().aria_live("polite"),
        if state.preview_loading {
          copy(
            state.locale,
            "Updating preview…",
            "正在自动更新预览…",
          )
        } else {
          match state.preview {
            Some(preview) if active_form == Some(preview.form) =>
              copy(
                state.locale,
                "Preview is synchronized",
                "预览已自动同步",
              )
            _ if active_form is Some(_) =>
              copy(
                state.locale,
                "Preview updates automatically",
                "预览将自动更新",
              )
            _ =>
              copy(
                state.locale,
                "Select a form to preview",
                "请选择要预览的表单",
              )
          }
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
            let page_width_twips = preview.page_width_twips.unwrap_or(11905)
            let page_height_twips = preview.page_height_twips.unwrap_or(16840)
            let margin_top_twips = preview.margin_top_twips.unwrap_or(1440)
            let margin_right_twips = preview.margin_right_twips.unwrap_or(1800)
            let margin_bottom_twips = preview.margin_bottom_twips.unwrap_or(
              1440,
            )
            let margin_left_twips = preview.margin_left_twips.unwrap_or(1800)
            let content_width_twips = (page_width_twips -
            margin_left_twips -
            margin_right_twips).max(1)
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
                  ignore(
                    paper.style(
                      "aspect-ratio",
                      "\{page_width_twips} / \{page_height_twips}",
                    ),
                  )
                  ignore(
                    paper.style(
                      "padding-top",
                      page_percent(margin_top_twips, page_width_twips),
                    ),
                  )
                  ignore(
                    paper.style(
                      "padding-right",
                      page_percent(margin_right_twips, page_width_twips),
                    ),
                  )
                  ignore(
                    paper.style(
                      "padding-bottom",
                      page_percent(margin_bottom_twips, page_width_twips),
                    ),
                  )
                  ignore(
                    paper.style(
                      "padding-left",
                      page_percent(margin_left_twips, page_width_twips),
                    ),
                  )
                  @html.article(
                    class="contract-paper moonleaf-document",
                    attrs=paper,
                    [
                      for block in page => {
                        preview_block(block, content_width_twips)
                      }
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
  editable : Bool,
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
      disabled=!editable,
      on_change=text_command(emit, next => FieldChanged(field.field_id, next)),
      options,
    )
  } else if field.kind == MultilineText {
    @html.textarea(
      id~,
      disabled=!editable,
      maxlength=field.maximum_characters,
      value~,
      on_input=text_command(emit, next => FieldChanged(field.field_id, next)),
      "",
    )
  } else {
    @html.input(
      id~,
      attrs=@html.Attrs::build().disabled(!editable),
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
fn capability_button(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  manifest : @contractdoc.ContractTemplateManifest,
  packet : @contractdoc.ContractPacket,
  capability : ContractPacketCapability,
) -> @rabbita.Html {
  let quiet = match capability {
    SaveInformation | ClosePacket | SupersedePacket => true
    _ => false
  }
  let (message, label) : (ContractDocumentsMessage, String) = match capability {
    SaveInformation =>
      (
        SaveInformation(
          packet.packet_id,
          packet.revision,
          editable_draft_values(state, manifest),
        ),
        copy(state.locale, "Save information", "保存资料"),
      )
    ConfirmInformation =>
      (
        BeginConfirmInformation(packet.packet_id, packet.revision),
        copy(state.locale, "Review and confirm", "审阅并确认"),
      )
    RequestGeneration =>
      (
        BeginRequestGeneration(
          packet.packet_id,
          packet.revision,
          packet.values_sha256.unwrap_or(""),
        ),
        copy(
          state.locale,
          "Generate exact DOCX + PDF",
          "生成原格式 DOCX + PDF",
        ),
      )
    RetryGeneration =>
      (
        BeginRequestGeneration(
          packet.packet_id,
          packet.revision,
          packet.values_sha256.unwrap_or(""),
        ),
        copy(state.locale, "Retry generation", "重试生成"),
      )
    RegisterExecution =>
      (
        BeginRegisterExecution(packet.packet_id, packet.revision),
        copy(state.locale, "Register signed evidence", "登记签署证据"),
      )
    ClosePacket =>
      (
        BeginClosePacket(packet.packet_id, packet.revision),
        copy(state.locale, "Close packet", "关闭资料包"),
      )
    SupersedePacket =>
      (
        BeginSupersedePacket(packet.packet_id, packet.revision),
        copy(state.locale, "Supersede packet", "替代资料包"),
      )
    RequestRenewal =>
      (
        BeginRequestRenewal(packet.packet_id),
        copy(state.locale, "Request renewal", "发起续约"),
      )
  }
  @html.button(
    type_="button",
    class=if quiet { "quiet-button" } else { "primary-button" },
    disabled=state.loading,
    on_click=command(emit, message),
    label,
  )
}

///|
fn packet_editor(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  manifest : @contractdoc.ContractTemplateManifest,
  packet : @contractdoc.ContractPacket,
) -> @rabbita.Html {
  let packet_editable = packet.state == InformationDraft ||
    packet.state == ReadyForConfirmation ||
    packet.state == InformationConfirmed
  let active_form = match state.selected_form {
    Some(value) => Some(value)
    None => packet.active_forms.get(0)
  }
  let form = match active_form {
    Some(kind) => find_form(manifest.forms, kind)
    None => None
  }
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
    step_bar(state.locale, packet),
    @html.p(
      class="contract-guidance",
      state_guidance(state.locale, packet, state.actor_owner),
    ),
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
                  if packet_editable {
                    copy(
                      state.locale,
                      "Only the fields assigned to your side are shown. Labels and choices come directly from the supplied contract.",
                      "这里只显示由您这一方填写的字段；标签与选项均直接来自所提供合同。",
                    )
                  } else {
                    copy(
                      state.locale,
                      "Only fields assigned to your side are shown. This lifecycle record is read-only.",
                      "这里只显示由您这一方负责的字段；该生命周期记录为只读。",
                    )
                  },
                ),
              ]),
              {
                let fields : Array[@rabbita.Html] = []
                for field_id in definition.field_ids {
                  match manifest.field(field_id) {
                    Some(field) if visible_to_actor(state.actor_owner, field) =>
                      fields.push(
                        input_for(state, emit, field, packet_editable),
                      )
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
        @html.div(
          class="contract-actions",
          [
            for
              capability in contract_packet_capabilities(
                packet,
                state.actor_owner,
              ) => capability_button(state, emit, manifest, packet, capability)
          ],
        ),
      ]),
      preview_panel(state, packet, form),
    ]),
  ])
}

///|
fn dialog_text_input(
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  id : String,
  label : String,
  value : String,
  field : ContractConfirmationField,
) -> @rabbita.Html {
  @html.div(class="contract-field", [
    @html.label(for_=id, [@html.span(label)]),
    @html.input(
      id~,
      value~,
      on_input=text_command(emit, next => ConfirmationInputChanged(field, next)),
    ),
  ])
}

///|
/// Dialog for the operator lifecycle actions: registering offline execution
/// evidence, closing an effective packet, and superseding a stale packet.
fn operator_confirmation(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  action : ContractDocumentConfirmation,
) -> @rabbita.Html {
  let (title, body) : (String, String) = match action {
    RegisterExecution(_) =>
      (
        copy(
          state.locale,
          "Register the signed and stamped evidence?",
          "登记签署盖章证据？",
        ),
        copy(
          state.locale,
          "Signing stays offline. Record only the digest of the stamped scan and the signing date; the scan itself never enters the platform.",
          "签署保持在线下完成。这里只记录盖章扫描件的摘要与签署日期；扫描件本身不进入平台。",
        ),
      )
    ClosePacket(_) =>
      (
        copy(
          state.locale,
          "Close this effective packet?",
          "关闭该已生效资料包？",
        ),
        copy(
          state.locale,
          "Closing is final. Early termination is accepted only after a settlement confirmation has been generated.",
          "关闭不可撤销。提前退租只有在结算确认单生成后才会被接受。",
        ),
      )
    RejectApproval(_) =>
      (
        copy(
          state.locale,
          "Reject or withdraw this approval request?",
          "拒绝或撤回该审批请求？",
        ),
        copy(
          state.locale,
          "The transition is not applied. A reason is required and is recorded with the decision.",
          "过渡操作不会执行。必须填写原因，并随决定一并记录。",
        ),
      )
    _ =>
      (
        copy(state.locale, "Supersede this packet?", "替代该资料包？"),
        copy(
          state.locale,
          "The packet becomes read-only and every follower moves to the successor packet. Effective or closed packets cannot be superseded.",
          "替代后本资料包转为只读，后续工作都在后续资料包中进行。已生效或已关闭的资料包不能被替代。",
        ),
      )
  }
  let inputs : Array[@rabbita.Html] = match action {
    RegisterExecution(_, _, digest, signed_on) =>
      [
        dialog_text_input(
          emit,
          "contract-confirm-evidence",
          copy(
            state.locale,
            "Evidence digest (sha256:…)",
            "证据摘要（sha256:…）",
          ),
          digest,
          EvidenceDigest,
        ),
        dialog_text_input(
          emit,
          "contract-confirm-signed-on",
          copy(state.locale, "Signing date", "签署日期"),
          signed_on,
          SignedOn,
        ),
      ]
    ClosePacket(_, _, kind, reason) =>
      [
        @html.div(class="contract-field", [
          @html.label(for_="contract-confirm-closure-kind", [
            @html.span(copy(state.locale, "Closure kind", "关闭类型")),
          ]),
          @html.select(
            id="contract-confirm-closure-kind",
            on_change=text_command(emit, next => {
              ConfirmationInputChanged(ClosureKind, next)
            }),
            [
              for candidate in closure_kinds() => {
                @html.option(
                  value=match candidate {
                    Expired => "Expired"
                    EarlyTermination => "EarlyTermination"
                    Settled => "Settled"
                  },
                  selected=kind == candidate,
                  closure_kind_label(state.locale, candidate),
                )
              }
            ],
          ),
        ]),
        dialog_text_input(
          emit,
          "contract-confirm-closure-reason",
          copy(state.locale, "Closure reason", "关闭原因"),
          reason,
          ClosureReason,
        ),
      ]
    SupersedePacket(_, _, successor, reason) =>
      [
        dialog_text_input(
          emit,
          "contract-confirm-successor",
          copy(state.locale, "Successor packet id", "后续资料包编号"),
          successor,
          SuccessorReference,
        ),
        dialog_text_input(
          emit,
          "contract-confirm-supersede-reason",
          copy(state.locale, "Supersession reason", "替代原因"),
          reason,
          SupersessionReason,
        ),
      ]
    RejectApproval(_, reason) =>
      [
        dialog_text_input(
          emit,
          "contract-confirm-rejection-reason",
          copy(state.locale, "Rejection reason", "拒绝原因"),
          reason,
          RejectionReason,
        ),
      ]
    _ => []
  }
  let ready = match action {
    RegisterExecution(_, _, digest, signed_on) =>
      digest.trim() != "" && signed_on.trim() != ""
    ClosePacket(_, _, _, reason) => reason.trim() != ""
    SupersedePacket(_, _, successor, reason) =>
      successor.trim() != "" && reason.trim() != ""
    RejectApproval(_, reason) => reason.trim() != ""
    _ => true
  }
  @html.div(class="modal-backdrop", [
    @html.section(
      class="confirmation-dialog",
      attrs=@html.Attrs::build().role("alertdialog").aria_modal("true"),
      [
        @html.h2(title),
        @html.p(body),
        @html.div(class="contract-field-grid", inputs),
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
            disabled=!ready || state.loading,
            on_click=command(emit, ConfirmAction(action)),
            copy(state.locale, "Confirm", "确认执行"),
          ),
        ]),
      ],
    ),
  ])
}

///|
fn confirmation(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
) -> @rabbita.Html {
  match state.confirmation {
    None => @html.span("")
    Some(action) =>
      match action {
        RegisterExecution(_)
        | ClosePacket(_)
        | SupersedePacket(_)
        | RejectApproval(_) => operator_confirmation(state, emit, action)
        ConfirmInformation(_) | RequestGeneration(_) | RequestRenewal(_) => {
          let generating = action is RequestGeneration(_, _, _)
          let renewing = action is RequestRenewal(_)
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
                  } else if renewing {
                    copy(
                      state.locale,
                      "Request a renewal of this contract?",
                      "发起该合同的续约？",
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
                  } else if renewing {
                    copy(
                      state.locale,
                      "A new draft packet carries this packet's initial forms and information forward. Signatures and seals are redone offline, and every value can still be edited before confirmation.",
                      "系统将新建草稿资料包并带入本资料包的初始表单与资料；签字盖章在线下重新完成，所有资料在确认前仍可修改。",
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
                    } else if renewing {
                      copy(state.locale, "Request renewal", "发起续约")
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
}

///|
/// The operator-only four-eyes queue. Pending approval requests render with
/// Approve/Reject actions; an empty queue renders a single empty-state line
/// (demo mode seeds no approvals, so no decision buttons are reachable).
fn approvals_block(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
) -> @rabbita.Html {
  if state.actor_owner != ManagerOperator {
    return @html.nothing
  }
  let pending = state.approvals.filter(approval => approval.status == Pending)
  @html.section(class="contract-approvals", [
    @html.div(class="contract-approvals-heading", [
      @html.p(
        class="eyebrow",
        copy(state.locale, "FOUR-EYES APPROVAL", "双人审批"),
      ),
      @html.h2(copy(state.locale, "Pending approvals", "待审批")),
    ]),
    if pending.is_empty() {
      @html.p(
        class="contract-approvals-empty",
        copy(state.locale, "No pending approvals.", "暂无待审批事项。"),
      )
    } else {
      @html.ul(
        class="contract-approvals-list",
        [
          for approval in pending => {
            @html.li(class="contract-approval-item", [
              @html.div(class="contract-approval-facts", [
                @html.strong(approval.packet_id),
                @html.span(
                  copy(
                    state.locale,
                    "action: \{approval.action}",
                    "操作：\{approval.action}",
                  ),
                ),
                @html.span(
                  copy(
                    state.locale,
                    "initiator: \{approval.initiator}",
                    "发起人：\{approval.initiator}",
                  ),
                ),
                @html.span(
                  copy(
                    state.locale,
                    "requested: \{approval.created_unix_ms}",
                    "发起时间：\{approval.created_unix_ms}",
                  ),
                ),
              ]),
              @html.div(class="contract-approval-actions", [
                @html.button(
                  type_="button",
                  class="primary-button",
                  disabled=state.loading,
                  on_click=command(emit, ApproveApproval(approval.approval_id)),
                  copy(state.locale, "Approve", "批准"),
                ),
                @html.button(
                  type_="button",
                  class="quiet-button",
                  disabled=state.loading,
                  on_click=command(
                    emit,
                    BeginRejectApproval(approval.approval_id),
                  ),
                  copy(state.locale, "Reject", "拒绝"),
                ),
              ]),
            ])
          }
        ],
      )
    },
  ])
}

///|
/// A compact portfolio read model for the operator console. The API exposes
/// the durable governance dashboard; this local projection keeps the browser
/// useful while a refresh is in flight and never invents amounts or dates.
fn governance_summary_block(state : ContractDocumentsState) -> @rabbita.Html {
  if state.actor_owner != ManagerOperator {
    return @html.nothing
  }
  let effective = state.packets
    .filter(packet => packet.state == Effective)
    .length()
  let pending = state.approvals
    .filter(approval => approval.status == Pending)
    .length()
  let dashboard = state.governance_dashboard
  let metric_value = fn(label : String, fallback : String) -> @rabbita.Html {
    @html.div(class="contract-governance-metric", [
      @html.span(label),
      @html.strong(fallback),
    ])
  }
  @html.section(class="contract-governance-summary", [
    @html.div(class="contract-governance-summary-heading", [
      @html.p(
        class="eyebrow",
        copy(state.locale, "OPERATING VIEW", "经营视图"),
      ),
      @html.h2(copy(state.locale, "Contract governance", "合同治理")),
      @html.p(
        copy(
          state.locale,
          "A read-only view of the durable contract state. Amounts and obligations come from the ledger/governance API when loaded.",
          "只读展示持久化合同状态；金额和履约义务由台账/治理 API 提供。",
        ),
      ),
    ]),
    @html.div(class="contract-governance-metrics", [
      metric_value(
        copy(state.locale, "Effective contracts", "生效合同"),
        match dashboard {
          Some(value) => value.effective_packets.to_string()
          None => effective.to_string()
        },
      ),
      metric_value(
        copy(state.locale, "Pending approvals", "待审批"),
        match dashboard {
          Some(value) => value.pending_approvals.to_string()
          None => pending.to_string()
        },
      ),
      metric_value(
        copy(state.locale, "Overdue obligations", "逾期待办"),
        match dashboard {
          Some(value) => value.overdue_obligations.to_string()
          None => copy(state.locale, "Unavailable", "不可用")
        },
      ),
      metric_value(
        copy(state.locale, "Open closure proposals", "未决关单提案"),
        match dashboard {
          Some(value) => value.open_closure_proposals.to_string()
          None => copy(state.locale, "Unavailable", "不可用")
        },
      ),
      metric_value(
        copy(state.locale, "Ledger amount", "台账金额"),
        match dashboard {
          Some(value) => value.total_amount_minor_units.to_string()
          None => copy(state.locale, "Unavailable", "不可用")
        },
      ),
      metric_value(
        copy(state.locale, "Lifecycle source", "生命周期来源"),
        match dashboard {
          Some(_) =>
            copy(
              state.locale,
              "Durable governance read model",
              "持久化治理读模型",
            )
          None =>
            copy(state.locale, "ContractDocumentStore", "合同持久化存储")
        },
      ),
    ]),
  ])
}

///|
fn packet_switcher(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
) -> @rabbita.Html {
  if state.packets.length() <= 1 {
    return @html.nothing
  }
  let selected = state.selected_packet_id.unwrap_or(state.packets[0].packet_id)
  let options = [
    for packet in state.packets => {
      @html.option(
        value=packet.packet_id,
        selected=packet.packet_id == selected,
        "\{state_label(state.locale, packet.state)} · \{packet.packet_id}",
      )
    }
  ]
  @html.div(class="contract-packet-switcher", [
    @html.label(for_="contract-packet-selector", [
      @html.span(copy(state.locale, "Contract packet", "合同资料包")),
      @html.small(
        copy(
          state.locale,
          "Choose the lifecycle record before acting.",
          "操作前先选择对应的生命周期记录。",
        ),
      ),
    ]),
    @html.select(
      id="contract-packet-selector",
      on_change=text_command(emit, packet_id => SelectPacket(packet_id)),
      options,
    ),
  ])
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
    governance_summary_block(state),
    approvals_block(state, emit),
    packet_switcher(state, emit),
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
    #|.contract-steps{list-style:none;display:flex;flex-wrap:wrap;gap:.4rem;margin:0;padding:.6rem .8rem}.contract-step{display:inline-flex;align-items:center;gap:.4rem;padding:.3rem .6rem;border:1px solid var(--line,#223743);border-radius:999px;color:var(--muted,#91a7ad);font-size:.85rem}.contract-step-marker{display:inline-flex;align-items:center;justify-content:center;width:1.3rem;height:1.3rem;border-radius:50%;border:1px solid currentColor;font-size:.75rem}.contract-step.is-done{color:var(--ink,#ecf5f2);border-color:rgba(126,224,189,.35)}.contract-step.is-current{color:var(--ink,#ecf5f2);border-color:rgba(126,224,189,.7);background:rgba(126,224,189,.1)}.contract-step.is-failed{color:#f2a3a3;border-color:rgba(242,163,163,.6);background:rgba(242,163,163,.08)}.contract-steps-terminal{display:flex;align-items:center;gap:.6rem;padding:.6rem .8rem;color:var(--muted,#91a7ad)}.contract-step-badge.is-superseded{padding:.3rem .6rem;border:1px solid rgba(242,163,163,.6);border-radius:999px;color:#f2a3a3;font-size:.85rem}.contract-guidance{margin:0;padding:0 .8rem .8rem;color:var(--muted,#91a7ad)}
    #|.contract-editor-layout{display:grid;grid-template-columns:minmax(10rem,.18fr) minmax(18rem,.58fr) minmax(30rem,1fr)!important}.contract-form-nav{min-width:0;padding:.8rem;border-right:1px solid var(--line,#223743);display:grid;align-content:start;gap:.4rem}.contract-form-tab{min-height:3.2rem;padding:.6rem .75rem;border:1px solid transparent;border-radius:.5rem;background:transparent;color:inherit;font:inherit;text-align:left;display:flex;flex-direction:column;cursor:pointer}.contract-form-tab small{color:var(--muted,#91a7ad)}.contract-form-tab.is-active{border-color:rgba(126,224,189,.35);background:rgba(126,224,189,.08)}.contract-form-panel{min-width:0;padding:1.25rem}.contract-form-heading h2{margin:.15rem 0}.contract-form-heading p:last-child{color:var(--muted,#91a7ad)}.contract-field-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.9rem;margin:1.2rem 0}.contract-field label{display:flex;justify-content:space-between;gap:.5rem;margin-bottom:.35rem;font-weight:750}.contract-field label small{color:var(--muted,#91a7ad);font-weight:500}.contract-field input,.contract-field select,.contract-field textarea{width:100%;min-height:44px;padding:.65rem .75rem;border:1px solid #35505f;border-radius:.5rem;background:#09151c;color:#ecf5f2;font:inherit}.contract-field textarea{min-height:7rem;resize:vertical}.contract-actions{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:.65rem;padding-top:1rem;border-top:1px solid var(--line,#223743)}.contract-preview{min-width:0;padding:1.25rem;border-left:1px solid var(--line,#223743);background:var(--panel2,#111f29);color:var(--ink,#ecf5f2)}.contract-preview-heading,.contract-preview-toolbar{display:flex;justify-content:space-between;align-items:center;gap:.75rem;flex-wrap:wrap}.contract-preview-heading h2{margin:.1rem 0}.contract-preview-revision,.contract-page-count{color:var(--muted,#91a7ad);font-family:ui-monospace,SFMono-Regular,Menlo,monospace}.contract-preview-sync{display:inline-flex;align-items:center;min-height:2rem;padding:.35rem .6rem;border:1px solid rgba(126,224,189,.28);border-radius:999px;color:#7ee0bd;font-size:.72rem;font-weight:750}.contract-preview-sync.is-loading{color:#f1c36d;border-color:rgba(241,195,109,.35)}.contract-preview-toolbar{margin:.8rem 0}.contract-paper-stage{display:grid;grid-template-columns:minmax(0,1fr);gap:.75rem}.contract-paper-viewport{height:min(76vh,64rem);padding:1rem;overflow:auto;border:1px solid var(--line,#223743);border-radius:.55rem;background:#273138}.moonleaf-pages{display:grid;gap:1.5rem}.contract-paper{container-type:inline-size;display:block;box-sizing:border-box;width:100%;min-height:0;overflow:hidden;background:white;color:#111;box-shadow:0 .8rem 2rem rgba(0,0,0,.35);font-family:"Songti SC","STSong","Noto Serif CJK SC","Source Han Serif SC",serif;font-size:0;line-height:normal}.moonleaf-document{font-kerning:normal;font-synthesis:none;word-break:normal;overflow-wrap:break-word}.moonleaf-document span{white-space:pre-wrap}.moonleaf-paragraph,.moonleaf-heading,.moonleaf-list-item,.moonleaf-cell-paragraph{font-size:2.89cqw;line-height:6.743cqw;text-justify:inter-character}.moonleaf-paragraph,.moonleaf-cell-paragraph{min-height:0;margin:0;text-indent:0}.moonleaf-heading{margin:0;text-align:center;font-weight:700}.moonleaf-list-item{display:flex;gap:.5rem;margin:0}.moonleaf-table{width:100%;margin:0;border-collapse:collapse;table-layout:fixed;font-size:2.89cqw;line-height:normal}.moonleaf-table td{box-sizing:border-box;border:1px solid #555;white-space:pre-wrap;overflow-wrap:anywhere}.is-bold{font-weight:700}.is-italic{font-style:italic}.is-underline{text-decoration:underline}.moonleaf-empty{display:grid;place-content:center;gap:.5rem;text-align:center;color:#3c4850}.moonleaf-empty p{max-width:34rem}.contract-preview-note{color:var(--muted,#91a7ad);font-size:.72rem}@media(max-width:78rem){.contract-editor-layout{grid-template-columns:12rem minmax(0,1fr)!important}.contract-preview{grid-column:1/-1;border-left:0;border-top:1px solid var(--line,#223743)}.contract-paper{max-width:52rem;margin:0 auto}}@media(max-width:52rem){.contract-editor-layout{grid-template-columns:1fr!important}.contract-form-nav{border-right:0;border-bottom:1px solid var(--line,#223743)}.contract-field-grid{grid-template-columns:1fr}.contract-preview-heading{align-items:flex-start;flex-direction:column}.contract-preview-toolbar{position:sticky;top:0;z-index:2;padding:.5rem;background:var(--panel2,#111f29)}.contract-paper-viewport{height:auto;max-height:45rem;padding:.5rem}}
    #|.contract-approvals{margin:0 0 1rem;padding:.9rem 1rem;border:1px solid var(--line,#223743);border-radius:.6rem}.contract-approvals-heading h2{margin:.15rem 0}.contract-approvals-empty{margin:.4rem 0 0;color:var(--muted,#91a7ad)}.contract-approvals-list{list-style:none;margin:.6rem 0 0;padding:0;display:grid;gap:.5rem}.contract-approval-item{display:flex;justify-content:space-between;align-items:center;gap:.8rem;flex-wrap:wrap;padding:.5rem .7rem;border:1px solid var(--line,#223743);border-radius:.5rem}.contract-approval-facts{display:flex;gap:1rem;flex-wrap:wrap;color:var(--muted,#91a7ad)}.contract-approval-facts strong{color:var(--ink,#ecf5f2)}.contract-approval-actions{display:flex;gap:.5rem}.contract-governance-summary{margin:0 0 1rem;padding:1rem;border:1px solid rgba(126,224,189,.28);border-radius:.6rem;background:linear-gradient(135deg,rgba(126,224,189,.08),rgba(17,31,41,.5))}.contract-governance-summary-heading h2{margin:.15rem 0}.contract-governance-summary-heading p:last-child{max-width:62rem;color:var(--muted,#91a7ad)}.contract-governance-metrics{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:.65rem;margin-top:.8rem}.contract-governance-metric{display:grid;gap:.25rem;padding:.7rem;border:1px solid var(--line,#223743);border-radius:.5rem;background:rgba(0,0,0,.12)}.contract-governance-metric span{color:var(--muted,#91a7ad);font-size:.78rem}.contract-governance-metric strong{overflow-wrap:anywhere}@media(max-width:52rem){.contract-governance-metrics{grid-template-columns:1fr}}
    #|.contract-packet-switcher{display:flex;align-items:end;justify-content:space-between;gap:1rem;margin:0 0 1rem;padding:.8rem 1rem;border:1px solid var(--line,#223743);border-radius:.6rem;background:var(--panel2,#111f29)}.contract-packet-switcher label{display:grid;gap:.2rem;font-weight:750}.contract-packet-switcher label small{color:var(--muted,#91a7ad);font-weight:500}.contract-packet-switcher select{width:min(32rem,100%);min-height:44px;padding:.6rem .75rem;border:1px solid #35505f;border-radius:.5rem;background:#09151c;color:#ecf5f2;font:inherit}@media(max-width:52rem){.contract-packet-switcher{align-items:stretch;flex-direction:column}.contract-packet-switcher select{width:100%}}
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
