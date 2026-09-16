///|
fn required(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure("Missing WebIDE deployment setting: " + name)
  }
  value
}

///|
async fn main {
  try {
    let config : @host.HostConfig = @json.from_json(
      @json.parse(@fs.read_file(required("LUNANEXA_WEBIDE_CONFIG_FILE")).text()),
    )
    let host = @host.WorkspaceHost::new(config)
    let client_id = required("LUNANEXA_WEBIDE_CLIENT_ID")
    let bridge = @webide.Bridge::new(
      {
        client_id,
        public_origin: required("LUNANEXA_WEBIDE_PUBLIC_ORIGIN"),
        maximum_sessions: 512,
        maximum_request_bytes: 67108864,
        maximum_socket_message_bytes: 16777216,
        request_timeout_ms: 300000,
        authorization_interval_ms: 5000,
      },
      code => {
        // Fixed stage names only: exceptions may contain credentials or JSON.
        errdefer println("WebIDE launch failed at controller redemption")
        host.redeem(client_id, code)
      },
      grant => {
        let authorized = host.authorize(grant)
        if !authorized {
          println("WebIDE authority check rejected")
        }
        authorized
      },
      (id, grant) => {
        errdefer println("WebIDE launch failed at workspace provisioning")
        host.provision(id, grant)
      },
    )
    let server = @http.Server(
      @socket.Addr::parse(required("LUNANEXA_WEBIDE_BIND")),
    )
    defer server.close()
    @async.with_task_group <| group => {
      group.spawn_bg(() => {
        while true {
          host.reconcile() catch {
            _ =>
              println(
                "WebIDE reconciliation incomplete; retrying without releasing authority",
              )
          }
          @async.sleep(30000)
        }
      })
      server.run_forever(
        (request, body, connection) => bridge.handle(request, body, connection),
        max_connections=1024,
        allow_failure=true,
      )
    }
  } catch {
    _ => {
      // Full exceptions may include a secret-bearing JSON input or upstream URL.
      println(
        "WebIDE gateway stopped: verify deployment configuration and private service connectivity",
      )
      @sys.exit(1)
    }
  }
}
