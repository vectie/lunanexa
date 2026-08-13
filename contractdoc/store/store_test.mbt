///|
async test "contract packets persist drafts and audit no raw values" {
  let path = "contractdoc-store-wbtest-\{@async.now()}.json"
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-durable",
    "packet-durable-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    [ReservationApplication],
    1000L,
  )
  let store = ContractDocumentStore::open(path)
  ignore(store.create_packet(packet, "subject-1"))
  let updated = store.update_information(
    manifest,
    packet.packet_id,
    1L,
    [
      { field_id: "reservation.organization_name", value: "测试单位" },
      { field_id: "reservation.contact_phone", value: "13800000000" },
    ],
    "subject-1",
    2000L,
  )
  assert_eq(updated.revision, 2L)
  let reopened = ContractDocumentStore::open(path)
  assert_eq(reopened.packet(packet.packet_id), Some(updated))
  let snapshot = reopened.snapshot()
  assert_eq(snapshot.events.length(), 2)
  let audit_json = snapshot.events.to_json().stringify()
  assert_false(audit_json.contains("测试单位"))
  assert_false(audit_json.contains("13800000000"))
  assert_true(audit_json.contains("reservation.organization_name"))
  @fs.remove(path)
}

///|
async test "confirmed generation request and exact paired artifacts survive restart" {
  let path = "contractdoc-generation-wbtest-\{@async.now()}.json"
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let initial = @contractdoc.new_packet(
    manifest,
    "packet-generation",
    "packet-generation-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    [ViolationNotice],
    1000L,
  )
  let required : Array[@contractdoc.ContractFieldValue] = [
    for field in manifest.fields if field.form == ViolationNotice &&
    field.required => {
      let value = if field.allowed_values.length() > 0 {
        field.allowed_values[0]
      } else {
        match field.kind {
          Identifier => "id-001"
          WholeNumber => "1"
          MoneyAmount | MoneyUppercase => "1"
          CalendarDate => "2026年8月13日"
          _ => "已核实资料"
        }
      }
      { field_id: field.field_id, value }
    }
  ]
  let store = ContractDocumentStore::open(path)
  ignore(store.create_packet(initial, "subject-1"))
  let ready = store.update_information(
    manifest,
    initial.packet_id,
    1L,
    required,
    "subject-1",
    2000L,
  )
  assert_eq(ready.state, ReadyForConfirmation)
  let digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let confirmed = store.confirm_information(
    manifest,
    initial.packet_id,
    ready.revision,
    digest,
    "subject-1",
    3000L,
  )
  let requested = store.request_generation(
    initial.packet_id,
    confirmed.revision,
    digest,
    "subject-1",
    4000L,
  )
  let evidence = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let docx : @contractdoc.ContractGeneratedArtifact = {
    artifact_id: "contract-docx-1",
    media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    sha256: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    byte_count: 419200L,
    page_count: 14,
    render_evidence_sha256: evidence,
    generated_unix_ms: 5000L,
  }
  let pdf : @contractdoc.ContractGeneratedArtifact = {
    artifact_id: "contract-pdf-1",
    media_type: "application/pdf",
    sha256: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    byte_count: 722000L,
    page_count: 14,
    render_evidence_sha256: evidence,
    generated_unix_ms: 5000L,
  }
  let generated = store.complete_generation(
    initial.packet_id,
    requested.revision,
    docx,
    pdf,
    "contract-renderer",
    5000L,
  )
  assert_eq(generated.state, Generated)
  assert_eq(generated.artifacts.length(), 2)
  let reopened = ContractDocumentStore::open(path)
  assert_eq(reopened.packet(initial.packet_id), Some(generated))
  assert_eq(reopened.snapshot().events.length(), 5)
  @fs.remove(path)
}
