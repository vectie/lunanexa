///|
enum ContractPersistence {
  ContractFile(String)
  ContractPostgres(@database.PostgresDatabase)
}

///|
/// The v1 packet shape is retained only for deterministic on-open migration.
/// No migration code writes this representation.
struct LegacyContractPacketV1 {
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
} derive(FromJson)

///|
struct LegacyContractDocumentSnapshotV1 {
  schema_version : String
  packets : Array[LegacyContractPacketV1]
  events : Array[@contractdoc.ContractPacketEvent]
} derive(FromJson)

///|
/// The v2 packet shape is retained only for deterministic on-open migration.
/// It predates the full lifecycle: execution, closure, supersession, the
/// preceding-packet link, and the generation-failure reason all default to
/// `None` when migrating forward.
struct LegacyContractPacketV2 {
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
} derive(FromJson)

///|
struct LegacyContractDocumentSnapshotV2 {
  schema_version : String
  packets : Array[LegacyContractPacketV2]
  events : Array[@contractdoc.ContractPacketEvent]
} derive(FromJson)

///|
pub struct ContractDocumentStore {
  persistence : ContractPersistence
  mut packets : Map[String, @contractdoc.ContractPacket]
  mut idempotency_keys : Map[String, String]
  mut events : Array[@contractdoc.ContractPacketEvent]
  mutex : @async.Mutex
}

///|
fn ContractDocumentStore::empty(
  persistence : ContractPersistence,
) -> ContractDocumentStore {
  {
    persistence,
    packets: Map([]),
    idempotency_keys: Map([]),
    events: [],
    mutex: Mutex(),
  }
}

///|
fn sorted_packets(
  packets : Map[String, @contractdoc.ContractPacket],
) -> Array[@contractdoc.ContractPacket] {
  let pairs = packets.to_array()
  pairs.sort_by((left, right) => left.0.compare(right.0))
  pairs.map(pair => pair.1)
}

///|
fn ContractDocumentStore::snapshot_unlocked(
  self : ContractDocumentStore,
) -> @contractdoc.ContractDocumentSnapshot {
  {
    schema_version: @contractdoc.snapshot_schema_version,
    packets: sorted_packets(self.packets),
    events: self.events.copy(),
  }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : @contractdoc.ContractDocumentSnapshot,
) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
fn decode_snapshot(
  payload : String,
) -> @contractdoc.ContractDocumentSnapshot raise @contractdoc.ContractDocumentError {
  let document = @json.parse(payload) catch {
    _ => raise InvalidInput("invalid contract-document snapshot")
  }
  let snapshot : @contractdoc.ContractDocumentSnapshot = @json.from_json(
    document,
  ) catch {
    _ => return migrate_legacy_snapshot(document)
  }
  if snapshot.schema_version != @contractdoc.snapshot_schema_version {
    // Missing Option fields decode as `None`, so a legacy document can parse
    // as the current shape; the schema version decides which migration runs.
    return migrate_legacy_snapshot(document)
  }
  snapshot
}

///|
fn migrate_legacy_snapshot(
  document : Json,
) -> @contractdoc.ContractDocumentSnapshot raise @contractdoc.ContractDocumentError {
  let legacy : LegacyContractDocumentSnapshotV2 = @json.from_json(document) catch {
    _ => return migrate_legacy_v1_snapshot(document)
  }
  if legacy.schema_version != "lunanexa.contract-document.snapshot.v2" {
    raise InvalidInput("unsupported contract-document snapshot")
  }
  let packets : Array[@contractdoc.ContractPacket] = legacy.packets.map(packet => {
    packet_id: packet.packet_id,
    idempotency_key: packet.idempotency_key,
    template_id: packet.template_id,
    template_version: packet.template_version,
    template_sha256: packet.template_sha256,
    tenant_ref: packet.tenant_ref,
    organization_id: packet.organization_id,
    subject_ref: packet.subject_ref,
    order_ref: packet.order_ref,
    preceding_packet_ref: None,
    active_forms: packet.active_forms,
    values: packet.values,
    assignments: packet.assignments,
    values_sha256: packet.values_sha256,
    confirmed_by: packet.confirmed_by,
    confirmed_unix_ms: packet.confirmed_unix_ms,
    artifacts: packet.artifacts,
    state: packet.state,
    execution: None,
    closure: None,
    supersession: None,
    generation_failure: None,
    revision: packet.revision,
    created_unix_ms: packet.created_unix_ms,
    updated_unix_ms: packet.updated_unix_ms,
  })
  {
    schema_version: @contractdoc.snapshot_schema_version,
    packets,
    events: legacy.events,
  }
}

///|
fn migrate_legacy_v1_snapshot(
  document : Json,
) -> @contractdoc.ContractDocumentSnapshot raise @contractdoc.ContractDocumentError {
  let legacy : LegacyContractDocumentSnapshotV1 = @json.from_json(document) catch {
    _ => raise InvalidInput("invalid contract-document snapshot")
  }
  if legacy.schema_version != "lunanexa.contract-document.snapshot.v1" {
    raise InvalidInput("unsupported contract-document snapshot")
  }
  let packets : Array[@contractdoc.ContractPacket] = legacy.packets.map(packet => {
    let manifest = @contractdoc.manifest_for_template_id(packet.template_id)
    let assignments : Array[@contractdoc.ContractFieldAssignment] = packet.values.filter_map(value => {
        match manifest.field(value.field_id) {
          Some(definition) if definition.owner != OfflineParticipant =>
            Some({
              field_id: value.field_id,
              value: value.value,
              owner: definition.owner,
              source_ref: "legacy-contract-snapshot-v1",
              updated_by: packet.confirmed_by.unwrap_or(packet.subject_ref),
              updated_unix_ms: packet.updated_unix_ms,
            })
          _ => None
        }
      },
    )
    let migrated : @contractdoc.ContractPacket = {
      packet_id: packet.packet_id,
      idempotency_key: packet.idempotency_key,
      template_id: packet.template_id,
      template_version: packet.template_version,
      template_sha256: packet.template_sha256,
      tenant_ref: packet.tenant_ref,
      organization_id: packet.organization_id,
      subject_ref: packet.subject_ref,
      order_ref: packet.order_ref,
      preceding_packet_ref: None,
      active_forms: packet.active_forms,
      values: packet.values,
      assignments,
      values_sha256: packet.values_sha256,
      confirmed_by: packet.confirmed_by,
      confirmed_unix_ms: packet.confirmed_unix_ms,
      artifacts: packet.artifacts,
      state: packet.state,
      execution: None,
      closure: None,
      supersession: None,
      generation_failure: None,
      revision: packet.revision,
      created_unix_ms: packet.created_unix_ms,
      updated_unix_ms: packet.updated_unix_ms,
    }
    migrated
  })
  {
    schema_version: @contractdoc.snapshot_schema_version,
    packets,
    events: legacy.events,
  }
}

///|
fn ContractDocumentStore::restore(
  self : ContractDocumentStore,
  snapshot : @contractdoc.ContractDocumentSnapshot,
) -> Unit raise @contractdoc.ContractDocumentError {
  for packet in snapshot.packets {
    if self.packets.contains(packet.packet_id) ||
      self.idempotency_keys.contains(packet.idempotency_key) {
      raise InvalidInput("duplicate contract packet")
    }
    self.packets[packet.packet_id] = packet
    self.idempotency_keys[packet.idempotency_key] = packet.packet_id
  }
  let last_revision : Map[String, Int64] = Map([])
  for event in snapshot.events {
    if !self.packets.contains(event.packet_id) ||
      event.revision <= last_revision.get(event.packet_id).unwrap_or(0L) {
      raise InvalidInput("invalid contract packet event chain")
    }
    last_revision[event.packet_id] = event.revision
    self.events.push(event)
  }
}

///|
pub async fn ContractDocumentStore::open(
  path : String,
) -> ContractDocumentStore {
  if path.trim() == "" {
    raise @contractdoc.ContractDocumentError::InvalidInput(
      "contract-document store path is empty",
    )
  }
  let store = ContractDocumentStore::empty(ContractFile(path))
  if @fs.exists(path) {
    store.restore(decode_snapshot(@fs.read_file(path).text()))
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn ContractDocumentStore::open_postgres(
  database : @database.PostgresDatabase,
) -> ContractDocumentStore {
  let store = ContractDocumentStore::empty(ContractPostgres(database))
  match
    database.load_snapshot(
      "contract_documents", @contractdoc.snapshot_schema_version,
    ) {
    Some(payload) => store.restore(decode_snapshot(payload))
    None => ()
  }
  database.save_opaque_snapshot(
    "contract_documents",
    @contractdoc.snapshot_schema_version,
    store.snapshot_unlocked().to_json().stringify(),
  )
  store
}

///|
async fn ContractDocumentStore::persist(self : ContractDocumentStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    ContractFile(path) => write_snapshot(path, snapshot)
    ContractPostgres(database) =>
      database.save_opaque_snapshot(
        "contract_documents",
        @contractdoc.snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
fn event_for(
  packet : @contractdoc.ContractPacket,
  kind : @contractdoc.ContractPacketEventKind,
  actor_ref : String,
  changed_field_ids : Array[String],
  artifact_sha256 : String?,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacketEvent {
  {
    event_id: "contract-event-\{packet.packet_id}-\{packet.revision}",
    packet_id: packet.packet_id,
    revision: packet.revision,
    kind,
    actor_ref,
    changed_field_ids,
    values_sha256: packet.values_sha256,
    artifact_sha256,
    occurred_unix_ms: now_unix_ms,
  }
}

///|
pub async fn ContractDocumentStore::snapshot(
  self : ContractDocumentStore,
) -> @contractdoc.ContractDocumentSnapshot {
  self.mutex.acquire()
  let value = self.snapshot_unlocked()
  self.mutex.release()
  value
}

///|
pub async fn ContractDocumentStore::create_packet(
  self : ContractDocumentStore,
  packet : @contractdoc.ContractPacket,
  actor_ref : String,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_keys = self.idempotency_keys.copy()
  let before_events = self.events.copy()
  try {
    match self.idempotency_keys.get(packet.idempotency_key) {
      Some(packet_id) if self.packets.get(packet_id) == Some(packet) => {
        self.mutex.release()
        return packet
      }
      Some(_) =>
        raise @contractdoc.ContractDocumentError::IdempotencyConflict(
          packet.idempotency_key,
        )
      None => ()
    }
    if self.packets.contains(packet.packet_id) {
      raise @contractdoc.ContractDocumentError::AlreadyExists(packet.packet_id)
    }
    let needs_preceding = packet.active_forms.any(form => {
      @contractdoc.form_creation_stage(form) == EffectiveStage
    })
    if needs_preceding {
      guard packet.preceding_packet_ref is Some(preceding_ref) else {
        raise @contractdoc.ContractDocumentError::ContractNotEffective(
          "follow-up contract forms require a preceding packet",
        )
      }
      guard self.packets.get(preceding_ref) is Some(preceding) &&
        preceding.tenant_ref == packet.tenant_ref &&
        preceding.state == Effective else {
        raise @contractdoc.ContractDocumentError::ContractNotEffective(
          "preceding contract packet is not effective",
        )
      }
    }
    self.packets[packet.packet_id] = packet
    self.idempotency_keys[packet.idempotency_key] = packet.packet_id
    self.events.push(
      event_for(
        packet,
        PacketCreated,
        actor_ref,
        [],
        None,
        packet.created_unix_ms,
      ),
    )
    self.persist()
    self.mutex.release()
    packet
  } catch {
    error => {
      self.packets = before_packets
      self.idempotency_keys = before_keys
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Persists a renewal draft for an effective source packet, following the
/// same idempotency-key replay pattern as `create_packet`: a replayed key
/// returns the stored renewal when it points back at the same source, and
/// any other reuse conflicts. The manifest is resolved from the source
/// packet's persisted template id.
pub async fn ContractDocumentStore::renew_packet(
  self : ContractDocumentStore,
  source_packet_id : String,
  packet_id : String,
  idempotency_key : String,
  actor_ref : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_keys = self.idempotency_keys.copy()
  let before_events = self.events.copy()
  try {
    match self.idempotency_keys.get(idempotency_key) {
      Some(existing_id) =>
        match self.packets.get(existing_id) {
          Some(existing) if existing_id == packet_id &&
            existing.preceding_packet_ref == Some(source_packet_id) => {
            self.mutex.release()
            return existing
          }
          _ =>
            raise @contractdoc.ContractDocumentError::IdempotencyConflict(
              idempotency_key,
            )
        }
      None => ()
    }
    if self.packets.contains(packet_id) {
      raise @contractdoc.ContractDocumentError::AlreadyExists(packet_id)
    }
    guard self.packets.get(source_packet_id) is Some(source) else {
      raise @contractdoc.ContractDocumentError::NotFound("contract packet")
    }
    let renewal = source.renewal_draft(
      @contractdoc.manifest_for_template_id(source.template_id),
      packet_id,
      idempotency_key,
      now_unix_ms,
    )
    self.packets[renewal.packet_id] = renewal
    self.idempotency_keys[renewal.idempotency_key] = renewal.packet_id
    self.events.push(
      event_for(renewal, PacketCreated, actor_ref, [], None, now_unix_ms),
    )
    self.persist()
    self.mutex.release()
    renewal
  } catch {
    error => {
      self.packets = before_packets
      self.idempotency_keys = before_keys
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::packet(
  self : ContractDocumentStore,
  packet_id : String,
) -> @contractdoc.ContractPacket? {
  self.mutex.acquire()
  let value = self.packets.get(packet_id)
  self.mutex.release()
  value
}

///|
pub async fn ContractDocumentStore::packets_for_subject(
  self : ContractDocumentStore,
  subject_ref : String,
) -> Array[@contractdoc.ContractPacket] {
  self.mutex.acquire()
  let value = sorted_packets(self.packets).filter(packet => {
    packet.subject_ref == subject_ref
  })
  self.mutex.release()
  value
}

///|
pub async fn ContractDocumentStore::pending_generation_packets(
  self : ContractDocumentStore,
) -> Array[@contractdoc.ContractPacket] {
  self.mutex.acquire()
  let value = sorted_packets(self.packets).filter(packet => {
    packet.state == GenerationRequested
  })
  self.mutex.release()
  value
}

///|
pub async fn ContractDocumentStore::update_information(
  self : ContractDocumentStore,
  manifest : @contractdoc.ContractTemplateManifest,
  packet_id : String,
  expected_revision : Int64,
  changes : Array[@contractdoc.ContractFieldValue],
  actor_owner : @contractdoc.ContractFieldOwner,
  actor_ref : String,
  source_ref : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_events = self.events.copy()
  try {
    guard self.packets.get(packet_id) is Some(packet) else {
      raise @contractdoc.ContractDocumentError::NotFound("contract packet")
    }
    let updated = packet.update_information(
      manifest, expected_revision, changes, actor_owner, actor_ref, source_ref, now_unix_ms,
    )
    self.packets[packet_id] = updated
    self.events.push(
      event_for(
        updated,
        if actor_owner == PlatformDerived {
          SystemInformationSynchronized
        } else {
          InformationUpdated
        },
        actor_ref,
        changes.map(change => change.field_id),
        None,
        now_unix_ms,
      ),
    )
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.packets = before_packets
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::confirm_information(
  self : ContractDocumentStore,
  manifest : @contractdoc.ContractTemplateManifest,
  packet_id : String,
  expected_revision : Int64,
  values_sha256 : String,
  actor_ref : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_events = self.events.copy()
  try {
    guard self.packets.get(packet_id) is Some(packet) else {
      raise @contractdoc.ContractDocumentError::NotFound("contract packet")
    }
    let updated = packet.confirm_information(
      manifest, expected_revision, values_sha256, actor_ref, now_unix_ms,
    )
    self.packets[packet_id] = updated
    self.events.push(
      event_for(
        updated,
        InformationConfirmedEvent,
        actor_ref,
        [],
        None,
        now_unix_ms,
      ),
    )
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.packets = before_packets
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::request_generation(
  self : ContractDocumentStore,
  packet_id : String,
  expected_revision : Int64,
  expected_values_sha256 : String,
  actor_ref : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_events = self.events.copy()
  try {
    guard self.packets.get(packet_id) is Some(packet) else {
      raise @contractdoc.ContractDocumentError::NotFound("contract packet")
    }
    let updated = packet.request_generation(
      expected_revision, expected_values_sha256, now_unix_ms,
    )
    self.packets[packet_id] = updated
    self.events.push(
      event_for(
        updated,
        GenerationRequestedEvent,
        actor_ref,
        [],
        None,
        now_unix_ms,
      ),
    )
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.packets = before_packets
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::complete_generation(
  self : ContractDocumentStore,
  packet_id : String,
  expected_revision : Int64,
  docx : @contractdoc.ContractGeneratedArtifact,
  pdf : @contractdoc.ContractGeneratedArtifact,
  actor_ref : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_events = self.events.copy()
  try {
    guard self.packets.get(packet_id) is Some(packet) else {
      raise @contractdoc.ContractDocumentError::NotFound("contract packet")
    }
    let updated = packet.complete_generation(
      expected_revision, docx, pdf, now_unix_ms,
    )
    self.packets[packet_id] = updated
    self.events.push(
      event_for(
        updated,
        GenerationCompletedEvent,
        actor_ref,
        [],
        Some(pdf.sha256),
        now_unix_ms,
      ),
    )
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.packets = before_packets
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::fail_generation(
  self : ContractDocumentStore,
  packet_id : String,
  expected_revision : Int64,
  reason : String,
  worker_ref : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_events = self.events.copy()
  try {
    guard self.packets.get(packet_id) is Some(packet) else {
      raise @contractdoc.ContractDocumentError::NotFound("contract packet")
    }
    let updated = packet.fail_generation(expected_revision, reason, now_unix_ms)
    self.packets[packet_id] = updated
    self.events.push(
      event_for(
        updated,
        GenerationFailedEvent,
        worker_ref,
        [],
        None,
        now_unix_ms,
      ),
    )
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.packets = before_packets
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::register_execution(
  self : ContractDocumentStore,
  packet_id : String,
  expected_revision : Int64,
  evidence : @contractdoc.ContractExecution,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_events = self.events.copy()
  try {
    guard self.packets.get(packet_id) is Some(packet) else {
      raise @contractdoc.ContractDocumentError::NotFound("contract packet")
    }
    let updated = packet.register_execution(
      expected_revision, evidence, now_unix_ms,
    )
    self.packets[packet_id] = updated
    self.events.push(
      event_for(
        updated,
        ExecutionRegisteredEvent,
        evidence.registered_by,
        [],
        Some(evidence.evidence_sha256),
        now_unix_ms,
      ),
    )
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.packets = before_packets
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Early termination is only accepted once a settlement confirmation for the
/// same tenant has taken effect in another packet; a merely generated
/// settlement is unsigned and must not unlock closure.
pub async fn ContractDocumentStore::close_packet(
  self : ContractDocumentStore,
  packet_id : String,
  expected_revision : Int64,
  kind : @contractdoc.ContractClosureKind,
  reason : String,
  closed_by : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_events = self.events.copy()
  try {
    guard self.packets.get(packet_id) is Some(packet) else {
      raise @contractdoc.ContractDocumentError::NotFound("contract packet")
    }
    let settlement_confirmed = sorted_packets(self.packets).any(other => {
      other.packet_id != packet.packet_id &&
      other.tenant_ref == packet.tenant_ref &&
      other.active_forms.contains(SettlementConfirmation) &&
      (other.state == Effective || other.state == Closed)
    })
    let closure : @contractdoc.ContractClosure = {
      kind,
      reason,
      closed_by,
      closed_unix_ms: now_unix_ms,
    }
    let updated = packet.close_packet(
      expected_revision, closure, settlement_confirmed, now_unix_ms,
    )
    self.packets[packet_id] = updated
    self.events.push(
      event_for(updated, PacketClosedEvent, closed_by, [], None, now_unix_ms),
    )
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.packets = before_packets
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ContractDocumentStore::supersede_packet(
  self : ContractDocumentStore,
  packet_id : String,
  expected_revision : Int64,
  successor_ref : String,
  reason : String,
  superseded_by : String,
  now_unix_ms : Int64,
) -> @contractdoc.ContractPacket {
  self.mutex.acquire()
  let before_packets = self.packets.copy()
  let before_events = self.events.copy()
  try {
    guard self.packets.get(packet_id) is Some(packet) else {
      raise @contractdoc.ContractDocumentError::NotFound("contract packet")
    }
    guard self.packets.get(successor_ref) is Some(successor) else {
      raise @contractdoc.ContractDocumentError::NotFound(
        "successor contract packet",
      )
    }
    if successor.tenant_ref != packet.tenant_ref {
      raise @contractdoc.ContractDocumentError::InvalidInput(
        "contract successor belongs to another tenant",
      )
    }
    let supersession : @contractdoc.ContractSupersession = {
      successor_ref,
      reason,
      superseded_by,
      superseded_unix_ms: now_unix_ms,
    }
    let updated = packet.supersede_packet(
      expected_revision, supersession, now_unix_ms,
    )
    self.packets[packet_id] = updated
    self.events.push(
      event_for(
        updated,
        PacketSupersededEvent,
        superseded_by,
        [],
        None,
        now_unix_ms,
      ),
    )
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.packets = before_packets
      self.events = before_events
      self.mutex.release()
      raise error
    }
  }
}
