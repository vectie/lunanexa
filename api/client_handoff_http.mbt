///|
fn client_handoff_path(path : String) -> Bool {
  path == "/v1/client-handoffs:redeem" ||
  path == "/v1/portal/self/client" ||
  path == "/v1/portal/self/clients" ||
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
  project_id : String
  allowed_models : Array[String]
  order_id : String?
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
  let configs = [config, ..self.additional_client_launch_configs]
  if path == "/v1/client-handoffs:redeem" {
    if verb != Post {
      return api_error(405, "MethodNotAllowed", "POST required", false)
    }
    guard decode_client_handoff_redemption(body) is Some(request) else {
      return api_error(
        400, "InvalidRequest", "invalid client handoff redemption", false,
      )
    }
    guard configs.filter(config => config.client_id == request.client_id).get(0)
      is Some(config) else {
      return api_error(403, "ClientMismatch", "client is not configured", false)
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
    let contracted = self.private_workspace_key_authorized(
        redeemed.api_key_id,
        redeemed.tenant_ref,
        redeemed.subject_ref,
        now,
      ) ||
      (match self.contract_document_store {
        Some(contracts) =>
          self.has_effective_rental_authority(
            contracts,
            redeemed.tenant_ref,
            redeemed.subject_ref,
            now,
            organization_id=redeemed.organization_id,
          )
        None => false
      })
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
      "subject_ref": redeemed.subject_ref,
      "organization_id": redeemed.organization_id,
      "project_id": redeemed.project_id,
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
  let portal_view = try
    portal_view_for_request(portal, subject_ref, headers)
  catch {
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
    (Get, "/v1/portal/self/client" | "/v1/portal/self/clients") => {
      let now = @async.now()
      let contract_ready = self.private_cloud_workspace_access ||
        (match self.contract_document_store {
          Some(contracts) =>
            self.has_effective_rental_authority(
              contracts,
              portal_view.membership.tenant_ref,
              subject_ref,
              now,
              organization_id=portal_view.membership.organization_id,
            )
          None => false
        })
      let workspace_ready = match self.workspace_directory {
        Some(directory) =>
          try {
            ignore(
              directory.authorize_subject_for_tenant(
                subject_ref,
                portal_view.membership.tenant_ref,
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
      let aliases = access_package_approved_aliases(self.registry)
      let blockers : Array[String] = []
      if !contract_ready {
        blockers.push("MasterLeaseRequired")
      }
      if !workspace_ready {
        blockers.push("ActiveWorkspaceLeaseRequired")
      }
      if aliases.length() == 0 {
        blockers.push("ApprovedModelRequired")
      }
      let subject_handoffs = handoffs.views_for_subject(
        portal_view.membership.tenant_ref,
        subject_ref,
      )
      let views = configs.map(config => {
        (
          {
            "client_id": config.client_id,
            "display_name": config.display_name,
            "launch_uri": config.launch_uri,
            "handoff_lifetime_ms": config.handoff_lifetime_ms.to_json(),
            "contract_required": !self.private_cloud_workspace_access,
            "contract_ready": contract_ready,
            "workspace_ready": workspace_ready,
            "models_ready": aliases.length() > 0,
            "ready": blockers.length() == 0,
            "blocker_codes": blockers.to_json(),
            "approved_model_aliases": aliases.to_json(),
            "handoffs": subject_handoffs
            .filter(handoff => handoff.client_id == config.client_id)
            .to_json(),
          } : Json)
      })
      if path == "/v1/portal/self/client" {
        json_reply(200, views[0])
      } else {
        json_reply(200, views.to_json())
      }
    }
    (Post, "/v1/portal/self/client-handoffs") => {
      guard decode_portal_client_handoff(body) is Some(intent) &&
        configs.filter(config => config.client_id == intent.client_id).get(0)
        is Some(config) &&
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
      if self.management_database is Some(_) &&
        !self.commercial_project_exists(
          portal_view.membership.organization_id,
          intent.project_id,
        ) {
        return api_error(
          409, "CommercialProjectRequired", "a project owned by the enterprise organization is required",
          false,
        )
      }
      let now = @async.now()
      let paid_order = match intent.order_id {
        Some(order_id) => {
          guard self.machine_commerce_store is Some(machine_store) &&
            machine_store.order(order_id) is Some(order) &&
            order.tenant_ref == portal_view.membership.tenant_ref &&
            order.organization_id == portal_view.membership.organization_id &&
            order.project_id == intent.project_id &&
            order.purchaser_subject_ref == subject_ref else {
            return api_error(
              404, "NotFound", "dedicated machine order was not found", false,
            )
          }
          guard order.offering_kind == DedicatedEndpoint &&
            order.state == Active &&
            order.requested_model_selector is Some(selected) &&
            intent.allowed_models == [selected] &&
            order.active_started_unix_ms is Some(started) &&
            started + order.duration_seconds * 1000L > now &&
            order.target_deployment_ref is Some(deployment_id) &&
            self.deployment_store is Some(deployments) &&
            deployments.deployment(deployment_id) is Some(operation) &&
            operation.state == Ready &&
            operation.endpoint is Some(_) else {
            return api_error(
              409, "DedicatedEndpointUnavailable", "the selected paid endpoint is not active and ready",
              true,
            )
          }
          Some(order)
        }
        None => None
      }
      guard (self.private_cloud_workspace_access && paid_order is None) ||
        (
          self.contract_document_store is Some(contract_store) &&
          self.has_effective_rental_authority(
            contract_store,
            portal_view.membership.tenant_ref,
            subject_ref,
            now,
            organization_id=portal_view.membership.organization_id,
          )
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
      let credential_expiry = match paid_order {
        Some(order) =>
          (order.active_started_unix_ms.unwrap() +
          order.duration_seconds * 1000L).min(workspace.lease.expires_unix_ms)
        None => workspace.lease.expires_unix_ms
      }
      let requested_handoff_expiry = now + config.handoff_lifetime_ms
      let handoff_expiry = if requested_handoff_expiry < credential_expiry {
        requested_handoff_expiry
      } else {
        credential_expiry - 1L
      }
      if handoff_expiry <= now {
        return api_error(
          409, "ActiveLeaseRequired", "the workspace lease is ending", false,
        )
      }
      let issued = try
        handoffs.issue(
          {
            request_id: intent.request_id,
            client_id: intent.client_id,
            tenant_ref: portal_view.membership.tenant_ref,
            subject_ref,
            organization_id: portal_view.membership.organization_id,
            project_id: intent.project_id,
            display_name: config.display_name,
            allowed_models: intent.allowed_models,
            handoff_expires_unix_ms: handoff_expiry,
            credential_expires_unix_ms: credential_expiry,
            maximum_requests: config.maximum_requests,
          },
          now,
        )
      catch {
        error => return client_handoff_error_reply(error)
      } noraise {
        value => value
      }
      // The one-time code is not exposed until the identifier binding is
      // durable. A partial failure leaves an unusable, revoked credential,
      // never an accidentally shared-model fallback for a paid launch.
      if paid_order is Some(order) {
        let binding_ok = try {
          guard self.machine_commerce_store is Some(machine_store) &&
            handoffs
            .views_for_subject(order.tenant_ref, subject_ref)
            .filter(view => view.handoff_id == issued.handoff_id)
            .get(0)
            is Some(view) else {
            raise Failure("handoff binding unavailable")
          }
          ignore(
            machine_store.bind_access_key(
              order.order_id,
              subject_ref,
              view.api_key_id,
              now,
            ),
          )
          let (_, denied) = self.dedicated_order_binding(
            {
              key_id: view.api_key_id,
              tenant_ref: order.tenant_ref,
              subject_ref,
              organization_id: order.organization_id,
              project_id: order.project_id,
            },
            order.requested_model_selector,
            @async.now(),
          )
          denied is None
        } catch {
          _ => false
        }
        if !binding_ok {
          ignore(
            handoffs.revoke_for_subject(
              issued.handoff_id,
              order.tenant_ref,
              subject_ref,
              @async.now(),
            ),
          ) catch {
            _ => ()
          }
          return api_error(
            503, "DedicatedHandoffBindingFailed", "the paid workspace handoff could not be bound",
            true,
          )
        }
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
