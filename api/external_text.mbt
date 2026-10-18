///|
/// A separately operated, explicitly registered text backend. This is not a
/// managed deployment: readiness is measured against the live model endpoint.
struct ExternalTextRoute {
  model_alias : String
  tenant_ref : String
  node_id : String
  origin : String
  served_model : String
  credential : String
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
    let (ready, context_window_tokens) = self.external_text_observation()
    return if verb == Get && path == "/v1/portal/self/external-model-service" {
      json_reply(200, {
        "model_alias": route.model_alias,
        "state": "Unmanaged",
        "can_stop": false,
        "ready": ready,
        "context_window_tokens": context_window_tokens,
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
  let (ready, context_window_tokens) = self.external_text_observation()
  json_reply(200, {
    "model_alias": route.model_alias,
    "state": state,
    "can_stop": can_manage,
    "ready": ready,
    "context_window_tokens": context_window_tokens,
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
  credential~ : String = "",
  native_revision? : String,
  text_chat_completions~ : Bool = false,
) -> ApiService raise {
  if !@contracts.valid_identifier(model_alias) ||
    !@contracts.valid_identifier(tenant_ref) ||
    !@contracts.valid_identifier(node_id) ||
    !@contracts.valid_identifier(served_model) ||
    !origin.has_prefix("http://127.0.0.1:") ||
    origin["http://127.0.0.1:".length():].contains_char('/') ||
    credential.contains_char('\n') ||
    credential.contains_char('\r') {
    raise Failure::Failure("invalid external text route")
  }
  let endpoint = origin +
    (if text_chat_completions {
      "/v1/chat/completions"
    } else {
      "/v1/responses"
    })
  let runtime = match native_revision {
    Some(revision) => {
      guard image_digest == "" else {
        raise Failure::Failure("native route cannot claim an OCI image")
      }
      @runtimes.OpenAiTextRuntime::native(
        endpoint,
        credential,
        runtime_version,
        revision,
        artifact_digest,
        allow_http_loopback=true,
      )
    }
    None =>
      @runtimes.OpenAiTextRuntime::new(
        endpoint,
        credential,
        runtime_version,
        image_digest,
        artifact_digest,
        allow_http_loopback=true,
      )
  }
  let runtime = if text_chat_completions {
    runtime.with_text_chat_completions()
  } else {
    runtime
  }
  let runtime = runtime.with_served_model_name(served_model)
  {
    ..self,
    external_text_route: Some({
      model_alias,
      tenant_ref,
      node_id,
      origin,
      served_model,
      credential,
      runtime,
    }),
  }
}

///|
/// A separately authenticated text backend reserved for one organization's
/// shared trial node. This does not replace the dedicated company route.
pub fn ApiService::with_shared_trial_text_route(
  self : ApiService,
  model_alias : String,
  tenant_ref : String,
  node_id : String,
  origin : String,
  served_model : String,
  runtime_version : String,
  image_digest : String,
  artifact_digest : String,
  credential : String,
) -> ApiService raise {
  guard self.shared_trial_offerings.any(offering => {
      offering.kind == "Text" &&
      offering.tenant_ref == tenant_ref &&
      offering.model_alias == model_alias &&
      offering.node_id == node_id
    }) &&
    credential.trim() != "" &&
    !credential.contains_char('\n') &&
    !credential.contains_char('\r') else {
    raise Failure::Failure(
      "shared trial text route is not bound to an offering",
    )
  }
  let base = self.with_external_text_route(
    model_alias, tenant_ref, node_id, origin, served_model, runtime_version, image_digest,
    artifact_digest,
  )
  guard base.external_text_route is Some(route) else {
    raise Failure::Failure("shared trial text route is unavailable")
  }
  {
    ..self,
    shared_trial_text_route: Some({
      ..route,
      credential,
      // Qwen's default template streams internal planning as text; Code
      // needs the final assistant answer from this shared trial route.
      runtime: @runtimes.OpenAiTextRuntime::new(
        "\{origin}/v1/responses",
        credential,
        runtime_version,
        image_digest,
        artifact_digest,
        allow_http_loopback=true,
      )
      .with_served_model_name(served_model)
      .with_thinking_disabled(),
    }),
  }
}

///|
/// An approved alias and artifact alone do not make a model serving. Check
/// the exact advertised model and health on each readiness decision.
async fn ApiService::external_text_ready(self : ApiService) -> Bool {
  self.external_text_observation().0
}

///|
fn external_model_context(model : Json) -> Int32? {
  match model {
    { "max_model_len": Number(limit, ..), .. } if limit > 0 &&
      limit <= 10485760 &&
      limit == limit.to_int().to_double() => Some(limit.to_int())
    _ => None
  }
}

///|
async fn ApiService::external_text_observation(
  self : ApiService,
) -> (Bool, Int32?) {
  guard self.external_text_route is Some(route) else { return (false, None) }
  self.external_route_observation(route)
}

///|
async fn ApiService::external_route_observation(
  self : ApiService,
  route : ExternalTextRoute,
) -> (Bool, Int32?) {
  guard self.registry is Some(registry) else { return (false, None) }
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
    return (false, None)
  }
  try
    @async.with_timeout(5000, () => {
      let (health, _) = @http.get("\{route.origin}/health")
      if health.code != 200 {
        return (false, None)
      }
      let headers : @http.Headers = if route.credential == "" {
        Map([])
      } else {
        { "Authorization": "Bearer \{route.credential}" }
      }
      let (response, body) = @http.get("\{route.origin}/v1/models", headers~)
      if response.code != 200 || body.text().length() > 65536 {
        return (false, None)
      }
      match @json.parse(body.text()) {
        { "data": Array(models), .. } =>
          match
            models
            .iter()
            .find_first(model => {
              model is { "id": String(id), .. } && id == route.served_model
            }) {
            Some(model) => (true, external_model_context(model))
            None => (false, None)
          }
        _ => (false, None)
      }
    })
  catch {
    _ => (false, None)
  } noraise {
    value => value
  }
}
