///|
enum PortalPersistence {
  PortalFile(String)
  PortalPostgres(@database.PostgresDatabase)
}

///|
pub struct FilePortalStore {
  persistence : PortalPersistence
  mut memberships : Map[String, @portal.EnterpriseMembership]
  mut agreements : Map[String, @portal.PortalAgreement]
  mut lease_requests : Map[String, @portal.EnterpriseLeaseRequest]
  mutex : @async.Mutex
}

///|
fn sorted_memberships(
  values : Map[String, @portal.EnterpriseMembership],
) -> Array[@portal.EnterpriseMembership] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.membership_id)
  result
}

///|
fn sorted_agreements(
  values : Map[String, @portal.PortalAgreement],
) -> Array[@portal.PortalAgreement] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.agreement_id)
  result
}

///|
fn sorted_requests(
  values : Map[String, @portal.EnterpriseLeaseRequest],
) -> Array[@portal.EnterpriseLeaseRequest] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.submission.request_id)
  result
}

///|
fn FilePortalStore::snapshot_unlocked(
  self : FilePortalStore,
) -> @portal.PortalSnapshot {
  {
    schema_version: @portal.snapshot_schema_version,
    memberships: sorted_memberships(self.memberships),
    agreements: sorted_agreements(self.agreements),
    lease_requests: sorted_requests(self.lease_requests),
  }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : @portal.PortalSnapshot,
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
fn FilePortalStore::restore_snapshot(
  self : FilePortalStore,
  snapshot : @portal.PortalSnapshot,
) -> Unit raise {
  if snapshot.schema_version != @portal.snapshot_schema_version {
    raise @portal.PortalError::InvalidInput("unsupported portal snapshot")
  }
  let active_subjects : Map[String, Unit] = Map([])
  for membership in snapshot.memberships {
    @portal.validate_membership(membership)
    if self.memberships.contains(membership.membership_id) {
      raise @portal.PortalError::InvalidInput("duplicate portal membership")
    }
    if membership.active && active_subjects.contains(membership.subject_ref) {
      raise @portal.PortalError::InvalidInput("duplicate active portal subject")
    }
    if membership.active {
      active_subjects[membership.subject_ref] = ()
    }
    self.memberships[membership.membership_id] = membership
  }
  for agreement in snapshot.agreements {
    @portal.validate_agreement(agreement)
    if self.agreements.contains(agreement.agreement_id) {
      raise @portal.PortalError::InvalidInput("duplicate portal agreement")
    }
    self.agreements[agreement.agreement_id] = agreement
  }
  let scoped_idempotency : Map[String, Unit] = Map([])
  for request in snapshot.lease_requests {
    @portal.validate_submission(request.submission)
    if !@contracts.valid_identifier(request.subject_ref) ||
      request.generation <= 0L ||
      request.updated_unix_ms < request.created_unix_ms ||
      self.lease_requests.contains(request.submission.request_id) {
      raise @portal.PortalError::InvalidInput("invalid portal lease request")
    }
    guard self.membership_for_subject_unlocked(request.subject_ref)
      is Some(membership) else {
      raise @portal.PortalError::InvalidInput(
        "portal lease request subject has no active membership",
      )
    }
    if membership.tenant_ref != request.submission.tenant_ref ||
      membership.organization_id != request.submission.organization_id {
      raise @portal.PortalError::InvalidInput(
        "portal lease request crosses its membership boundary",
      )
    }
    let scope = "\{request.submission.tenant_ref}|\{request.subject_ref}|\{request.submission.idempotency_key}"
    if scoped_idempotency.contains(scope) {
      raise @portal.PortalError::InvalidInput(
        "duplicate scoped portal idempotency key",
      )
    }
    scoped_idempotency[scope] = ()
    self.lease_requests[request.submission.request_id] = request
  }
}

///|
pub async fn FilePortalStore::open(path : String) -> FilePortalStore {
  if path.trim() == "" {
    raise @portal.PortalError::InvalidInput("portal store path is empty")
  }
  let store : FilePortalStore = {
    persistence: PortalFile(path),
    memberships: Map([]),
    agreements: Map([]),
    lease_requests: Map([]),
    mutex: @async.Mutex::Mutex(),
  }
  if @fs.exists(path) {
    let snapshot : @portal.PortalSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error =>
        raise @portal.PortalError::InvalidInput(
          "invalid portal snapshot: \{Repr(error)}",
        )
    }
    store.restore_snapshot(snapshot)
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn FilePortalStore::open_postgres(
  database : @database.PostgresDatabase,
) -> FilePortalStore {
  let store : FilePortalStore = {
    persistence: PortalPostgres(database),
    memberships: Map([]),
    agreements: Map([]),
    lease_requests: Map([]),
    mutex: @async.Mutex::Mutex(),
  }
  match
    database.load_snapshot("enterprise_portal", @portal.snapshot_schema_version) {
    Some(payload) => {
      let snapshot : @portal.PortalSnapshot = @json.from_json(
        @json.parse(payload),
      ) catch {
        error =>
          raise @portal.PortalError::InvalidInput(
            "invalid database portal snapshot: \{Repr(error)}",
          )
      }
      store.restore_snapshot(snapshot)
    }
    None => database.save_portal_snapshot(store.snapshot_unlocked())
  }
  store
}

///|
async fn FilePortalStore::persist(self : FilePortalStore) -> Unit {
  match self.persistence {
    PortalFile(path) => write_snapshot(path, self.snapshot_unlocked())
    PortalPostgres(database) =>
      database.save_portal_snapshot(self.snapshot_unlocked())
  }
}

///|
fn FilePortalStore::membership_for_subject_unlocked(
  self : FilePortalStore,
  subject_ref : String,
) -> @portal.EnterpriseMembership? {
  self.memberships
  .values()
  .find_first(value => value.subject_ref == subject_ref && value.active)
}

///|
fn FilePortalStore::executed_agreement_unlocked(
  self : FilePortalStore,
  tenant_ref : String,
  organization_id : String,
) -> Bool {
  self.agreements
  .values()
  .any(value => {
    value.tenant_ref == tenant_ref &&
    value.organization_id == organization_id &&
    value.state == Executed
  })
}

///|
pub async fn FilePortalStore::snapshot(
  self : FilePortalStore,
) -> @portal.PortalSnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}

///|
pub async fn FilePortalStore::self_view(
  self : FilePortalStore,
  subject_ref : String,
) -> @portal.EnterpriseSelfView {
  self.mutex.acquire()
  try {
    guard self.membership_for_subject_unlocked(subject_ref) is Some(membership) else {
      raise @portal.PortalError::Unauthorized("enterprise membership required")
    }
    let agreements = sorted_agreements(self.agreements).filter(value => {
      value.tenant_ref == membership.tenant_ref &&
      value.organization_id == membership.organization_id
    })
    let all_requests = sorted_requests(self.lease_requests)
    let requests = if @portal.role_allows(
        membership.roles,
        OrganizationAdministrator,
      ) {
      all_requests.filter(value => {
        value.submission.tenant_ref == membership.tenant_ref &&
        value.submission.organization_id == membership.organization_id
      })
    } else {
      all_requests.filter(value => value.subject_ref == subject_ref)
    }
    let view : @portal.EnterpriseSelfView = {
      version: @portal.contract_version,
      membership,
      agreements,
      lease_requests: requests,
      can_sign: @portal.role_allows(membership.roles, LegalSigner),
      can_request_lease: @portal.role_allows(membership.roles, LeaseRequester),
    }
    self.mutex.release()
    view
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FilePortalStore::put_membership(
  self : FilePortalStore,
  membership : @portal.EnterpriseMembership,
) -> @portal.EnterpriseMembership {
  @portal.validate_membership(membership)
  self.mutex.acquire()
  let previous = self.memberships.copy()
  try {
    if self.memberships.contains(membership.membership_id) {
      raise @portal.PortalError::AlreadyExists(membership.membership_id)
    }
    if self.memberships
      .values()
      .any(value => value.subject_ref == membership.subject_ref && value.active) {
      raise @portal.PortalError::AlreadyExists(membership.subject_ref)
    }
    self.memberships[membership.membership_id] = membership
    self.persist()
    self.mutex.release()
    membership
  } catch {
    error => {
      self.memberships = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FilePortalStore::publish_agreement(
  self : FilePortalStore,
  agreement : @portal.PortalAgreement,
) -> @portal.PortalAgreement {
  @portal.validate_agreement(agreement)
  if agreement.state != ReviewRequired || agreement.generation != 1L {
    raise @portal.PortalError::InvalidInput(
      "new portal agreements must require review",
    )
  }
  self.mutex.acquire()
  let previous = self.agreements.copy()
  try {
    if self.agreements.contains(agreement.agreement_id) {
      raise @portal.PortalError::AlreadyExists(agreement.agreement_id)
    }
    if !self.memberships
      .values()
      .any(value => {
        value.tenant_ref == agreement.tenant_ref &&
        value.organization_id == agreement.organization_id &&
        value.active
      }) {
      raise @portal.PortalError::NotFound("enterprise organization membership")
    }
    self.agreements[agreement.agreement_id] = agreement
    self.persist()
    self.mutex.release()
    agreement
  } catch {
    error => {
      self.agreements = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FilePortalStore::request_signature(
  self : FilePortalStore,
  subject_ref : String,
  request : @portal.SignatureRequest,
  now_unix_ms : Int64,
) -> @portal.PortalAgreement {
  self.mutex.acquire()
  let previous = self.agreements.copy()
  try {
    guard self.membership_for_subject_unlocked(subject_ref) is Some(membership) else {
      raise @portal.PortalError::Unauthorized("enterprise membership required")
    }
    if !@portal.role_allows(membership.roles, LegalSigner) {
      raise @portal.PortalError::Unauthorized("legal signer role required")
    }
    guard self.agreements.get(request.agreement_id) is Some(agreement) else {
      raise @portal.PortalError::NotFound(request.agreement_id)
    }
    if agreement.tenant_ref != membership.tenant_ref ||
      agreement.organization_id != membership.organization_id {
      raise @portal.PortalError::TenantMismatch
    }
    if !@contracts.valid_identifier(request.idempotency_key) {
      raise @portal.PortalError::InvalidInput("invalid idempotency key")
    }
    let receipt = "portal-signature:\{request.idempotency_key}"
    if agreement.state == SignatureRequested &&
      agreement.signer_subject_ref == Some(subject_ref) &&
      agreement.signature_request_receipt == Some(receipt) {
      self.mutex.release()
      return agreement
    }
    let updated = agreement.request_signature(
      subject_ref,
      receipt,
      request.expected_generation,
      now_unix_ms,
    )
    self.agreements[request.agreement_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.agreements = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FilePortalStore::record_execution(
  self : FilePortalStore,
  execution : @portal.AgreementExecution,
  now_unix_ms : Int64,
) -> @portal.PortalAgreement {
  self.mutex.acquire()
  let previous = self.agreements.copy()
  try {
    guard self.agreements.get(execution.agreement_id) is Some(agreement) else {
      raise @portal.PortalError::NotFound(execution.agreement_id)
    }
    let updated = agreement.record_execution(execution, now_unix_ms)
    self.agreements[execution.agreement_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.agreements = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
fn FilePortalStore::request_by_idempotency_unlocked(
  self : FilePortalStore,
  tenant_ref : String,
  subject_ref : String,
  idempotency_key : String,
) -> @portal.EnterpriseLeaseRequest? {
  self.lease_requests
  .values()
  .find_first(value => {
    value.submission.tenant_ref == tenant_ref &&
    value.subject_ref == subject_ref &&
    value.submission.idempotency_key == idempotency_key
  })
}

///|
pub async fn FilePortalStore::submit_lease_request(
  self : FilePortalStore,
  subject_ref : String,
  submission : @portal.LeaseRequestSubmission,
  now_unix_ms : Int64,
) -> @portal.EnterpriseLeaseRequest {
  @portal.validate_submission(submission)
  if now_unix_ms >= submission.expires_unix_ms {
    raise @portal.PortalError::InvalidInput("lease request already expired")
  }
  self.mutex.acquire()
  let previous = self.lease_requests.copy()
  try {
    guard self.membership_for_subject_unlocked(subject_ref) is Some(membership) else {
      raise @portal.PortalError::Unauthorized("enterprise membership required")
    }
    if !@portal.role_allows(membership.roles, LeaseRequester) {
      raise @portal.PortalError::Unauthorized("lease requester role required")
    }
    if submission.tenant_ref != membership.tenant_ref ||
      submission.organization_id != membership.organization_id {
      raise @portal.PortalError::TenantMismatch
    }
    match
      self.request_by_idempotency_unlocked(
        submission.tenant_ref,
        subject_ref,
        submission.idempotency_key,
      ) {
      Some(existing) if existing.subject_ref == subject_ref &&
        existing.submission == submission => {
        self.mutex.release()
        return existing
      }
      Some(_) =>
        raise @portal.PortalError::IdempotencyConflict(
          submission.idempotency_key,
        )
      None => ()
    }
    if self.lease_requests.contains(submission.request_id) {
      raise @portal.PortalError::AlreadyExists(submission.request_id)
    }
    if !self.executed_agreement_unlocked(
        submission.tenant_ref,
        submission.organization_id,
      ) {
      raise @portal.PortalError::AgreementRequired
    }
    let request : @portal.EnterpriseLeaseRequest = {
      submission,
      subject_ref,
      state: Submitted,
      generation: 1L,
      assigned_node_id: None,
      exclusive_lease_id: None,
      decision_receipt: None,
      created_unix_ms: now_unix_ms,
      updated_unix_ms: now_unix_ms,
    }
    self.lease_requests[submission.request_id] = request
    self.persist()
    self.mutex.release()
    request
  } catch {
    error => {
      self.lease_requests = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FilePortalStore::lease_request(
  self : FilePortalStore,
  request_id : String,
) -> @portal.EnterpriseLeaseRequest? {
  self.mutex.acquire()
  let request = self.lease_requests.get(request_id)
  self.mutex.release()
  request
}

///|
pub async fn FilePortalStore::review_lease_request(
  self : FilePortalStore,
  review : @portal.LeaseReview,
  exclusive_lease_id : String?,
  now_unix_ms : Int64,
) -> @portal.EnterpriseLeaseRequest {
  self.mutex.acquire()
  let previous = self.lease_requests.copy()
  try {
    guard self.lease_requests.get(review.request_id) is Some(request) else {
      raise @portal.PortalError::NotFound(review.request_id)
    }
    let updated = request.review(review, exclusive_lease_id, now_unix_ms)
    self.lease_requests[review.request_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.lease_requests = previous
      self.mutex.release()
      raise error
    }
  }
}
