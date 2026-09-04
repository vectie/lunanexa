///|
async fn main {
  let config = load_config()
  let server = @http.Server(
    @socket.Addr::parse(config.listen_address),
    reuse_addr=true,
  )
  println("lunanexa identity gateway listening on \{server.addr}")
  match config.mode {
    Proxy => {
      let store = GatewaySessionStore::open(config.database_url)
      defer store.close()
      server.run_forever(
        (request, reader, connection) => {
          handle_proxy(store, config, request, reader, connection) catch {
            Failure(message) => {
              println("[identity-gateway] proxy request failed: \{message}")
              send_error(connection, 503, "identity-gateway-unavailable")
            }
            _ => {
              println("[identity-gateway] proxy request failed: internal error")
              send_error(connection, 503, "identity-gateway-unavailable")
            }
          }
        },
        allow_failure=true,
      )
    }
    Relay =>
      server.run_forever(
        (request, reader, connection) => {
          handle_relay(config, request, reader, connection) catch {
            Failure(message) => {
              println("[identity-gateway] relay request failed: \{message}")
              send_error(connection, 503, "identity-gateway-unavailable")
            }
            _ => {
              println("[identity-gateway] relay request failed: internal error")
              send_error(connection, 503, "identity-gateway-unavailable")
            }
          }
        },
        allow_failure=true,
      )
  }
}
