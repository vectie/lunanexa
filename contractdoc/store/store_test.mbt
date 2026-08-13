///|
/// Frozen v1 test fixtures prove long-running packets migrate without losing
/// field ownership or provenance. Production code never writes this shape.
struct LegacyPacketV1Fixture {
  packet_id : String
  idempotency_key : String
  template_id : String
  template_version : String
  template_sha256 : String
  tenant_ref : String
  organization_id : String
  subject_ref : String
  order_ref : String
  active_forms : Array[@contractdoc.ContractFormKind]
  values : Array[@contractdoc.ContractFieldValue]
  values_sha256 : String?
  confirmed_by : String?
  confirmed_unix_ms : Int64?
  artifacts : Array[@contractdoc.ContractGeneratedArtifact]
  state : @contractdoc.ContractPacketState
  revision : Int64
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(ToJson)

///|
struct LegacySnapshotV1Fixture {
  schema_version : String
  packets : Array[LegacyPacketV1Fixture]
  events : Array[@contractdoc.ContractPacketEvent]
} derive(ToJson)

///|
async test "v1 contract snapshots migrate ownership and provenance" {
  let path = "contractdoc-v1-migration-wbtest-\{@async.now()}.json"
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let fixture : LegacySnapshotV1Fixture = {
    schema_version: "lunanexa.contract-document.snapshot.v1",
    packets: [
      {
        packet_id: "packet-v1",
        idempotency_key: "packet-v1-key",
        template_id: manifest.template_id,
        template_version: manifest.template_version,
        template_sha256: manifest.sha256,
        tenant_ref: "tenant-1",
        organization_id: "org-1",
        subject_ref: "subject-1",
        order_ref: "order-1",
        active_forms: [MasterLease],
        values: [{ field_id: "lessee.name", value: "测试单位" }],
        values_sha256: None,
        confirmed_by: None,
        confirmed_unix_ms: None,
        artifacts: [],
        state: InformationDraft,
        revision: 1L,
        created_unix_ms: 1000L,
        updated_unix_ms: 1000L,
      },
    ],
    events: [],
  }
  @fs.write_file(
    path,
    fixture.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let store = ContractDocumentStore::open(path)
  let migrated = store.packet("packet-v1").unwrap()
  assert_eq(migrated.value("lessee.name"), Some("测试单位"))
  assert_eq(migrated.assignments.length(), 1)
  assert_eq(migrated.assignments[0].owner, CustomerMessenger)
  assert_eq(migrated.assignments[0].source_ref, "legacy-contract-snapshot-v1")
  @fs.remove(path)
}

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
    CustomerMessenger,
    "subject-1",
    "enterprise-portal",
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
    ManagerOperator,
    "operator-1",
    "operator-console",
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
    page_count: 18,
    render_evidence_sha256: evidence,
    generated_unix_ms: 5000L,
  }
  let pdf : @contractdoc.ContractGeneratedArtifact = {
    artifact_id: "contract-pdf-1",
    media_type: "application/pdf",
    sha256: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    byte_count: 722000L,
    page_count: 18,
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
