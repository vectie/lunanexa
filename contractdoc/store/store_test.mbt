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
    None,
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
  let directory = @fs.tmpdir(prefix="lunanexa-contractdoc-generation-")
  let path = "\{directory}/packet-store.json"
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let initial = @contractdoc.new_packet(
    manifest,
    "packet-generation",
    "packet-generation-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    Some("packet-generation-master"),
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
  let master = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-generation-master",
      "packet-generation-master-key",
      "tenant-1",
      "org-1",
      "subject-1",
      "order-1",
      None,
      [MasterLease],
      500L,
    ),
    state: Effective,
  }
  ignore(store.create_packet(master, "subject-1"))
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
  assert_eq(reopened.snapshot().events.length(), 6)
  @fs.remove(path)
}

///|
/// Frozen v2 test fixtures prove long-running packets migrate forward with
/// empty lifecycle extensions. Production code never writes this shape.
struct LegacyPacketV2Fixture {
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
  assignments : Array[@contractdoc.ContractFieldAssignment]
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
struct LegacySnapshotV2Fixture {
  schema_version : String
  packets : Array[LegacyPacketV2Fixture]
  events : Array[@contractdoc.ContractPacketEvent]
} derive(ToJson)

///|
async test "v2 contract snapshots load with empty lifecycle extensions" {
  let directory = @fs.tmpdir(prefix="lunanexa-contractdoc-v2-migration-")
  let path = "\{directory}/legacy-snapshot.json"
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let fixture : LegacySnapshotV2Fixture = {
    schema_version: "lunanexa.contract-document.snapshot.v2",
    packets: [
      {
        packet_id: "packet-v2",
        idempotency_key: "packet-v2-key",
        template_id: manifest.template_id,
        template_version: manifest.template_version,
        template_sha256: manifest.sha256,
        tenant_ref: "tenant-1",
        organization_id: "org-1",
        subject_ref: "subject-1",
        order_ref: "order-1",
        active_forms: [MasterLease],
        values: [{ field_id: "lessee.name", value: "测试单位" }],
        assignments: [
          {
            field_id: "lessee.name",
            value: "测试单位",
            owner: CustomerMessenger,
            source_ref: "enterprise-portal",
            updated_by: "subject-1",
            updated_unix_ms: 1500L,
          },
        ],
        values_sha256: None,
        confirmed_by: None,
        confirmed_unix_ms: None,
        artifacts: [],
        state: InformationDraft,
        revision: 2L,
        created_unix_ms: 1000L,
        updated_unix_ms: 1500L,
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
  let migrated = store.packet("packet-v2").unwrap()
  assert_eq(migrated.value("lessee.name"), Some("测试单位"))
  assert_eq(migrated.assignments.length(), 1)
  assert_eq(migrated.preceding_packet_ref, None)
  assert_eq(migrated.execution, None)
  assert_eq(migrated.closure, None)
  assert_eq(migrated.supersession, None)
  assert_eq(migrated.generation_failure, None)
  assert_eq(
    store.snapshot().schema_version,
    @contractdoc.snapshot_schema_version,
  )
  @fs.remove(path)
}

///|
async test "effective-stage forms require an effective preceding packet" {
  let path = "contractdoc-gating-wbtest-\{@async.now()}.json"
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let store = ContractDocumentStore::open(path)
  let master = @contractdoc.new_packet(
    manifest,
    "packet-master",
    "packet-master-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    None,
    [MasterLease],
    1000L,
  )
  ignore(store.create_packet(master, "subject-1"))
  let follow_up = @contractdoc.new_packet(
    manifest,
    "packet-access",
    "packet-access-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    Some("packet-master"),
    [AccessConfirmation],
    2000L,
  )
  try store.create_packet(follow_up, "subject-1") catch {
    @contractdoc.ContractDocumentError::ContractNotEffective(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a drafting predecessor must not unlock follow-up forms")
  }
  try
    store.create_packet(
      { ..follow_up, preceding_packet_ref: None },
      "subject-1",
    )
  catch {
    @contractdoc.ContractDocumentError::ContractNotEffective(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("follow-up forms must name a preceding packet")
  }
  let effective_master = {
    ..master,
    packet_id: "packet-master-effective",
    idempotency_key: "packet-master-effective-key",
    state: Effective,
  }
  ignore(store.create_packet(effective_master, "subject-1"))
  let foreign_master = {
    ..master,
    packet_id: "packet-master-foreign",
    idempotency_key: "packet-master-foreign-key",
    tenant_ref: "tenant-2",
    state: Effective,
  }
  ignore(store.create_packet(foreign_master, "subject-1"))
  try
    store.create_packet(
      {
        ..follow_up,
        packet_id: "packet-access-foreign",
        idempotency_key: "packet-access-foreign-key",
        preceding_packet_ref: Some("packet-master-foreign"),
      },
      "subject-1",
    )
  catch {
    @contractdoc.ContractDocumentError::ContractNotEffective(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a cross-tenant predecessor must not unlock follow-up forms")
  }
  let accepted = store.create_packet(
    {
      ..follow_up,
      packet_id: "packet-access-accepted",
      idempotency_key: "packet-access-accepted-key",
      preceding_packet_ref: Some("packet-master-effective"),
    },
    "subject-1",
  )
  assert_eq(accepted.preceding_packet_ref, Some("packet-master-effective"))
  @fs.remove(path)
}

///|
async test "early termination closure requires an effective settlement packet" {
  let path = "contractdoc-closure-wbtest-\{@async.now()}.json"
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let store = ContractDocumentStore::open(path)
  let effective = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-main",
      "packet-main-key",
      "tenant-1",
      "org-1",
      "subject-1",
      "order-1",
      None,
      [MasterLease],
      1000L,
    ),
    state: Effective,
  }
  ignore(store.create_packet(effective, "operator-1"))
  let expiry = store.close_packet(
    "packet-main",
    1L,
    Expired,
    "lease term ended",
    "operator-1",
    5000L,
  )
  assert_eq(expiry.state, Closed)
  let renewable = {
    ..effective,
    packet_id: "packet-renewable",
    idempotency_key: "packet-renewable-key",
  }
  ignore(store.create_packet(renewable, "operator-1"))
  try
    store.close_packet(
      "packet-renewable",
      1L,
      EarlyTermination,
      "tenant vacated",
      "operator-1",
      5000L,
    )
  catch {
    @contractdoc.ContractDocumentError::InvalidInput(
      "early termination requires a confirmed settlement"
    ) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("early termination without settlement must be rejected")
  }
  let drafting_settlement = @contractdoc.new_packet(
    manifest,
    "packet-settlement-draft",
    "packet-settlement-draft-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    Some("packet-renewable"),
    [SettlementConfirmation],
    2000L,
  )
  ignore(store.create_packet(drafting_settlement, "operator-1"))
  try
    store.close_packet(
      "packet-renewable",
      1L,
      EarlyTermination,
      "tenant vacated",
      "operator-1",
      5000L,
    )
  catch {
    @contractdoc.ContractDocumentError::InvalidInput(
      "early termination requires a confirmed settlement"
    ) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a drafting settlement must not unlock early termination")
  }
  let generated_settlement = {
    ..drafting_settlement,
    packet_id: "packet-settlement-generated",
    idempotency_key: "packet-settlement-generated-key",
    state: Generated,
  }
  ignore(store.create_packet(generated_settlement, "operator-1"))
  try
    store.close_packet(
      "packet-renewable",
      1L,
      EarlyTermination,
      "tenant vacated",
      "operator-1",
      5000L,
    )
  catch {
    @contractdoc.ContractDocumentError::InvalidInput(
      "early termination requires a confirmed settlement"
    ) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ =>
      fail("an unsigned generated settlement must not unlock early termination")
  }
  let execution : @contractdoc.ContractExecution = {
    evidence_sha256: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    signed_on: "2026-08-14",
    registered_by: "operator-1",
    registered_unix_ms: 5500L,
  }
  let effective_settlement = store.register_execution(
    "packet-settlement-generated", 1L, execution, 5500L,
  )
  assert_eq(effective_settlement.state, Effective)
  let closed = store.close_packet(
    "packet-renewable",
    1L,
    EarlyTermination,
    "tenant vacated",
    "operator-1",
    6000L,
  )
  assert_eq(closed.state, Closed)
  assert_eq(closed.closure.map(closure => closure.kind), Some(EarlyTermination))
  assert_true(
    store.snapshot().events.any(event => event.kind == PacketClosedEvent),
  )
  @fs.remove(path)
}

///|
async test "supersession validates the successor and records the event" {
  let path = "contractdoc-supersede-wbtest-\{@async.now()}.json"
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let store = ContractDocumentStore::open(path)
  let draft = @contractdoc.new_packet(
    manifest,
    "packet-old",
    "packet-old-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    None,
    [MasterLease],
    1000L,
  )
  ignore(store.create_packet(draft, "subject-1"))
  try
    store.supersede_packet(
      "packet-old", 1L, "packet-missing", "reissued", "operator-1", 3000L,
    )
  catch {
    @contractdoc.ContractDocumentError::NotFound(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a missing successor must be rejected")
  }
  let foreign = @contractdoc.new_packet(
    manifest,
    "packet-foreign",
    "packet-foreign-key",
    "tenant-2",
    "org-2",
    "subject-2",
    "order-2",
    None,
    [MasterLease],
    1500L,
  )
  ignore(store.create_packet(foreign, "subject-2"))
  try
    store.supersede_packet(
      "packet-old", 1L, "packet-foreign", "reissued", "operator-1", 3000L,
    )
  catch {
    @contractdoc.ContractDocumentError::InvalidInput(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a cross-tenant successor must be rejected")
  }
  let successor = @contractdoc.new_packet(
    manifest,
    "packet-new",
    "packet-new-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    None,
    [MasterLease],
    2000L,
  )
  ignore(store.create_packet(successor, "subject-1"))
  let superseded = store.supersede_packet(
    "packet-old", 1L, "packet-new", "reissued with corrected dates", "operator-1",
    3000L,
  )
  assert_eq(superseded.state, Superseded)
  assert_eq(
    superseded.supersession.map(supersession => supersession.successor_ref),
    Some("packet-new"),
  )
  assert_true(
    store.snapshot().events.any(event => event.kind == PacketSupersededEvent),
  )
  let reopened = ContractDocumentStore::open(path)
  assert_eq(reopened.packet("packet-old"), Some(superseded))
  @fs.remove(path)
}

///|
async test "generation failure and execution registration append audit events" {
  let path = "contractdoc-execution-wbtest-\{@async.now()}.json"
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let digest = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  let requested = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-worker",
      "packet-worker-key",
      "tenant-1",
      "org-1",
      "subject-1",
      "order-1",
      None,
      [MasterLease],
      1000L,
    ),
    state: GenerationRequested,
    values_sha256: Some(digest),
    revision: 3L,
  }
  let store = ContractDocumentStore::open(path)
  ignore(store.create_packet(requested, "subject-1"))
  let failed = store.fail_generation(
    "packet-worker", 3L, "renderer crashed", "contract-renderer", 4000L,
  )
  assert_eq(failed.state, GenerationFailed)
  assert_eq(failed.generation_failure, Some("renderer crashed"))
  let retried = store.request_generation(
    "packet-worker",
    failed.revision,
    digest,
    "subject-1",
    5000L,
  )
  assert_eq(retried.state, GenerationRequested)
  assert_eq(retried.generation_failure, None)
  let evidence = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let docx : @contractdoc.ContractGeneratedArtifact = {
    artifact_id: "contract-docx-retry",
    media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    sha256: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    byte_count: 419200L,
    page_count: 18,
    render_evidence_sha256: evidence,
    generated_unix_ms: 6000L,
  }
  let pdf : @contractdoc.ContractGeneratedArtifact = {
    artifact_id: "contract-pdf-retry",
    media_type: "application/pdf",
    sha256: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    byte_count: 722000L,
    page_count: 18,
    render_evidence_sha256: evidence,
    generated_unix_ms: 6000L,
  }
  let generated = store.complete_generation(
    "packet-worker",
    retried.revision,
    docx,
    pdf,
    "contract-renderer",
    6000L,
  )
  let execution : @contractdoc.ContractExecution = {
    evidence_sha256: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    signed_on: "2026-08-14",
    registered_by: "operator-1",
    registered_unix_ms: 7000L,
  }
  let effective = store.register_execution(
    "packet-worker",
    generated.revision,
    execution,
    7000L,
  )
  assert_eq(effective.state, Effective)
  assert_eq(effective.execution, Some(execution))
  let events = store.snapshot().events
  assert_true(events.any(event => event.kind == GenerationFailedEvent))
  assert_true(events.any(event => event.kind == ExecutionRegisteredEvent))
  let reopened = ContractDocumentStore::open(path)
  assert_eq(reopened.packet("packet-worker"), Some(effective))
  @fs.remove(path)
}
