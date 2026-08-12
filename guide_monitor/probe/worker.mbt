///|
fn probe_failure_code(error : Error) -> String {
  match error {
    GuideProbeError::RedirectRejected => "RedirectRejected"
    GuideProbeError::ResponseTooLarge => "ResponseTooLarge"
    GuideProbeError::MalformedResponse => "MalformedResponse"
    GuideProbeError::UntrustedResponse => "UntrustedResponse"
    _ => "TransportUnavailable"
  }
}

///|
fn failed_observation(
  plan : @guide_monitor.GuideProbePlan,
  observation_secret : String,
  now_unix_ms : Int64,
) -> @guide_monitor.GuideHealthObservation {
  @guide_monitor.sign_observation(
    {
      version: @guide_monitor.contract_version,
      observation_id: "guide-observation-\{plan.correlation_receipt}",
      target_ref: plan.target_ref,
      correlation_receipt: plan.correlation_receipt,
      scheduled_unix_ms: plan.scheduled_unix_ms,
      observed_unix_ms: now_unix_ms.max(plan.scheduled_unix_ms),
      coursebook_ok: false,
      admin_diagnostics_enabled: false,
      admin_diagnostics_ok: false,
      knowledge_revision: "unavailable",
      knowledge_stale: false,
      knowledge_age_ms: 0L,
      signature: "",
    },
    observation_secret,
  )
}

///|
pub async fn GuideProbeWorker::open(
  config : GuideProbeConfig,
  policy : @guide_monitor.GuideMonitorPolicy,
  scheduler_path : String,
  notifications : @store.NotificationStore,
  identity_secret : String,
  observation_secret : String,
) -> GuideProbeWorker {
  validate_config(config)
  @guide_monitor.validate_policy(policy)
  if identity_secret.length() < 32 || observation_secret.length() < 32 {
    raise InvalidConfiguration("guide probe signing secrets are too short")
  }
  let scheduler = GuideProbeScheduler::open(scheduler_path)
  {
    config,
    policy,
    scheduler,
    notifications,
    identity_secret,
    observation_secret,
  }
}

/// One scheduled execution. Transport and response failures are converted into
/// a signed unavailable observation so the durable operator alert is still
/// reconciled. State persistence failures remain fail-closed.

///|
pub async fn GuideProbeWorker::run_once(
  self : GuideProbeWorker,
  now_unix_ms : Int64,
) -> GuideProbeRunResult {
  let plan = match self.scheduler.reserve_due(self.policy, now_unix_ms) {
    None =>
      return {
        was_due: false,
        probe_ok: true,
        failure_code: None,
        monitor_result: None,
      }
    Some(plan) => plan
  }
  let mut failure_code : String? = None
  let observation = fetch_observation(
    self.config,
    self.policy,
    plan,
    self.identity_secret,
    self.observation_secret,
    now_unix_ms,
  ) catch {
    error => {
      failure_code = Some(probe_failure_code(error))
      failed_observation(plan, self.observation_secret, now_unix_ms)
    }
  }
  let monitor_result = @guide_monitor.reconcile_planned_observation(
    self.notifications,
    self.policy,
    plan,
    observation,
    self.observation_secret,
    now_unix_ms,
  )
  {
    was_due: true,
    probe_ok: failure_code is None,
    failure_code,
    monitor_result: Some(monitor_result),
  }
}

/// Resilient periodic loop. A single filesystem, transport, decoding, or store
/// failure cannot terminate the controller's long-running monitor task.

///|
pub async fn GuideProbeWorker::run_forever(self : GuideProbeWorker) -> Unit {
  for ;; {
    ignore(self.run_once(@async.now())) catch {
      _ => ()
    }
    @async.sleep(self.policy.probe_interval_ms.to_int().max(1000))
  }
}
