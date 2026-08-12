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
  mutex : @async.Mutex
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
    let snapshot : @offline.OfflineCommerceSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error =>
        raise @offline.OfflineCommerceError::InvalidInput(
          "invalid offline-commerce snapshot: \{Repr(error)}",
        )
    }
    store.restore(snapshot)
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
  match
    database.load_snapshot("offline_commerce", @offline.snapshot_schema_version) {
    Some(payload) => {
      let snapshot : @offline.OfflineCommerceSnapshot = @json.from_json(
        @json.parse(payload),
      ) catch {
        error =>
          raise @offline.OfflineCommerceError::InvalidInput(
            "invalid offline-commerce snapshot: \{Repr(error)}",
          )
      }
      store.restore(snapshot)
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
  if request.organization_id != order.organization_id ||
    !kind_matches ||
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
  try {
    self.validate_generation_request_unlocked(request)
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
    self.persist()
    self.mutex.release()
    request
  } catch {
    error => {
      self.generation_requests = before
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
  try {
    guard self.generation_requests.get(result.request_id) is Some(request) else {
      raise @offline.OfflineCommerceError::NotFound("generation request")
    }
    guard self.orders.get(request.order_id) is Some(order) else {
      raise @offline.OfflineCommerceError::NotFound("generation order")
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
    self.persist()
    self.mutex.release()
    artifact
  } catch {
    error => {
      self.artifacts = before_artifacts
      self.orders = before_orders
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
  entitlement_ref : String,
  now_unix_ms : Int64,
) -> @offline.CommercialOrder {
  self.mutex.acquire()
  let before = self.orders.copy()
  try {
    let order = self.require_order_unlocked(order_id)
    if order.generation != expected_generation {
      raise @offline.OfflineCommerceError::StaleGeneration
    }
    if order.state != UnderReconciliation {
      raise @offline.OfflineCommerceError::InvalidTransition(
        "order is not under reconciliation",
      )
    }
    if !@contracts.valid_identifier(entitlement_ref) {
      raise @offline.OfflineCommerceError::InvalidInput(
        "invalid entitlement reference",
      )
    }
    let accepted = self.accepted_evidence_unlocked(order)
    let missing = @offline.required_evidence(order.policy).filter(kind => {
      !accepted.contains(kind)
    })
    if missing.length() > 0 {
      raise @offline.OfflineCommerceError::EvidenceMissing(missing)
    }
    let updated = {
      ..order,
      entitlement_ref: Some(entitlement_ref),
      state: Fulfilled,
      generation: order.generation + 1L,
      updated_unix_ms: now_unix_ms,
    }
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
