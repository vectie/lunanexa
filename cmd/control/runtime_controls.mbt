///|
priv struct RuntimeControlConfig {
  binding_ref : String
  origin : String?
  token_environment : String?
  kubernetes : KubernetesRuntimeConfig?
} derive(FromJson)

///|
priv struct KubernetesRuntimeConfig {
  origin : String
  token_file : String
  ca_file : String
  namespace_name : String
  target : @model_pool.Target
  uid : String
} derive(FromJson)

///|
/// Host-owned transport configuration. It describes execution mechanics, never
/// the model family, consumer application or company permission policy.
fn configured_runtime_controls() -> Map[String, async (String) -> String] raise {
  let controls : Map[String, async (String) -> String] = Map([])
  guard @env.get_env_var("LUNANEXA_RUNTIME_CONTROLS_JSON") is Some(raw) else {
    return controls
  }
  let configs : Array[RuntimeControlConfig] = @json.from_json(@json.parse(raw))
  for config in configs {
    guard config.binding_ref != "" && !controls.contains(config.binding_ref) else {
      raise Failure("invalid runtime control binding")
    }
    if config.kubernetes is Some(kube) {
      guard config.origin is None &&
        config.token_environment is None &&
        kube.uid != "" else {
        raise Failure("ambiguous runtime control transport")
      }
      let transport = @model_pool.authenticated_transport(
        kube.origin,
        kube.token_file,
        kube.ca_file,
        kube.namespace_name,
        [kube.target],
      )
      controls[config.binding_ref] = @model_pool.kubernetes_runtime_control(
        transport,
        kube.namespace_name,
        kube.target,
        kube.uid,
      )
      continue
    }
    guard config.origin is Some(origin) &&
      @runtimecontrol.valid_origin(origin) &&
      config.token_environment is Some(token_environment) else {
      raise Failure("runtime control transport unavailable")
    }
    let token = required_environment(token_environment).trim().to_owned()
    guard token.length() >= 32 else {
      raise Failure("invalid runtime control credential reference")
    }
    controls[config.binding_ref] = action => {
      let headers : @http.Headers = { "authorization": "Bearer " + token }
      let (response, body) = if action == "status" {
        @http.get(origin + "/v1/runtime-control", headers~)
      } else {
        @http.post(
          origin + "/v1/runtime-control:" + action,
          Json::null(),
          headers~,
        )
      }
      guard response.code == 200 &&
        body.text().length() < 4096 &&
        @json.parse(body.text()) is { "state": String(state), .. } &&
        ["Running", "Stopped", "Partial"].contains(state) else {
        raise Failure("runtime control unavailable")
      }
      state
    }
  }
  controls
}
