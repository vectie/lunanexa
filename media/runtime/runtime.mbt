///|
pub(all) suberror RuntimeError {
  Unauthorized
  AuthorityUnavailable
  ContentUnavailable
} derive(Debug, Eq)

///|
pub extend RuntimeError with Debug::{to_repr}

///|
pub extend RuntimeError with Eq::{not_equal, equal}

///|
/// All hooks are server-owned. resolve must bind an immutable deployment ID;
/// authorized must recheck the account, order, model and deployment authority;
/// settle must return an idempotent durable usage receipt keyed by job_id.
pub struct VideoRuntime {
  store : @jobs.JobStore
  resolve : async (String) -> @provider.Provider
  authorized : async (@jobs.Owner, String, String) -> Bool
  settle : async (@jobs.StoredJob) -> String
  now : () -> Int64
}

///|
pub fn VideoRuntime::new(
  store : @jobs.JobStore,
  resolve : async (String) -> @provider.Provider,
  authorized : async (@jobs.Owner, String, String) -> Bool,
  settle : async (@jobs.StoredJob) -> String,
  now? : () -> Int64 = @async.now,
) -> VideoRuntime {
  { store, resolve, authorized, settle, now, }
}

///|
async fn VideoRuntime::record_terminal(
  self : VideoRuntime,
  job : @jobs.StoredJob,
) -> @jobs.StoredJob {
  if !job.execution_terminal || job.usage_receipt is Some(_) {
    return job
  }
  let receipt = (self.settle)(job)
  self.store.record_usage(job.job_id, job.owner, receipt)
}

///|
pub async fn VideoRuntime::submit(
  self : VideoRuntime,
  owner : @jobs.Owner,
  idempotency_key : String,
  request : @provider.VideoRequest,
  deployment_id : String,
  deadline_unix_ms : Int64,
  retain_until_unix_ms : Int64,
  maximum_active? : Int = 1,
  maximum_per_hour? : Int = 100,
  execution_context? : @jobs.ExecutionContext,
) -> @jobs.StoredJob {
  if !(self.authorized)(owner, request.model(), deployment_id) {
    raise Unauthorized
  }
  let (job, _) = self.store.reserve(
    owner,
    idempotency_key,
    request.digest(),
    request.model(),
    deployment_id,
    (self.now)(),
    deadline_unix_ms,
    retain_until_unix_ms,
    maximum_active~,
    maximum_per_hour~,
    execution_context?,
  )
  // Only a durable Intent can be submitted. Network ambiguity is never retried.
  if job.state != Intent {
    return job
  }
  let provider = (self.resolve)(deployment_id)
  if !(self.authorized)(owner, request.model(), deployment_id) {
    ignore(self.store.cancel(job.job_id, owner, false, (self.now)()))
    raise Unauthorized
  }
  ignore(self.store.begin_submission(job.job_id, owner, (self.now)()))
  // Also runs on task cancellation. If persistence is unavailable, startup
  // recovery converts the already durable Submitting state to Unknown.
  errdefer (ignore(
    self.store.submission_unknown(job.job_id, owner, (self.now)()),
  ) catch {
    _ => ()
  })
  let result = provider.submit(request)
  let attached = self.store.attach_provider(
    job.job_id,
    owner,
    result.id,
    (self.now)(),
  )
  if attached.state == Cancelling {
    return self.refresh_internal(attached)
  }
  let observed = self.store.observe(
    job.job_id,
    owner,
    result.state,
    result.progress,
    (self.now)(),
  )
  self.record_terminal(observed)
}

///|
async fn VideoRuntime::refresh_internal(
  self : VideoRuntime,
  previous : @jobs.StoredJob,
) -> @jobs.StoredJob {
  let mut job = self.store.get(previous.job_id, previous.owner)
  if job.termination_evidence_ref is Some(_) && job.execution_terminal {
    return self.record_terminal(job)
  }
  if job.execution_context is Some(context) &&
    self.store.termination_for_context(context) is Some(accepted) {
    if job.state == Intent {
      return self.record_terminal(
        self.store.cancel(
          job.job_id,
          job.owner,
          (self.now)() >= job.deadline_unix_ms,
          (self.now)(),
        ),
      )
    }
    return self.reconcile_verified_termination(
      job.job_id,
      job.owner,
      job.deployment_id,
      context,
      accepted.reference(),
      accepted.evidence.observed_unix_ms,
    )
  }
  let now = (self.now)()
  let expired = now >= job.retain_until_unix_ms ||
    (!job.execution_terminal && now >= job.deadline_unix_ms)
  // A local durable deadline is conclusive even if the authority is down.
  // For unexpired jobs, an unavailable authority must leave state unchanged.
  if expired {
    job = self.store.cancel(job.job_id, job.owner, expired, now)
  } else if !(self.authorized)(job.owner, job.model, job.deployment_id) {
    job = self.store.cancel(job.job_id, job.owner, false, now)
  }
  if [@jobs.State::Cancelled, Expired].contains(job.state) {
    return self.record_terminal(job)
  }
  // Unknown submissions have no safely attributable provider job to delete.
  // Keep the capacity slot until an operator reconciles a real provider ID.
  guard job.provider_job_id is Some(id) else {
    return self.record_terminal(job)
  }
  if job.state != Cancelling && job.state != Queued && job.state != Running {
    return self.record_terminal(job)
  }
  let provider = (self.resolve)(job.deployment_id)
  if job.state == Cancelling {
    if provider.delete(id) {
      job = self.store.acknowledge_deletion(
        job.job_id,
        job.owner,
        id,
        (self.now)(),
      )
    }
  } else if [@jobs.State::Queued, Running].contains(job.state) {
    let result = provider.poll(id)
    job = self.store.observe(
      job.job_id,
      job.owner,
      result.state,
      result.progress,
      (self.now)(),
    )
  }
  self.record_terminal(job)
}

///|
pub async fn VideoRuntime::get(
  self : VideoRuntime,
  id : String,
  owner : @jobs.Owner,
) -> @jobs.StoredJob {
  let job = self.store.get(id, owner)
  if !(self.authorized)(owner, job.model, job.deployment_id) {
    raise Unauthorized
  }
  self.refresh_internal(job)
}

///|
pub async fn VideoRuntime::cancel(
  self : VideoRuntime,
  id : String,
  owner : @jobs.Owner,
) -> @jobs.StoredJob {
  let job = self.store.get(id, owner)
  if !(self.authorized)(owner, job.model, job.deployment_id) {
    raise Unauthorized
  }
  let cancelled = self.store.cancel(id, owner, false, (self.now)())
  self.refresh_internal(cancelled)
}

///|
/// Operator-only recovery: the caller must attest the mapping outside this
/// runtime. Poll the original provider before attaching; never create a job.
pub async fn VideoRuntime::reconcile_submission(
  self : VideoRuntime,
  id : String,
  owner : @jobs.Owner,
  provider_id : String,
) -> @jobs.StoredJob {
  let job = self.store.get(id, owner)
  let provider = (self.resolve)(job.deployment_id)
  let observed = provider.poll(provider_id)
  let attached = self.store.attach_provider(
    id,
    owner,
    observed.id,
    (self.now)(),
  )
  if attached.state == Cancelling {
    return self.refresh_internal(attached)
  }
  let updated = self.store.observe(
    id,
    owner,
    observed.state,
    observed.progress,
    (self.now)(),
  )
  self.record_terminal(updated)
}

///|
/// A bounded sweep returns only counts, never tenant prompts or provider URLs.
/// One unavailable provider must not block cancellation for unrelated orders.
pub async fn VideoRuntime::reconcile(self : VideoRuntime) -> (Int, Int) {
  let saved = self.store.snapshot()
  let mut updated = 0
  let mut failed = 0
  let pending = saved.jobs.filter(job => {
    !([@jobs.State::Cancelled, Expired].contains(job.state) &&
    job.usage_receipt is Some(_))
  })
  // Expiring jobs are serviced first; at most eight network requests run at
  // once. A slow provider cannot serialize cancellation of every other order.
  pending.sort_by_key(job => job.deadline_unix_ms)
  let mut next = 0
  @async.with_task_group <| group => {
    for _ in 0..<pending.length().min(8) {
      group.spawn_bg(() => {
        while next < pending.length() {
          // Claim a record before the first await (cooperative async runtime).
          let job = pending[next]
          next += 1
          try {
            ignore(self.refresh_internal(job))
            updated += 1
          } catch {
            _ => failed += 1
          }
        }
      })
    }
  }
  (updated, failed)
}

///|
pub async fn VideoRuntime::content(
  self : VideoRuntime,
  id : String,
  owner : @jobs.Owner,
  maximum_bytes : Int64,
  write_chunk : async (Bytes) -> Unit,
) -> Int64 {
  let job = self.get(id, owner)
  guard job.state == Completed &&
    job.termination_evidence_ref is None &&
    (self.now)() < job.retain_until_unix_ms &&
    job.provider_job_id is Some(provider_id) else {
    raise ContentUnavailable
  }
  let provider = (self.resolve)(job.deployment_id)
  provider.content(provider_id, maximum_bytes, bytes => {
    let current = self.store.get(id, owner)
    if current.state != Completed ||
      current.termination_evidence_ref is Some(_) ||
      (self.now)() >= current.retain_until_unix_ms ||
      !(self.authorized)(owner, current.model, current.deployment_id) {
      raise Unauthorized
    }
    write_chunk(bytes)
  })
}
