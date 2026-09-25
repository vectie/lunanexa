///|
/// A separately operated, explicitly registered text backend. This is not a
/// managed deployment: readiness is measured against the live model endpoint.
struct ExternalTextRoute {
  model_alias : String
  tenant_ref : String
  node_id : String
  origin : String
  served_model : String
  runtime : @runtimes.OpenAiTextRuntime
}

///|
fn external_text_control_path(path : String) -> Bool {
  path == "/v1/portal/self/external-model-service" ||
  path == "/v1/portal/self/external-model-service:stop" ||
  path == "/v1/portal/self/external-model-service:start"
}

///|
pub fn ApiService::has_external_text_route(self : ApiService) -> Bool {
  self.external_text_route is Some(_)
}

///|
pub fn ApiService::with_external_text_control(
  self : ApiService,
  control : async (String) -> String,
) -> ApiService {
  { ..self, external_text_control: Some(control), }
}

///|
async fn ApiService::handle_external_text_control(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.portal_store is Some(portal) &&
    self.portal_subject(headers, allow_asserted_subject) is Some(subject) else {
    return api_error(
      401, "Unauthenticated", "enterprise sign-in is required", false,
    )
  }
  guard self.external_text_route is Some(route) else {
    return api_error(
      404, "NotFound", "external model service was not found", false,
    )
  }
  let view = try portal_view_for_request(portal, subject, headers) catch {
    error => return portal_error_reply(error)
  } noraise {
    value => value
  }
  if view.membership.tenant_ref != route.tenant_ref {
    return api_error(
      404, "NotFound", "external model service was not found", false,
    )
  }
  let can_manage = view.membership.roles.contains(OrganizationAdministrator)
  guard self.external_text_control is Some(control) else {
    return if verb == Get && path == "/v1/portal/self/external-model-service" {
      json_reply(200, {
        "model_alias": route.model_alias,
        "state": "Unmanaged",
        "can_stop": false,
        "ready": self.external_text_ready(),
      })
    } else {
      api_error(
        503, "ModelControlUnavailable", "this external model is not controlled by LunaNexa",
        true,
      )
    }
  }
  if verb == Post &&
    (
      path == "/v1/portal/self/external-model-service:stop" ||
      path == "/v1/portal/self/external-model-service:start"
    ) &&
    !can_manage {
    return api_error(
      403, "OrganizationAdministratorRequired", "company administrator permission is required to manage a shared model",
      false,
    )
  }
  guard (verb == Get && path == "/v1/portal/self/external-model-service") ||
    (
      verb == Post &&
      (
        path == "/v1/portal/self/external-model-service:stop" ||
        path == "/v1/portal/self/external-model-service:start"
      )
    ) else {
    return api_error(
      405, "MethodNotAllowed", "unsupported model service action", false,
    )
  }
  let state = try
    @async.with_timeout(150000, () => {
      control(
        if verb == Get {
          "status"
        } else if path.has_suffix(":start") {
          "start"
        } else {
          "stop"
        },
      )
    })
  catch {
    _ =>
      return api_error(
        503, "ModelControlUnavailable", "model service state could not be confirmed",
        true,
      )
  } noraise {
    value => value
  }
  if state != "Running" && state != "Stopped" && state != "Partial" {
    return api_error(
      503, "ModelControlUnavailable", "model service state could not be confirmed",
      true,
    )
  }
  if verb == Post {
    self.with_audit_lock(() => {
      self.store.append_audit(
        self.next_audit(
          "portal:\{subject}",
          if path.has_suffix(":start") {
            "external-model.start"
          } else {
            "external-model.stop"
          },
          route.model_alias,
          "requested",
          state,
          if (path.has_suffix(":start") && state == "Running") ||
            (path.has_suffix(":stop") && state == "Stopped") {
            "accepted"
          } else {
            "partial"
          },
          "external-model:\{route.node_id}",
          @async.now(),
        ),
      )
    })
  }
  json_reply(200, {
    "model_alias": route.model_alias,
    "state": state,
    "can_stop": can_manage,
    "ready": self.external_text_ready(),
  })
}

///|
/// The origin is a controller-local proxy, never an arbitrary user URL.
pub fn ApiService::with_external_text_route(
  self : ApiService,
  model_alias : String,
  tenant_ref : String,
  node_id : String,
  origin : String,
  served_model : String,
  runtime_version : String,
  image_digest : String,
  artifact_digest : String,
) -> ApiService raise {
  if !@contracts.valid_identifier(model_alias) ||
    !@contracts.valid_identifier(tenant_ref) ||
    !@contracts.valid_identifier(node_id) ||
    !@contracts.valid_identifier(served_model) ||
    !origin.has_prefix("http://127.0.0.1:") ||
    origin["http://127.0.0.1:".length():].contains_char('/') {
    raise Failure::Failure("invalid external text route")
  }
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "\{origin}/v1/responses",
    "",
    runtime_version,
    image_digest,
    artifact_digest,
    allow_http_loopback=true,
  ).with_served_model_name(served_model)
  {
    ..self,
    external_text_route: Some({
      model_alias,
      tenant_ref,
      node_id,
      origin,
      served_model,
      runtime,
    }),
  }
}

///|
/// An approved alias and artifact alone do not make a model serving. Check
/// the exact advertised model and health on each readiness decision.
async fn ApiService::external_text_ready(self : ApiService) -> Bool {
  guard self.external_text_route is Some(route) &&
    self.registry is Some(registry) else {
    return false
  }
  let snapshot = registry.snapshot()
  guard snapshot.aliases
    .iter()
    .find_first(item => item.name == route.model_alias)
    is Some(selected) &&
    snapshot.models
    .iter()
    .find_first(model => {
      model.model_id == selected.model_id &&
      model.version == selected.version &&
      model.state == Approved &&
      model.artifact.digest == route.runtime.artifact_digest()
    })
    is Some(_) else {
    return false
  }
  try
    @async.with_timeout(5000, () => {
      let (health, _) = @http.get("\{route.origin}/health")
      if health.code != 200 {
        return false
      }
      let (response, body) = @http.get("\{route.origin}/v1/models")
      if response.code != 200 || body.text().length() > 65536 {
        return false
      }
      match @json.parse(body.text()) {
        { "data": Array(models), .. } =>
          models.any(model => {
            model is { "id": String(id), .. } && id == route.served_model
          })
        _ => false
      }
    })
  catch {
    _ => false
  } noraise {
    value => value
  }
}
