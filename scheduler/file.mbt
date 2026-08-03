///|
pub(all) struct ActiveAdmission {
  workload_id : String
  tenant_ref : String
  accepted_unix_ms : Int64
  deadline_unix_ms : Int64
  priority : @contracts.Priority
  started_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TenantUsage {
  tenant_ref : String
  accelerator_ms : Int64
  completed_workloads : Int64
  window_started_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SchedulerSnapshot {
  schema_version : String
  capacity : Int
  quotas : Array[TenantQuota]
  active : Array[ActiveAdmission]
  usage : Array[TenantUsage]
  decisions : Array[PlacementDecision]
  queued_count : Int?
  running_count : Int?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror SchedulerStateError {
  InvalidSchedulerState(String)
} derive(Debug, Eq)

///|
pub struct FileScheduler {
  path : String
  mut capacity : Int
  quotas : Map[String, TenantQuota]
  active : Map[String, ActiveAdmission]
  usage : Map[String, TenantUsage]
  decisions : Array[PlacementDecision]
  mutex : @async.Mutex
}

///|
fn FileScheduler::snapshot_unlocked(self : FileScheduler) -> SchedulerSnapshot {
  let active = [ for _, value in self.active => value ]
  {
    schema_version: "lunanexa.scheduler.v2",
    capacity: self.capacity,
    quotas: [
      for _, value in self.quotas => value
    ],
    active,
    usage: [
      for _, value in self.usage => value
    ],
    decisions: self.decisions.copy(),
    queued_count: Some(active.count_if(value => value.started_unix_ms is None)),
    running_count: Some(
      active.count_if(value => value.started_unix_ms is Some(_)),
    ),
  }
}

///|
async fn write_scheduler(path : String, snapshot : SchedulerSnapshot) -> Unit {
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
pub async fn FileScheduler::open(
  path : String,
  capacity : Int,
) -> FileScheduler {
  let scheduler : FileScheduler = {
    path,
    capacity: capacity.max(1),
    quotas: Map([]),
    active: Map([]),
    usage: Map([]),
    decisions: [],
    mutex: @async.Mutex::Mutex(),
  }
  let mut pruned = false
  if @fs.exists(path) {
    let snapshot : SchedulerSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error => raise InvalidSchedulerState("\{to_repr(error)}")
    }
    if snapshot.schema_version != "lunanexa.scheduler.v2" ||
      snapshot.capacity <= 0 {
      raise InvalidSchedulerState("unsupported or invalid scheduler snapshot")
    }
    scheduler.capacity = snapshot.capacity
    for quota in snapshot.quotas {
      scheduler.quotas[quota.tenant_ref] = quota
    }
    for admission in snapshot.active {
      if admission.deadline_unix_ms > @async.now() {
        scheduler.active[admission.workload_id] = admission
      } else {
        pruned = true
      }
    }
    for usage in snapshot.usage {
      scheduler.usage[usage.tenant_ref] = usage
    }
    scheduler.decisions.push_iter(snapshot.decisions.iter())
    if pruned {
      write_scheduler(path, scheduler.snapshot_unlocked())
    }
  } else {
    write_scheduler(path, scheduler.snapshot_unlocked())
  }
  scheduler
}

///|
async fn FileScheduler::persist(self : FileScheduler) -> Unit {
  write_scheduler(self.path, self.snapshot_unlocked())
}

///|
pub async fn FileScheduler::set_quota(
  self : FileScheduler,
  quota : TenantQuota,
) -> Unit {
  if quota.tenant_ref == "" ||
    quota.max_inflight <= 0 ||
    quota.max_accelerator_ms <= 0L ||
    quota.window_ms <= 0L {
    raise InvalidSchedulerState("tenant quota must have positive limits")
  }
  self.mutex.acquire()
  try {
    self.quotas[quota.tenant_ref] = quota
    self.persist()
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}

///|
pub async fn FileScheduler::admit(
  self : FileScheduler,
  request : @contracts.WorkloadEnvelope,
  now_unix_ms : Int64,
) -> AdmissionResult {
  self.mutex.acquire()
  if self.active.contains(request.workload_id) {
    self.mutex.release()
    return Rejected(reason=WorkloadAlreadyActive)
  }
  if request.deadline_unix_ms <= now_unix_ms {
    self.mutex.release()
    return Rejected(reason=DeadlineImpossible)
  }
  guard self.quotas.get(request.tenant_ref) is Some(quota) else {
    self.mutex.release()
    return Rejected(reason=QuotaExceeded)
  }
  let tenant_inflight = self.active
    .values()
    .filter(admission => admission.tenant_ref == request.tenant_ref)
    .length()
  let current_usage = self.usage
    .get(request.tenant_ref)
    .unwrap_or({
      tenant_ref: request.tenant_ref,
      accelerator_ms: 0L,
      completed_workloads: 0L,
      window_started_unix_ms: now_unix_ms,
    })
  let current_usage = if now_unix_ms >=
    current_usage.window_started_unix_ms + quota.window_ms {
    {
      tenant_ref: request.tenant_ref,
      accelerator_ms: 0L,
      completed_workloads: 0L,
      window_started_unix_ms: now_unix_ms,
    }
  } else {
    current_usage
  }
  self.usage[request.tenant_ref] = current_usage
  let consumed = current_usage.accelerator_ms
  if tenant_inflight >= quota.max_inflight ||
    consumed >= quota.max_accelerator_ms {
    self.mutex.release()
    return Rejected(reason=QuotaExceeded)
  }
  if self.active.length() >=
    priority_capacity_limit(self.capacity, request.priority) {
    self.mutex.release()
    return Rejected(reason=AdmissionCapacityExceeded)
  }
  let queue_position = self.active.length()
  self.active[request.workload_id] = {
    workload_id: request.workload_id,
    tenant_ref: request.tenant_ref,
    accepted_unix_ms: now_unix_ms,
    deadline_unix_ms: request.deadline_unix_ms,
    priority: request.priority,
    started_unix_ms: None,
  }
  try self.persist() catch {
    error => {
      ignore(self.active.remove(request.workload_id))
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  Accepted(queue_position~)
}

///|
pub async fn FileScheduler::mark_started(
  self : FileScheduler,
  workload_id : String,
  started_unix_ms : Int64,
) -> Unit {
  self.mutex.acquire()
  guard self.active.get(workload_id) is Some(admission) else {
    self.mutex.release()
    return
  }
  self.active[workload_id] = {
    ..admission,
    started_unix_ms: Some(started_unix_ms),
  }
  try self.persist() catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}

///|
pub async fn FileScheduler::complete(
  self : FileScheduler,
  workload_id : String,
  accelerator_ms : Int64,
) -> Unit {
  self.mutex.acquire()
  guard self.active.get(workload_id) is Some(admission) else {
    self.mutex.release()
    return
  }
  ignore(self.active.remove(workload_id))
  let current = self.usage
    .get(admission.tenant_ref)
    .unwrap_or({
      tenant_ref: admission.tenant_ref,
      accelerator_ms: 0L,
      completed_workloads: 0L,
      window_started_unix_ms: admission.accepted_unix_ms,
    })
  self.usage[admission.tenant_ref] = {
    ..current,
    accelerator_ms: current.accelerator_ms + accelerator_ms.max(0L),
    completed_workloads: current.completed_workloads + 1L,
  }
  try self.persist() catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}

///|
pub async fn FileScheduler::cancel(
  self : FileScheduler,
  workload_id : String,
) -> Bool {
  self.mutex.acquire()
  let removed = self.active.contains(workload_id)
  if removed {
    ignore(self.active.remove(workload_id))
    try self.persist() catch {
      error => {
        self.mutex.release()
        raise error
      }
    } noraise {
      _ => ()
    }
  }
  self.mutex.release()
  removed
}

///|
pub async fn FileScheduler::place(
  self : FileScheduler,
  nodes : Array[NodeSnapshot],
  requirements : PlacementRequirements,
  policy : ScorePolicy,
) -> PlacementDecision {
  let decision = place(nodes, requirements, policy)
  self.mutex.acquire()
  self.decisions.push(decision)
  while self.decisions.length() > 1024 {
    ignore(self.decisions.remove(0))
  }
  try self.persist() catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  decision
}

///|
pub async fn FileScheduler::snapshot(self : FileScheduler) -> SchedulerSnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}

///|
pub async fn FileScheduler::admission(
  self : FileScheduler,
  workload_id : String,
) -> ActiveAdmission? {
  self.mutex.acquire()
  let admission = self.active.get(workload_id)
  self.mutex.release()
  admission
}
