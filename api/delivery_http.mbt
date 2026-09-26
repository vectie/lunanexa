///|
/// Deployment-owned offering, paired with a pinned terminal gateway profile.
/// Image selection never comes from a customer request.
pub(all) struct GpuContainerOffering {
  template_id : String
  version : String
  display_name : String
  client_id : String
  image_digest : String
  cpu_millis : Int
  memory_mib : Int
} derive(FromJson, ToJson)

///|
pub extend GpuContainerOffering with FromJson::{from_json}

///|
pub extend GpuContainerOffering with ToJson::{to_json}

///|
pub fn ApiService::with_gpu_container_offering(
  self : ApiService,
  offering : GpuContainerOffering,
) -> ApiService raise {
  if !@contracts.valid_identifier(offering.template_id) ||
    !@contracts.valid_identifier(offering.version) ||
    !@contracts.valid_identifier(offering.client_id) ||
    offering.display_name.is_empty() ||
    !@contracts.valid_sha256_digest(offering.image_digest) ||
    offering.cpu_millis < 100 ||
    offering.memory_mib < 512 {
    raise Failure("invalid deployment-owned GPU container offering")
  }
  { ..self, gpu_container_offering: Some(offering), }
}

///|
fn ApiService::published_gpu_container_offering(
  self : ApiService,
) -> GpuContainerOffering? {
  guard self.gpu_container_offering is Some(offering) else { return None }
  if self.client_launch_config.map_or(false, config => {
      config.client_id == offering.client_id
    }) ||
    self.additional_client_launch_configs.any(config => {
      config.client_id == offering.client_id
    }) {
    Some(offering)
  } else {
    None
  }
}

///|
/// The currently published workspace client is the video-only ComfyUI
/// profile. A text template is valid for an API delivery, but advertising it
/// as an interactive ComfyUI workspace would launch the wrong model contract.
fn template_supports_delivery_kind(
  template : @deployment.ModelServiceTemplate,
  kind : @delivery.DeliveryKind,
) -> Bool {
  kind != Workspace || template.capability == VideoGenerate
}

///|
/// The customer chooser offers the newest immutable revision of each
/// template. Older revisions remain addressable by operators and existing
/// deliveries, but must not compete with a corrected one-click profile.
fn latest_delivery_template(
  template : @deployment.ModelServiceTemplate,
  templates : Array[@deployment.ModelServiceTemplate],
) -> Bool {
  !templates.any(other => {
    other.template_id == template.template_id &&
    other.version.compare(template.version) > 0
  })
}

///|
pub fn ApiService::with_delivery_store(
  self : ApiService,
  delivery_store : @delivery.DeliveryStore,
  gateway_observation_token? : String = "",
) -> ApiService {
  {
    ..self,
    delivery_store: Some(delivery_store),
    workspace_gateway_observation_token: gateway_observation_token,
  }
}

///|
priv struct DeliveryRequest {
  project_id : String
  idempotency_key : String
  reservation_id : String
  template_id : String
  template_version : String
  kind : @delivery.DeliveryKind
} derive(FromJson)

///|
priv struct DeliveryAction {
  generation : Int64
} derive(FromJson)

///|
fn delivery_path(path : String) -> Bool {
  path == "/v1/portal/self/delivery-options" ||
  path == "/v1/portal/self/deliveries" ||
  path.has_prefix("/v1/portal/self/deliveries/") ||
  path == "/v1/deliveries" ||
  path == "/v1/node-reservations"
}

///|
fn delivery_view(operation : @delivery.Operation, can_manage : Bool) -> Json {
  {
    "operation_id": operation.operation_id,
    "project_id": operation.intent.project_id,
    "kind": operation.intent.kind.to_json(),
    "template_id": operation.intent.template_id,
    "template_version": operation.intent.template_version,
    "node_count": operation.intent.node_count.to_json(),
    "model_replica_progress": match operation.model_replicas {
      None => Json::null()
      Some(replicas) =>
        {
          "topology": "independent_replicas",
          "observed": replicas.length().to_json(),
          "prepared": replicas
          .filter(replica => replica.prepared)
          .length()
          .to_json(),
          "ready": replicas
          .filter(replica => replica.ready && !replica.stopped)
          .length()
          .to_json(),
          "stopped": replicas
          .filter(replica => replica.stopped)
          .length()
          .to_json(),
        }
    },
    "stage": operation.stage.to_json(),
    "generation": operation.generation.to_json(),
    "cache_hit": operation.cache_hit,
    "transferred_bytes": operation.transferred_bytes.to_json(),
    "total_bytes": operation.total_bytes.to_json(),
    "failure_code": operation.failure_code.to_json(),
    "expires_at_ms": operation.intent.expires_at_ms.to_json(),
    "can_manage": can_manage,
  }
}

///|
fn delivery_visible_to_member(
  operation : @delivery.Operation,
  tenant_ref : String,
  organization_id : String,
  owns_personal_lease : Bool,
) -> Bool {
  operation.intent.tenant_id == tenant_ref &&
  operation.intent.organization_id == organization_id &&
  (operation.intent.kind == ModelApi || owns_personal_lease)
}

///|
fn delivery_manageable_by_member(
  operation : @delivery.Operation,
  company_admin : Bool,
  owns_personal_lease : Bool,
) -> Bool {
  owns_personal_lease || (company_admin && operation.intent.kind == ModelApi)
}

///|
fn delivery_error(error : Error) -> HttpReply {
  match error {
    @delivery.DeliveryError::NotFound =>
      api_error(404, "NotFound", "delivery was not found", false)
    @delivery.DeliveryError::StaleGeneration =>
      api_error(409, "StateChanged", "refresh the delivery and try again", true)
    @delivery.DeliveryError::AuthorizationExpired =>
      api_error(
        403, "AuthorizationExpired", "resource authorization has expired", false,
      )
    _ =>
      api_error(
        409, "DeliveryConflict", "delivery request conflicts with current resource state",
        false,
      )
  }
}

///|
/// Both sites project the same durable operation. Customer requests select an
/// existing resource grant; they cannot create their own node authority.
async fn ApiService::handle_delivery(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  if path.has_suffix("/access-key") {
    return self.handle_delivery_access_key(
      verb, path, headers, body, allow_asserted_subject,
    )
  }
  guard self.delivery_store is Some(deliveries) &&
    self.scheduler is Some(scheduler) else {
    return api_error(
      503, "DeliveryUnavailable", "delivery state is unavailable", true,
    )
  }
  if path == "/v1/deliveries" || path == "/v1/node-reservations" {
    if !self.operator_authorized(headers) {
      return api_error(
        401, "Unauthenticated", "operator authority is required", false,
      )
    }
    if verb == Get {
      return if path == "/v1/deliveries" {
        json_reply(
          200,
          deliveries
          .operations()
          .map(operation => delivery_view(operation, true))
          .to_json(),
        )
      } else {
        json_reply(
          200,
          scheduler.snapshot().node_reservations.unwrap_or([]).to_json(),
        )
      }
    }
    return api_error(
      405, "MethodNotAllowed", "use the resource authorization workflow", false,
    )
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
  let company_admin = view.membership.roles.contains(OrganizationAdministrator)
  guard @portal.role_allows(view.membership.roles, Developer) &&
    self.workspace_directory is Some(directory) else {
    return api_error(
      403, "AccessRequired", "active developer access is required", false,
    )
  }
  let now = @async.now()
  let member_leases = directory.snapshot(now).leases
  let owned = deliveries
    .operations()
    .filter(operation => {
      delivery_visible_to_member(
        operation,
        view.membership.tenant_ref,
        view.membership.organization_id,
        member_leases.any(lease => {
          lease.lease_id == operation.intent.lease_id &&
          lease.subject_ref == subject
        }),
      )
    })
  if !company_admin {
    ignore(
      directory.authorize_subject_for_tenant(
        subject,
        view.membership.tenant_ref,
        Developer,
        now,
      ),
    ) catch {
      _ =>
        return api_error(
          403, "ActiveLeaseRequired", "active workspace authorization is required",
          false,
        )
    }
  }
  if verb == Get && path == "/v1/portal/self/deliveries" {
    return json_reply(
      200,
      owned
      .map(operation => {
        delivery_view(
          operation,
          delivery_manageable_by_member(
            operation,
            company_admin,
            member_leases.any(lease => {
              lease.lease_id == operation.intent.lease_id &&
              lease.subject_ref == subject
            }),
          ),
        )
      })
      .to_json(),
    )
  }
  let reservation_candidates = scheduler.snapshot().node_reservations
    .unwrap_or([])
    .filter(value => {
      value.state == Reserved &&
      value.request.tenant_ref == view.membership.tenant_ref &&
      value.request.organization_id == view.membership.organization_id &&
      value.request.starts_unix_ms <= now &&
      value.request.expires_unix_ms > now
    })
  let reservations = []
  for value in reservation_candidates {
    if !self.undertaking_reservation_allowed(value, now) {
      continue
    }
    let company_allocation = value.request.reservation_id.has_prefix(
      "undertaking-resource-",
    )
    let authorized = try {
      if company_allocation {
        ignore(
          directory.authorize_subject_for_tenant(
            subject,
            value.request.tenant_ref,
            Developer,
            now,
          ),
        )
      } else {
        ignore(
          directory.authorize_subject_for_tenant_lease(
            subject,
            value.request.tenant_ref,
            value.request.lease_id,
            Developer,
            now,
            grant_id=value.request.authority_ref,
          ),
        )
      }
      true
    } catch {
      _ => false
    }
    if authorized {
      reservations.push(value)
    }
  }
  let model_templates = match self.deployment_store {
    Some(catalog) => catalog.templates()
    None => []
  }
  if verb == Get && path == "/v1/portal/self/delivery-options" {
    let undertaking_orders = match self.offline_commerce_store {
      Some(commerce) => commerce.snapshot().orders
      None => []
    }
    let templates : Array[Json] = []
    for template in model_templates {
      if !latest_delivery_template(template, model_templates) {
        continue
      }
      for kind in [@delivery.DeliveryKind::Workspace, ModelApi] {
        if !template_supports_delivery_kind(template, kind) {
          continue
        }
        templates.push({
          "template_id": template.template_id,
          "template_version": template.version,
          "kind": kind.to_json(),
          "label": template.display_name,
          "model_selector": template.model_selector,
          "client_id": if kind == Workspace {
            "comfyui"
          } else {
            self.client_launch_config.map_or("", config => config.client_id)
          },
        })
      }
    }
    if self.published_gpu_container_offering() is Some(offering) {
      templates.push({
        "template_id": offering.template_id,
        "template_version": offering.version,
        "kind": @delivery.DeliveryKind::GpuContainer.to_json(),
        "label": offering.display_name,
        "model_selector": "",
        "client_id": offering.client_id,
      })
    }
    return json_reply(200, {
      "reservations": reservations
      .map(value => {
        let undertaking_order = undertaking_orders
          .iter()
          .find_first(order => {
            value.request.reservation_id ==
            "undertaking-resource-\{undertaking_allocation_fingerprint(order.order_id)}" &&
            order.organization_id == view.membership.organization_id
          })
        (
          {
            "reservation_id": value.request.reservation_id,
            "label": undertaking_order.map_or(value.request.authority_ref, order => {
              "承诺函订单 · \{order.order_id}"
            }),
            "node_count": value.request.node_ids.length().to_json(),
            "expires_at_ms": value.request.expires_unix_ms.to_json(),
          } : Json)
      })
      .to_json(),
      "templates": templates.to_json(),
    })
  }
  if verb == Post && path == "/v1/portal/self/deliveries" {
    let request : DeliveryRequest = try
      @json.from_json(@json.parse(body))
    catch {
      _ =>
        return api_error(
          400, "InvalidRequest", "invalid delivery selection", false,
        )
    } noraise {
      value => value
    }
    if !self.commercial_project_exists(
        view.membership.organization_id,
        request.project_id,
      ) {
      return api_error(
        403, "ProjectRequired", "select a project belonging to this organization",
        false,
      )
    }
    guard reservations
      .iter()
      .find_first(value => {
        value.request.reservation_id == request.reservation_id
      })
      is Some(reservation) else {
      return api_error(
        409, "SelectionUnavailable", "select an active resource grant and published template",
        false,
      )
    }
    let mut capability : @workspace.WorkspaceCapability? = None
    let model_digest = if request.kind == GpuContainer {
      guard self.published_gpu_container_offering() is Some(offering) &&
        offering.template_id == request.template_id &&
        offering.version == request.template_version &&
        offering.memory_mib <= reservation.request.memory_mib_per_node else {
        return api_error(
          409, "SelectionUnavailable", "select a configured GPU container offering within the resource grant",
          false,
        )
      }
      None
    } else {
      guard model_templates
        .iter()
        .find_first(value => {
          value.template_id == request.template_id &&
          value.version == request.template_version
        })
        is Some(template) else {
        return api_error(
          409, "SelectionUnavailable", "select a published model template", false,
        )
      }
      if !template_supports_delivery_kind(template, request.kind) {
        return api_error(
          409, "SelectionUnavailable", "the published template does not support the selected delivery kind",
          false,
        )
      }
      capability = workspace_capability(template.capability)
      if capability is None {
        return api_error(
          409, "CapabilityUnavailable", "the selected model has no workspace capability",
          false,
        )
      }
      Some(template.artifact.digest)
    }
    let authorization = if reservation.request.reservation_id.has_prefix(
        "undertaking-resource-",
      ) {
      match capability {
        Some(value) =>
          directory.authorize_subject_for_tenant_capability(
            subject,
            view.membership.tenant_ref,
            value,
            now,
          )
        None =>
          directory.authorize_subject_for_tenant(
            subject,
            view.membership.tenant_ref,
            Developer,
            now,
          )
      }
    } else {
      directory.authorize_subject_for_tenant_lease(
        subject,
        view.membership.tenant_ref,
        reservation.request.lease_id,
        Developer,
        now,
        grant_id=reservation.request.authority_ref,
      )
    }
    let expiry = authorization.lease.expires_unix_ms
      .min(reservation.request.expires_unix_ms)
      .min(authorization.access_grant.expires_unix_ms)
    let operation = try {
      let created = deliveries.create(
        {
          tenant_id: view.membership.tenant_ref,
          organization_id: view.membership.organization_id,
          project_id: request.project_id,
          authorization_ref: authorization.access_grant.grant_id,
          lease_id: authorization.lease.lease_id,
          idempotency_key: request.idempotency_key,
          kind: request.kind,
          template_id: request.template_id,
          template_version: request.template_version,
          model_digest,
          node_count: reservation.request.node_ids.length(),
          expires_at_ms: expiry,
        },
        now,
      )
      if created.stage == Reserving {
        deliveries.observe(
          created.operation_id,
          created.generation,
          @delivery.Observation::Reserved(
            reservation_id=reservation.request.reservation_id,
            node_ids=reservation.request.node_ids,
          ),
          now,
        )
      } else {
        created
      }
    } catch {
      error => return delivery_error(error)
    } noraise {
      value => value
    }
    self.operator_audit(
      "delivery.request",
      operation.operation_id,
      "delivery:\{operation.operation_id}",
    )
    return json_reply(202, delivery_view(operation, true))
  }
  if verb == Post && path.has_prefix("/v1/portal/self/deliveries/") {
    let parts = path.split("/").collect()
    let action = parts.last().unwrap_or("").to_owned()
    let retry = action.has_suffix(":retry")
    let stop = action.has_suffix(":stop")
    if !retry && !stop {
      return api_error(404, "NotFound", "unknown delivery action", false)
    }
    let id = action.split(":").next().unwrap_or("").to_owned()
    guard owned.iter().find_first(value => value.operation_id == id)
      is Some(operation) else {
      return api_error(404, "NotFound", "delivery was not found", false)
    }
    let authorized = if delivery_manageable_by_member(
        operation, company_admin, false,
      ) {
      true
    } else {
      try {
        ignore(
          directory.authorize_subject_for_tenant_lease(
            subject,
            view.membership.tenant_ref,
            operation.intent.lease_id,
            Developer,
            now,
            grant_id=operation.intent.authorization_ref,
          ),
        )
        true
      } catch {
        _ => false
      }
    }
    if !authorized {
      return api_error(404, "NotFound", "delivery was not found", false)
    }
    let action : DeliveryAction = try @json.from_json(@json.parse(body)) catch {
      _ =>
        return api_error(
          400, "InvalidRequest", "delivery generation is required", false,
        )
    } noraise {
      value => value
    }
    let updated = try {
      if retry {
        deliveries.retry(id, action.generation, now)
      } else {
        deliveries.stop(id, action.generation, now)
      }
    } catch {
      error => return delivery_error(error)
    } noraise {
      value => value
    }
    return json_reply(202, delivery_view(updated, true))
  }
  api_error(404, "NotFound", "delivery route was not found", false)
}
