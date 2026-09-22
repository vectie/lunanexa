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
fn delivery_view(operation : @delivery.Operation) -> Json {
  {
    "operation_id": operation.operation_id,
    "kind": operation.intent.kind.to_json(),
    "template_id": operation.intent.template_id,
    "template_version": operation.intent.template_version,
    "node_count": operation.intent.node_count.to_json(),
    "stage": operation.stage.to_json(),
    "generation": operation.generation.to_json(),
    "cache_hit": operation.cache_hit,
    "transferred_bytes": operation.transferred_bytes.to_json(),
    "total_bytes": operation.total_bytes.to_json(),
    "failure_code": operation.failure_code.to_json(),
    "expires_at_ms": operation.intent.expires_at_ms.to_json(),
  }
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
        json_reply(200, deliveries.operations().map(delivery_view).to_json())
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
  let owned = deliveries
    .operations()
    .filter(operation => {
      operation.intent.tenant_id == view.membership.tenant_ref &&
      operation.intent.organization_id == view.membership.organization_id
    })
  if verb == Get && path == "/v1/portal/self/deliveries" {
    return json_reply(200, owned.map(delivery_view).to_json())
  }
  guard @portal.role_allows(view.membership.roles, Developer) &&
    self.workspace_directory is Some(directory) else {
    return api_error(
      403, "AccessRequired", "active developer access is required", false,
    )
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
        403, "ActiveLeaseRequired", "active workspace authorization is required",
        false,
      )
  } noraise {
    value => value
  }
  let reservations = scheduler.snapshot().node_reservations
    .unwrap_or([])
    .filter(value => {
      value.state == Reserved &&
      value.request.tenant_ref == view.membership.tenant_ref &&
      value.request.organization_id == view.membership.organization_id &&
      value.request.lease_id == authorization.lease.lease_id &&
      value.request.starts_unix_ms <= now &&
      value.request.expires_unix_ms > now
    })
  guard self.deployment_store is Some(catalog) else {
    return api_error(
      503, "CatalogUnavailable", "deployment catalog is unavailable", true,
    )
  }
  if verb == Get && path == "/v1/portal/self/delivery-options" {
    let templates : Array[Json] = []
    for template in catalog.templates() {
      for kind in [@delivery.DeliveryKind::Workspace, ModelApi] {
        templates.push({
          "template_id": template.template_id,
          "template_version": template.version,
          "kind": kind.to_json(),
          "label": template.display_name,
          "model_selector": template.model_selector,
        })
      }
    }
    return json_reply(200, {
      "reservations": reservations
      .map(value => {
        (
          {
            "reservation_id": value.request.reservation_id,
            "label": value.request.authority_ref,
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
      is Some(reservation) &&
      catalog
      .templates()
      .iter()
      .find_first(value => {
        value.template_id == request.template_id &&
        value.version == request.template_version
      })
      is Some(template) &&
      request.kind != GpuContainer else {
      return api_error(
        409, "SelectionUnavailable", "select an active resource grant and published template",
        false,
      )
    }
    let expiry = if authorization.lease.expires_unix_ms <
      reservation.request.expires_unix_ms {
      authorization.lease.expires_unix_ms
    } else {
      reservation.request.expires_unix_ms
    }
    let operation = try {
      let created = deliveries.create(
        {
          tenant_id: view.membership.tenant_ref,
          organization_id: view.membership.organization_id,
          project_id: request.project_id,
          authorization_ref: reservation.request.authority_ref,
          lease_id: authorization.lease.lease_id,
          idempotency_key: request.idempotency_key,
          kind: request.kind,
          template_id: template.template_id,
          template_version: template.version,
          model_digest: Some(template.artifact.digest),
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
    return json_reply(202, delivery_view(operation))
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
      is Some(operation) &&
      operation.intent.lease_id == authorization.lease.lease_id else {
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
    return json_reply(202, delivery_view(updated))
  }
  api_error(404, "NotFound", "delivery route was not found", false)
}
