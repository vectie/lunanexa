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
test "MoonLeaf scene renders Chinese text and tables without raster assets" {
  let preview : @contractdoc.ContractPreviewDocument = {
    engine: "moonleaf",
    packet_id: "packet-001",
    packet_revision: 1L,
    form: MasterLease,
    blocks: [
      {
        kind: "heading",
        level: 1,
        ordered: false,
        runs: [
          {
            text: "NVIDIA DGX Spark算力设备远程租赁合同",
            bold: true,
            italic: false,
            underline: false,
            font_size_half_points: Some(32),
            color: None,
            font_ascii: None,
            font_east_asia: Some("方正小标宋简体"),
            font_complex_script: None,
          },
        ],
        rows: [],
        alignment: Some("center"),
        spacing_before_twips: None,
        spacing_after_twips: Some(240),
        line_twips: None,
        left_indent_twips: None,
        right_indent_twips: None,
        first_line_twips: None,
        hanging_twips: None,
        grid_widths_twips: [],
        cell_widths_twips: [],
      },
      {
        kind: "table",
        level: 0,
        ordered: false,
        runs: [],
        rows: [["乙方单位名称", "星海科技"]],
        alignment: None,
        spacing_before_twips: None,
        spacing_after_twips: None,
        line_twips: None,
        left_indent_twips: None,
        right_indent_twips: None,
        first_line_twips: None,
        hanging_twips: None,
        grid_widths_twips: [1800, 3600],
        cell_widths_twips: [[Some(1800), Some(3600)]],
      },
      {
        kind: "page-break",
        level: 0,
        ordered: false,
        runs: [],
        rows: [],
        alignment: None,
        spacing_before_twips: None,
        spacing_after_twips: None,
        line_twips: None,
        left_indent_twips: None,
        right_indent_twips: None,
        first_line_twips: None,
        hanging_twips: None,
        grid_widths_twips: [],
        cell_widths_twips: [],
      },
      {
        kind: "paragraph",
        level: 0,
        ordered: false,
        runs: [
          {
            text: "第二页中文内容",
            bold: false,
            italic: false,
            underline: false,
            font_size_half_points: Some(24),
            color: None,
            font_ascii: None,
            font_east_asia: Some("仿宋_GB2312"),
            font_complex_script: None,
          },
        ],
        rows: [],
        alignment: None,
        spacing_before_twips: None,
        spacing_after_twips: None,
        line_twips: None,
        left_indent_twips: None,
        right_indent_twips: None,
        first_line_twips: None,
        hanging_twips: None,
        grid_widths_twips: [],
        cell_widths_twips: [],
      },
    ],
    pages: [
      [
        {
          kind: "heading",
          level: 1,
          ordered: false,
          runs: [
            {
              text: "NVIDIA DGX Spark算力设备远程租赁合同",
              bold: true,
              italic: false,
              underline: false,
              font_size_half_points: Some(32),
              color: None,
              font_ascii: None,
              font_east_asia: Some("方正小标宋简体"),
              font_complex_script: None,
            },
          ],
          rows: [],
          alignment: Some("center"),
          spacing_before_twips: None,
          spacing_after_twips: Some(240),
          line_twips: None,
          left_indent_twips: None,
          right_indent_twips: None,
          first_line_twips: None,
          hanging_twips: None,
          grid_widths_twips: [],
          cell_widths_twips: [],
        },
        {
          kind: "table",
          level: 0,
          ordered: false,
          runs: [],
          rows: [["乙方单位名称", "星海科技"]],
          alignment: None,
          spacing_before_twips: None,
          spacing_after_twips: None,
          line_twips: None,
          left_indent_twips: None,
          right_indent_twips: None,
          first_line_twips: None,
          hanging_twips: None,
          grid_widths_twips: [1800, 3600],
          cell_widths_twips: [[Some(1800), Some(3600)]],
        },
      ],
      [
        {
          kind: "paragraph",
          level: 0,
          ordered: false,
          runs: [
            {
              text: "第二页中文内容",
              bold: false,
              italic: false,
              underline: false,
              font_size_half_points: Some(24),
              color: None,
              font_ascii: None,
              font_east_asia: Some("仿宋_GB2312"),
              font_complex_script: None,
            },
          ],
          rows: [],
          alignment: None,
          spacing_before_twips: None,
          spacing_after_twips: None,
          line_twips: None,
          left_indent_twips: None,
          right_indent_twips: None,
          first_line_twips: None,
          hanging_twips: None,
          grid_widths_twips: [],
          cell_widths_twips: [],
        },
      ],
    ],
    diagnostic_codes: [],
    page_width_twips: Some(11906),
    page_height_twips: Some(16838),
    margin_top_twips: Some(1440),
    margin_right_twips: Some(1440),
    margin_bottom_twips: Some(1440),
    margin_left_twips: Some(1440),
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
  assert_true(html.contains("合同第 1 页"))
  assert_true(html.contains("合同第 2 页"))
  assert_true(html.contains("第二页中文内容"))
  assert_false(html.contains("<img"))
}
