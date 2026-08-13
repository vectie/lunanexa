///|
fn credential_handoff_path(path : String) -> Bool {
  path.has_prefix("/v1/machine-credentials/") ||
  (
    path.has_prefix("/v1/machine-access/self/") &&
    (path.has_suffix("/credential") || path.has_suffix("/credential:redeem"))
  )
}

///|
priv struct CredentialRedemptionRequest {
  expected_generation : Int64
} derive(FromJson)

///|
fn decode_credential_redemption(body : String) -> CredentialRedemptionRequest? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn credential_lease_id(
  path : String,
  prefix : String,
  suffix : String,
) -> String? {
  if !path.has_prefix(prefix) ||
    !path.has_suffix(suffix) ||
    path.length() <= prefix.length() + suffix.length() {
    return None
  }
  let lease_id = path[prefix.length():path.length() - suffix.length()].to_owned()
  if @contracts.valid_identifier(lease_id) {
    Some(lease_id)
  } else {
    None
  }
}

///|
fn credential_error_reply(error : Error) -> HttpReply {
  match error {
    @credential.CredentialHandoffError::NotFound
    | @credential.CredentialHandoffError::Unauthorized =>
      api_error(404, "NotFound", "credential handoff was not found", false)
    @credential.CredentialHandoffError::AlreadyRedeemed =>
      api_error(
        409, "CredentialAlreadyRedeemed", "credential handoff is single use", false,
      )
    @credential.CredentialHandoffError::Expired =>
      api_error(
        409, "CredentialExpired", "credential handoff has expired", false,
      )
    @credential.CredentialHandoffError::Revoked =>
      api_error(
        409, "CredentialRevoked", "credential handoff was revoked", false,
      )
    @credential.CredentialHandoffError::StaleGeneration =>
      api_error(
        409, "StaleGeneration", "machine access changed; refresh before retrying",
        true,
      )
    @credential.CredentialHandoffError::IdempotencyConflict =>
      api_error(
        409, "IdempotencyConflict", "request identifier is already bound", false,
      )
    _ =>
      api_error(
        400, "CredentialHandoffRejected", "credential handoff was rejected", false,
      )
  }
}

///|
async fn ApiService::credential_subject_context(
  self : ApiService,
  headers : Map[String, String],
  allow_asserted_subject : Bool,
) -> String? {
  guard self.portal_store is Some(portal) &&
    self.portal_subject(headers, allow_asserted_subject) is Some(subject_ref) else {
    return None
  }
  try portal.self_view(subject_ref) catch {
    _ => None
  } noraise {
    _ => Some(subject_ref)
  }
}

///|
async fn ApiService::handle_credential_handoff(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.credential_handoff_store is Some(credentials) &&
    self.exclusive_lease_store is Some(leases) else {
    return api_error(
      503, "CredentialHandoffUnavailable", "credential broker state is unavailable",
      true,
    )
  }
  let operator_prefix = "/v1/machine-credentials/"
  if credential_lease_id(path, operator_prefix, ":issue") is Some(lease_id) {
    if verb != Post {
      return api_error(405, "MethodNotAllowed", "POST required", false)
    }
    if !bearer_authorized(headers, self.operator_token) {
      return api_error(
        401, "Unauthenticated", "valid operator authority is required", false,
      )
    }
    if !credentials.issuer_adapter_ready(@async.now()) {
      return api_error(
        503, "CredentialIssuerNotReady", "external credential issuer evidence is unavailable or expired",
        true,
      )
    }
    guard leases.lease(lease_id) is Some(lease) else {
      return api_error(
        404, "NotFound", "exclusive machine lease was not found", false,
      )
    }
    let decoded : @credential.CredentialHandoffIssueIntent? = try
      @json.from_json(@json.parse(body))
    catch {
      _ => None
    } noraise {
      value => Some(value)
    }
    guard decoded is Some(intent) else {
      return api_error(
        400, "InvalidRequest", "credential handoff intent is invalid", false,
      )
    }
    if !credentials.issuer_redirect_ready(
        intent.issuer_redirect_url,
        @async.now(),
      ) {
      return api_error(
        400, "CredentialIssuerMismatch", "credential redirect is not authorized by current issuer evidence",
        false,
      )
    }
    let record = try credentials.issue(intent, lease, @async.now()) catch {
      error => return credential_error_reply(error)
    } noraise {
      value => value
    }
    self.operator_audit(
      "exclusive-lease.credential-handoff-issue",
      lease_id,
      "credential-handoff:\{record.request_id}",
    )
    // Operator response intentionally omits node ID and credential reference.
    return json_reply(
      201,
      @credential.customer_view(record, lease.intent.subject_ref, @async.now()).to_json(),
    )
  }
  guard self.credential_subject_context(headers, allow_asserted_subject)
    is Some(subject_ref) else {
    return api_error(
      401, "Unauthenticated", "verified enterprise identity is required", false,
    )
  }
  let self_prefix = "/v1/machine-access/self/"
  let is_redeem = path.has_suffix("/credential:redeem")
  let suffix = if is_redeem { "/credential:redeem" } else { "/credential" }
  guard credential_lease_id(path, self_prefix, suffix) is Some(lease_id) &&
    leases.lease(lease_id) is Some(lease) &&
    lease.intent.subject_ref == subject_ref else {
    return api_error(404, "NotFound", "credential handoff was not found", false)
  }
  if is_redeem {
    if verb != Post {
      return api_error(405, "MethodNotAllowed", "POST required", false)
    }
    if !credentials.issuer_adapter_ready(@async.now()) {
      return api_error(
        503, "CredentialIssuerNotReady", "external credential issuer evidence is unavailable or expired",
        true,
      )
    }
    guard decode_credential_redemption(body) is Some(request) &&
      credentials.view_for_lease(lease, subject_ref, @async.now()) is Some(view) else {
      return api_error(
        404, "NotFound", "credential handoff was not found", false,
      )
    }
    let redeemed = try
      credentials.redeem(
        view.handoff_ref,
        lease,
        subject_ref,
        request.expected_generation,
        @async.now(),
      )
    catch {
      error => return credential_error_reply(error)
    } noraise {
      value => value
    }
    self.with_audit_lock(() => {
      self.store.append_audit(
        self.next_audit(
          "portal-subject:\{subject_ref}",
          "exclusive-lease.credential-handoff-redeem",
          lease_id,
          "available",
          "redeemed",
          "accepted",
          "credential-handoff:\{view.handoff_ref}",
          @async.now(),
        ),
      )
    })
    return json_reply(200, redeemed.to_json())
  }
  if verb != Get {
    return api_error(405, "MethodNotAllowed", "GET required", false)
  }
  match credentials.view_for_lease(lease, subject_ref, @async.now()) {
    Some(view) => json_reply(200, view.to_json())
    None =>
      api_error(404, "NotFound", "credential handoff was not found", false)
  }
}
