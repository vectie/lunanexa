///|
priv struct AnnouncementIntent {
  announcement_id : String
  tenant_ref : String
  title : String
  body : String
  expires_unix_ms : Int64
} derive(FromJson)

///|
async fn ApiService::publish_announcement(
  self : ApiService,
  headers : Map[String, String],
  body : String,
  now : Int64,
) -> HttpReply {
  guard self.operator_identity(headers) is Some(operator_id) else {
    return api_error(
      401, "Unauthorized", "operator authorization is required", false,
    )
  }
  let intent : AnnouncementIntent = @json.from_json(@json.parse(body)) catch {
    _ =>
      return api_error(
        400, "InvalidRequest", "valid announcement is required", false,
      )
  }
  guard self.notification_store is Some(store) &&
    self.portal_store is Some(portal) else {
    return api_error(
      503, "Unavailable", "notification authority is unavailable", true,
    )
  }
  if !@contracts.valid_identifier(intent.announcement_id) ||
    !portal.snapshot().memberships.any(membership => {
      membership.active && membership.tenant_ref == intent.tenant_ref
    }) ||
    intent.expires_unix_ms <= now ||
    intent.expires_unix_ms - now > 2592000000L {
    return api_error(
      400, "InvalidRequest", "an active tenant and bounded future expiry are required",
      false,
    )
  }
  let audience = @notifications.NotificationAudience::TenantUsers(
    tenant_ref=intent.tenant_ref,
  )
  let key = "announcement-\{intent.announcement_id}"
  if store.snapshot().records.any(record => {
      record.event.notification_id == key && record.event.audience != audience
    }) {
    return api_error(
      409, "AnnouncementConflict", "announcement identifiers are immutable", false,
    )
  }
  if store.record_by_deduplication_key(key, audience) is Some(existing) {
    if existing.event.parameters.get("title") != Some(intent.title) ||
      existing.event.parameters.get("body") != Some(intent.body) ||
      existing.event.expires_unix_ms != Some(intent.expires_unix_ms) {
      return api_error(
        409, "AnnouncementConflict", "announcement identifiers are immutable", false,
      )
    }
    return json_reply(200, existing.to_json())
  }
  let event : @notifications.NotificationEvent = {
    version: @notifications.contract_version,
    notification_id: key,
    deduplication_key: key,
    source_receipt: "announcement:\{intent.announcement_id}:\{operator_id}",
    topic: Announcement,
    code: "PlatformAnnouncement",
    severity: Information,
    audience,
    title_key: "notifications.PlatformAnnouncement.title",
    body_key: "notifications.PlatformAnnouncement.body",
    parameters: { "title": intent.title, "body": intent.body },
    created_unix_ms: now,
    expires_unix_ms: Some(intent.expires_unix_ms),
  }
  // Existing notification validation permits bounded printable plain text only.
  json_reply(201, store.enqueue(event).to_json()) catch {
    error => notification_error_reply(error)
  }
}

///|
async fn ApiService::trial_summary(self : ApiService, now : Int64) -> Json {
  guard self.account_store is Some(accounts) else {
    return (None : String?).to_json()
  }
  let trials = accounts.snapshot().trials.unwrap_or([])
  let memberships = match self.portal_store {
    Some(portal) => portal.snapshot().memberships
    None => []
  }
  let account_views = accounts.views()
  let converted = trials.count_if(trial => {
    trial.revoked_unix_ms is Some(_) &&
    account_views.any(account => {
      account.account_id == trial.account_id &&
      memberships.any(membership => {
        membership.subject_ref == account.subject_ref &&
        membership.active &&
        membership.organization_id != trial.organization_id &&
        @portal.role_allows(membership.roles, Developer)
      })
    })
  })
  {
    "registered_trials": trials.length().to_json(),
    "active_trials": trials
    .count_if(t => {
      t.revoked_unix_ms is None &&
      t.starts_unix_ms <= now &&
      t.expires_unix_ms > now
    })
    .to_json(),
    "expired_trials": trials
    .count_if(t => t.revoked_unix_ms is None && t.expires_unix_ms <= now)
    .to_json(),
    "converted_trials": converted.to_json(),
    "generated_unix_ms": now.to_json(),
  }
}

///|
async fn ApiService::invoke_trial_session(
  self : ApiService,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  let now = @async.now()
  guard self.enterprise_session_subject(headers) is Some(subject) &&
    self.account_store is Some(accounts) &&
    accounts.active_trial_for_subject(subject, now) is Some(trial) else {
    return api_error(
      403, "TrialRequired", "an active signed-in trial is required", false,
    )
  }
  guard decode_workload(body) is Some(request) &&
    ephemeral_only(request) &&
    request.tenant_ref == trial.tenant_ref &&
    trial.allowed_models.contains(request.model_selector) &&
    request.capability == TextGenerate &&
    self.require_workspace_lease else {
    return api_error(
      403, "TrialScopeDenied", "request must remain within the trial model and tenant scope",
      false,
    )
  }
  guard self.portal_store is Some(portal) else {
    return api_error(
      503, "Unavailable", "membership authority is unavailable", true,
    )
  }
  let membership = portal.self_view_for_organization(
    subject,
    trial.organization_id,
  ) catch {
    _ =>
      return api_error(
        403, "TrialScopeDenied", "active trial membership is required", false,
      )
  }
  if !membership.membership.active ||
    !@portal.role_allows(membership.membership.roles, Developer) ||
    membership.membership.tenant_ref != trial.tenant_ref {
    return api_error(
      403, "TrialScopeDenied", "active trial membership is required", false,
    )
  }
  let internal_headers = { "X-LunaNexa-Subject": subject }
  let (rejected, reserved) = self.workspace_admit(
    internal_headers, request, true,
  )
  if rejected is Some(reply) {
    return reply
  }
  defer self.release_workspace_admission(request, reserved)
  let legacy_consumed = match self.access_store {
    Some(access) =>
      access
      .views_for_subject(trial.tenant_ref, subject)
      .filter(value => Some(value.key_id) == trial.api_key_id)
      .get(0)
      .map(value => value.consumed_requests)
      .unwrap_or(0L)
    None => 0L
  }
  if reserved &&
    !accounts.consume_trial_request(trial.trial_id, legacy_consumed, now) {
    return api_error(
      429, "QuotaExceeded", "trial request quota is exhausted", false,
    )
  }
  self.invoke_workload(request, {
    key_id: "trial-session-\{trial.trial_id}",
    tenant_ref: trial.tenant_ref,
    subject_ref: subject,
    organization_id: trial.organization_id,
    project_id: trial.project_id,
  })
}
