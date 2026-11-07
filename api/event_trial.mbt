///|
/// Use the controller's existing authenticated-heartbeat clock-skew window.
/// A small positive node offset must not alternate a live replica in and out
/// of readiness; stale evidence and timestamps beyond the accepted window fail.
fn event_heartbeat_time_blocker(
  timestamp : Int64,
  now : Int64,
  timing : @settings.ControlTimingSettings,
) -> String? {
  if timestamp > now + timing.heartbeat_replay_window_ms {
    Some("heartbeat clock exceeds accepted skew")
  } else if timestamp < now - timing.heartbeat_timeout_ms {
    Some("heartbeat is stale")
  } else {
    None
  }
}

///|
async fn ApiService::event_trial_ready_nodes(
  self : ApiService,
  policy : @event_trial.Policy,
  now : Int64,
) -> Array[String] {
  if !self.event_text_routes.is_empty() {
    return self.external_event_ready_nodes(policy, now)
  }
  guard self.runtime.uses_direct_node_routing() &&
    self.scheduler is Some(scheduler) &&
    self.registry is Some(registry) &&
    registry.scheduling_target(policy.allowed_models[0], TextGenerate)
    is Some(target) &&
    target.model.artifact.digest == self.runtime.artifact_digest() &&
    target.runtime.version == self.runtime.runtime_version() &&
    target.runtime.image_digest == self.runtime.image_digest() else {
    return []
  }
  let assignments = self.store.assignments()
  let held = scheduler.snapshot().node_reservations.unwrap_or([])
  let heartbeats = self.store.heartbeats()
  // Async authority reads above may have yielded while new heartbeats arrived.
  let now = now.max(@async.now())
  let ready : Array[String] = []
  for heartbeat in heartbeats {
    if policy.node_ids.contains(heartbeat.node_id) &&
      !held.any(r => {
        r.state != Released && r.request.node_ids.contains(heartbeat.node_id)
      }) &&
      self.runtime.has_node_endpoint(heartbeat.node_id) &&
      heartbeat.inventory.labels.get(machine_usage_pool_label) == Some("trial") &&
      event_heartbeat_time_blocker(
        heartbeat.timestamp_unix_ms,
        now,
        self.global_settings.control_timing,
      )
      is None &&
      assignments.any(a => {
        a.node_id == heartbeat.node_id &&
        a.artifact.digest == target.model.artifact.digest &&
        a.runtime.name == target.runtime.name &&
        a.runtime.version == target.runtime.version &&
        a.runtime.image_digest == target.runtime.image_digest &&
        a.lease_expires_unix_ms > now &&
        heartbeat.running_deployments.contains(a.deployment_id)
      }) {
      let node = self.managed_scheduler_node(heartbeat, now)
      if node.state == Active &&
        target.model.compatible_architectures.contains(node.architecture) &&
        node.memory_free_mib >= target.model.minimum_memory_mib &&
        node.runtimes.contains(target.runtime.name) &&
        node.licensed_models.contains(target.model_key) &&
        node.allowed_data_classes.contains(Confidential) {
        ready.push(heartbeat.node_id)
      }
    }
  }
  ready
}

///|
async fn ApiService::event_trial_views(
  self : ApiService,
  now : Int64,
) -> Array[@event_trial.View] {
  guard self.account_store is Some(accounts) else { return [] }
  let snapshot = accounts.snapshot()
  let result : Array[@event_trial.View] = []
  for policy in snapshot.events.unwrap_or([]) {
    let (ready_nodes, blockers) = if self.event_text_routes.is_empty() {
      (self.event_trial_ready_nodes(policy, now), [])
    } else {
      self.external_event_readiness(policy, now)
    }
    if ready_nodes.length() != policy.node_ids.length() {
      blockers.push(
        "All selected, approved, unreserved trial nodes must serve the same model through strict node routing.",
      )
    }
    if !self.require_workspace_lease ||
      self.workspace_directory is None ||
      self.portal_store is None {
      blockers.push(
        "Workspace lease and membership authorities must be enabled.",
      )
    }
    if policy.ended(now) {
      blockers.push("Event has ended.")
    }
    result.push({
      policy,
      ready_nodes,
      blockers,
      registered_users: snapshot.trials
      .unwrap_or([])
      .count_if(t => t.event_id == Some(policy.event_id)),
    })
  }
  result
}

///|
async fn ApiService::save_event_trial(
  self : ApiService,
  operator_id : String,
  body : String,
  now : Int64,
) -> HttpReply {
  let policy : @event_trial.Policy = @json.from_json(@json.parse(body)) catch {
    _ => return api_error(400, "InvalidRequest", "invalid event policy", false)
  }
  if !policy.valid() ||
    policy.output_budget() >
    self.global_settings.request_budgets.openai_max_output_units ||
    (policy.registration_open && policy.ended(now)) {
    return api_error(
      400, "InvalidRequest", "use a fixed event window or ongoing seven-day trials, one approved model and one to four distinct nodes",
      false,
    )
  }
  guard self.account_store is Some(accounts) else {
    return api_error(503, "Unavailable", "account authority unavailable", true)
  }
  if policy.registration_open &&
    (
      !self.require_workspace_lease ||
      self.workspace_directory is None ||
      self.portal_store is None ||
      self.event_trial_ready_nodes(policy, now).length() !=
      policy.node_ids.length()
    ) {
    return api_error(
      409, "EventCapacityNotReady", "save as a draft; all selected trial replicas and workspace enforcement are required to open registration",
      true,
    )
  }
  let saved = accounts.put_event(policy) catch {
    error => return account_error(error)
  }
  // Policy is durable first. A retry and request-time reconciliation repair a
  // partial workspace write without resetting any trial dates or counters.
  try {
    for trial in accounts.snapshot().trials.unwrap_or([]) {
      if trial.event_id == Some(saved.event_id) {
        self.sync_trial_output_budget(trial, saved, now)
      }
    }
  } catch {
    _ =>
      return api_error(
        503, "TrialOutputSyncPending", "request budget policy saved; existing workspace synchronization is pending, retry saving",
        true,
      )
  }
  self.operator_audit_as(
    operator_id,
    "event-trial.configure",
    policy.event_id,
    "registration:\{policy.registration_open};input_bytes:\{policy.input_budget()};output_tokens:\{policy.output_budget()}",
  )
  json_reply(200, Json(saved))
}

///|
async fn ApiService::sync_trial_output_budget(
  self : ApiService,
  trial : @account.TrialEntitlement,
  policy : @event_trial.Policy,
  now : Int64,
) -> Unit {
  if trial.event_id != Some(policy.event_id) ||
    trial.revoked_unix_ms is Some(_) ||
    now < trial.starts_unix_ms ||
    now >= trial.expires_unix_ms {
    return
  }
  guard self.workspace_directory is Some(directory) else { return }
  ignore(
    directory.sync_policy_output_budget(
      trial.tenant_ref,
      "trial:\{trial.trial_id}",
      policy.output_budget(),
      now,
      input_bytes=policy.input_budget(),
    ),
  )
}

///|
async fn ApiService::sync_subject_trial_output(
  self : ApiService,
  subject : String,
  now : Int64,
) -> Unit {
  if self.account_store is Some(accounts) &&
    accounts.active_trial_for_subject(subject, now) is Some(trial) &&
    accounts.event_for_tenant(trial.tenant_ref) is Some(policy) {
    self.sync_trial_output_budget(trial, policy, now)
  }
}

///|
async fn ApiService::trial_request_budgets(
  self : ApiService,
  tenant : String,
) -> @settings.RequestBudgetSettings {
  let budgets = self.global_settings.request_budgets
  if self.account_store is Some(accounts) &&
    accounts.event_for_tenant(tenant) is Some(policy) {
    {
      ..budgets,
      openai_default_output_units: policy
      .output_budget()
      .min(budgets.openai_max_output_units),
    }
  } else {
    budgets
  }
}

///|
async fn ApiService::ensure_registration_trial(
  self : ApiService,
  account : @account.AccountView,
  now : Int64,
  lifetime_ms : Int64,
  maximum_requests : Int64,
  allowed_models : Array[String],
) -> @account.TrialEntitlement? {
  guard self.account_store is Some(accounts) else { return None }
  let snapshot = accounts.snapshot()
  let existing = accounts.trial_for_account(account.account_id)
  // A UI benchmark uses ordinary identity registration, but its explicit
  // one-hour event grant must not be preceded by the legacy public trial.
  // Only the 32 exact identities owned by the currently running test qualify.
  if existing is None &&
    self.model_benchmark is Some(benchmark) &&
    benchmark.owns_registration(account.email) {
    return None
  }
  let events = snapshot.events.unwrap_or([])
  // A retry resumes a partial provision with its original fixed expiry. It
  // never converts Wi-Fi, ordinary trial, or company authority into an event.
  let event = match existing {
    Some({ event_id: Some(id), .. }) =>
      events.iter().find_first(e => e.event_id == id)
    Some(_) => None
    None => events.iter().find_first(e => e.accepting(now))
  }
  if event is Some(policy) {
    if policy.ended(now) ||
      existing.map_or(false, t => {
        t.revoked_unix_ms is Some(_) || now >= t.expires_unix_ms
      }) {
      return existing
    }
    if existing is None &&
      self.event_trial_ready_nodes(policy, now).length() !=
      policy.node_ids.length() {
      raise Failure::Failure("event capacity is not ready")
    }
    if self.portal_store is Some(portal) &&
      portal.snapshot().memberships.any(m => {
        m.subject_ref == account.subject_ref &&
        m.active &&
        !m.membership_id.has_prefix("trial-membership-")
      }) {
      return None
    }
    return self.ensure_open_trial(
      account,
      now,
      policy.grant_expires(now) - now,
      policy.maximum_requests,
      policy.allowed_models,
      event=policy,
    )
  }
  if existing is Some(trial) {
    if lifetime_ms > 0L &&
      trial.revoked_unix_ms is None &&
      now < trial.expires_unix_ms {
      return self.ensure_open_trial(
        account,
        now,
        trial.expires_unix_ms - now,
        trial.maximum_requests,
        trial.allowed_models,
      )
    }
    return Some(trial)
  }
  // Once the operator selects event mode, outside-window registration creates
  // an account only; it must not fall back to a more permissive legacy trial.
  if snapshot.event_mode_selected.unwrap_or(false) {
    return None
  }
  self.ensure_open_trial(
    account, now, lifetime_ms, maximum_requests, allowed_models,
  )
}

///|
/// Explicit operator invitation supports a private rehearsal without opening
/// public registration. The same durable grant, scope, expiry and router apply.
async fn ApiService::enroll_event_participant(
  self : ApiService,
  operator_id : String,
  event_id : String,
  body : String,
  now : Int64,
) -> HttpReply {
  let intent = @json.parse(body) catch {
    _ =>
      return api_error(
        400, "InvalidRequest", "an existing account_id is required", false,
      )
  }
  guard intent is { "account_id": String(account_id), .. } else {
    return api_error(
      400, "InvalidRequest", "an existing account_id is required", false,
    )
  }
  guard self.account_store is Some(accounts) &&
    self.portal_store is Some(portal) &&
    self.workspace_directory is Some(_) &&
    self.require_workspace_lease else {
    return api_error(503, "Unavailable", "trial authorities unavailable", true)
  }
  guard accounts.snapshot().events
    .unwrap_or([])
    .iter()
    .find_first(e => e.event_id == event_id)
    is Some(policy) &&
    policy.within_window(now) else {
    return api_error(
      409, "EventTrialUnavailable", "event must be within its configured window",
      false,
    )
  }
  guard accounts.views().iter().find_first(a => a.account_id == account_id)
    is Some(account) else {
    return api_error(404, "NotFound", "account not found", false)
  }
  if account.state != Active ||
    account.roles != [EnterpriseUser] ||
    portal.snapshot().memberships.any(m => {
      m.subject_ref == account.subject_ref &&
      m.active &&
      !m.membership_id.has_prefix("trial-membership-")
    }) {
    return api_error(
      409, "EventScopeDenied", "event invitations cannot replace company or operator access",
      false,
    )
  }
  if accounts.trial_for_account(account_id) is Some(existing) &&
    (
      (
        existing.event_id != Some(event_id) &&
        existing.revoked_unix_ms is None &&
        now < existing.expires_unix_ms
      ) ||
      (
        existing.event_id == Some(event_id) &&
        (existing.revoked_unix_ms is Some(_) || now >= existing.expires_unix_ms)
      )
    ) {
    return api_error(
      409, "EventTrialUnavailable", "end the previous event grant before inviting this participant to a new event",
      false,
    )
  }
  if self.event_trial_ready_nodes(policy, now).length() !=
    policy.node_ids.length() {
    return api_error(
      409, "EventCapacityNotReady", "all selected replicas are required for enrollment",
      true,
    )
  }
  let trial = self.ensure_open_trial(
    account,
    now,
    policy.grant_expires(now) - now,
    policy.maximum_requests,
    policy.allowed_models,
    event=policy,
    operator_enrollment=true,
  ) catch {
    error => return account_error(error)
  }
  guard trial is Some(trial) else {
    return api_error(503, "Unavailable", "trial provisioning unavailable", true)
  }
  self.operator_audit_as(
    operator_id,
    "event-trial.invite",
    account_id,
    "event:\{event_id}:\{trial.trial_id}",
  )
  json_reply(201, Json(trial))
}
