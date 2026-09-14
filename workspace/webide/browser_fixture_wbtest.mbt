///|
/// Manual integration fixture, deliberately excluded from the automated gate.
/// Start real ComfyUI on loopback :5876, run this test with --include-skipped,
/// then launch /connect#lunanexa_handoff=lnxc_offline_browser_acceptance on :5875.
/// It proves browser integration only, never controller/GPU/provider readiness.
#skip("requires a real local ComfyUI and interactive browser acceptance")
async test "interactive ComfyUI browser acceptance fixture" {
  let origin = "http://127.0.0.1:5875"
  let grant = test_grant("offline-browser-acceptance")
  let bridge = Bridge::new(
    {
      ..test_config(origin),
      request_timeout_ms: 30000,
      maximum_request_bytes: 16777216,
      maximum_socket_message_bytes: 16777216,
    },
    code => {
      if code != "lnxc_offline_browser_acceptance" {
        raise BridgeError::Unauthorized
      }
      { ..grant, expires_unix_ms: @async.now() + 900000L, }
    },
    _ => true,
    (_, _) => {
      http_url: "http://127.0.0.1:5876",
      websocket_url: "ws://127.0.0.1:5876",
    },
  )
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:5875"))
  defer server.close()
  let finished = { "value": false }
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((request, body, connection) => {
        if request.path == "/__acceptance/finish" &&
          request.meth == Post &&
          header(request.headers, "x-acceptance-token") ==
          Some("offline-browser-acceptance") {
          reply(connection, 200, "Acceptance fixture stopped")
          finished["value"] = true
        } else {
          bridge.handle(request, body, connection)
        }
      })
    })
    println(
      "Offline ComfyUI browser fixture: http://127.0.0.1:5875/connect#lunanexa_handoff=lnxc_offline_browser_acceptance",
    )
    @async.with_timeout(900000, () => {
      while !finished["value"] {
        @async.sleep(100)
      }
    })
  }
}
