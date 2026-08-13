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
  assert_true(
    html.contains("此项仅在线下打印件或获批签署件中填写"),
  )
  assert_true(html.contains("系统不会增加法律条款"))
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
