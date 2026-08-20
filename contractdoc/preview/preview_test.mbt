///|
async test "MoonLeaf previews the embedded Chinese contract with role-scoped draft values" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-preview",
    "packet-preview-key",
    "tenant-preview",
    "organization-preview",
    "subject-preview",
    "order-preview",
    None,
    [MasterLease],
    1000L,
  ).update_information(
    manifest,
    1L,
    [{ field_id: "lessor.name", value: "月桂算力服务有限公司" }],
    ManagerOperator,
    "operator-preview",
    "operator-console",
    2000L,
  )
  let template = @fs.read_file(
      "assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx",
    )
    .binary()
    .to_fixedarray()
  let preview = render(
    template,
    manifest,
    packet,
    CustomerMessenger,
    MasterLease,
    [{ field_id: "lessee.name", value: "星海人工智能实验室" }],
  )
  assert_eq(preview.engine, "moonleaf")
  assert_eq(preview.packet_revision, 3L)
  assert_eq(preview.page_width_twips, Some(11905))
  assert_eq(preview.page_height_twips, Some(16840))
  assert_eq(preview.margin_top_twips, Some(1440))
  assert_eq(preview.margin_right_twips, Some(1800))
  assert_eq(preview.margin_bottom_twips, Some(1440))
  assert_eq(preview.margin_left_twips, Some(1800))
  assert_eq(preview.pages.length(), 11)
  assert_true(preview.blocks.any(block => block.kind == "table"))
  assert_eq(
    preview.blocks.filter(block => block.kind == "page-break").length(),
    0,
  )
  let visible_text = preview.blocks.fold(init="", fn(acc, block) {
    let run_text = block.runs.fold(init="", fn(text, run) { text + run.text })
    let cell_text = block.rows.fold(init="", fn(text, row) {
      text + row.cells.map(cell => cell.text).join("")
    })
    acc + run_text + cell_text
  })
  assert_true(visible_text.contains("月桂算力服务有限公司"))
  assert_true(visible_text.contains("星海人工智能实验室"))
  assert_true(visible_text.contains("NVIDIA DGX Spark"))
  assert_false(visible_text.contains("文件1：算力租赁预约申请表"))
  assert_false(visible_text.contains("{{"))
  assert_true(
    preview.blocks.any(block => {
      block.runs.any(run => run.bold || run.font_size_half_points is Some(_))
    }),
  )
}

///|
fn preview_visible_text(
  preview : @contractdoc.ContractPreviewDocument,
) -> String {
  preview.blocks.fold(init="", fn(acc, block) {
    let run_text = block.runs.fold(init="", fn(text, run) { text + run.text })
    let cell_text = block.rows.fold(init="", fn(text, row) {
      text + row.cells.map(cell => cell.text).join("")
    })
    acc + run_text + cell_text
  })
}

///|
async test "MoonLeaf audits the 18-page marker copy against the authoritative DOCX" {
  let reference_bytes = @fs.read_file(
      "assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.docx",
    )
    .binary()
    .to_fixedarray()
  let candidate_bytes = @fs.read_file(
      "assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx",
    )
    .binary()
    .to_fixedarray()
  let reference = @opc.open(reference_bytes)
  let candidate = @opc.open(candidate_bytes)
  let reference_pages = @docx.paginate_document(reference)
  assert_eq(reference_pages.pages.length(), 18)
  let audit = @docx.audit_layout_equivalence(reference, candidate)
  assert_eq(audit.reference_cached_page_count, Some(18))
  assert_eq(audit.candidate_cached_page_count, Some(18))
  assert_eq(audit.reference_paragraph_count, 152)
  assert_eq(audit.candidate_paragraph_count, 152)
  assert_eq(audit.reference_table_count, 10)
  assert_eq(audit.candidate_table_count, 10)
  assert_eq(audit.reference_explicit_page_break_count, 6)
  assert_eq(audit.candidate_explicit_page_break_count, 6)
  assert_true(audit.non_document_parts_equal)
  assert_true(audit.paragraph_layout_equal)
  assert_true(audit.table_layout_equal)
  assert_true(audit.section_layout_equal)
  assert_true(audit.explicit_page_breaks_equal)
  assert_true(audit.run_style_layout_equal)
  assert_true(audit.main_structure_equal)
  assert_true(audit.equivalent)
  let markers = @worker.exact_docx_markers(candidate_bytes)
  let generated_bytes = @worker.customize_exact_docx_template(
    candidate_bytes,
    markers.map(marker => { placeholder: marker, value: "" }),
  )
  let generated = @opc.open(generated_bytes.bytes)
  let generated_pages = @docx.paginate_document(generated)
  assert_eq(generated_pages.pages.length(), 18)
  let generated_audit = @docx.audit_layout_equivalence(reference, generated)
  assert_eq(generated_audit.reference_cached_page_count, Some(18))
  assert_eq(generated_audit.candidate_cached_page_count, Some(18))
  assert_true(generated_audit.non_document_parts_equal)
  assert_true(generated_audit.paragraph_layout_equal)
  assert_true(generated_audit.run_style_layout_equal)
  assert_true(generated_audit.table_layout_equal)
  assert_true(generated_audit.section_layout_equal)
  assert_true(generated_audit.explicit_page_breaks_equal)
  assert_true(generated_audit.main_structure_equal)
  assert_true(generated_audit.equivalent)
}

///|
async test "generated demo scene materializes only the authorized role draft" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let source = @fs.read_file(
      "assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx",
    )
    .binary()
    .to_fixedarray()
  let scene = template(source, manifest)
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-demo-preview",
    "packet-demo-preview-key",
    "tenant-demo",
    "organization-demo",
    "subject-demo",
    "order-demo",
    None,
    [MasterLease],
    1000L,
  ).update_information(
    manifest,
    1L,
    [{ field_id: "lessor.name", value: "青年政策运营中心" }],
    ManagerOperator,
    "operator-demo",
    "operator-console",
    2000L,
  )
  let preview = @contractdoc.materialize_preview_template(
    scene,
    manifest,
    packet,
    CustomerMessenger,
    MasterLease,
    [{ field_id: "lessee.name", value: "星海客户实验室" }],
  )
  let json = preview.to_json().stringify()
  assert_true(json.contains("青年政策运营中心"))
  assert_true(json.contains("星海客户实验室"))
  assert_false(json.contains("{{"))
  assert_eq(preview.pages.length(), 11)
  try
    @contractdoc.materialize_preview_template(
      scene,
      manifest,
      packet,
      CustomerMessenger,
      MasterLease,
      [{ field_id: "lessor.name", value: "越权修改" }],
    )
  catch {
    InvalidInput("contract field is owned by another participant") => ()
    error => fail("unexpected role isolation error: \{Repr(error)}")
  } noraise {
    _ => fail("customer demo preview accepted an operator-owned value")
  }
}

///|
async test "every contract tab materializes only its associated MoonLeaf pages" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let source = @fs.read_file(
      "assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx",
    )
    .binary()
    .to_fixedarray()
  let scene = template(source, manifest)
  let forms = manifest.forms.map(definition => definition.form)
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-all-form-preview",
    "packet-all-form-preview-key",
    "tenant-demo",
    "organization-demo",
    "subject-demo",
    "order-demo",
    None,
    forms,
    1000L,
  )
  let expected_pages = [11, 2, 1, 1, 1, 1, 1]
  let expected_headings = [
    "NVIDIA DGX Spark算力设备远程租赁合同", "文件1：算力租赁预约申请表",
    "文件2：算力权限开通/关停确认单", "文件3：违规行为告知单",
    "文件4：设备损坏责任认定及赔偿通知单", "文件5：租赁结算确认单",
    "文件6：提前退租申请表",
  ]
  for index, form in forms {
    let preview = @contractdoc.materialize_preview_template(
      scene,
      manifest,
      packet,
      ManagerOperator,
      form,
      [],
    )
    assert_eq(preview.form, form)
    assert_eq(preview.pages.length(), expected_pages[index])
    let text = preview_visible_text(preview)
    assert_true(text.contains(expected_headings[index]))
    for other_index, heading in expected_headings {
      if other_index != index && other_index > 0 {
        assert_false(text.contains(heading))
      }
    }
  }
}

///|
async test "read-only packets preview their recorded values and ignore draft changes" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let source = @fs.read_file(
      "assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx",
    )
    .binary()
    .to_fixedarray()
  let scene = template(source, manifest)
  let draft = @contractdoc.new_packet(
    manifest,
    "packet-effective-preview",
    "packet-effective-preview-key",
    "tenant-demo",
    "organization-demo",
    "subject-demo",
    "order-demo",
    None,
    [MasterLease],
    1000L,
  ).update_information(
    manifest,
    1L,
    [{ field_id: "lessee.name", value: "Recorded customer" }],
    CustomerMessenger,
    "subject-demo",
    "customer-portal",
    2000L,
  )
  let effective = { ..draft, state: Effective }
  let preview = @contractdoc.materialize_preview_template(
    scene,
    manifest,
    effective,
    CustomerMessenger,
    MasterLease,
    [{ field_id: "lessee.name", value: "Uncommitted browser value" }],
  )
  let text = preview_visible_text(preview)
  assert_true(text.contains("Recorded customer"))
  assert_false(text.contains("Uncommitted browser value"))
  assert_eq(preview.packet_revision, effective.revision)
}
