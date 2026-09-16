///|
async fn load_runtime_supervisor(
  node_id : String,
  pid_limit : Int,
) -> @node_agent.ManagedRuntimeSupervisor {
  match @env.get_env_var("LUNANEXA_RUNTIME_BACKEND").unwrap_or("oci") {
    "oci" =>
      Oci(
        @node_agent.OciRuntimeSupervisor::new(
          environment("LUNANEXA_CONTAINER_ENGINE"),
          environment("LUNANEXA_RUNTIME_NETWORK"),
          environment("LUNANEXA_CONTAINER_ENGINE_ENDPOINT"),
          pid_limit~,
        ),
      )
    "kubernetes" => {
      let file = @fs.open(
        environment("LUNANEXA_KUBERNETES_RUNTIME_CONFIG_PATH"),
        mode=ReadOnly,
      )
      defer file.close()
      let buffer = Buffer()
      let mut size = 0
      while file.read_some(max_len=8192) is Some(bytes) {
        size += bytes.length()
        if size > 65536 {
          fail("Kubernetes runtime configuration exceeds limit")
        }
        buffer.write_bytes(bytes)
      }
      let settings : @kubernetes.RuntimeSettings = @json.from_json(
        @json.parse(@utf8.decode(buffer.to_bytes())),
      )
      let cache_root = @env.get_env_var("LUNANEXA_MODEL_CACHE_PATH").unwrap_or(
        "/var/lib/lunanexa/models",
      )
      if settings.node_id != node_id || settings.model_cache_root != cache_root {
        fail(
          "Kubernetes runtime identity or cache root does not match the node agent",
        )
      }
      let transport = @kubernetes.authenticated_transport(
        @env.get_env_var("LUNANEXA_KUBERNETES_ORIGIN").unwrap_or(
          "https://kubernetes.default.svc",
        ),
        @env.get_env_var("LUNANEXA_KUBERNETES_TOKEN_PATH").unwrap_or(
          "/var/run/secrets/kubernetes.io/serviceaccount/token",
        ),
        @env.get_env_var("LUNANEXA_KUBERNETES_CA_PATH").unwrap_or(
          "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
        ),
      )
      Kubernetes(
        @kubernetes.RuntimeSupervisor::open_file(
          settings,
          transport,
          environment("LUNANEXA_KUBERNETES_RUNTIME_STATE_PATH"),
        ),
      )
    }
    _ => fail("LUNANEXA_RUNTIME_BACKEND must be oci or kubernetes")
  }
}
