///|
/// Resolves an assertion from the trusted TLS ingress without retaining a raw
/// certificate distinguished name. With standard auth-TLS headers, the opaque
/// subject is mtls:sha256:<hex(sha256(utf8(ssl-client-subject-dn)))> and
/// verification must be SUCCESS. X-LunaNexa-Subject is accepted only when the
/// server has independently proved that the TCP peer is loopback, or for the
/// explicitly trusted in-process `handle` adapter used by acceptance tests.
fn trusted_workspace_subject(
  headers : Map[String, String],
  allow_asserted_subject : Bool,
) -> String? {
  match header(headers, "ssl-client-verify") {
    Some(value) if value == "SUCCESS" => {
      guard header(headers, "ssl-client-subject-dn") is Some(raw_dn) &&
        raw_dn.trim() != "" else {
        return None
      }
      return Some("mtls:sha256:\{digest_hex(raw_dn.trim().to_owned())}")
    }
    Some(_) => return None
    None => ()
  }
  if !allow_asserted_subject {
    return None
  }
  guard header(headers, "X-LunaNexa-Subject") is Some(asserted_subject) else {
    return None
  }
  let subject_ref = asserted_subject.trim().to_owned()
  if !@workspace.valid_identifier(subject_ref) {
    return None
  }
  Some(subject_ref)
}

///|
fn workspace_capability(
  capability : @contracts.Capability,
) -> @workspace.WorkspaceCapability? {
  match capability {
    @contracts.Capability::TextGenerate => Some(TextGenerate)
    EmbeddingCreate => Some(EmbeddingCreate)
    ImageGenerate => Some(ImageGenerate)
    VideoGenerate => Some(VideoGenerate)
    AudioGenerate => Some(AudioGenerate)
    ModelEvaluate | ModelTrain => None
  }
}

///|
async fn ApiService::workspace_admit(
  self : ApiService,
  headers : Map[String, String],
  request : @contracts.WorkloadEnvelope,
  allow_asserted_subject : Bool,
) -> (HttpReply?, Bool) {
  if !self.require_workspace_lease {
    return (None, false)
  }
  @contracts.validate_workload(request) catch {
    _ =>
      return (
        Some(
          api_error(
            400, "InvalidRequest", "invalid canonical workload contract", false,
          ),
        ),
        false,
      )
  }
  guard self.workspace_directory is Some(directory) else {
    return (
      Some(
        api_error(
          503, "WorkspaceUnavailable", "workspace lease enforcement is enabled but durable workspace state is unavailable",
          true,
        ),
      ),
      false,
    )
  }
  guard trusted_workspace_subject(headers, allow_asserted_subject)
    is Some(subject_ref) else {
    return (
      Some(
        api_error(
          401, "Unauthenticated", "a verified auth-TLS identity or accepted loopback subject assertion is required",
          false,
        ),
      ),
      false,
    )
  }
  let now = @async.now()
  let authorization = try
    directory.authorize_subject_for_tenant(
      subject_ref,
      request.tenant_ref,
      Developer,
      now,
    )
  catch {
    _ =>
      return (
        Some(
          api_error(
            403, "WorkspaceAccessDenied", "active developer access and an unexpired workspace lease are required",
            false,
          ),
        ),
        false,
      )
  } noraise {
    value => value
  }
  guard workspace_capability(request.capability) is Some(capability) &&
    @workspace.capability_limit(authorization.lease, capability) is Some(limit) else {
    return (
      Some(
        api_error(
          403, "WorkspaceCapabilityDenied", "the active workspace lease does not authorize this capability",
          false,
        ),
      ),
      false,
    )
  }
  let actual_input_units = @utf8.encode(request.payload.stringify()).length()
  if actual_input_units > request.resource_ceiling.max_input_units {
    return (
      Some(
        api_error(
          400, "InvalidRequest", "the canonical workload payload exceeds its declared input ceiling",
          false,
        ),
      ),
      false,
    )
  }
  if actual_input_units > limit.max_input_units_per_request ||
    request.resource_ceiling.max_input_units > limit.max_input_units_per_request ||
    request.resource_ceiling.max_output_units >
    limit.max_output_units_per_request {
    return (
      Some(
        api_error(
          403, "WorkspaceLimitExceeded", "the request resource ceiling exceeds the active workspace lease",
          false,
        ),
      ),
      false,
    )
  }
  let request_key = idempotency_scope(request)
  let replay_exists = match self.cached_result(request_key) {
    Some(_) => true
    None => self.store.idempotent_result(request_key) is Some(_)
  }
  if replay_exists {
    let owned = try
      directory.workload_owned_by(
        request.workload_id,
        subject_ref,
        request.tenant_ref,
        now,
      )
    catch {
      _ => false
    } noraise {
      value => value
    }
    if owned {
      return (None, false)
    }
    return (
      Some(
        api_error(
          403, "WorkspaceAccessDenied", "workload ownership could not be proven for this replay",
          false,
        ),
      ),
      false,
    )
  }
  if request.deadline_unix_ms <= now {
    return (
      Some(
        api_error(
          400, "InvalidRequest", "the workload deadline has already elapsed", false,
        ),
      ),
      false,
    )
  }
  let maximum_reservation_expiry = now + 86400000L
  let reservation_expiry = if request.deadline_unix_ms <
    maximum_reservation_expiry {
    request.deadline_unix_ms
  } else {
    maximum_reservation_expiry
  }
  directory.reserve_workload(
    authorization.lease.lease_id,
    subject_ref,
    request.tenant_ref,
    capability,
    request.workload_id,
    request_key,
    reservation_expiry,
    now,
  ) catch {
    @workspace.WorkspaceDirectoryError::ConcurrentRequestLimitExceeded(_) =>
      return (
        Some(
          api_error(
            429, "WorkspaceConcurrencyExceeded", "the workspace capability concurrency limit is in use",
            true,
          ),
        ),
        false,
      )
    @workspace.WorkspaceDirectoryError::HourlyRequestLimitExceeded(_) =>
      return (
        Some(
          api_error(
            429, "WorkspaceRateExceeded", "the workspace capability hourly request limit is exhausted",
            true,
          ),
        ),
        false,
      )
    @workspace.WorkspaceDirectoryError::DuplicateRecord(_) =>
      return (
        Some(
          api_error(
            409, "WorkspaceDuplicateWorkload", "the workspace workload identity was already reserved",
            false,
          ),
        ),
        false,
      )
    _ =>
      return (
        Some(
          api_error(
            403, "WorkspaceAccessDenied", "workspace authority changed before admission completed",
            false,
          ),
        ),
        false,
      )
  }
  (None, true)
}

///|
async fn ApiService::release_workspace_admission(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
  reserved : Bool,
) -> Unit {
  if !reserved {
    return
  }
  guard self.workspace_directory is Some(directory) else { return }
  directory.release_workload(
    request.workload_id,
    idempotency_scope(request),
    @async.now(),
  ) catch {
    _ => ()
  }
}

///|
async fn ApiService::workspace_workload_access_error(
  self : ApiService,
  headers : Map[String, String],
  workload_id : String,
  allow_asserted_subject : Bool,
) -> HttpReply? {
  if !self.require_workspace_lease {
    return None
  }
  guard self.workspace_directory is Some(directory) else {
    return Some(
      api_error(
        503, "WorkspaceUnavailable", "durable workspace ownership state is unavailable",
        true,
      ),
    )
  }
  guard trusted_workspace_subject(headers, allow_asserted_subject)
    is Some(subject_ref) else {
    return Some(
      api_error(
        401, "Unauthenticated", "a verified auth-TLS identity or accepted loopback subject assertion is required",
        false,
      ),
    )
  }
  let owned = try
    directory.workload_owned_by_subject(workload_id, subject_ref, @async.now())
  catch {
    _ => false
  } noraise {
    value => value
  }
  if !owned {
    return Some(
      api_error(404, "NotFound", "workload receipt was not found", false),
    )
  }
  None
}

///|
fn decode_workspace_user(body : String) -> @workspace.WorkspaceUser? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_workspace_access_grant(
  body : String,
) -> @workspace.WorkspaceAccessGrant? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_workspace_lease(body : String) -> @workspace.WorkspaceLease? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
async fn ApiService::transition_workspace_user(
  self : ApiService,
  user_id : String,
  to : @workspace.WorkspaceUserState,
  action : String,
) -> HttpReply {
  if !@workspace.valid_identifier(user_id) {
    return api_error(404, "NotFound", "workspace user was not found", false)
  }
  guard self.workspace_directory is Some(directory) else {
    return api_error(
      503, "WorkspaceUnavailable", "durable workspace state is unavailable", true,
    )
  }
  let now = @async.now()
  let (previous, persisted) = try {
    match to {
      UserActive => directory.activate_user_with_prior(user_id, now)
      UserSuspended => directory.suspend_user_with_prior(user_id, now)
      UserRevoked => directory.revoke_user_with_prior(user_id, now)
      UserInvited =>
        return api_error(
          409, "WorkspaceRejected", "workspace user transition was rejected", false,
        )
    }
  } catch {
    @workspace.WorkspaceDirectoryError::RecordNotFound(_) =>
      return api_error(404, "NotFound", "workspace user was not found", false)
    _ =>
      return api_error(
        409, "WorkspaceRejected", "workspace user transition was rejected", false,
      )
  } noraise {
    value => value
  }
  let receipt = "workspace-user-transition:\{user_id}:\{now}"
  self.operator_transition_audit(
    action,
    user_id,
    "\{Repr(previous.state)}",
    "\{Repr(persisted.state)}",
    receipt,
  )
  json_reply(200, persisted.to_json())
}

///|
async fn ApiService::activate_workspace_lease(
  self : ApiService,
  lease_id : String,
) -> HttpReply {
  if !@workspace.valid_identifier(lease_id) {
    return api_error(404, "NotFound", "workspace lease was not found", false)
  }
  guard self.workspace_directory is Some(directory) else {
    return api_error(
      503, "WorkspaceUnavailable", "durable workspace state is unavailable", true,
    )
  }
  let now = @async.now()
  let (previous, persisted) = try
    directory.activate_lease_with_prior(lease_id, now)
  catch {
    @workspace.WorkspaceDirectoryError::RecordNotFound(_) =>
      return api_error(404, "NotFound", "workspace lease was not found", false)
    _ =>
      return api_error(
        409, "WorkspaceRejected", "workspace lease activation was rejected", false,
      )
  } noraise {
    value => value
  }
  let receipt = "workspace-lease-activate:\{lease_id}:\{now}"
  self.operator_transition_audit(
    "workspace.lease.activate",
    lease_id,
    "\{Repr(previous.state)}",
    "\{Repr(persisted.state)}",
    receipt,
  )
  json_reply(200, persisted.to_json())
}
