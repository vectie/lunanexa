///|
fn packet(
  state : @contractdoc.ContractPacketState,
) -> @contractdoc.ContractPacket raise {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let created = @contractdoc.new_packet(
    manifest,
    "packet-001",
    "packet-idempotency-001",
    "tenant-a",
    "org-a",
    "subject-a",
    "order-a",
    None,
    [MasterLease],
    1000L,
  )
  { ..created, state, }
}

///|
test "contract collection renders source labels and preserves offline signatures" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let html = @contract_documents.render({
    ..@contract_documents.default_state(ChineseSimplified),
    manifest: Some(manifest),
    packets: [packet(InformationDraft)],
    selected_packet_id: Some("packet-001"),
    selected_form: Some(MasterLease),
  })
  assert_true(html.contains("合同资料与文件"))
  assert_true(html.contains("NVIDIA DGX Spark算力设备远程租赁合同"))
  assert_true(html.contains("乙方单位名称"))
  assert_false(html.contains("甲方单位名称"))
  assert_false(html.contains("法定代表人或授权代表"))
  assert_true(html.contains("这里只显示由您这一方填写的字段"))
}

///|
test "ready packet requires explicit review confirmation" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let base = {
    ..@contract_documents.default_state(English),
    manifest: Some(manifest),
    packets: [packet(ReadyForConfirmation)],
    selected_packet_id: Some("packet-001"),
  }
  let html = @contract_documents.render(base)
  assert_true(html.contains("Review and confirm"))
  let dialog = @contract_documents.render(
    base.update(BeginConfirmInformation("packet-001", 1L)),
  )
  assert_true(dialog.contains("Confirm the information is exact?"))
  assert_true(dialog.contains("role=\"alertdialog\""))
}

///|
test "field changes remain local until explicit save" {
  let changed = @contract_documents.default_state(English).update(
    FieldChanged("lease.lessee_name", "Example Organization"),
  )
  assert_eq(changed.draft_values.length(), 1)
  assert_false(changed.loading)
  let saving = changed.update(
    SaveInformation("packet-001", 1L, changed.draft_values),
  )
  assert_true(saving.loading)
}

///|
test "reactive preview follows the selected form and current role draft" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-preview-request",
    "packet-preview-request-key",
    "tenant-preview",
    "organization-preview",
    "subject-preview",
    "order-preview",
    None,
    manifest.forms.map(form => form.form),
    1000L,
  )
  let state = {
    ..@contract_documents.default_state(
      ChineseSimplified,
      actor_owner=ManagerOperator,
    ),
    manifest: Some(manifest),
    packets: [packet],
    selected_packet_id: Some(packet.packet_id),
    selected_form: Some(ReservationApplication),
    draft_values: [
      { field_id: "reservation.operator_comment", value: "档期已核验" },
      { field_id: "reservation.organization_name", value: "客户不可代填" },
    ],
  }
  guard state.preview_request()
    is Some(RequestPreview(packet_id, revision, form, changes)) else {
    fail("expected a reactive preview request")
  }
  assert_eq(packet_id, packet.packet_id)
  assert_eq(revision, packet.revision)
  assert_eq(form, ReservationApplication)
  assert_eq(changes, [
    { field_id: "reservation.operator_comment", value: "档期已核验" },
  ])
}

///|
test "customer and operator share one packet with role-owned fields and live preview" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
      manifest,
      "packet-role-preview",
      "packet-role-preview-key",
      "tenant-1",
      "org-1",
      "subject-1",
      "order-1",
      None,
      [MasterLease, AccessConfirmation],
      1000L,
    )
    .update_information(
      manifest,
      1L,
      [{ field_id: "lessee.name", value: "星海科技" }],
      CustomerMessenger,
      "subject-1",
      "enterprise-portal",
      2000L,
    )
    .update_information(
      manifest,
      2L,
      [{ field_id: "lessor.name", value: "青年政策运营方" }],
      ManagerOperator,
      "operator-1",
      "operator-console",
      3000L,
    )
    .update_information(
      manifest,
      3L,
      [{ field_id: "access.order_number", value: "order-1" }],
      PlatformDerived,
      "contract-system",
      "linked-order:order-1",
      4000L,
    )
  let state = {
    ..@contract_documents.default_state(
      ChineseSimplified,
      actor_owner=CustomerMessenger,
    ),
    manifest: Some(manifest),
    packets: [packet],
    selected_packet_id: Some(packet.packet_id),
    selected_form: Some(MasterLease),
    draft_values: packet.values,
  }
  let html = @contract_documents.render(state)
  assert_true(html.contains("填写乙方资料"))
  assert_true(html.contains("乙方单位名称"))
  assert_false(html.contains("甲方单位名称"))
  assert_false(html.contains("合同编号"))
  assert_true(html.contains("MOONLEAF LIVE PREVIEW"))
  assert_true(html.contains("使用 MoonLeaf 渲染当前角色草稿"))
  assert_false(html.contains("contract-previews/"))
  assert_false(html.contains("readonly"))

  let operator_html = @contract_documents.render({
    ..state,
    actor_owner: ManagerOperator,
  })
  assert_true(operator_html.contains("填写甲方及运营资料"))
  assert_true(operator_html.contains("甲方单位名称"))
  assert_true(operator_html.contains("合同编号"))
  assert_false(operator_html.contains("乙方单位名称"))
  assert_false(operator_html.contains("readonly"))
}

///|
test "MoonLeaf scene renders Chinese text, merged cells, and tables without raster assets" {
  let title_run : @contractdoc.ContractPreviewRun = {
    text: "NVIDIA DGX Spark算力设备远程租赁合同",
    bold: true,
    italic: false,
    underline: false,
    font_size_half_points: Some(32),
    color: None,
    font_ascii: None,
    font_east_asia: Some("方正小标宋简体"),
    font_complex_script: None,
  }
  let paragraph : @contractdoc.ContractPreviewParagraph = {
    runs: [title_run],
    alignment: Some("center"),
    spacing_before_twips: None,
    spacing_after_twips: None,
    line_twips: Some(288),
    line_rule: Some("auto"),
    left_indent_twips: None,
    right_indent_twips: None,
    first_line_twips: None,
    hanging_twips: None,
  }
  let table_row : @contractdoc.ContractPreviewRow = {
    cells: [
      {
        text: "乙方单位名称",
        paragraphs: [
          { ..paragraph, runs: [{ ..title_run, text: "乙方单位名称" }] },
        ],
        grid_span: 1,
        vertical_merge: Some("restart"),
        width_twips: Some(1800),
        margin_top_twips: Some(60),
        margin_right_twips: Some(120),
        margin_bottom_twips: Some(30),
        margin_left_twips: Some(120),
        vertical_alignment: Some("center"),
      },
      {
        text: "星海科技",
        paragraphs: [
          { ..paragraph, runs: [{ ..title_run, text: "星海科技" }] },
        ],
        grid_span: 2,
        vertical_merge: None,
        width_twips: Some(3600),
        margin_top_twips: None,
        margin_right_twips: None,
        margin_bottom_twips: None,
        margin_left_twips: None,
        vertical_alignment: Some("center"),
      },
    ],
    height_twips: Some(781),
    height_rule: Some("atLeast"),
  }
  let empty : @contractdoc.ContractPreviewBlock = {
    kind: "paragraph",
    level: 0,
    ordered: false,
    runs: [],
    rows: [],
    alignment: None,
    spacing_before_twips: None,
    spacing_after_twips: None,
    line_twips: None,
    line_rule: None,
    left_indent_twips: None,
    right_indent_twips: None,
    first_line_twips: None,
    hanging_twips: None,
    grid_widths_twips: [],
  }
  let title = {
    ..empty,
    kind: "heading",
    runs: [title_run],
    alignment: Some("center"),
    spacing_after_twips: Some(240),
    line_twips: Some(288),
    line_rule: Some("auto"),
  }
  let table = {
    ..empty,
    kind: "table",
    rows: [
      table_row,
      {
        cells: [{ ..table_row.cells[0], vertical_merge: Some("continue") }],
        height_twips: Some(559),
        height_rule: Some("atLeast"),
      },
    ],
    grid_widths_twips: [1800, 1800, 1800],
  }
  let second = {
    ..empty,
    runs: [
      {
        ..title_run,
        text: "第二页中文内容",
        bold: false,
        font_ascii: Some("仿宋_GB2312"),
        font_east_asia: Some("仿宋_GB2312"),
      },
    ],
  }
  let preview : @contractdoc.ContractPreviewDocument = {
    engine: "moonleaf",
    packet_id: "packet-001",
    packet_revision: 1L,
    form: MasterLease,
    blocks: [title, table, { ..empty, kind: "page-break" }, second],
    pages: [[title, table], [second]],
    diagnostic_codes: [],
    page_width_twips: Some(11906),
    page_height_twips: Some(16838),
    margin_top_twips: Some(1440),
    margin_right_twips: Some(1800),
    margin_bottom_twips: Some(1440),
    margin_left_twips: Some(1800),
  }
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let html = @contract_documents.render({
    ..@contract_documents.default_state(ChineseSimplified),
    manifest: Some(manifest),
    packets: [packet(InformationDraft)],
    selected_packet_id: Some("packet-001"),
    selected_form: Some(MasterLease),
    preview: Some(preview),
  })
  assert_true(html.contains("NVIDIA DGX Spark算力设备远程租赁合同"))
  assert_true(html.contains("乙方单位名称"))
  assert_true(html.contains("星海科技"))
  assert_true(html.contains("moonleaf-table"))
  assert_true(html.contains("colspan=\"2\""))
  assert_true(html.contains("rowspan=\"2\""))
  assert_true(html.contains("合同第 1 页"))
  assert_true(html.contains("合同第 2 页"))
  assert_true(html.contains("第二页中文内容"))
  assert_true(html.contains("LunaNexa FZ XiaoBiaoSong"))
  assert_true(html.contains("LunaNexa FangSong GB2312"))
  assert_true(html.contains("font-kerning:normal"))
  assert_true(html.contains("text-justify:inter-character"))
  assert_true(html.contains("white-space:pre-wrap"))
  assert_false(html.contains("<img"))
}

///|
fn scene(
  packet : @contractdoc.ContractPacket,
  actor_owner : @contractdoc.ContractFieldOwner,
) -> String {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  @contract_documents.render({
    ..@contract_documents.default_state(English, actor_owner~),
    manifest: Some(manifest),
    packets: [packet],
    selected_packet_id: Some(packet.packet_id),
  })
}

///|
test "capabilities follow packet state and actor role" {
  let digest = Some(
    "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(InformationDraft),
      CustomerMessenger,
    ),
    [SaveInformation],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(ReadyForConfirmation),
      CustomerMessenger,
    ),
    [SaveInformation, ConfirmInformation],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      { ..packet(InformationConfirmed), values_sha256: digest },
      CustomerMessenger,
    ),
    [SaveInformation, RequestGeneration],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      { ..packet(GenerationFailed), values_sha256: digest },
      CustomerMessenger,
    ),
    [RetryGeneration],
  )
  // Customers never see operator lifecycle actions.
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(Generated),
      CustomerMessenger,
    ),
    [],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(Generated),
      ManagerOperator,
    ),
    [RegisterExecution, SupersedePacket],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(Effective),
      ManagerOperator,
    ),
    [ClosePacket],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(Closed),
      ManagerOperator,
    ),
    [],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(Superseded),
      ManagerOperator,
    ),
    [],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(InformationDraft),
      ManagerOperator,
    ),
    [SaveInformation, SupersedePacket],
  )
  // Confirmation and generation requests are the customer's attestation; the
  // operator never sees them, only the shared save and operator lifecycle
  // actions.
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(ReadyForConfirmation),
      ManagerOperator,
    ),
    [SaveInformation, SupersedePacket],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      { ..packet(InformationConfirmed), values_sha256: digest },
      ManagerOperator,
    ),
    [SaveInformation, SupersedePacket],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      { ..packet(GenerationFailed), values_sha256: digest },
      ManagerOperator,
    ),
    [SupersedePacket],
  )
  assert_eq(
    @contract_documents.contract_packet_capabilities(
      packet(ReadyForConfirmation),
      CustomerMessenger,
    ),
    [SaveInformation, ConfirmInformation],
  )
}

///|
test "step bar marks the current step and generation failures" {
  let generated = scene(packet(Generated), CustomerMessenger)
  assert_true(generated.contains("contract-step is-done"))
  assert_true(generated.contains("contract-step is-current"))
  let failed = scene(packet(GenerationFailed), CustomerMessenger)
  assert_true(failed.contains("contract-step is-failed"))
  let superseded = scene(
    {
      ..packet(Superseded),
      supersession: Some({
        successor_ref: "packet-002",
        reason: "reissued with corrected dates",
        superseded_by: "operator",
        superseded_unix_ms: 3000L,
      }),
    },
    CustomerMessenger,
  )
  assert_true(superseded.contains("contract-step-badge is-superseded"))
  assert_true(superseded.contains("packet-002"))
  assert_false(superseded.contains("contract-step is-current"))
}

///|
test "guidance surfaces failure reasons evidence and closure facts" {
  let failed = scene(
    {
      ..packet(GenerationFailed),
      values_sha256: Some(
        "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      ),
      generation_failure: Some("renderer crashed"),
    },
    CustomerMessenger,
  )
  assert_true(failed.contains("renderer crashed"))
  assert_true(failed.contains("Retry generation"))
  let effective = scene(
    {
      ..packet(Effective),
      execution: Some({
        evidence_sha256: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        signed_on: "2026-08-14",
        registered_by: "operator",
        registered_unix_ms: 6000L,
      }),
    },
    ManagerOperator,
  )
  assert_true(effective.contains("2026-08-14"))
  assert_true(effective.contains("111111111111"))
  let closed = scene(
    {
      ..packet(Closed),
      closure: Some({
        kind: EarlyTermination,
        reason: "tenant vacated ahead of term",
        closed_by: "operator",
        closed_unix_ms: 8000L,
      }),
    },
    ManagerOperator,
  )
  assert_true(closed.contains("Early termination"))
  assert_true(closed.contains("tenant vacated ahead of term"))
  let customer_generated = scene(packet(Generated), CustomerMessenger)
  assert_false(customer_generated.contains("Register signed evidence"))
  let operator_generated = scene(packet(Generated), ManagerOperator)
  assert_true(operator_generated.contains("Register signed evidence"))
  assert_true(operator_generated.contains("Supersede packet"))
}

///|
test "effective guidance renders the recorded lease window when present" {
  let execution : @contractdoc.ContractExecution? = Some({
    evidence_sha256: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    signed_on: "2026-08-15",
    registered_by: "operator",
    registered_unix_ms: 7000L,
  })
  let windowed = scene(
    {
      ..packet(Effective),
      values: [
        { field_id: "lease.start_date", value: "2026-09-01" },
        { field_id: "lease.end_date", value: "2026-10-01" },
      ],
      execution,
    },
    ManagerOperator,
  )
  assert_true(windowed.contains("Recorded effective window"))
  assert_true(windowed.contains("2026-09-01"))
  assert_true(windowed.contains("2026-10-01"))
  let reservation_windowed = scene(
    {
      ..packet(Effective),
      values: [
        { field_id: "reservation.start_date", value: "2026-11-01" },
        { field_id: "reservation.end_date", value: "2026-12-01" },
      ],
      execution,
    },
    CustomerMessenger,
  )
  assert_true(reservation_windowed.contains("2026-11-01"))
  assert_true(reservation_windowed.contains("2026-12-01"))
  // Form kinds without lease date fields render no window line.
  let plain = scene({ ..packet(Effective), execution, }, ManagerOperator)
  assert_false(plain.contains("Recorded effective window"))
}

///|
test "operator dialogs collect typed payloads for lifecycle actions" {
  let base = @contract_documents.default_state(
    English,
    actor_owner=ManagerOperator,
  )
  let executing = base.update(BeginRegisterExecution("packet-001", 5L))
  assert_eq(
    executing.confirmation,
    Some(RegisterExecution("packet-001", 5L, "", "")),
  )
  let filled = executing
    .update(
      ConfirmationInputChanged(
        EvidenceDigest,
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
      ),
    )
    .update(ConfirmationInputChanged(SignedOn, "2026-08-14"))
  assert_eq(
    filled.confirmation,
    Some(
      RegisterExecution(
        "packet-001", 5L, "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        "2026-08-14",
      ),
    ),
  )
  let closing = base
    .update(BeginClosePacket("packet-001", 6L))
    .update(ConfirmationInputChanged(ClosureKind, "EarlyTermination"))
    .update(ConfirmationInputChanged(ClosureReason, "tenant vacated"))
  assert_eq(
    closing.confirmation,
    Some(ClosePacket("packet-001", 6L, EarlyTermination, "tenant vacated")),
  )
  let acted = closing.update(ConfirmAction(closing.confirmation.unwrap()))
  assert_true(acted.loading)
  assert_eq(acted.confirmation, None)
}
