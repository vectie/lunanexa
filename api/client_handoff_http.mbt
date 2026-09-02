///|
fn client_handoff_path(path : String) -> Bool {
  path == "/v1/client-handoffs:redeem" ||
  path == "/v1/portal/self/client" ||
  path == "/v1/portal/self/client-handoffs" ||
  (
    path.has_prefix("/v1/portal/self/client-handoffs/") &&
    path.has_suffix(":revoke")
  )
}

///|
priv struct PortalClientHandoffIntent {
  request_id : String
  client_id : String
  allowed_models : Array[String]
} derive(FromJson)

///|
priv struct ClientHandoffRedemptionRequest {
  client_id : String
  handoff_code : String
} derive(FromJson)

///|
fn decode_portal_client_handoff(body : String) -> PortalClientHandoffIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_client_handoff_redemption(
  body : String,
) -> ClientHandoffRedemptionRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn client_handoff_error_reply(error : Error) -> HttpReply {
  match error {
    @client_handoff.ClientHandoffError::AlreadyRedeemed =>
      api_error(
        409, "HandoffAlreadyRedeemed", "client handoff is single use", false,
      )
    @client_handoff.ClientHandoffError::Expired =>
      api_error(409, "HandoffExpired", "client handoff has expired", false)
    @client_handoff.ClientHandoffError::Revoked =>
      api_error(409, "HandoffRevoked", "client handoff was revoked", false)
    @client_handoff.ClientHandoffError::ClientMismatch =>
      api_error(
        403, "ClientMismatch", "client handoff is bound to another client", false,
      )
    @client_handoff.ClientHandoffError::IdempotencyConflict =>
      api_error(
        409, "IdempotencyConflict", "request identifier is already bound", false,
      )
    @client_handoff.ClientHandoffError::QuotaExceeded =>
      api_error(
        429, "QuotaExceeded", "client credential quota is exhausted", false,
      )
    @client_handoff.ClientHandoffError::NotFound
    | @client_handoff.ClientHandoffError::Unauthorized =>
      api_error(404, "NotFound", "client handoff was not found", false)
    _ =>
      api_error(
        400, "ClientHandoffRejected", "client handoff was rejected", false,
      )
  }
}

///|
async fn ApiService::configured_model_allowed(
  self : ApiService,
  model : String,
) -> Bool {
  if !@contracts.valid_identifier(model) {
    return false
  }
  match self.registry {
    Some(registry) =>
      registry.snapshot().aliases.any(model_alias => model_alias.name == model) catch {
        _ => false
      }
    None => false
  }
}

///|
async fn ApiService::handle_client_handoff(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.client_handoff_store is Some(handoffs) &&
    self.client_launch_config is Some(config) else {
    return api_error(
      503, "ClientHandoffUnavailable", "desktop workspace integration is not configured",
      true,
    )
  }
  if path == "/v1/client-handoffs:redeem" {
    if verb != Post {
      return api_error(405, "MethodNotAllowed", "POST required", false)
    }
    guard decode_client_handoff_redemption(body) is Some(request) else {
      return api_error(
        400, "InvalidRequest", "invalid client handoff redemption", false,
      )
    }
    let now = @async.now()
    let redeemed = try
      handoffs.redeem(request.handoff_code, request.client_id, now)
    catch {
      error => return client_handoff_error_reply(error)
    } noraise {
      value => value
    }
    // Redemption is fail-closed and burns the one-time code when the owning
    // lease or contract has disappeared. This prevents a stale browser page
    // from reactivating access after early termination.
    let authorized = match self.workspace_directory {
      Some(directory) =>
        try {
          ignore(
            directory.authorize_subject_for_tenant(
              redeemed.subject_ref,
              redeemed.tenant_ref,
              Developer,
              now,
            ),
          )
          true
        } catch {
          _ => false
        }
      None => false
    }
    let contracted = match self.contract_document_store {
      Some(contracts) =>
        contracts.has_effective_master_lease(
          redeemed.tenant_ref,
          redeemed.subject_ref,
          now,
        )
      None => false
    }
    if !authorized || !contracted {
      ignore(
        try
          handoffs.revoke_for_subject(
            redeemed.handoff_id,
            redeemed.tenant_ref,
            redeemed.subject_ref,
            now,
          )
        catch {
          _ => ()
        } noraise {
          _ => ()
        },
      )
      return api_error(
        409, "ActiveLeaseRequired", "an active workspace lease and effective master lease are required",
        false,
      )
    }
    self.with_audit_lock(() => {
      self.store.append_audit(
        self.next_audit(
          "desktop-client:\{redeemed.client_id}",
          "workspace.client-handoff.redeem",
          redeemed.handoff_id,
          "pending",
          "redeemed",
          "accepted",
          "client-handoff:\{redeemed.api_key_id}",
          now,
        ),
      )
    })
    return json_reply(200, {
      "version": @client_handoff.contract_version,
      "handoff_id": redeemed.handoff_id,
      "client_id": redeemed.client_id,
      "api_key_id": redeemed.api_key_id,
      "api_secret": redeemed.api_secret,
      "api_base_url": config.public_api_base_url,
      "tenant_ref": redeemed.tenant_ref,
      "allowed_models": redeemed.allowed_models.to_json(),
      "expires_unix_ms": redeemed.expires_unix_ms.to_json(),
      "maximum_requests": redeemed.maximum_requests.to_json(),
      "one_time": true,
    })
  }
  guard self.portal_store is Some(portal) &&
    self.portal_subject(headers, allow_asserted_subject) is Some(subject_ref) else {
    return api_error(
      401, "Unauthenticated", "verified enterprise identity is required", false,
    )
  }
  let portal_view = try portal.self_view(subject_ref) catch {
    error => return portal_error_reply(error)
  } noraise {
    value => value
  }
  if !@portal.role_allows(portal_view.membership.roles, Developer) {
    return api_error(
      403, "PortalAccessDenied", "developer role is required", false,
    )
  }
  match (verb, path) {
    (Get, "/v1/portal/self/client") =>
      json_reply(200, {
        "client_id": config.client_id,
        "display_name": config.display_name,
        "launch_uri": config.launch_uri,
        "handoff_lifetime_ms": config.handoff_lifetime_ms.to_json(),
        "handoffs": handoffs
        .views_for_subject(portal_view.membership.tenant_ref, subject_ref)
        .to_json(),
      })
    (Post, "/v1/portal/self/client-handoffs") => {
      guard decode_portal_client_handoff(body) is Some(intent) &&
        intent.client_id == config.client_id &&
        intent.allowed_models.length() > 0 else {
        return api_error(
          400, "InvalidRequest", "invalid client handoff intent", false,
        )
      }
      for model in intent.allowed_models {
        if !self.configured_model_allowed(model) {
          return api_error(
            400, "InvalidRequest", "client handoff contains an unavailable model",
            false,
          )
        }
      }
      let now = @async.now()
      guard self.contract_document_store is Some(contract_store) &&
        contract_store.has_effective_master_lease(
          portal_view.membership.tenant_ref,
          subject_ref,
          now,
        ) else {
        return api_error(
          409, "MasterLeaseRequired", "an effective master lease is required", false,
        )
      }
      guard self.workspace_directory is Some(directory) else {
        return api_error(
          503, "WorkspaceUnavailable", "workspace authority is unavailable", true,
        )
      }
      let workspace = try
        directory.authorize_subject_for_tenant(
          subject_ref,
          portal_view.membership.tenant_ref,
          Developer,
          now,
        )
      catch {
        _ =>
          return api_error(
            409, "ActiveLeaseRequired", "an active workspace lease is required",
            false,
          )
      } noraise {
        value => value
      }
      let requested_handoff_expiry = now + config.handoff_lifetime_ms
      let handoff_expiry = if requested_handoff_expiry <
        workspace.lease.expires_unix_ms {
        requested_handoff_expiry
      } else {
        workspace.lease.expires_unix_ms
      }
      let issued = try
        handoffs.issue(
          {
            request_id: intent.request_id,
            client_id: intent.client_id,
            tenant_ref: portal_view.membership.tenant_ref,
            subject_ref,
            display_name: config.display_name,
            allowed_models: intent.allowed_models,
            handoff_expires_unix_ms: handoff_expiry,
            credential_expires_unix_ms: workspace.lease.expires_unix_ms,
            maximum_requests: config.maximum_requests,
          },
          now,
        )
      catch {
        error => return client_handoff_error_reply(error)
      } noraise {
        value => value
      }
      json_reply(201, {
        "handoff_id": issued.handoff_id,
        "client_id": issued.client_id,
        "display_name": config.display_name,
        "launch_uri": config.launch_uri,
        "public_api_base_url": config.public_api_base_url,
        "handoff_code": issued.handoff_code,
        "redemption_path": issued.redemption_path,
        "handoff_expires_unix_ms": issued.handoff_expires_unix_ms.to_json(),
        "credential_expires_unix_ms": issued.credential_expires_unix_ms.to_json(),
        "one_time": true,
      })
    }
    (Post, _) if path.has_prefix("/v1/portal/self/client-handoffs/") &&
      path.has_suffix(":revoke") => {
      let prefix = "/v1/portal/self/client-handoffs/".length()
      let suffix = ":revoke".length()
      if path.length() <= prefix + suffix {
        return api_error(404, "NotFound", "client handoff was not found", false)
      }
      let handoff_id = path[prefix:path.length() - suffix].to_owned()
      let revoked = try
        handoffs.revoke_for_subject(
          handoff_id,
          portal_view.membership.tenant_ref,
          subject_ref,
          @async.now(),
        )
      catch {
        error => return client_handoff_error_reply(error)
      } noraise {
        value => value
      }
      json_reply(200, revoked.to_json())
    }
    _ => api_error(404, "NotFound", "client handoff route was not found", false)
  }
}
