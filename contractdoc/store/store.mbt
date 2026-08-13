///|
enum ContractPersistence {
  ContractFile(String)
  ContractPostgres(@database.PostgresDatabase)
}

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
  let snapshot : @contractdoc.ContractDocumentSnapshot = @json.from_json(
    @json.parse(payload),
  ) catch {
    _ => raise InvalidInput("invalid contract-document snapshot")
  }
  if snapshot.schema_version != @contractdoc.snapshot_schema_version {
    raise InvalidInput("unsupported contract-document snapshot")
  }
  snapshot
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
    let updated = packet.update_information(
      manifest, expected_revision, changes, now_unix_ms,
    )
    self.packets[packet_id] = updated
    self.events.push(
      event_for(
        updated,
        InformationUpdated,
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
