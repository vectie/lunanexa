///|
priv struct DeliveryAccessKeyRequest {
  request_id : String
} derive(FromJson)

///|
async fn ApiService::handle_delivery_access_key(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  if verb != Post {
    return api_error(
      405, "MethodNotAllowed", "use POST to create a delivery API key", false,
    )
  }
  let prefix = "/v1/portal/self/deliveries/"
  let suffix = "/access-key"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return api_error(404, "NotFound", "delivery was not found", false)
  }
  let id = path[prefix.length():path.length() - suffix.length()].to_owned()
  let request : DeliveryAccessKeyRequest = try
    @json.from_json(@json.parse(body))
  catch {
    _ =>
      return api_error(
        400, "InvalidRequest", "a unique request_id is required", false,
      )
  } noraise {
    value => value
  }
  if !@contracts.valid_identifier(request.request_id) {
    return api_error(400, "InvalidRequest", "invalid request_id", false)
  }
  guard self.portal_store is Some(portal) &&
    self.portal_subject(headers, allow_asserted_subject) is Some(subject) else {
    return api_error(
      401, "Unauthenticated", "enterprise sign-in is required", false,
    )
  }
  let view = try portal_view_for_request(portal, subject, headers) catch {
    error => return portal_error_reply(error)
  } noraise {
    value => value
  }
  guard @portal.role_allows(view.membership.roles, Developer) &&
    self.delivery_store is Some(deliveries) &&
    self.scheduler is Some(scheduler) &&
    self.workspace_directory is Some(directory) &&
    self.client_handoff_store is Some(handoffs) &&
    self.client_launch_config is Some(config) &&
    self.deployment_store is Some(catalog) else {
    return api_error(
      403, "DeliveryAccessUnavailable", "developer access and delivery key configuration are required",
      false,
    )
  }
  guard deliveries.operation(id) is Some(operation) &&
    operation.intent.tenant_id == view.membership.tenant_ref &&
    operation.intent.organization_id == view.membership.organization_id else {
    return api_error(404, "NotFound", "delivery was not found", false)
  }
  let now = @async.now()
  let authorization = try
    directory.authorize_subject_for_tenant(
      subject,
      view.membership.tenant_ref,
      Developer,
      now,
    )
  catch {
    _ =>
      return api_error(
        403, "ActiveLeaseRequired", "active delivery workspace access is required",
        false,
      )
  } noraise {
    value => value
  }
  guard operation.intent.kind == ModelApi &&
    operation.stage == Ready &&
    operation.intent.expires_at_ms > now &&
    authorization.lease.lease_id == operation.intent.lease_id &&
    authorization.access_grant.grant_id == operation.intent.authorization_ref &&
    operation.reservation_id is Some(reservation_id) &&
    scheduler.node_reservation(reservation_id) is Some(reservation) &&
    reservation.state == Reserved &&
    reservation.request.tenant_ref == operation.intent.tenant_id &&
    reservation.request.organization_id == operation.intent.organization_id &&
    reservation.request.lease_id == operation.intent.lease_id &&
    reservation.request.authority_ref == operation.intent.authorization_ref &&
    reservation.request.expires_unix_ms > now &&
    catalog.template({
      template_id: operation.intent.template_id,
      version: operation.intent.template_version,
    })
    is Some(template) else {
    return api_error(
      409, "DeliveryUnavailable", "the model API delivery is not ready or its authorization ended",
      true,
    )
  }
  if self.management_database is Some(_) &&
    !self.commercial_project_exists(
      operation.intent.organization_id,
      operation.intent.project_id,
    ) {
    return api_error(
      403, "ProjectUnavailable", "delivery project no longer belongs to this organization",
      false,
    )
  }
  if config.public_api_base_url.contains("://127.") ||
    config.public_api_base_url.contains("://localhost") ||
    config.public_api_base_url.contains("://[::1]") {
    return api_error(
      503, "PublicEndpointUnavailable", "publish the external model API endpoint first",
      false,
    )
  }
  let expiry = operation.intent.expires_at_ms
    .min(authorization.lease.expires_unix_ms)
    .min(reservation.request.expires_unix_ms)
    .min(authorization.access_grant.expires_unix_ms)
  let handoff_expiry = (now + 60000L).min(expiry - 1L)
  if handoff_expiry <= now {
    return api_error(
      409, "ActiveLeaseRequired", "delivery access is ending", false,
    )
  }
  let issued = try
    handoffs.issue(
      {
        request_id: "delivery-api-" +
        webide_access_package_fingerprint(
          id + ":" + subject,
          request.request_id,
        ),
        client_id: "delivery-model-api",
        tenant_ref: operation.intent.tenant_id,
        subject_ref: subject,
        organization_id: operation.intent.organization_id,
        project_id: operation.intent.project_id,
        display_name: "Model API delivery",
        allowed_models: [template.model_selector],
        handoff_expires_unix_ms: handoff_expiry,
        credential_expires_unix_ms: expiry,
        maximum_requests: config.maximum_requests,
      },
      now,
      delivery_id=id,
    )
  catch {
    error => return client_handoff_error_reply(error)
  } noraise {
    value => value
  }
  let redeemed = try
    handoffs.redeem(issued.handoff_code, "delivery-model-api", now)
  catch {
    error => return client_handoff_error_reply(error)
  } noraise {
    value => value
  }
  self.operator_audit("delivery.access-key.created", id, redeemed.api_key_id)
  json_reply(201, {
    "delivery_id": id,
    "key_id": redeemed.api_key_id,
    "api_secret": redeemed.api_secret,
    "model": template.model_selector,
    "base_url": config.public_api_base_url,
    "expires_unix_ms": expiry.to_json(),
    "maximum_requests": config.maximum_requests.to_json(),
    "one_time": true,
  })
}
