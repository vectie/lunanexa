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
    observability: None,
    identity_secret,
    observation_secret,
  }
}

///| Installs the aggregate-only operational event sink. Probe responses and

///|
/// guide identities never enter observability payloads.
pub fn GuideProbeWorker::with_observability_store(
  self : GuideProbeWorker,
  observability : @observability.ObservabilityStore,
) -> GuideProbeWorker {
  { ..self, observability: Some(observability) }
}

///|
async fn GuideProbeWorker::record_probe_event(
  self : GuideProbeWorker,
  now_unix_ms : Int64,
  healthy : Bool,
  correlation_receipt : String,
  duration_ms : Int64,
) -> Unit {
  match self.observability {
    Some(store) =>
      store.record_component_event(
        "event-guide-probe-\{now_unix_ms}",
        now_unix_ms,
        if healthy {
          Information
        } else {
          Error
        },
        "guide-monitor",
        "GuideDiagnosticsProbeCompleted",
        correlation_receipt,
        "guide",
        if healthy {
          "healthy"
        } else {
          "degraded"
        },
        if healthy {
          200
        } else {
          503
        },
        duration_ms,
      )
    None => ()
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
  let started = @async.now()
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
  self.record_probe_event(
    now_unix_ms,
    failure_code is None &&
    !monitor_result.adapter_alert_active &&
    !monitor_result.knowledge_alert_active,
    plan.correlation_receipt,
    (@async.now() - started).max(0L),
  )
  {
    was_due: true,
    probe_ok: failure_code is None,
    failure_code,
    monitor_result: Some(monitor_result),
  }
}

/// Unexpected persistence or reconciliation failures are recorded when
/// possible and then propagated to the controller supervisor.

///|
pub async fn GuideProbeWorker::run_forever(self : GuideProbeWorker) -> Unit {
  for ;; {
    let now = @async.now()
    ignore(self.run_once(now)) catch {
      error => {
        ignore(
          self.record_probe_event(
            now,
            false,
            "guide-probe-worker-failed-\{now}",
            0L,
          ),
        ) catch {
          _ => ()
        }
        raise error
      }
    }
    @async.sleep(self.policy.probe_interval_ms.to_int().max(1000))
  }
}
