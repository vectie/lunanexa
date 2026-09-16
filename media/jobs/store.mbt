///|
fn digest(value : String) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn owner_valid(owner : Owner) -> Bool {
  [
    owner.tenant_ref,
    owner.subject_ref,
    owner.organization_id,
    owner.project_id,
    owner.authority.reference(),
  ].all(value => @contracts.valid_identifier(value))
}

///|
fn busy(job : StoredJob) -> Bool {
  if job.execution_terminal {
    return false
  }
  match job.state {
    Intent | Submitting | SubmissionUnknown | Queued | Running | Cancelling =>
      true
    Completed | Failed | Cancelled | Expired => false
  }
}

///|
fn provider_id_valid(id : String) -> Bool {
  !id.is_empty() &&
  id.length() <= 128 &&
  id.all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '-' ||
    c == '_'
  })
}

///|
fn execution_context_valid(value : ExecutionContext) -> Bool {
  @contracts.valid_identifier(value.deployment_id) &&
  @contracts.valid_identifier(value.node_id) &&
  value.instance_id.map_or(true, id => {
    @contracts.valid_sha256_digest("sha256:" + id)
  }) &&
  value.generation > 0L
}

///|
fn snapshot(
  jobs : Map[String, StoredJob],
  terminations : Array[AcceptedTermination],
) -> Snapshot {
  let values = jobs.values().to_array()
  values.sort_by_key(job => job.job_id)
  { schema_version, jobs: values, terminations: Some(terminations.copy()), }
}

///|
fn execution_context_compatible(
  a : ExecutionContext,
  b : ExecutionContext,
) -> Bool {
  a.deployment_id == b.deployment_id &&
  a.generation == b.generation &&
  a.node_id == b.node_id &&
  (
    a.instance_id is None ||
    b.instance_id is None ||
    a.instance_id == b.instance_id
  )
}

///|
/// A restored submission whose provider acknowledgement was not committed is
/// uncertain, not queued for retry. It continues occupying its paid order slot.
pub async fn JobStore::restore(
  saved : Snapshot,
  persist : async (Snapshot) -> Unit,
  maximum_jobs? : Int = 10000,
) -> JobStore {
  if saved.schema_version != schema_version ||
    maximum_jobs < 1 ||
    maximum_jobs > 100000 ||
    saved.jobs.length() > maximum_jobs {
    raise InvalidSnapshot
  }
  let jobs : Map[String, StoredJob] = Map([])
  let terminations = saved.terminations.unwrap_or([]).copy()
  if terminations.length() > 10000 || !terminations.all(termination_valid) {
    raise InvalidSnapshot
  }
  // Online acceptance allows one immutable record per node/incarnation. Restore
  // must enforce the same invariant instead of choosing the first conflicting
  // record during reconciliation. JSON tuple encoding avoids delimiter aliases.
  let incarnations : Map[String, Bool] = Map([])
  for value in terminations {
    let identity = ([value.node_id, value.evidence.instance_id] : Array[String])
      .to_json()
      .stringify()
    if incarnations.contains(identity) {
      raise InvalidSnapshot
    }
    incarnations[identity] = true
  }
  let requests : Map[String, Bool] = Map([])
  let active_orders : Map[String, Bool] = Map([])
  let mut recovered = false
  for record in saved.jobs {
    if !owner_valid(record.owner) ||
      !@contracts.valid_identifier(record.job_id) ||
      !@contracts.valid_identifier(record.model) ||
      !@contracts.valid_identifier(record.deployment_id) ||
      (record.termination_evidence_ref is Some(_)) !=
      (record.termination_observed_unix_ms is Some(_)) ||
      record.termination_observed_unix_ms.map_or(false, observed => {
        observed < record.created_unix_ms || observed > record.updated_unix_ms
      }) ||
      record.termination_evidence_ref.map_or(false, reference => {
        !@contracts.valid_identifier(reference) ||
        !record.execution_terminal ||
        record.execution_context.map_or(true, context => {
          context.instance_id is None
        }) ||
        ![Completed, Failed, Cancelled, Expired, Cancelling].contains(
          record.state,
        )
      }) ||
      record.execution_context.map_or(false, value => {
        !execution_context_valid(value)
      }) ||
      !@contracts.valid_sha256_digest(record.request_digest) ||
      !@contracts.valid_sha256_digest(record.idempotency_digest) ||
      record.created_unix_ms <= 0L ||
      record.updated_unix_ms < record.created_unix_ms ||
      record.deadline_unix_ms <= record.created_unix_ms ||
      record.retain_until_unix_ms < record.deadline_unix_ms ||
      record.progress.map_or(false, value => value < 0 || value > 100) ||
      record.provider_job_id.map_or(false, id => !provider_id_valid(id)) ||
      record.execution_terminal != (record.terminal_unix_ms is Some(_)) ||
      record.terminal_unix_ms.map_or(false, ended => {
        ended < record.created_unix_ms || ended > record.updated_unix_ms
      }) ||
      record.usage_receipt.map_or(false, value => {
        !@contracts.valid_identifier(value)
      }) ||
      jobs.contains(record.job_id) ||
      requests.contains(record.idempotency_digest) {
      raise InvalidSnapshot
    }
    if [Queued, Running, Completed].contains(record.state) &&
      record.provider_job_id is None {
      raise InvalidSnapshot
    }
    if record.job_id != "video-" + record.idempotency_digest[7:].to_owned() ||
      (
        [Completed, Failed, Cancelled, Expired].contains(record.state) &&
        !record.execution_terminal
      ) ||
      (
        [Intent, Submitting, SubmissionUnknown, Queued, Running].contains(
          record.state,
        ) &&
        record.execution_terminal
      ) {
      raise InvalidSnapshot
    }
    if record.execution_context is Some(context) &&
      jobs
      .values()
      .any(other => {
        other.deployment_id == record.deployment_id &&
        other.execution_context.map_or(false, previous => {
          !execution_context_compatible(previous, context)
        })
      }) {
      raise InvalidSnapshot
    }
    if record.provider_job_id is Some(provider_id) &&
      jobs
      .values()
      .any(other => {
        other.deployment_id == record.deployment_id &&
        other.provider_job_id == Some(provider_id)
      }) {
      raise InvalidSnapshot
    }
    if busy(record) {
      let order = record.owner.authority.slot()
      if active_orders.contains(order) {
        raise InvalidSnapshot
      }
      active_orders[order] = true
    }
    let record = if record.state == Submitting {
      recovered = true
      { ..record, state: SubmissionUnknown, }
    } else {
      record
    }
    requests[record.idempotency_digest] = true
    // Earlier termination recovery could persist Cancelling after an already
    // evidenced exit. Complete that local cleanup without contacting a dead
    // provider; all evidence/terminal/context validation above still applies.
    if record.state == Cancelling && record.termination_evidence_ref is Some(_) {
      recovered = true
      jobs[record.job_id] = {
        ..record,
        state: if record.expiry_requested {
          Expired
        } else {
          Cancelled
        },
      }
    } else {
      jobs[record.job_id] = record
    }
  }
  if recovered {
    persist(snapshot(jobs, terminations))
  }
  { jobs, terminations, persist, maximum_jobs, mutex: @async.Mutex(), }
}

///|
pub async fn JobStore::snapshot(self : JobStore) -> Snapshot {
  self.mutex.acquire()
  defer self.mutex.release()
  snapshot(self.jobs, self.terminations)
}

///|
async fn JobStore::commit(self : JobStore, value : StoredJob) -> StoredJob {
  let next = self.jobs.copy()
  next[value.job_id] = value
  (self.persist)(snapshot(next, self.terminations))
  self.jobs = next
  value
}

///|
pub async fn JobStore::reserve(
  self : JobStore,
  owner : Owner,
  idempotency_key : String,
  request_digest : String,
  model : String,
  deployment_id : String,
  now : Int64,
  deadline : Int64,
  retain_until : Int64,
  maximum_active? : Int = 1,
  maximum_per_hour? : Int = 100,
  execution_context? : ExecutionContext,
) -> (StoredJob, Bool) {
  if !owner_valid(owner) ||
    !@contracts.valid_identifier(idempotency_key) ||
    !@contracts.valid_sha256_digest(request_digest) ||
    !@contracts.valid_identifier(model) ||
    !@contracts.valid_identifier(deployment_id) ||
    execution_context.map_or(false, value => !execution_context_valid(value)) ||
    now <= 0L ||
    deadline <= now ||
    deadline - now > 7200000L ||
    retain_until < deadline ||
    retain_until - now > 604800000L ||
    maximum_active < 1 ||
    maximum_active > 10000 ||
    maximum_per_hour < 1 ||
    maximum_per_hour > 100000 {
    raise InvalidInput
  }
  let request_key = digest(
    ({ "owner": ToJson::to_json(owner), "key": idempotency_key } : Json).stringify(),
  )
  self.mutex.acquire()
  defer self.mutex.release()
  for record in self.jobs.values() {
    if record.deployment_id == deployment_id &&
      record.execution_context is Some(previous) &&
      execution_context is Some(next) &&
      !execution_context_compatible(previous, next) {
      raise Conflict
    }
    if record.idempotency_digest == request_key {
      if record.owner != owner ||
        record.request_digest != request_digest ||
        record.model != model ||
        record.deployment_id != deployment_id ||
        (
          record.execution_context is Some(previous) &&
          execution_context is Some(next) &&
          !execution_context_compatible(previous, next)
        ) {
        raise Conflict
      }
      if record.execution_context is None && execution_context is Some(context) {
        return (
          self.commit({ ..record, execution_context: Some(context), }),
          false,
        )
      }
      return (record, false)
    }
  }
  if execution_context is Some(context) &&
    self.terminations.any(value => {
      value.node_id == context.node_id &&
      value.evidence.deployment_id == context.deployment_id &&
      value.evidence.generation == context.generation &&
      context.instance_id == Some(value.evidence.instance_id)
    }) {
    raise InvalidTransition
  }
  if self.jobs
    .values()
    .any(job => job.owner.authority == owner.authority && busy(job)) {
    raise Busy
  }
  if self.jobs.length() >= self.maximum_jobs {
    raise CapacityExceeded
  }
  let related = self.jobs
    .values()
    .filter(job => {
      job.owner.tenant_ref == owner.tenant_ref &&
      job.owner.subject_ref == owner.subject_ref
    })
    .to_array()
  if related.filter(job => busy(job)).length() >= maximum_active ||
    related.filter(job => job.created_unix_ms > now - 3600000L).length() >=
    maximum_per_hour {
    raise Busy
  }
  let value : StoredJob = {
    job_id: "video-" + request_key[7:].to_owned(),
    owner,
    request_digest,
    idempotency_digest: request_key,
    model,
    deployment_id,
    execution_context,
    provider_job_id: None,
    state: Intent,
    progress: None,
    created_unix_ms: now,
    updated_unix_ms: now,
    deadline_unix_ms: deadline,
    retain_until_unix_ms: retain_until,
    expiry_requested: false,
    execution_terminal: false,
    terminal_unix_ms: None,
    usage_receipt: None,
    termination_evidence_ref: None,
    termination_observed_unix_ms: None,
  }
  (self.commit(value), true)
}

///|
fn JobStore::owned(
  self : JobStore,
  id : String,
  owner : Owner,
) -> StoredJob raise JobError {
  guard self.jobs.get(id) is Some(job) && job.owner == owner else {
    raise NotFound
  }
  job
}

///|
pub async fn JobStore::get(
  self : JobStore,
  id : String,
  owner : Owner,
) -> StoredJob {
  self.mutex.acquire()
  defer self.mutex.release()
  self.owned(id, owner)
}

///|
pub async fn JobStore::begin_submission(
  self : JobStore,
  id : String,
  owner : Owner,
  now : Int64,
) -> StoredJob {
  self.mutex.acquire()
  defer self.mutex.release()
  let job = self.owned(id, owner)
  if job.state != Intent ||
    now < job.updated_unix_ms ||
    now >= job.deadline_unix_ms {
    raise InvalidTransition
  }
  if job.execution_context is Some(context) &&
    self.terminations.any(value => {
      value.node_id == context.node_id &&
      value.evidence.deployment_id == context.deployment_id &&
      value.evidence.generation == context.generation &&
      context.instance_id == Some(value.evidence.instance_id)
    }) {
    raise InvalidTransition
  }
  self.commit({ ..job, state: Submitting, updated_unix_ms: now, })
}

///|
pub async fn JobStore::submission_unknown(
  self : JobStore,
  id : String,
  owner : Owner,
  now : Int64,
) -> StoredJob {
  self.mutex.acquire()
  defer self.mutex.release()
  let job = self.owned(id, owner)
  if now < job.updated_unix_ms {
    raise InvalidTransition
  }
  if job.state == Cancelling {
    return job
  }
  if job.state != Submitting && job.state != SubmissionUnknown {
    raise InvalidTransition
  }
  self.commit({ ..job, state: SubmissionUnknown, updated_unix_ms: now, })
}

///|
/// Server-side provider acknowledgement or operator reconciliation only.
pub async fn JobStore::attach_provider(
  self : JobStore,
  id : String,
  owner : Owner,
  provider_id : String,
  now : Int64,
) -> StoredJob {
  if !provider_id_valid(provider_id) {
    raise InvalidInput
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let job = self.owned(id, owner)
  if job.provider_job_id is Some(previous) {
    if previous == provider_id {
      return job
    }
    raise Conflict
  }
  if self.jobs
    .values()
    .any(other => {
      other.job_id != id &&
      other.deployment_id == job.deployment_id &&
      other.provider_job_id == Some(provider_id)
    }) {
    raise Conflict
  }
  if ![Submitting, SubmissionUnknown, Cancelling].contains(job.state) ||
    now < job.updated_unix_ms {
    raise InvalidTransition
  }
  self.commit({
    ..job,
    provider_job_id: Some(provider_id),
    state: if job.state == Cancelling {
      Cancelling
    } else {
      Queued
    },
    updated_unix_ms: now,
  })
}

///|
pub async fn JobStore::observe(
  self : JobStore,
  id : String,
  owner : Owner,
  state : State,
  progress : Int?,
  now : Int64,
) -> StoredJob {
  if ![Queued, Running, Completed, Failed].contains(state) ||
    progress.map_or(false, n => n < 0 || n > 100) {
    raise InvalidInput
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let job = self.owned(id, owner)
  if now < job.updated_unix_ms {
    return job
  }
  if ![Queued, Running].contains(job.state) {
    return job
  }
  if job.state == Running && state == Queued {
    return job
  }
  let progress = match (job.progress, progress) {
    (Some(previous), Some(next)) => Some(previous.max(next))
    (previous, None) => previous
    (None, next) => next
  }
  self.commit({
    ..job,
    state,
    progress,
    execution_terminal: state == Completed || state == Failed,
    terminal_unix_ms: if state == Completed || state == Failed {
      Some(now)
    } else {
      None
    },
    updated_unix_ms: now,
  })
}

///|
pub async fn JobStore::cancel(
  self : JobStore,
  id : String,
  owner : Owner,
  expired : Bool,
  now : Int64,
) -> StoredJob {
  self.mutex.acquire()
  defer self.mutex.release()
  let job = self.owned(id, owner)
  if now < job.updated_unix_ms {
    raise InvalidTransition
  }
  if [Cancelled, Expired].contains(job.state) {
    return job
  }
  let expiry = expired || job.expiry_requested
  let state = if job.state == Intent ||
    (job.execution_terminal && job.termination_evidence_ref is Some(_)) {
    if expiry {
      Expired
    } else {
      Cancelled
    }
  } else {
    Cancelling
  }
  self.commit({
    ..job,
    state,
    expiry_requested: expiry,
    execution_terminal: job.execution_terminal || job.state == Intent,
    terminal_unix_ms: if job.state == Intent {
      Some(now)
    } else {
      job.terminal_unix_ms
    },
    updated_unix_ms: now,
  })
}

///|
/// Call only after deletion/cancellation is acknowledged by the bound provider.
pub async fn JobStore::acknowledge_deletion(
  self : JobStore,
  id : String,
  owner : Owner,
  provider_id : String,
  now : Int64,
) -> StoredJob {
  self.mutex.acquire()
  defer self.mutex.release()
  let job = self.owned(id, owner)
  if job.provider_job_id != Some(provider_id) {
    raise Conflict
  }
  if [Cancelled, Expired].contains(job.state) {
    return job
  }
  if job.state != Cancelling || now < job.updated_unix_ms {
    raise InvalidTransition
  }
  self.commit({
    ..job,
    state: if job.expiry_requested {
      Expired
    } else {
      Cancelled
    },
    execution_terminal: true,
    terminal_unix_ms: Some(job.terminal_unix_ms.unwrap_or(now)),
    updated_unix_ms: now,
  })
}

///|
/// Meter ingestion is idempotent by job ID in the commercial ledger. Call this
/// only with its durable receipt, so retry after either store fails cannot bill
/// prepaid capacity a second time or falsely report a recorded charge.
pub async fn JobStore::record_usage(
  self : JobStore,
  id : String,
  owner : Owner,
  receipt : String,
) -> StoredJob {
  if !@contracts.valid_identifier(receipt) {
    raise InvalidInput
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let job = self.owned(id, owner)
  if !job.execution_terminal {
    raise InvalidTransition
  }
  if job.usage_receipt is Some(previous) {
    if previous == receipt {
      return job
    }
    raise Conflict
  }
  self.commit({ ..job, usage_receipt: Some(receipt), })
}

///|
pub fn StoredJob::public_view(self : StoredJob, now : Int64) -> Json {
  let expired = now >= self.retain_until_unix_ms || self.expiry_requested
  let status = if expired {
    "failed"
  } else {
    match self.state {
      Intent | Submitting | Queued => "queued"
      Running | Cancelling => "in_progress"
      Completed => "completed"
      SubmissionUnknown | Failed | Cancelled | Expired => "failed"
    }
  }
  let error_code : String? = if expired {
    Some("ResultExpired")
  } else {
    match self.state {
      SubmissionUnknown => Some("SubmissionRequiresReconciliation")
      Failed => Some("GenerationFailed")
      Cancelled => Some("Cancelled")
      Expired => Some("ResultExpired")
      _ => None
    }
  }
  {
    "id": self.job_id,
    "object": "video",
    "model": self.model,
    "status": status,
    "created_at": ToJson::to_json(self.created_unix_ms / 1000L),
    "progress": ToJson::to_json(self.progress),
    "error": error_code.map_or(Json::null(), code => {
      ({ "code": code, "message": code } : Json)
    }),
    "content_available": self.state == Completed &&
    !expired &&
    self.termination_evidence_ref is None,
  }
}
