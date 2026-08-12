///|
fn validate_scheduler_state(
  state : GuideProbeSchedulerState,
) -> Unit raise GuideProbeError {
  if state.schema_version != scheduler_state_version ||
    state.sequence < 0L ||
    state.sequence > 9223372036854775806L ||
    state.last_scheduled_unix_ms.map_or(false, value => value <= 0L) {
    raise InvalidSchedulerState
  }
}

///|
async fn persist_scheduler_state(
  path : String,
  state : GuideProbeSchedulerState,
) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    state.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.chmod(temporary, 0o600)
  @fs.rename(temporary, path, replace=true)
  @fs.chmod(path, 0o600)
}

/// Opens the durable scheduler state. Corruption is fail-closed and is never
/// silently replaced with an empty sequence.

///|
pub async fn GuideProbeScheduler::open(path : String) -> GuideProbeScheduler {
  if path.trim() == "" {
    raise InvalidConfiguration("guide probe scheduler path is empty")
  }
  let state : GuideProbeSchedulerState = if @fs.exists(path) {
    @json.from_json(@json.parse(@fs.read_file(path).text())) catch {
      _ => raise InvalidSchedulerState
    }
  } else {
    {
      schema_version: scheduler_state_version,
      sequence: 0L,
      last_scheduled_unix_ms: None,
    }
  }
  validate_scheduler_state(state)
  if !@fs.exists(path) {
    persist_scheduler_state(path, state)
  } else {
    @fs.chmod(path, 0o600)
  }
  { path, state, mutex: Mutex() }
}

///|
pub async fn GuideProbeScheduler::snapshot(
  self : GuideProbeScheduler,
) -> GuideProbeSchedulerState {
  self.mutex.acquire()
  defer self.mutex.release()
  self.state
}

/// Persist the new sequence before a network call is made. A crash can skip one
/// probe, but can never replay the same signed schedule identity.

///|
pub async fn GuideProbeScheduler::reserve_due(
  self : GuideProbeScheduler,
  policy : @guide_monitor.GuideMonitorPolicy,
  now_unix_ms : Int64,
) -> @guide_monitor.GuideProbePlan? {
  self.mutex.acquire()
  defer self.mutex.release()
  if !@guide_monitor.probe_due(
      policy,
      self.state.last_scheduled_unix_ms,
      now_unix_ms,
    ) {
    return None
  }
  let next_sequence = self.state.sequence + 1L
  let plan = @guide_monitor.scheduled_probe_plan(
    policy, next_sequence, now_unix_ms,
  )
  let next = {
    schema_version: scheduler_state_version,
    sequence: next_sequence,
    last_scheduled_unix_ms: Some(now_unix_ms),
  }
  persist_scheduler_state(self.path, next)
  self.state = next
  Some(plan)
}
