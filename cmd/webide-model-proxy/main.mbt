///|
async fn main {
  try {
    if @env.get_env_var("LUNANEXA_WEBIDE_INITIALIZE") is Some(root) {
      guard @env.get_env_var("LUNANEXA_WEBIDE_INITIAL_MODEL") is Some(model) else {
        raise Failure("Initial model is required")
      }
      @host.initialize_workspace(root, model)
      return
    }
    guard @env.get_env_var("LUNANEXA_MODEL_PROXY_CONFIG_FILE") is Some(path) &&
      path.has_prefix("/") else {
      raise Failure("Model proxy configuration is required")
    }
    // Never bind this unauthenticated, pod-private injector to all interfaces.
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:8189"))
    defer server.close()
    server.run_forever(
      (request, body, connection) => {
        @host.handle_model_proxy(path, request, body, connection)
      },
      max_connections=16,
      allow_failure=true,
    )
  } catch {
    _ => {
      println("Workspace model proxy stopped; check server-side configuration")
      @sys.exit(1)
    }
  }
}
