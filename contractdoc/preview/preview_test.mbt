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
  assert_eq(preview.packet_revision, 2L)
  assert_true(preview.page_width_twips is Some(_))
  assert_true(preview.blocks.any(block => block.kind == "table"))
  let visible_text = preview.blocks.fold(init="", fn(acc, block) {
    let run_text = block.runs.fold(init="", fn(text, run) { text + run.text })
    let cell_text = block.rows.fold(init="", fn(text, row) {
      text + row.join("")
    })
    acc + run_text + cell_text
  })
  assert_true(visible_text.contains("月桂算力服务有限公司"))
  assert_true(visible_text.contains("星海人工智能实验室"))
  assert_true(visible_text.contains("NVIDIA DGX Spark"))
  assert_false(visible_text.contains("{{"))
  assert_true(
    preview.blocks.any(block => {
      block.runs.any(run => run.bold || run.font_size_half_points is Some(_))
    }),
  )
}
