///|
pub(all) struct HostConfig {
  namespace_name : String
  comfyui_image : String
  model_proxy_image : String
  storage_class : String
  storage_gib : Int
  cpu_millis : Int
  memory_mib : Int
  controller_origin : String
  model_gateway_origin : String
  controller_port : Int
  model_gateway_port : Int
  kubernetes_origin : String
  kubernetes_ca_file : String
  kubernetes_token_file : String
} derive(FromJson)

///|
/// Never derive a printable instance: API secrets must not reach diagnostics.
struct ModelProxyConfig {
  client_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
  api_secret : String
  allowed_models : Array[String]
  expires_unix_ms : Int64
  controller_origin : String
  model_gateway_origin : String
} derive(FromJson, ToJson)

///|
fn ModelProxyConfig::grant(self : ModelProxyConfig) -> @webide.Grant {
  {
    client_id: self.client_id,
    tenant_ref: self.tenant_ref,
    subject_ref: self.subject_ref,
    organization_id: self.organization_id,
    project_id: self.project_id,
    api_secret: self.api_secret,
    allowed_models: self.allowed_models,
    expires_unix_ms: self.expires_unix_ms,
  }
}

///|
pub struct WorkspaceHost {
  config : HostConfig
  locks : Map[String, @async.Mutex]
  kubernetes_override : (async (@http.RequestMethod, String, Json?) -> (
    Int,
    Json,
  ))?
}

///|
pub(all) suberror HostError {
  InvalidConfiguration
  ControllerRejected
  WorkspaceUnavailable
} derive(Debug, Eq)

///|
fn dns_label(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 63 &&
  !value.has_prefix("-") &&
  !value.has_suffix("-") &&
  value.all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')
}

///|
fn pinned_image(value : String) -> Bool {
  let parts = value.split("@sha256:").to_array()
  parts.length() == 2 &&
  parts[0].length() > 0 &&
  parts[0].length() <= 255 &&
  parts[0].all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= '0' && c <= '9') ||
    c == '/' ||
    c == '.' ||
    c == '-' ||
    c == '_' ||
    c == ':'
  }) &&
  parts[1].length() == 64 &&
  parts[1].all(c => (c >= 'a' && c <= 'f') || (c >= '0' && c <= '9'))
}

///|
fn origin(value : String) -> Bool {
  let offset = if value.has_prefix("https://") {
    8
  } else if value.has_prefix("http://") {
    7
  } else {
    return false
  }
  let authority = value[offset:]
  authority.length() > 0 &&
  authority.length() <= 253 &&
  authority.all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= '0' && c <= '9') ||
    c == '.' ||
    c == '-' ||
    c == ':'
  })
}

///|
pub fn WorkspaceHost::new(config : HostConfig) -> WorkspaceHost raise HostError {
  if !dns_label(config.namespace_name) ||
    !dns_label(config.storage_class) ||
    !pinned_image(config.comfyui_image) ||
    !pinned_image(config.model_proxy_image) ||
    config.storage_gib < 1 ||
    config.storage_gib > 1024 ||
    config.cpu_millis < 100 ||
    config.cpu_millis > 16000 ||
    config.memory_mib < 512 ||
    config.memory_mib > 32768 ||
    !origin(config.controller_origin) ||
    !origin(config.model_gateway_origin) ||
    !origin(config.kubernetes_origin) ||
    !config.kubernetes_origin.has_prefix("https://") ||
    !config.kubernetes_ca_file.has_prefix("/") ||
    !config.kubernetes_token_file.has_prefix("/") ||
    config.controller_port < 1 ||
    config.controller_port > 65535 ||
    config.model_gateway_port < 1 ||
    config.model_gateway_port > 65535 {
    raise InvalidConfiguration
  }
  { config, locks: {}, kubernetes_override: None, }
}

///|
fn WorkspaceHost::workspace_lock(
  self : WorkspaceHost,
  name : String,
) -> @async.Mutex raise HostError {
  match self.locks.get(name) {
    Some(lock) => lock
    None => {
      if self.locks.length() >= 4096 {
        raise WorkspaceUnavailable
      }
      let lock = @async.Mutex()
      self.locks[name] = lock
      lock
    }
  }
}
