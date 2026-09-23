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
