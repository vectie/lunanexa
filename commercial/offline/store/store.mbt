///|
enum OfflinePersistence {
  OfflineFile(String)
  OfflinePostgres(@database.PostgresDatabase)
}

///|
pub struct OfflineCommerceStore {
  persistence : OfflinePersistence
  mut templates : Map[String, @offline.DocumentTemplate]
  mut orders : Map[String, @offline.CommercialOrder]
  mut order_keys : Map[String, String]
  mut artifacts : Map[String, @offline.DocumentArtifact]
  mut generation_requests : Map[String, @offline.ArtifactGenerationRequest]
  mut upload_grants : Map[String, @offline.EvidenceUploadGrant]
  mut upload_keys : Map[String, String]
  mut upload_callbacks : Map[String, @offline.EvidenceUploadCallback]
  mut reviews : Map[String, @offline.EvidenceReview]
  mut entitlement_activations : Map[String, @offline.EntitlementActivation]
  mut reversals : Map[String, @offline.CommercialReversal]
  mut reversal_recoveries : Map[String, @offline.ReversalRecovery]
  mut transfer_sessions : Map[String, @offline.OfflineTransferSession]
  mut transfer_evidence : Map[String, @offline.OfflineTransferEvidence]
  mut work_claims : Map[String, @offline.OfflineWorkClaim]
  mut worker_health : @offline.OfflineWorkerHealth
  mutex : @async.Mutex
}

///|
/// Exact persisted v1 shape retained for in-place upgrade migration.
priv struct OfflineCommerceSnapshotV1 {
  templates : Array[@offline.DocumentTemplate]
  orders : Array[@offline.CommercialOrder]
  artifacts : Array[@offline.DocumentArtifact]
  generation_requests : Array[@offline.ArtifactGenerationRequest]
  upload_grants : Array[@offline.EvidenceUploadGrant]
  upload_callbacks : Array[@offline.EvidenceUploadCallback]
  reviews : Array[@offline.EvidenceReview]
} derive(FromJson)

///|
/// Persisted v2 shape before opaque transfer sessions were introduced.
priv struct OfflineCommerceSnapshotV2 {
  templates : Array[@offline.DocumentTemplate]
  orders : Array[@offline.CommercialOrder]
  artifacts : Array[@offline.DocumentArtifact]
  generation_requests : Array[@offline.ArtifactGenerationRequest]
  upload_grants : Array[@offline.EvidenceUploadGrant]
  upload_callbacks : Array[@offline.EvidenceUploadCallback]
  reviews : Array[@offline.EvidenceReview]
  entitlement_activations : Array[@offline.EntitlementActivation]
  reversals : Array[@offline.CommercialReversal]
} derive(FromJson)

///|
/// Persisted v3 shape before durable worker claims and health evidence.
priv struct OfflineCommerceSnapshotV3 {
  templates : Array[@offline.DocumentTemplate]
  orders : Array[@offline.CommercialOrder]
  artifacts : Array[@offline.DocumentArtifact]
  generation_requests : Array[@offline.ArtifactGenerationRequest]
  upload_grants : Array[@offline.EvidenceUploadGrant]
  upload_callbacks : Array[@offline.EvidenceUploadCallback]
  reviews : Array[@offline.EvidenceReview]
  entitlement_activations : Array[@offline.EntitlementActivation]
  reversals : Array[@offline.CommercialReversal]
  transfer_sessions : Array[@offline.OfflineTransferSession]
} derive(FromJson)

///|
/// Persisted v4 shape before manual reversal recovery records.
priv struct OfflineCommerceSnapshotV4 {
  templates : Array[@offline.DocumentTemplate]
  orders : Array[@offline.CommercialOrder]
  artifacts : Array[@offline.DocumentArtifact]
  generation_requests : Array[@offline.ArtifactGenerationRequest]
  upload_grants : Array[@offline.EvidenceUploadGrant]
  upload_callbacks : Array[@offline.EvidenceUploadCallback]
  reviews : Array[@offline.EvidenceReview]
  entitlement_activations : Array[@offline.EntitlementActivation]
  reversals : Array[@offline.CommercialReversal]
  transfer_sessions : Array[@offline.OfflineTransferSession]
  transfer_evidence : Array[@offline.OfflineTransferEvidence]
  work_claims : Array[@offline.OfflineWorkClaim]
  worker_health : @offline.OfflineWorkerHealth
} derive(FromJson)

///|
fn decode_snapshot(
  payload : String,
) -> @offline.OfflineCommerceSnapshot raise @offline.OfflineCommerceError {
  let parsed = @json.parse(payload) catch {
    error =>
      raise InvalidInput("invalid offline-commerce snapshot: \{Repr(error)}")
  }
  let schema = match parsed {
    { "schema_version": String(value), .. } => value
    _ => raise InvalidInput("offline-commerce snapshot has no schema version")
  }
  if schema == @offline.snapshot_schema_version {
    @json.from_json(parsed) catch {
      error =>
        raise InvalidInput("invalid offline-commerce snapshot: \{Repr(error)}")
    }
  } else if schema == "lunanexa.offline-commerce.snapshot.v4" {
    let legacy : OfflineCommerceSnapshotV4 = @json.from_json(parsed) catch {
      error =>
        raise InvalidInput(
          "invalid v4 offline-commerce snapshot: \{Repr(error)}",
        )
    }
    {
      schema_version: @offline.snapshot_schema_version,
      templates: legacy.templates,
      orders: legacy.orders,
      artifacts: legacy.artifacts,
      generation_requests: legacy.generation_requests,
      upload_grants: legacy.upload_grants,
      upload_callbacks: legacy.upload_callbacks,
      reviews: legacy.reviews,
      entitlement_activations: legacy.entitlement_activations,
      reversals: legacy.reversals,
      reversal_recoveries: [],
      transfer_sessions: legacy.transfer_sessions,
      transfer_evidence: legacy.transfer_evidence,
      work_claims: legacy.work_claims,
      worker_health: legacy.worker_health,
    }
  } else if schema == "lunanexa.offline-commerce.snapshot.v3" {
    let legacy : OfflineCommerceSnapshotV3 = @json.from_json(parsed) catch {
      error =>
        raise InvalidInput(
          "invalid v3 offline-commerce snapshot: \{Repr(error)}",
        )
    }
    {
      schema_version: @offline.snapshot_schema_version,
      templates: legacy.templates,
      orders: legacy.orders,
      artifacts: legacy.artifacts,
      generation_requests: legacy.generation_requests,
      upload_grants: legacy.upload_grants,
      upload_callbacks: legacy.upload_callbacks,
      reviews: legacy.reviews,
      entitlement_activations: legacy.entitlement_activations,
      reversals: legacy.reversals,
      reversal_recoveries: [],
      transfer_sessions: legacy.transfer_sessions,
      transfer_evidence: [],
      work_claims: [],
      worker_health: @offline.empty_offline_worker_health(),
    }
  } else if schema == "lunanexa.offline-commerce.snapshot.v2" {
    let legacy : OfflineCommerceSnapshotV2 = @json.from_json(parsed) catch {
      error =>
        raise InvalidInput(
          "invalid v2 offline-commerce snapshot: \{Repr(error)}",
        )
    }
    {
      schema_version: @offline.snapshot_schema_version,
      templates: legacy.templates,
      orders: legacy.orders,
      artifacts: legacy.artifacts,
      generation_requests: legacy.generation_requests,
      upload_grants: legacy.upload_grants,
      upload_callbacks: legacy.upload_callbacks,
      reviews: legacy.reviews,
      entitlement_activations: legacy.entitlement_activations,
      reversals: legacy.reversals,
      reversal_recoveries: [],
      transfer_sessions: [],
      transfer_evidence: [],
      work_claims: [],
      worker_health: @offline.empty_offline_worker_health(),
    }
  } else if schema == "lunanexa.offline-commerce.snapshot.v1" {
    let legacy : OfflineCommerceSnapshotV1 = @json.from_json(parsed) catch {
      error =>
        raise InvalidInput(
          "invalid v1 offline-commerce snapshot: \{Repr(error)}",
        )
    }
    {
      schema_version: @offline.snapshot_schema_version,
      templates: legacy.templates,
      orders: legacy.orders,
      artifacts: legacy.artifacts,
      generation_requests: legacy.generation_requests,
      upload_grants: legacy.upload_grants,
      upload_callbacks: legacy.upload_callbacks,
      reviews: legacy.reviews,
      entitlement_activations: [],
      reversals: [],
      reversal_recoveries: [],
      transfer_sessions: [],
      transfer_evidence: [],
      work_claims: [],
      worker_health: @offline.empty_offline_worker_health(),
    }
  } else {
    raise InvalidInput("unsupported offline-commerce snapshot")
  }
}

///|
fn template_key(template_id : String, version : String) -> String {
  "\{template_id}@\{version}"
}

///|
fn scoped_key(organization_id : String, key : String) -> String {
  "\{organization_id}:\{key}"
}

///|
fn artifact_work_id(request_id : String) -> String {
  "artifact:\{request_id}"
}

///|
fn activation_work_id(activation_id : String) -> String {
  "activation:\{activation_id}"
}

///|
fn reversal_work_id(reversal_id : String) -> String {
  "reversal:\{reversal_id}"
}

///|
fn constant_time_string_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}

///|
fn same_order_intent(
  left : @offline.CommercialOrder,
  right : @offline.CommercialOrder,
) -> Bool {
  left.order_id == right.order_id &&
  left.idempotency_key == right.idempotency_key &&
  left.tenant_ref == right.tenant_ref &&
  left.organization_id == right.organization_id &&
  left.project_id == right.project_id &&
  left.purchaser_subject_ref == right.purchaser_subject_ref &&
  left.selected_service_code == right.selected_service_code &&
  left.selected_sla_code == right.selected_sla_code &&
  left.policy == right.policy &&
  left.expires_unix_ms == right.expires_unix_ms
}

///|
fn OfflineCommerceStore::empty(
  persistence : OfflinePersistence,
) -> OfflineCommerceStore {
  {
    persistence,
    templates: Map([]),
    orders: Map([]),
    order_keys: Map([]),
    artifacts: Map([]),
    generation_requests: Map([]),
    upload_grants: Map([]),
    upload_keys: Map([]),
    upload_callbacks: Map([]),
    reviews: Map([]),
    entitlement_activations: Map([]),
    reversals: Map([]),
    reversal_recoveries: Map([]),
    transfer_sessions: Map([]),
    transfer_evidence: Map([]),
    work_claims: Map([]),
    worker_health: @offline.empty_offline_worker_health(),
    mutex: Mutex(),
  }
}

///|
fn[T] sorted_values(values : Map[String, T]) -> Array[T] {
  let pairs = values.to_array()
  pairs.sort_by((left, right) => left.0.compare(right.0))
  pairs.map(pair => pair.1)
}

///|
fn OfflineCommerceStore::snapshot_unlocked(
  self : OfflineCommerceStore,
) -> @offline.OfflineCommerceSnapshot {
  {
    schema_version: @offline.snapshot_schema_version,
    templates: sorted_values(self.templates),
    orders: sorted_values(self.orders),
    artifacts: sorted_values(self.artifacts),
    generation_requests: sorted_values(self.generation_requests),
    upload_grants: sorted_values(self.upload_grants),
    upload_callbacks: sorted_values(self.upload_callbacks),
    reviews: sorted_values(self.reviews),
    entitlement_activations: sorted_values(self.entitlement_activations),
    reversals: sorted_values(self.reversals),
    reversal_recoveries: sorted_values(self.reversal_recoveries),
    transfer_sessions: sorted_values(self.transfer_sessions),
    transfer_evidence: sorted_values(self.transfer_evidence),
    work_claims: sorted_values(self.work_claims),
    worker_health: self.worker_health,
  }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : @offline.OfflineCommerceSnapshot,
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
fn OfflineCommerceStore::restore(
  self : OfflineCommerceStore,
  snapshot : @offline.OfflineCommerceSnapshot,
) -> Unit raise @offline.OfflineCommerceError {
  if snapshot.schema_version != @offline.snapshot_schema_version {
    raise InvalidInput("unsupported offline-commerce snapshot")
  }
  for template in snapshot.templates {
    @offline.validate_template(template)
    let key = template_key(template.template_id, template.version)
    if self.templates.contains(key) {
      raise InvalidInput("duplicate document template")
    }
    self.templates[key] = template
  }
  for order in snapshot.orders {
    @offline.validate_order(order)
    let key = scoped_key(order.organization_id, order.idempotency_key)
    if self.orders.contains(order.order_id) || self.order_keys.contains(key) {
      raise InvalidInput("duplicate commercial order")
    }
    self.orders[order.order_id] = order
    self.order_keys[key] = order.order_id
  }
  for artifact in snapshot.artifacts {
    self.validate_artifact_unlocked(artifact)
    if self.artifacts.contains(artifact.artifact_id) {
      raise InvalidInput("duplicate document artifact")
    }
    self.artifacts[artifact.artifact_id] = artifact
  }
  for request in snapshot.generation_requests {
    self.validate_generation_request_unlocked(request)
    if self.generation_requests.contains(request.request_id) {
      raise InvalidInput("duplicate generation request")
    }
    self.generation_requests[request.request_id] = request
  }
  for grant in snapshot.upload_grants {
    self.validate_upload_grant_unlocked(grant)
    let key = scoped_key(grant.organization_id, grant.idempotency_key)
    if self.upload_grants.contains(grant.grant_id) ||
      self.upload_keys.contains(key) {
      raise InvalidInput("duplicate upload grant")
    }
    self.upload_grants[grant.grant_id] = grant
    self.upload_keys[key] = grant.grant_id
  }
  for callback in snapshot.upload_callbacks {
    if self.upload_callbacks.contains(callback.callback_id) ||
      !self.upload_grants.contains(callback.grant_id) {
      raise InvalidInput("invalid upload callback")
    }
    self.upload_callbacks[callback.callback_id] = callback
  }
  for review in snapshot.reviews {
    if self.reviews.contains(review.review_id) ||
      !self.artifacts.contains(review.artifact_id) {
      raise InvalidInput("invalid evidence review")
    }
    self.reviews[review.review_id] = review
  }
  for activation in snapshot.entitlement_activations {
    @offline.validate_activation(activation)
    if self.entitlement_activations.contains(activation.activation_id) ||
      !self.orders.contains(activation.order_id) {
      raise InvalidInput("invalid entitlement activation")
    }
    self.entitlement_activations[activation.activation_id] = activation
  }
  for reversal in snapshot.reversals {
    @offline.validate_reversal(reversal)
    if self.reversals.contains(reversal.reversal_id) ||
      !self.orders.contains(reversal.order_id) {
      raise InvalidInput("invalid commercial reversal")
    }
    self.reversals[reversal.reversal_id] = reversal
  }
  for recovery in snapshot.reversal_recoveries {
    @offline.validate_reversal_recovery(recovery)
    if self.reversal_recoveries.contains(recovery.recovery_id) ||
      !self.orders.contains(recovery.order_id) ||
      !self.reversals.contains(recovery.failed_reversal_id) {
      raise InvalidInput("invalid commercial reversal recovery")
    }
    self.reversal_recoveries[recovery.recovery_id] = recovery
  }
  for session in snapshot.transfer_sessions {
    @offline.validate_transfer_session(session)
    if self.transfer_sessions.contains(session.session_id) ||
      !self.orders.contains(session.order_id) ||
      (
        session.direction == DownloadTransfer &&
        !self.artifacts.contains(session.artifact_id)
      ) {
      raise InvalidInput("invalid offline transfer session")
    }
    self.transfer_sessions[session.session_id] = session
  }
  for evidence in snapshot.transfer_evidence {
    guard self.transfer_sessions.get(evidence.session_id) is Some(session) else {
      raise InvalidInput("transfer evidence has no session")
    }
    if session.state != TransferConsumed ||
      !session.media_types.contains(evidence.media_type) ||
      evidence.byte_count <= 0L ||
      evidence.byte_count > session.maximum_byte_count ||
      !@offline.valid_sha256(evidence.sha256) ||
      session.expected_sha256.map_or(false, digest => digest != evidence.sha256) ||
      !@contracts.valid_identifier(
        evidence.provider_receipt,
        maximum_length=512,
      ) ||
      session.consumed_unix_ms != Some(evidence.completed_unix_ms) ||
      self.transfer_evidence.contains(evidence.session_id) {
      raise InvalidInput("invalid transfer completion evidence")
    }
    self.transfer_evidence[evidence.session_id] = evidence
  }
  for claim in snapshot.work_claims {
    if !@contracts.valid_identifier(claim.work_id) ||
      claim.expected_order_generation <= 0L ||
      claim.attempt < 0 ||
      claim.attempt > 5 ||
      claim.claimed_unix_ms <= 0L ||
      (claim.attempt > 0 && claim.retry_after_unix_ms <= claim.claimed_unix_ms) ||
      claim.completed_unix_ms.map_or(false, value => {
        value < claim.claimed_unix_ms
      }) ||
      self.work_claims.contains(claim.work_id) {
      raise InvalidInput("invalid offline work claim")
    }
    self.work_claims[claim.work_id] = claim
  }
  let health = snapshot.worker_health
  let health_times = [
    health.artifact_dispatcher_heartbeat_unix_ms,
    health.artifact_dispatcher_success_unix_ms,
    health.entitlement_dispatcher_heartbeat_unix_ms,
    health.entitlement_dispatcher_success_unix_ms,
    health.reconciler_attempt_unix_ms,
    health.reconciler_success_unix_ms,
  ]
  if health_times.any(value => value.map_or(false, time => time <= 0L)) ||
    health.reconciler_failure_code.map_or(false, value => {
      !@contracts.valid_identifier(value)
    }) {
    raise InvalidInput("invalid offline worker health")
  }
  self.worker_health = health
}

///|
pub async fn OfflineCommerceStore::open(path : String) -> OfflineCommerceStore {
  if path.trim() == "" {
    raise @offline.OfflineCommerceError::InvalidInput(
      "offline-commerce store path is empty",
    )
  }
  let store = OfflineCommerceStore::empty(OfflineFile(path))
  if @fs.exists(path) {
    let snapshot = decode_snapshot(@fs.read_file(path).text())
    store.restore(snapshot)
    if snapshot.schema_version == @offline.snapshot_schema_version {
      write_snapshot(path, store.snapshot_unlocked())
    }
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn OfflineCommerceStore::open_postgres(
  database : @database.PostgresDatabase,
) -> OfflineCommerceStore {
  let store = OfflineCommerceStore::empty(OfflinePostgres(database))
  let payload = try
    database.load_snapshot("offline_commerce", @offline.snapshot_schema_version)
  catch {
    @database.DatabaseError::UnsupportedSnapshot(_) =>
      database.load_snapshot(
        "offline_commerce", "lunanexa.offline-commerce.snapshot.v3",
      ) catch {
        @database.DatabaseError::UnsupportedSnapshot(_) =>
          database.load_snapshot(
            "offline_commerce", "lunanexa.offline-commerce.snapshot.v2",
          ) catch {
            @database.DatabaseError::UnsupportedSnapshot(_) =>
              database.load_snapshot(
                "offline_commerce", "lunanexa.offline-commerce.snapshot.v1",
              )
            error => raise error
          }
        error => raise error
      }
    error => raise error
  } noraise {
    value => value
  }
  match payload {
    Some(payload) => {
      let snapshot = decode_snapshot(payload)
      store.restore(snapshot)
      database.save_opaque_snapshot(
        "offline_commerce",
        @offline.snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
    }
    None =>
      database.save_opaque_snapshot(
        "offline_commerce",
        @offline.snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
  }
  store
}

///|
async fn OfflineCommerceStore::persist(self : OfflineCommerceStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    OfflineFile(path) => write_snapshot(path, snapshot)
    OfflinePostgres(database) =>
      database.save_opaque_snapshot(
        "offline_commerce",
        @offline.snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
fn OfflineCommerceStore::require_order_unlocked(
  self : OfflineCommerceStore,
  order_id : String,
) -> @offline.CommercialOrder raise @offline.OfflineCommerceError {
  match self.orders.get(order_id) {
    Some(order) => order
    None => raise NotFound("commercial order")
  }
}

///|
fn with_artifact_id(
  order : @offline.CommercialOrder,
  artifact_id : String,
  now_unix_ms : Int64,
) -> @offline.CommercialOrder {
  if order.artifact_ids.contains(artifact_id) {
    order
  } else {
    {
      ..order,
      artifact_ids: order.artifact_ids + [artifact_id],
      generation: order.generation + 1L,
      updated_unix_ms: now_unix_ms,
    }
  }
}

///|
fn OfflineCommerceStore::validate_artifact_unlocked(
  self : OfflineCommerceStore,
  artifact : @offline.DocumentArtifact,
) -> Unit raise @offline.OfflineCommerceError {
  guard self.orders.get(artifact.order_id) is Some(order) else {
    raise NotFound("artifact order")
  }
  if artifact.organization_id != order.organization_id {
    raise TenantMismatch
  }
  if !@contracts.valid_identifier(artifact.artifact_id) ||
    artifact.revision <= 0 ||
    !@contracts.valid_identifier(artifact.locale) ||
    !@offline.expected_media_type(artifact.kind).contains(artifact.media_type) ||
    artifact.byte_count <= 0L ||
    artifact.byte_count > 100000000L ||
    !@offline.valid_sha256(artifact.sha256) ||
    !@offline.valid_object_ref(artifact.object_ref) ||
    !@contracts.valid_identifier(artifact.submitted_by) ||
    !@contracts.valid_identifier(artifact.creator_receipt) ||
    artifact.created_unix_ms <= 0L {
    raise InvalidInput("invalid document artifact")
  }
  if artifact.scan_state != ScanPassed &&
    artifact.review_state == ReviewAccepted {
    raise InvalidInput("unscanned artifact cannot be accepted")
  }
}

///|
fn OfflineCommerceStore::validate_generation_request_unlocked(
  self : OfflineCommerceStore,
  request : @offline.ArtifactGenerationRequest,
) -> Unit raise @offline.OfflineCommerceError {
  guard self.orders.get(request.order_id) is Some(order) else {
    raise NotFound("generation order")
  }
  guard self.templates.get(
      template_key(request.template_id, request.template_version),
    )
    is Some(template) else {
    raise NotFound("document template")
  }
  let kind_matches = match request.kind {
    EditableContractDocx | PrintReadyContractPdf =>
      template.kind == ContractTemplate
    QuoteScheduleXlsx => template.kind == QuoteScheduleTemplate
    _ => false
  }
  guard order.quote is Some(quote) else {
    raise InvalidTransition("generation order has no immutable quote")
  }
  if request.organization_id != order.organization_id ||
    !kind_matches ||
    request.input_snapshot_sha256 != quote.terms_digest ||
    !@contracts.valid_identifier(request.request_id) ||
    !@contracts.valid_identifier(request.artifact_id) ||
    !@offline.valid_object_ref(request.expected_object_ref) ||
    !@offline.valid_sha256(request.input_snapshot_sha256) ||
    !@contracts.valid_identifier(request.requested_by) ||
    request.requested_unix_ms < order.created_unix_ms {
    raise InvalidInput("invalid artifact generation request")
  }
}

///|
fn OfflineCommerceStore::validate_upload_grant_unlocked(
  self : OfflineCommerceStore,
  grant : @offline.EvidenceUploadGrant,
) -> Unit raise @offline.OfflineCommerceError {
  guard self.orders.get(grant.order_id) is Some(order) else {
    raise NotFound("upload order")
  }
  if grant.organization_id != order.organization_id ||
    @offline.evidence_kind(grant.kind) is None ||
    !@contracts.valid_identifier(grant.grant_id) ||
    !@contracts.valid_identifier(grant.idempotency_key) ||
    !@contracts.valid_identifier(grant.subject_ref) ||
    !@contracts.valid_identifier(grant.artifact_id) ||
    grant.revision <= 0 ||
    !@offline.valid_object_ref(grant.expected_object_ref) ||
    grant.allowed_media_types.length() == 0 ||
    grant.allowed_media_types.any(value => {
      !@offline.expected_media_type(grant.kind).contains(value)
    }) ||
    grant.maximum_byte_count <= 0L ||
    grant.maximum_byte_count > 100000000L ||
    grant.created_unix_ms <= 0L ||
    grant.expires_unix_ms <= grant.created_unix_ms ||
    grant.expires_unix_ms > grant.created_unix_ms + 3600000L {
    raise InvalidInput("invalid evidence upload grant")
  }
}

///|
pub async fn OfflineCommerceStore::register_template(
  self : OfflineCommerceStore,
  template : @offline.DocumentTemplate,
) -> @offline.DocumentTemplate {
  @offline.validate_template(template)
  self.mutex.acquire()
  let before = self.templates.copy()
  try {
    let key = template_key(template.template_id, template.version)
    match self.templates.get(key) {
      Some(existing) if existing == template => {
        self.mutex.release()
        return existing
      }
      Some(_) => raise @offline.OfflineCommerceError::IdempotencyConflict(key)
      None => ()
    }
    self.templates[key] = template
    self.persist()
    self.mutex.release()
    template
  } catch {
    error => {
      self.templates = before
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::create_order(
  self : OfflineCommerceStore,
  order : @offline.CommercialOrder,
) -> @offline.CommercialOrder {
  @offline.validate_order(order)
  if order.state != Draft ||
    order.quote is Some(_) ||
    order.artifact_ids.length() != 0 ||
    order.entitlement_ref is Some(_) {
    raise @offline.OfflineCommerceError::InvalidInput(
      "new order must be an empty draft",
    )
  }
  self.mutex.acquire()
  let before_orders = self.orders.copy()
  let before_keys = self.order_keys.copy()
  try {
    let key = scoped_key(order.organization_id, order.idempotency_key)
    match self.order_keys.get(key) {
      Some(existing_id) => {
        guard self.orders.get(existing_id) is Some(existing) else {
          raise @offline.OfflineCommerceError::InvalidInput(
            "broken order idempotency index",
          )
        }
        if existing == order ||
          (existing.state == Draft && same_order_intent(existing, order)) {
          self.mutex.release()
          return existing
        }
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          order.idempotency_key,
        )
      }
      None => ()
    }
    if self.orders.contains(order.order_id) {
      raise @offline.OfflineCommerceError::AlreadyExists(order.order_id)
    }
    self.orders[order.order_id] = order
    self.order_keys[key] = order.order_id
    self.persist()
    self.mutex.release()
    order
  } catch {
    error => {
      self.orders = before_orders
      self.order_keys = before_keys
      self.mutex.release()
      raise error
    }
  }
}

///|
async fn OfflineCommerceStore::replace_order(
  self : OfflineCommerceStore,
  order_id : String,
  transform : (@offline.CommercialOrder) -> @offline.CommercialOrder raise,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  let before = self.orders.copy()
  try {
    let updated = transform(self.require_order_unlocked(order_id))
    @offline.validate_order(updated)
    self.orders[order_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.orders = before
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::quote_order(
  self : OfflineCommerceStore,
  order_id : String,
  quote : @offline.ImmutableQuote,
  actor_ref : String,
  now_unix_ms : Int64,
) -> @offline.CommercialOrder {
  self.replace_order(order_id, order => {
    order.with_quote(quote, actor_ref, now_unix_ms)
  })
}

///|
pub async fn OfflineCommerceStore::begin_offline_execution(
  self : OfflineCommerceStore,
  order_id : String,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> @offline.CommercialOrder {
  self.replace_order(order_id, order => {
    order.begin_offline_execution(expected_generation, now_unix_ms)
  })
}

///|
pub async fn OfflineCommerceStore::request_generation(
  self : OfflineCommerceStore,
  request : @offline.ArtifactGenerationRequest,
) -> @offline.ArtifactGenerationRequest {
  self.mutex.acquire()
  let before = self.generation_requests.copy()
  let before_claims = self.work_claims.copy()
  try {
    self.validate_generation_request_unlocked(request)
    let order = self.require_order_unlocked(request.order_id)
    if order.state != PendingInternalApproval &&
      order.state != PendingOfflineExecution {
      raise @offline.OfflineCommerceError::InvalidTransition(
        "order is not accepting document generation",
      )
    }
    match self.generation_requests.get(request.request_id) {
      Some(existing) if existing == request => {
        self.mutex.release()
        return existing
      }
      Some(_) =>
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          request.request_id,
        )
      None => ()
    }
    if self.artifacts.contains(request.artifact_id) {
      raise @offline.OfflineCommerceError::AlreadyExists(request.artifact_id)
    }
    self.generation_requests[request.request_id] = request
    self.work_claims[artifact_work_id(request.request_id)] = {
      work_id: artifact_work_id(request.request_id),
      worker_kind: ArtifactDispatcher,
      expected_order_generation: order.generation,
      attempt: 0,
      claimed_unix_ms: request.requested_unix_ms,
      retry_after_unix_ms: request.requested_unix_ms,
      completed_unix_ms: None,
    }
    self.persist()
    self.mutex.release()
    request
  } catch {
    error => {
      self.generation_requests = before
      self.work_claims = before_claims
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::complete_generation(
  self : OfflineCommerceStore,
  result : @offline.ArtifactGenerationResult,
) -> @offline.DocumentArtifact {
  self.mutex.acquire()
  let before_artifacts = self.artifacts.copy()
  let before_orders = self.orders.copy()
  let before_claims = self.work_claims.copy()
  let before_health = self.worker_health
  try {
    guard self.generation_requests.get(result.request_id) is Some(request) else {
      raise @offline.OfflineCommerceError::NotFound("generation request")
    }
    guard self.orders.get(request.order_id) is Some(order) else {
      raise @offline.OfflineCommerceError::NotFound("generation order")
    }
    guard self.work_claims.get(artifact_work_id(request.request_id))
      is Some(claim) else {
      raise @offline.OfflineCommerceError::InvalidInput(
        "generation request has no durable order binding",
      )
    }
    if claim.completed_unix_ms is Some(completed_unix_ms) {
      guard self.artifacts.get(request.artifact_id) is Some(existing) &&
        result.verified &&
        !result.active_content_detected &&
        result.render_verified &&
        @offline.valid_sha256(result.visual_evidence_sha256) &&
        result.artifact_id == request.artifact_id &&
        result.expected_object_ref == request.expected_object_ref &&
        result.media_type == existing.media_type &&
        existing.sha256 == result.sha256 &&
        existing.byte_count == result.byte_count &&
        existing.creator_receipt == result.worker_receipt &&
        completed_unix_ms == result.completed_unix_ms else {
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          result.request_id,
        )
      }
      self.mutex.release()
      return existing
    }
    if claim.worker_kind != ArtifactDispatcher ||
      claim.attempt <= 0 ||
      order.generation != claim.expected_order_generation {
      raise @offline.OfflineCommerceError::StaleGeneration
    }
    if !result.verified ||
      result.active_content_detected ||
      !result.render_verified ||
      result.formula_error_count < 0 ||
      !@offline.valid_sha256(result.visual_evidence_sha256) ||
      result.artifact_id != request.artifact_id ||
      result.expected_object_ref != request.expected_object_ref ||
      !@offline.expected_media_type(request.kind).contains(result.media_type) ||
      result.byte_count <= 0L ||
      result.byte_count > 100000000L ||
      !@offline.valid_sha256(result.sha256) ||
      !@contracts.valid_identifier(result.worker_receipt) ||
      result.completed_unix_ms < request.requested_unix_ms {
      raise @offline.OfflineCommerceError::ArtifactUnavailable(
        "artifact worker result failed verification",
      )
    }
    if (
        request.kind == EditableContractDocx ||
        request.kind == QuoteScheduleXlsx
      ) &&
      !result.moonleaf_verified {
      raise @offline.OfflineCommerceError::ArtifactUnavailable(
        "OOXML artifact did not pass MoonLeaf reopen verification",
      )
    }
    if request.kind == QuoteScheduleXlsx && result.formula_error_count != 0 {
      raise @offline.OfflineCommerceError::ArtifactUnavailable(
        "XLSX artifact contains formula errors",
      )
    }
    let artifact : @offline.DocumentArtifact = {
      artifact_id: request.artifact_id,
      order_id: request.order_id,
      organization_id: request.organization_id,
      kind: request.kind,
      revision: 1,
      template_id: Some(request.template_id),
      template_version: Some(request.template_version),
      locale: request.locale,
      media_type: result.media_type,
      byte_count: result.byte_count,
      sha256: result.sha256,
      object_ref: request.expected_object_ref,
      generation_state: ArtifactGenerated,
      scan_state: ScanPassed,
      review_state: ReviewNotRequired,
      submitted_by: request.requested_by,
      creator_receipt: result.worker_receipt,
      created_unix_ms: result.completed_unix_ms,
    }
    self.validate_artifact_unlocked(artifact)
    match self.artifacts.get(artifact.artifact_id) {
      Some(existing) if existing == artifact => {
        self.mutex.release()
        return existing
      }
      Some(_) =>
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          artifact.artifact_id,
        )
      None => ()
    }
    self.artifacts[artifact.artifact_id] = artifact
    self.orders[order.order_id] = with_artifact_id(
      order,
      artifact.artifact_id,
      result.completed_unix_ms,
    )
    self.work_claims[claim.work_id] = {
      ..claim,
      completed_unix_ms: Some(result.completed_unix_ms),
    }
    self.worker_health = {
      ..self.worker_health,
      artifact_dispatcher_success_unix_ms: Some(result.completed_unix_ms),
    }
    self.persist()
    self.mutex.release()
    artifact
  } catch {
    error => {
      self.artifacts = before_artifacts
      self.orders = before_orders
      self.work_claims = before_claims
      self.worker_health = before_health
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::release_offline_packet(
  self : OfflineCommerceStore,
  order_id : String,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> @offline.CommercialOrder {
  self.replace_order(order_id, order => {
    let has_pdf = order.artifact_ids.any(id => {
      self.artifacts
      .get(id)
      .map_or(false, artifact => {
        artifact.kind == PrintReadyContractPdf &&
        artifact.scan_state == ScanPassed
      })
    })
    if !has_pdf {
      raise @offline.OfflineCommerceError::ArtifactUnavailable(
        "print-ready contract PDF is unavailable",
      )
    }
    order.release_offline_packet(expected_generation, now_unix_ms)
  })
}

///|
pub async fn OfflineCommerceStore::grant_upload(
  self : OfflineCommerceStore,
  grant : @offline.EvidenceUploadGrant,
) -> @offline.EvidenceUploadGrant {
  self.mutex.acquire()
  let before_grants = self.upload_grants.copy()
  let before_keys = self.upload_keys.copy()
  try {
    self.validate_upload_grant_unlocked(grant)
    let order = self.require_order_unlocked(grant.order_id)
    if order.state != PendingEvidenceUpload &&
      order.state != NeedsCorrection &&
      order.state != PendingInternalApproval {
      raise @offline.OfflineCommerceError::InvalidTransition(
        "order is not accepting offline evidence",
      )
    }
    if grant.state != UploadGranted {
      raise @offline.OfflineCommerceError::InvalidInput(
        "new upload grant has invalid state",
      )
    }
    let key = scoped_key(grant.organization_id, grant.idempotency_key)
    match self.upload_keys.get(key) {
      Some(existing_id) => {
        guard self.upload_grants.get(existing_id) is Some(existing) else {
          raise @offline.OfflineCommerceError::InvalidInput(
            "broken upload idempotency index",
          )
        }
        if existing == grant {
          self.mutex.release()
          return existing
        }
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          grant.idempotency_key,
        )
      }
      None => ()
    }
    if self.upload_grants.contains(grant.grant_id) ||
      self.artifacts.contains(grant.artifact_id) {
      raise @offline.OfflineCommerceError::AlreadyExists(grant.grant_id)
    }
    self.upload_grants[grant.grant_id] = grant
    self.upload_keys[key] = grant.grant_id
    self.persist()
    self.mutex.release()
    grant
  } catch {
    error => {
      self.upload_grants = before_grants
      self.upload_keys = before_keys
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::complete_upload(
  self : OfflineCommerceStore,
  callback : @offline.EvidenceUploadCallback,
) -> @offline.DocumentArtifact {
  self.mutex.acquire()
  let before_grants = self.upload_grants.copy()
  let before_callbacks = self.upload_callbacks.copy()
  let before_artifacts = self.artifacts.copy()
  let before_orders = self.orders.copy()
  try {
    guard self.upload_grants.get(callback.grant_id) is Some(grant) else {
      raise @offline.OfflineCommerceError::NotFound("upload grant")
    }
    match self.upload_callbacks.get(callback.callback_id) {
      Some(existing) if existing == callback => {
        guard self.artifacts.get(grant.artifact_id) is Some(artifact) else {
          raise @offline.OfflineCommerceError::InvalidInput(
            "callback artifact is missing",
          )
        }
        self.mutex.release()
        return artifact
      }
      Some(_) =>
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          callback.callback_id,
        )
      None => ()
    }
    if grant.state != UploadGranted ||
      callback.completed_unix_ms < grant.created_unix_ms ||
      callback.completed_unix_ms > grant.expires_unix_ms ||
      callback.expected_object_ref != grant.expected_object_ref ||
      !grant.allowed_media_types.contains(callback.media_type) ||
      callback.byte_count <= 0L ||
      callback.byte_count > grant.maximum_byte_count ||
      !@offline.valid_sha256(callback.sha256) ||
      !@contracts.valid_identifier(callback.callback_id) ||
      !@contracts.valid_identifier(callback.scanner_receipt) ||
      !callback.verified {
      raise @offline.OfflineCommerceError::ArtifactUnavailable(
        "upload callback failed grant verification",
      )
    }
    let accepted_scan = callback.scan_passed &&
      !callback.active_content_detected
    let artifact : @offline.DocumentArtifact = {
      artifact_id: grant.artifact_id,
      order_id: grant.order_id,
      organization_id: grant.organization_id,
      kind: grant.kind,
      revision: grant.revision,
      template_id: None,
      template_version: None,
      locale: "und",
      media_type: callback.media_type,
      byte_count: callback.byte_count,
      sha256: callback.sha256,
      object_ref: grant.expected_object_ref,
      generation_state: UserUploaded,
      scan_state: if accepted_scan {
        ScanPassed
      } else {
        ScanRejected
      },
      review_state: if accepted_scan {
        AwaitingReview
      } else {
        ReviewRejected
      },
      submitted_by: grant.subject_ref,
      creator_receipt: callback.scanner_receipt,
      created_unix_ms: callback.completed_unix_ms,
    }
    self.validate_artifact_unlocked(artifact)
    self.artifacts[artifact.artifact_id] = artifact
    self.upload_callbacks[callback.callback_id] = callback
    self.upload_grants[grant.grant_id] = {
      ..grant,
      state: if accepted_scan {
        UploadCompleted
      } else {
        UploadRejected
      },
    }
    let updated_order = with_artifact_id(
      self.require_order_unlocked(grant.order_id),
      artifact.artifact_id,
      callback.completed_unix_ms,
    )
    self.orders[grant.order_id] = if accepted_scan &&
      (
        updated_order.state == PendingEvidenceUpload ||
        updated_order.state == NeedsCorrection
      ) {
      updated_order.mark_reconciling(
        updated_order.generation,
        callback.completed_unix_ms,
      )
    } else if !accepted_scan && updated_order.state != PendingInternalApproval {
      {
        ..updated_order,
        state: NeedsCorrection,
        generation: updated_order.generation + 1L,
      }
    } else {
      updated_order
    }
    self.persist()
    self.mutex.release()
    artifact
  } catch {
    error => {
      self.upload_grants = before_grants
      self.upload_callbacks = before_callbacks
      self.artifacts = before_artifacts
      self.orders = before_orders
      self.mutex.release()
      raise error
    }
  }
}

///|
fn OfflineCommerceStore::accepted_evidence_unlocked(
  self : OfflineCommerceStore,
  order : @offline.CommercialOrder,
) -> Array[@offline.OfflineEvidenceKind] {
  let accepted = []
  for artifact_id in order.artifact_ids {
    match self.artifacts.get(artifact_id) {
      Some(artifact) if artifact.scan_state == ScanPassed &&
        artifact.review_state == ReviewAccepted =>
        match @offline.evidence_kind(artifact.kind) {
          Some(kind) => if !accepted.contains(kind) { accepted.push(kind) }
          None => ()
        }
      _ => ()
    }
  }
  accepted
}

///|
pub async fn OfflineCommerceStore::review_evidence(
  self : OfflineCommerceStore,
  review : @offline.EvidenceReview,
) -> @offline.DocumentArtifact {
  self.mutex.acquire()
  let before_reviews = self.reviews.copy()
  let before_artifacts = self.artifacts.copy()
  let before_orders = self.orders.copy()
  try {
    match self.reviews.get(review.review_id) {
      Some(existing) if existing == review => {
        guard self.artifacts.get(review.artifact_id) is Some(artifact) else {
          raise @offline.OfflineCommerceError::NotFound("review artifact")
        }
        self.mutex.release()
        return artifact
      }
      Some(_) =>
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          review.review_id,
        )
      None => ()
    }
    guard self.artifacts.get(review.artifact_id) is Some(artifact) else {
      raise @offline.OfflineCommerceError::NotFound("review artifact")
    }
    guard self.orders.get(review.order_id) is Some(order) else {
      raise @offline.OfflineCommerceError::NotFound("review order")
    }
    if artifact.order_id != order.order_id ||
      artifact.sha256 != review.expected_artifact_sha256 ||
      artifact.scan_state != ScanPassed ||
      artifact.review_state != AwaitingReview ||
      !@contracts.valid_identifier(review.review_id) ||
      !@contracts.valid_identifier(review.reviewer_ref) ||
      !@contracts.valid_identifier(review.reason_code) ||
      !@contracts.valid_identifier(review.audit_receipt) ||
      review.reviewed_unix_ms < artifact.created_unix_ms {
      raise @offline.OfflineCommerceError::InvalidInput(
        "invalid evidence review",
      )
    }
    if artifact.submitted_by == review.reviewer_ref {
      raise @offline.OfflineCommerceError::SeparationOfDuties
    }
    let updated_artifact = {
      ..artifact,
      review_state: if review.accepted {
        ReviewAccepted
      } else {
        ReviewRejected
      },
    }
    self.artifacts[artifact.artifact_id] = updated_artifact
    self.reviews[review.review_id] = review
    let updated_order = if !review.accepted {
      {
        ..order,
        state: NeedsCorrection,
        generation: order.generation + 1L,
        updated_unix_ms: review.reviewed_unix_ms,
      }
    } else if order.state == PendingInternalApproval &&
      @offline.evidence_kind(artifact.kind) == Some(InternalApproval) {
      {
        ..order,
        state: PendingOfflineExecution,
        generation: order.generation + 1L,
        updated_unix_ms: review.reviewed_unix_ms,
      }
    } else {
      {
        ..order,
        generation: order.generation + 1L,
        updated_unix_ms: review.reviewed_unix_ms,
      }
    }
    self.orders[order.order_id] = updated_order
    self.persist()
    self.mutex.release()
    updated_artifact
  } catch {
    error => {
      self.reviews = before_reviews
      self.artifacts = before_artifacts
      self.orders = before_orders
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::fulfill(
  self : OfflineCommerceStore,
  order_id : String,
  expected_generation : Int64,
  activation : @offline.EntitlementActivation,
  now_unix_ms : Int64,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  let before_orders = self.orders.copy()
  let before_activations = self.entitlement_activations.copy()
  try {
    let order = self.require_order_unlocked(order_id)
    @offline.validate_activation(activation)
    if activation.order_id != order.order_id ||
      activation.organization_id != order.organization_id ||
      activation.purchaser_subject_ref != order.purchaser_subject_ref ||
      activation.expected_order_generation != expected_generation ||
      activation.state != EntitlementActivationRequested {
      raise @offline.OfflineCommerceError::InvalidInput(
        "entitlement activation is not bound to the order",
      )
    }
    match self.entitlement_activations.get(activation.activation_id) {
      Some(existing) if existing == activation => {
        self.mutex.release()
        return order
      }
      Some(_) =>
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          activation.activation_id,
        )
      None => ()
    }
    if order.generation != expected_generation {
      raise @offline.OfflineCommerceError::StaleGeneration
    }
    if order.state != UnderReconciliation {
      raise @offline.OfflineCommerceError::InvalidTransition(
        "order is not under reconciliation",
      )
    }
    let accepted = self.accepted_evidence_unlocked(order)
    let missing = @offline.required_evidence(order.policy).filter(kind => {
      !accepted.contains(kind)
    })
    if missing.length() > 0 {
      raise @offline.OfflineCommerceError::EvidenceMissing(missing)
    }
    let updated = order.request_activation(expected_generation, now_unix_ms)
    self.orders[order_id] = updated
    self.entitlement_activations[activation.activation_id] = activation
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.orders = before_orders
      self.entitlement_activations = before_activations
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Completes a pending entitlement saga only from a trusted authority result.
pub async fn OfflineCommerceStore::complete_activation(
  self : OfflineCommerceStore,
  completed : @offline.EntitlementActivation,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  let before_orders = self.orders.copy()
  let before_activations = self.entitlement_activations.copy()
  let before_claims = self.work_claims.copy()
  let before_health = self.worker_health
  try {
    @offline.validate_activation(completed)
    guard self.entitlement_activations.get(completed.activation_id)
      is Some(pending) else {
      raise @offline.OfflineCommerceError::NotFound("entitlement activation")
    }
    guard self.orders.get(completed.order_id) is Some(order) else {
      raise @offline.OfflineCommerceError::NotFound("activation order")
    }
    if pending.state != EntitlementActivationRequested {
      if pending ==
        { ..completed, completed_unix_ms: pending.completed_unix_ms } {
        self.mutex.release()
        return order
      }
      raise @offline.OfflineCommerceError::IdempotencyConflict(
        completed.activation_id,
      )
    }
    guard self.work_claims.get(activation_work_id(completed.activation_id))
      is Some(claim) &&
      claim.worker_kind == EntitlementDispatcher &&
      claim.attempt > 0 &&
      claim.completed_unix_ms is None &&
      claim.expected_order_generation == pending.expected_order_generation else {
      raise @offline.OfflineCommerceError::Unauthorized
    }
    if completed.activation_id != pending.activation_id ||
      completed.idempotency_key != pending.idempotency_key ||
      completed.order_id != pending.order_id ||
      completed.organization_id != pending.organization_id ||
      completed.purchaser_subject_ref != pending.purchaser_subject_ref ||
      completed.kind != pending.kind ||
      completed.authority_target_ref != pending.authority_target_ref ||
      completed.expected_order_generation != pending.expected_order_generation ||
      completed.requested_by != pending.requested_by ||
      completed.requested_unix_ms != pending.requested_unix_ms {
      raise @offline.OfflineCommerceError::InvalidInput(
        "entitlement authority result does not match the pending request",
      )
    }
    let updated = match completed.state {
      EntitlementActivationConfirmed => {
        guard completed.entitlement_ref is Some(entitlement_ref) &&
          completed.completed_unix_ms is Some(completed_unix_ms) else {
          raise @offline.OfflineCommerceError::InvalidInput(
            "confirmed activation is incomplete",
          )
        }
        order.confirm_activation(
          order.generation,
          entitlement_ref,
          completed_unix_ms,
        )
      }
      EntitlementActivationRejected => {
        guard completed.completed_unix_ms is Some(completed_unix_ms) else {
          raise @offline.OfflineCommerceError::InvalidInput(
            "rejected activation is incomplete",
          )
        }
        {
          ..order,
          state: UnderReconciliation,
          generation: order.generation + 1L,
          updated_unix_ms: completed_unix_ms,
        }
      }
      EntitlementActivationRequested =>
        raise @offline.OfflineCommerceError::InvalidTransition(
          "activation result remains pending",
        )
    }
    self.entitlement_activations[completed.activation_id] = completed
    self.orders[order.order_id] = updated
    let completed_unix_ms = completed.completed_unix_ms.unwrap()
    self.work_claims[claim.work_id] = {
      ..claim,
      completed_unix_ms: Some(completed_unix_ms),
    }
    self.worker_health = {
      ..self.worker_health,
      entitlement_dispatcher_success_unix_ms: Some(completed_unix_ms),
    }
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.orders = before_orders
      self.entitlement_activations = before_activations
      self.work_claims = before_claims
      self.worker_health = before_health
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::cancel_order(
  self : OfflineCommerceStore,
  order_id : String,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> @offline.CommercialOrder {
  self.replace_order(order_id, order => {
    order.cancel(expected_generation, now_unix_ms)
  })
}

///|
/// Reconciles elapsed order clocks independently of browser traffic.
pub async fn OfflineCommerceStore::expire_orders(
  self : OfflineCommerceStore,
  now_unix_ms : Int64,
) -> Array[@offline.CommercialOrder] {
  self.mutex.acquire()
  let before = self.orders.copy()
  let before_reversals = self.reversals.copy()
  try {
    let expired = []
    for order_id, order in self.orders {
      let updated = if order.state == Fulfilled &&
        order.expires_unix_ms <= now_unix_ms {
        guard order.entitlement_ref is Some(entitlement_ref) else {
          raise @offline.OfflineCommerceError::InvalidInput(
            "expired fulfilled order lacks entitlement",
          )
        }
        let reversal_id = "expiry-\{order.order_id}-\{order.generation}"
        let reversal : @offline.CommercialReversal = {
          reversal_id,
          idempotency_key: reversal_id,
          order_id: order.order_id,
          organization_id: order.organization_id,
          entitlement_ref,
          reason: ContractExpired,
          expected_order_generation: order.generation,
          state: ReversalRequested,
          authority_receipt: None,
          reason_code: None,
          requested_by: "offline-expiry-reconciler",
          requested_unix_ms: now_unix_ms,
          completed_unix_ms: None,
        }
        @offline.validate_reversal(reversal)
        self.reversals[reversal_id] = reversal
        order.request_reversal(order.generation, now_unix_ms)
      } else {
        order.expire(now_unix_ms)
      }
      if updated != order {
        self.orders[order_id] = updated
        expired.push(updated)
      }
    }
    if expired.length() > 0 {
      self.persist()
    }
    self.mutex.release()
    expired
  } catch {
    error => {
      self.orders = before
      self.reversals = before_reversals
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::request_reversal(
  self : OfflineCommerceStore,
  reversal : @offline.CommercialReversal,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  let before_orders = self.orders.copy()
  let before_reversals = self.reversals.copy()
  try {
    @offline.validate_reversal(reversal)
    guard self.orders.get(reversal.order_id) is Some(order) else {
      raise @offline.OfflineCommerceError::NotFound("reversal order")
    }
    if reversal.organization_id != order.organization_id ||
      order.entitlement_ref != Some(reversal.entitlement_ref) ||
      reversal.state != ReversalRequested {
      raise @offline.OfflineCommerceError::InvalidInput(
        "commercial reversal is not bound to the fulfilled order",
      )
    }
    match self.reversals.get(reversal.reversal_id) {
      Some(existing) if existing == reversal => {
        self.mutex.release()
        return order
      }
      Some(_) =>
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          reversal.reversal_id,
        )
      None => ()
    }
    if reversal.expected_order_generation != order.generation {
      raise @offline.OfflineCommerceError::StaleGeneration
    }
    let updated = order.request_reversal(
      reversal.expected_order_generation,
      reversal.requested_unix_ms,
    )
    self.reversals[reversal.reversal_id] = reversal
    self.orders[order.order_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.orders = before_orders
      self.reversals = before_reversals
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::complete_reversal(
  self : OfflineCommerceStore,
  completed : @offline.CommercialReversal,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  let before_orders = self.orders.copy()
  let before_reversals = self.reversals.copy()
  let before_claims = self.work_claims.copy()
  let before_health = self.worker_health
  try {
    @offline.validate_reversal(completed)
    guard self.reversals.get(completed.reversal_id) is Some(pending) else {
      raise @offline.OfflineCommerceError::NotFound("commercial reversal")
    }
    guard self.orders.get(completed.order_id) is Some(order) else {
      raise @offline.OfflineCommerceError::NotFound("reversal order")
    }
    if pending.state != ReversalRequested {
      if pending ==
        { ..completed, completed_unix_ms: pending.completed_unix_ms } {
        self.mutex.release()
        return order
      }
      raise @offline.OfflineCommerceError::IdempotencyConflict(
        completed.reversal_id,
      )
    }
    guard self.work_claims.get(reversal_work_id(completed.reversal_id))
      is Some(claim) &&
      claim.worker_kind == EntitlementDispatcher &&
      claim.attempt > 0 &&
      claim.completed_unix_ms is None &&
      claim.expected_order_generation == pending.expected_order_generation else {
      raise @offline.OfflineCommerceError::Unauthorized
    }
    if completed.reversal_id != pending.reversal_id ||
      completed.idempotency_key != pending.idempotency_key ||
      completed.order_id != pending.order_id ||
      completed.organization_id != pending.organization_id ||
      completed.entitlement_ref != pending.entitlement_ref ||
      completed.reason != pending.reason ||
      completed.expected_order_generation != pending.expected_order_generation ||
      completed.requested_by != pending.requested_by ||
      completed.requested_unix_ms != pending.requested_unix_ms {
      raise @offline.OfflineCommerceError::InvalidInput(
        "reversal authority result does not match the pending request",
      )
    }
    guard completed.completed_unix_ms is Some(completed_unix_ms) else {
      raise @offline.OfflineCommerceError::InvalidInput(
        "reversal authority result is incomplete",
      )
    }
    let updated = match completed.state {
      ReversalConfirmed =>
        order.confirm_reversal(order.generation, completed_unix_ms)
      ReversalFailed =>
        order.hold_failed_reversal(order.generation, completed_unix_ms)
      ReversalRequested =>
        raise @offline.OfflineCommerceError::InvalidTransition(
          "reversal result remains pending",
        )
    }
    self.reversals[completed.reversal_id] = completed
    self.orders[order.order_id] = updated
    self.work_claims[claim.work_id] = {
      ..claim,
      completed_unix_ms: Some(completed_unix_ms),
    }
    self.worker_health = {
      ..self.worker_health,
      entitlement_dispatcher_success_unix_ms: Some(completed_unix_ms),
    }
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.orders = before_orders
      self.reversals = before_reversals
      self.work_claims = before_claims
      self.worker_health = before_health
      self.mutex.release()
      raise error
    }
  }
}

///| Resolves a failed entitlement reversal without discarding either the

///|
/// authority failure or the operator's reconciliation evidence.
pub async fn OfflineCommerceStore::recover_failed_reversal(
  self : OfflineCommerceStore,
  recovery : @offline.ReversalRecovery,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  let before_orders = self.orders.copy()
  let before_reversals = self.reversals.copy()
  let before_recoveries = self.reversal_recoveries.copy()
  try {
    @offline.validate_reversal_recovery(recovery)
    guard self.orders.get(recovery.order_id) is Some(order) else {
      raise @offline.OfflineCommerceError::NotFound("reversal recovery order")
    }
    match self.reversal_recoveries.get(recovery.recovery_id) {
      Some(existing) if existing == recovery => {
        self.mutex.release()
        return order
      }
      Some(_) =>
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          recovery.recovery_id,
        )
      None => ()
    }
    if self.reversal_recoveries
      .values()
      .any(existing => {
        existing.organization_id == recovery.organization_id &&
        existing.idempotency_key == recovery.idempotency_key
      }) {
      raise @offline.OfflineCommerceError::IdempotencyConflict(
        recovery.idempotency_key,
      )
    }
    guard self.reversals.get(recovery.failed_reversal_id) is Some(failed) else {
      raise @offline.OfflineCommerceError::NotFound("failed reversal")
    }
    if recovery.organization_id != order.organization_id ||
      failed.order_id != order.order_id ||
      failed.organization_id != order.organization_id ||
      failed.state != ReversalFailed ||
      order.entitlement_ref != Some(failed.entitlement_ref) {
      raise @offline.OfflineCommerceError::InvalidInput(
        "recovery is not bound to the failed reversal",
      )
    }
    if recovery.expected_order_generation != order.generation {
      raise @offline.OfflineCommerceError::StaleGeneration
    }
    let updated = order.recover_failed_reversal(
      recovery.expected_order_generation,
      recovery.decision,
      recovery.recovered_unix_ms,
    )
    if recovery.decision == RetryReversal {
      let replacement_id = recovery.replacement_reversal_id.unwrap()
      if self.reversals.contains(replacement_id) {
        raise @offline.OfflineCommerceError::IdempotencyConflict(replacement_id)
      }
      let replacement : @offline.CommercialReversal = {
        reversal_id: replacement_id,
        idempotency_key: recovery.idempotency_key,
        order_id: order.order_id,
        organization_id: order.organization_id,
        entitlement_ref: failed.entitlement_ref,
        reason: failed.reason,
        expected_order_generation: order.generation,
        state: ReversalRequested,
        authority_receipt: None,
        reason_code: None,
        requested_by: recovery.recovered_by,
        requested_unix_ms: recovery.recovered_unix_ms,
        completed_unix_ms: None,
      }
      @offline.validate_reversal(replacement)
      self.reversals[replacement_id] = replacement
    }
    self.reversal_recoveries[recovery.recovery_id] = recovery
    self.orders[order.order_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.orders = before_orders
      self.reversals = before_reversals
      self.reversal_recoveries = before_recoveries
      self.mutex.release()
      raise error
    }
  }
}

///| Issues one bounded transfer capability. The raw token is returned only by

///|
/// the API layer; the durable store retains its digest.
pub async fn OfflineCommerceStore::issue_transfer_session(
  self : OfflineCommerceStore,
  session : @offline.OfflineTransferSession,
) -> @offline.OfflineTransferSession {
  @offline.validate_transfer_session(session)
  if session.state != TransferIssued || session.consumed_unix_ms is Some(_) {
    raise @offline.OfflineCommerceError::InvalidInput(
      "new transfer session must be issued and unused",
    )
  }
  self.mutex.acquire()
  let before = self.transfer_sessions.copy()
  try {
    guard self.orders.get(session.order_id) is Some(order) else {
      raise @offline.OfflineCommerceError::NotFound("transfer order")
    }
    if order.organization_id != session.organization_id ||
      order.purchaser_subject_ref != session.subject_ref {
      raise @offline.OfflineCommerceError::TenantMismatch
    }
    match session.direction {
      UploadTransfer => {
        guard self.upload_grants
          .values()
          .any(grant => {
            grant.order_id == session.order_id &&
            grant.artifact_id == session.artifact_id &&
            grant.organization_id == session.organization_id &&
            grant.subject_ref == session.subject_ref &&
            grant.state == UploadGranted &&
            grant.expires_unix_ms >= session.expires_unix_ms
          }) else {
          raise @offline.OfflineCommerceError::InvalidTransition(
            "upload transfer has no live evidence grant",
          )
        }
      }
      DownloadTransfer => {
        guard self.artifacts.get(session.artifact_id) is Some(artifact) &&
          artifact.order_id == session.order_id &&
          artifact.organization_id == session.organization_id &&
          artifact.scan_state == ScanPassed else {
          raise @offline.OfflineCommerceError::ArtifactUnavailable(
            "download artifact is unavailable",
          )
        }
      }
    }
    match self.transfer_sessions.get(session.session_id) {
      Some(existing) if existing == session => {
        self.mutex.release()
        return existing
      }
      Some(_) =>
        raise @offline.OfflineCommerceError::IdempotencyConflict(
          session.session_id,
        )
      None => ()
    }
    self.transfer_sessions[session.session_id] = session
    self.persist()
    self.mutex.release()
    session
  } catch {
    error => {
      self.transfer_sessions = before
      self.mutex.release()
      raise error
    }
  }
}

///| Consumes the one-time capability after the transfer adapter confirms the

///|
/// exact digest/size transaction. Replay is rejected.
pub async fn OfflineCommerceStore::consume_transfer_session(
  self : OfflineCommerceStore,
  session_id : String,
  token_sha256 : String,
  media_type : String,
  byte_count : Int64,
  sha256 : String,
  provider_receipt : String,
  now_unix_ms : Int64,
) -> @offline.OfflineTransferSession {
  self.mutex.acquire()
  let before = self.transfer_sessions.copy()
  let before_evidence = self.transfer_evidence.copy()
  try {
    guard self.transfer_sessions.get(session_id) is Some(session) else {
      raise @offline.OfflineCommerceError::NotFound("transfer session")
    }
    if session.state != TransferIssued ||
      !constant_time_string_equal(session.session_token_sha256, token_sha256) ||
      !session.media_types.contains(media_type) ||
      byte_count <= 0L ||
      byte_count > session.maximum_byte_count ||
      !@offline.valid_sha256(sha256) ||
      session.expected_sha256.map_or(false, digest => digest != sha256) ||
      !@contracts.valid_identifier(provider_receipt, maximum_length=512) ||
      now_unix_ms < session.issued_unix_ms ||
      now_unix_ms > session.expires_unix_ms {
      raise @offline.OfflineCommerceError::Unauthorized
    }
    let consumed = {
      ..session,
      state: TransferConsumed,
      consumed_unix_ms: Some(now_unix_ms),
    }
    @offline.validate_transfer_session(consumed)
    self.transfer_sessions[session_id] = consumed
    self.transfer_evidence[session_id] = {
      session_id,
      media_type,
      byte_count,
      sha256,
      provider_receipt,
      completed_unix_ms: now_unix_ms,
    }
    self.persist()
    self.mutex.release()
    consumed
  } catch {
    error => {
      self.transfer_sessions = before
      self.transfer_evidence = before_evidence
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::expire_transfer_sessions(
  self : OfflineCommerceStore,
  now_unix_ms : Int64,
) -> Int {
  self.mutex.acquire()
  let before = self.transfer_sessions.copy()
  try {
    let mut expired = 0
    for id, session in self.transfer_sessions {
      if session.state == TransferIssued &&
        session.expires_unix_ms < now_unix_ms {
        self.transfer_sessions[id] = { ..session, state: TransferExpired }
        expired += 1
      }
    }
    if expired > 0 {
      self.persist()
    }
    self.mutex.release()
    expired
  } catch {
    error => {
      self.transfer_sessions = before
      self.mutex.release()
      raise error
    }
  }
}

///| Returns one transfer authority only within the exact organization and

///|
/// purchaser boundary. Raw tokens are never stored and cannot be recovered.
pub async fn OfflineCommerceStore::transfer_session(
  self : OfflineCommerceStore,
  organization_id : String,
  subject_ref : String,
  session_id : String,
) -> @offline.OfflineTransferSession {
  self.mutex.acquire()
  guard self.transfer_sessions.get(session_id) is Some(session) else {
    self.mutex.release()
    raise @offline.OfflineCommerceError::NotFound("transfer session")
  }
  if session.organization_id != organization_id ||
    session.subject_ref != subject_ref {
    self.mutex.release()
    raise @offline.OfflineCommerceError::TenantMismatch
  }
  self.mutex.release()
  session
}

///| Bounded, durable, retry-fenced work claim for the external artifact

///| dispatcher. Polling also records its heartbeat, while terminal callbacks

///|
/// provide separate success evidence.
pub async fn OfflineCommerceStore::claim_generation_requests(
  self : OfflineCommerceStore,
  now_unix_ms : Int64,
  limit? : Int = 100,
) -> Array[@offline.ArtifactGenerationRequest] {
  if limit < 1 || limit > 1000 || now_unix_ms <= 0L {
    raise @offline.OfflineCommerceError::InvalidInput(
      "generation request limit is invalid",
    )
  }
  self.mutex.acquire()
  let before_claims = self.work_claims.copy()
  let before_health = self.worker_health
  try {
    let pending = []
    for request in sorted_values(self.generation_requests) {
      if pending.length() >= limit ||
        self.artifacts.contains(request.artifact_id) {
        continue
      }
      let key = artifact_work_id(request.request_id)
      guard self.work_claims.get(key) is Some(claim) else { continue }
      guard self.orders.get(request.order_id) is Some(order) &&
        order.generation == claim.expected_order_generation &&
        claim.completed_unix_ms is None &&
        claim.attempt < 5 &&
        now_unix_ms >= claim.retry_after_unix_ms else {
        continue
      }
      self.work_claims[key] = {
        ..claim,
        attempt: claim.attempt + 1,
        claimed_unix_ms: now_unix_ms,
        retry_after_unix_ms: now_unix_ms + 60000L,
      }
      pending.push(request)
    }
    self.worker_health = {
      ..self.worker_health,
      artifact_dispatcher_heartbeat_unix_ms: Some(now_unix_ms),
    }
    self.persist()
    self.mutex.release()
    pending
  } catch {
    error => {
      self.work_claims = before_claims
      self.worker_health = before_health
      self.mutex.release()
      raise error
    }
  }
}

///| Claims pending activation/reversal authority work. The exact persisted

///|
/// request is returned; body-supplied authority identities never create work.
pub async fn OfflineCommerceStore::claim_authority_work(
  self : OfflineCommerceStore,
  now_unix_ms : Int64,
  limit? : Int = 100,
) -> @offline.OfflineAuthorityWorkBatch {
  if limit < 1 || limit > 1000 || now_unix_ms <= 0L {
    raise @offline.OfflineCommerceError::InvalidInput(
      "authority work limit is invalid",
    )
  }
  self.mutex.acquire()
  let before_claims = self.work_claims.copy()
  let before_health = self.worker_health
  try {
    let activations = []
    let reversals = []
    let claims = []
    for activation in sorted_values(self.entitlement_activations) {
      if claims.length() >= limit {
        break
      }
      if activation.state != EntitlementActivationRequested {
        continue
      }
      let key = activation_work_id(activation.activation_id)
      let prior = self.work_claims.get(key)
      let attempt = prior.map(value => value.attempt).unwrap_or(0)
      let retry_after = prior
        .map(value => value.retry_after_unix_ms)
        .unwrap_or(0L)
      if attempt >= 5 || now_unix_ms < retry_after {
        continue
      }
      let claim : @offline.OfflineWorkClaim = {
        work_id: key,
        worker_kind: EntitlementDispatcher,
        expected_order_generation: activation.expected_order_generation,
        attempt: attempt + 1,
        claimed_unix_ms: now_unix_ms,
        retry_after_unix_ms: now_unix_ms + 60000L,
        completed_unix_ms: None,
      }
      self.work_claims[key] = claim
      activations.push(activation)
      claims.push(claim)
    }
    for reversal in sorted_values(self.reversals) {
      if claims.length() >= limit {
        break
      }
      if reversal.state != ReversalRequested {
        continue
      }
      let key = reversal_work_id(reversal.reversal_id)
      let prior = self.work_claims.get(key)
      let attempt = prior.map(value => value.attempt).unwrap_or(0)
      let retry_after = prior
        .map(value => value.retry_after_unix_ms)
        .unwrap_or(0L)
      if attempt >= 5 || now_unix_ms < retry_after {
        continue
      }
      let claim : @offline.OfflineWorkClaim = {
        work_id: key,
        worker_kind: EntitlementDispatcher,
        expected_order_generation: reversal.expected_order_generation,
        attempt: attempt + 1,
        claimed_unix_ms: now_unix_ms,
        retry_after_unix_ms: now_unix_ms + 60000L,
        completed_unix_ms: None,
      }
      self.work_claims[key] = claim
      reversals.push(reversal)
      claims.push(claim)
    }
    self.worker_health = {
      ..self.worker_health,
      entitlement_dispatcher_heartbeat_unix_ms: Some(now_unix_ms),
    }
    self.persist()
    self.mutex.release()
    { activations, reversals, claims, heartbeat_unix_ms: now_unix_ms }
  } catch {
    error => {
      self.work_claims = before_claims
      self.worker_health = before_health
      self.mutex.release()
      raise error
    }
  }
}

///| Persists the start of every clock-driven reconciliation pass. If the pass

///|
/// crashes before success, readiness observes attempt newer than success.
pub async fn OfflineCommerceStore::record_reconciler_attempt(
  self : OfflineCommerceStore,
  now_unix_ms : Int64,
) -> Unit {
  if now_unix_ms <= 0L {
    raise @offline.OfflineCommerceError::InvalidInput(
      "invalid reconciler clock",
    )
  }
  self.mutex.acquire()
  let before = self.worker_health
  try {
    self.worker_health = {
      ..self.worker_health,
      reconciler_attempt_unix_ms: Some(now_unix_ms),
    }
    self.persist()
    self.mutex.release()
  } catch {
    error => {
      self.worker_health = before
      self.mutex.release()
      raise error
    }
  }
}

///| Records a deployment acceptance proof after a verified dispatcher

///| round-trip. Production API code normally derives this from terminal

///|
/// callbacks; acceptance tests may seed the same durable proof explicitly.
pub async fn OfflineCommerceStore::record_worker_acceptance(
  self : OfflineCommerceStore,
  worker_kind : @offline.OfflineWorkerKind,
  now_unix_ms : Int64,
) -> Unit {
  if now_unix_ms <= 0L {
    raise @offline.OfflineCommerceError::InvalidInput(
      "invalid worker proof clock",
    )
  }
  self.mutex.acquire()
  let before = self.worker_health
  try {
    self.worker_health = match worker_kind {
      ArtifactDispatcher =>
        {
          ..self.worker_health,
          artifact_dispatcher_heartbeat_unix_ms: Some(now_unix_ms),
          artifact_dispatcher_success_unix_ms: Some(now_unix_ms),
        }
      EntitlementDispatcher =>
        {
          ..self.worker_health,
          entitlement_dispatcher_heartbeat_unix_ms: Some(now_unix_ms),
          entitlement_dispatcher_success_unix_ms: Some(now_unix_ms),
        }
    }
    self.persist()
    self.mutex.release()
  } catch {
    error => {
      self.worker_health = before
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::record_reconciler_success(
  self : OfflineCommerceStore,
  now_unix_ms : Int64,
) -> Unit {
  self.mutex.acquire()
  let before = self.worker_health
  try {
    guard self.worker_health.reconciler_attempt_unix_ms is Some(attempt) &&
      now_unix_ms >= attempt else {
      raise @offline.OfflineCommerceError::InvalidInput(
        "reconciler success has no attempt",
      )
    }
    self.worker_health = {
      ..self.worker_health,
      reconciler_success_unix_ms: Some(now_unix_ms),
      reconciler_failure_code: None,
    }
    self.persist()
    self.mutex.release()
  } catch {
    error => {
      self.worker_health = before
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn OfflineCommerceStore::record_reconciler_failure(
  self : OfflineCommerceStore,
  code : String,
) -> Unit {
  if !@contracts.valid_identifier(code) {
    raise @offline.OfflineCommerceError::InvalidInput(
      "invalid reconciler failure code",
    )
  }
  self.mutex.acquire()
  let before = self.worker_health
  try {
    self.worker_health = {
      ..self.worker_health,
      reconciler_failure_code: Some(code),
    }
    self.persist()
    self.mutex.release()
  } catch {
    error => {
      self.worker_health = before
      self.mutex.release()
      raise error
    }
  }
}

///| Returns only stable blocker codes; no work IDs, tenant IDs, or provider

///|
/// receipts cross the readiness boundary.
pub async fn OfflineCommerceStore::worker_readiness_blockers(
  self : OfflineCommerceStore,
  now_unix_ms : Int64,
) -> Array[String] {
  self.mutex.acquire()
  let health = self.worker_health
  let claims = sorted_values(self.work_claims)
  self.mutex.release()
  let blockers = []
  let recent = (value : Int64?) => {
    value.map_or(false, time => {
      time <= now_unix_ms && now_unix_ms - time <= 120000L
    })
  }
  let recent_success = (value : Int64?) => {
    value.map_or(false, time => {
      time <= now_unix_ms && now_unix_ms - time <= 86400000L
    })
  }
  if !recent(health.artifact_dispatcher_heartbeat_unix_ms) {
    blockers.push("ReadinessArtifactDispatcherHeartbeatStale")
  }
  if !recent_success(health.artifact_dispatcher_success_unix_ms) {
    blockers.push("ReadinessArtifactDispatcherSuccessStale")
  }
  if !recent(health.entitlement_dispatcher_heartbeat_unix_ms) {
    blockers.push("ReadinessEntitlementDispatcherHeartbeatStale")
  }
  if !recent_success(health.entitlement_dispatcher_success_unix_ms) {
    blockers.push("ReadinessEntitlementDispatcherSuccessStale")
  }
  if !recent(health.reconciler_attempt_unix_ms) ||
    !recent(health.reconciler_success_unix_ms) ||
    health.reconciler_attempt_unix_ms.map_or(false, attempt => {
      health.reconciler_success_unix_ms.map_or(true, success => {
        success < attempt
      })
    }) ||
    health.reconciler_failure_code is Some(_) {
    blockers.push("ReadinessOfflineReconcilerDegraded")
  }
  if claims.any(claim => claim.completed_unix_ms is None && claim.attempt >= 5) {
    blockers.push("ReadinessOfflineWorkRetryExhausted")
  }
  blockers
}

///|
pub async fn OfflineCommerceStore::order(
  self : OfflineCommerceStore,
  organization_id : String,
  order_id : String,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  let order = self.require_order_unlocked(order_id)
  self.mutex.release()
  if order.organization_id != organization_id {
    raise @offline.OfflineCommerceError::TenantMismatch
  }
  order
}

///| Operator-only callers already passed the API authority boundary. Keeping

///| this read explicit avoids forging a tenant identifier during lifecycle

///|
/// reconciliation while preserving tenant checks on every public self route.
pub async fn OfflineCommerceStore::order_for_operator(
  self : OfflineCommerceStore,
  order_id : String,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  let order = self.require_order_unlocked(order_id)
  self.mutex.release()
  order
}

///|
pub async fn OfflineCommerceStore::orders_for_organization(
  self : OfflineCommerceStore,
  organization_id : String,
) -> Array[@offline.CommercialOrder] {
  if !@contracts.valid_identifier(organization_id) {
    raise @offline.OfflineCommerceError::InvalidInput("invalid organization")
  }
  self.mutex.acquire()
  let values = sorted_values(self.orders).filter(order => {
    order.organization_id == organization_id
  })
  self.mutex.release()
  values
}

///|
pub async fn OfflineCommerceStore::artifact(
  self : OfflineCommerceStore,
  organization_id : String,
  artifact_id : String,
) -> @offline.DocumentArtifact {
  self.mutex.acquire()
  let found = self.artifacts.get(artifact_id)
  self.mutex.release()
  guard found is Some(value) else {
    raise @offline.OfflineCommerceError::NotFound("document artifact")
  }
  if value.organization_id != organization_id {
    raise @offline.OfflineCommerceError::TenantMismatch
  }
  value
}

///|
pub async fn OfflineCommerceStore::snapshot(
  self : OfflineCommerceStore,
) -> @offline.OfflineCommerceSnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}
