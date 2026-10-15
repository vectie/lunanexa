///|
/// An explicitly qualified, separately operated media provider. Provider IDs
/// are distinct from managed deployment IDs and retain durable job attribution.
pub(all) struct ExternalMediaProvider {
  provider_id : String
  generation : Int64
  active : Bool
  tenant_ref : String
  node_id : String
  artifact_digest : String
  origin : String
  bearer_file : String?
  profile : @media_provider.Profile
} derive(FromJson)

///|
pub extend ExternalMediaProvider with FromJson::{from_json}

///|
pub fn ApiService::with_external_media_providers(
  self : ApiService,
  providers : Array[ExternalMediaProvider],
) -> ApiService raise {
  if self.media is Some(_) || providers.length() > 16 {
    raise Failure(
      "external media providers must be configured before media jobs",
    )
  }
  let ids : Map[String, Bool] = Map([])
  for provider in providers {
    let identity = provider.provider_id +
      ":" +
      provider.generation.to_string() +
      ":" +
      provider.node_id
    if !provider.provider_id.has_prefix("external-media-") ||
      !@contracts.valid_identifier(provider.provider_id) ||
      !@contracts.valid_identifier(provider.tenant_ref) ||
      !@contracts.valid_identifier(provider.node_id) ||
      !@contracts.valid_sha256_digest(provider.artifact_digest) ||
      provider.generation <= 0L ||
      !provider.origin.has_prefix("http://127.0.0.1:") ||
      provider.origin["http://127.0.0.1:".length():].contains_char('/') ||
      ids.contains(identity) ||
      provider.bearer_file.map_or(false, path => {
        !path.has_prefix("/") || path.contains("..") || path.contains("\u0000")
      }) {
      raise Failure("invalid external media provider")
    }
    ignore(@media_provider.Provider::new(provider.origin, provider.profile))
    ids[identity] = true
  }
  { ..self, external_media_providers: providers, }
}

///|
async fn ExternalMediaProvider::binding(
  self : ExternalMediaProvider,
) -> MediaBinding {
  let bearer = match self.bearer_file {
    None => None
    Some(path) => {
      let token = @fs.read_file(path).text().trim().to_owned()
      guard token.length() >= 16 &&
        token.length() <= 4096 &&
        token.all(c => c >= '!' && c <= '~') else {
        raise Failure("invalid media provider credential reference")
      }
      Some(token)
    }
  }
  {
    deployment_id: self.provider_id,
    deployment_generation: self.generation,
    node_id: self.node_id,
    origin: self.origin,
    bearer,
    profile: self.profile,
    instance_id: None,
  }
}

///|
async fn ApiService::external_media_ready(
  self : ApiService,
  provider : ExternalMediaProvider,
) -> Bool {
  if !self.external_media_approved(provider) {
    return false
  }
  @async.with_timeout(5000, () => {
    let binding = provider.binding()
    let client = @http.Client(provider.origin)
    defer client.close()
    let headers : @http.Headers = Map([])
    if binding.bearer is Some(token) {
      headers["authorization"] = "Bearer " + token
    }
    let health = client.get("/health", extra_headers=headers)
    ignore(external_media_body(client))
    if health.code != 200 {
      return false
    }
    let response = client.get("/v1/models", extra_headers=headers)
    let content = external_media_body(client)
    guard response.code == 200 &&
      @json.parse(content) is { "data": Array(models), .. } else {
      return false
    }
    models.any(model => {
      model is { "id": String(id), .. } && id == provider.profile.provider_model
    })
  }) catch {
    _ => false
  }
}

///|
async fn ApiService::external_media_approved(
  self : ApiService,
  provider : ExternalMediaProvider,
) -> Bool {
  guard self.registry is Some(registry) else { return false }
  let snapshot = registry.snapshot()
  guard snapshot.aliases
    .iter()
    .find_first(a => a.name == provider.profile.model)
    is Some(selected) &&
    snapshot.models.any(model => {
      model.model_id == selected.model_id &&
      model.version == selected.version &&
      model.state == Approved &&
      model.artifact.digest == provider.artifact_digest
    }) else {
    return false
  }
  true
}

///|
async fn external_media_body(reader : &@io.Reader) -> String {
  let buffer = Buffer()
  while reader.read_some(max_len=8192) is Some(bytes) {
    if buffer.length() + bytes.length() > 65536 {
      raise Failure("media readiness response is too large")
    }
    buffer.write_bytes(bytes)
  }
  @utf8.decode(buffer.to_bytes())
}

///|
pub fn ApiService::with_client_model_policies(
  self : ApiService,
  policies : Map[String, Array[String]],
) -> ApiService raise {
  for client, models in policies {
    if !@contracts.valid_identifier(client) ||
      models.is_empty() ||
      models.any(model => !@contracts.valid_identifier(model)) ||
      models.any(model => models.count(model) != 1) {
      raise Failure("invalid client model policy")
    }
  }
  { ..self, client_model_policies: policies, }
}

///|
fn ApiService::client_models(
  self : ApiService,
  client : String,
  serving : Array[String],
) -> Array[String] {
  match self.client_model_policies.get(client) {
    None => serving
    Some(models) => serving.filter(model => models.contains(model))
  }
}
