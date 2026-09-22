///|
async test "exclusive gateway resolves scoped reservation and never falls back on missing placement" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let config = { ..host_config(), controller_origin: "http://\{server.addr}", }
  let grant = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let host = WorkspaceHost::new(
    config,
    require_exclusive=true,
    observation_token="fixture-token",
  )
  let state = { "status": 200, "wrong_tenant": 0 }
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((request, _body, connection) => {
        assert_eq(
          request_header(request.headers, "authorization"),
          Some("Bearer " + grant.api_secret),
        )
        if request.path == "/v1/models" {
          connection.send_response(200, "OK")
          connection.write_string("{}")
        } else {
          assert_eq(request.path, "/v1/workspace-delivery/placement")
          assert_eq(
            request_header(request.headers, "x-lunanexa-client"),
            Some(grant.client_id),
          )
          connection.send_response(state["status"], "Fixture")
          let response : Json = {
            "reservation_id": "reservation-123",
            "node_name": "spark-25e2",
            "tenant_ref": if state["wrong_tenant"] == 1 {
              "other"
            } else {
              grant.tenant_ref
            },
            "organization_id": grant.organization_id,
            "project_id": grant.project_id,
            "expires_unix_ms": grant.expires_unix_ms,
          }
          connection.write_string(response.stringify())
        }
        connection.end_response()
      })
    })
    assert_true(host.authorize(grant))
    assert_true(
      host.delivery_placement(grant) is Some((placement, _)) &&
      placement.node_name == "spark-25e2",
    )
    state["wrong_tenant"] = 1
    assert_false(host.authorize(grant))
    state["wrong_tenant"] = 0
    state["status"] = 404
    assert_false(host.authorize(grant))
    state["status"] = 503
    try host.authorize(grant) catch {
      @webide.BridgeError::AuthorityUnavailable => ()
      _ => fail("unexpected authority error")
    } noraise {
      _ => fail("outage was treated as authority")
    }
  }
}

///|
async test "ready callback requires an actual successful workspace response" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let config = { ..host_config(), controller_origin: "http://\{server.addr}", }
  let grant = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let host = WorkspaceHost::new(
    config,
    require_exclusive=true,
    observation_token="fixture-token",
  )
  let state = { "probe_status": 503, "callbacks": 0 }
  let backend : @webide.Backend = {
    http_url: config.controller_origin,
    websocket_url: "ws://\{server.addr}",
  }
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((request, _body, connection) => {
        if request.path == "/system_stats" {
          connection.send_response(state["probe_status"], "Fixture")
        } else {
          assert_eq(request.path, "/v1/workspace-delivery/ready")
          assert_eq(
            request_header(request.headers, "x-lunanexa-gateway-token"),
            Some("fixture-token"),
          )
          assert_eq(
            request_header(request.headers, "authorization"),
            Some("Bearer " + grant.api_secret),
          )
          state["callbacks"] += 1
          connection.send_response(200, "OK")
        }
        connection.write_string("{}")
        connection.end_response()
      })
    })
    try host.report_delivery_ready(grant, backend, "/system_stats") catch {
      HostError::WorkspaceUnavailable => ()
      _ => fail("unexpected probe failure")
    } noraise {
      _ => fail("failed workspace marked ready")
    }
    assert_eq(state["callbacks"], 0)
    state["probe_status"] = 200
    host.report_delivery_ready(grant, backend, "/system_stats")
    assert_eq(state["callbacks"], 1)
  }
}

///|
async test "exclusive callbacks claim budget before launch and report stop only after pod drain" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let config = { ..host_config(), controller_origin: "http://\{server.addr}", }
  let grant = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let id = @webide.workspace_id(grant)
  let events : Array[String] = []
  let state = { "drain_failed": true }
  let host : WorkspaceHost = {
    config,
    require_exclusive: true,
    observation_token: "fixture-token",
    locks: {},
    kubernetes_override: Some((verb, path, _body) => {
      if path.contains("/deployments?") {
        return (
          200,
          { "items": [{ "metadata": { "name": resource_name(id) } }] },
        )
      }
      if verb == Put {
        events.push("scaled-zero")
        return (200, {})
      }
      if state["drain_failed"] {
        raise HostError::WorkspaceUnavailable
      }
      events.push("pods-gone")
      (200, { "items": [] })
    }),
  }
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((request, body, connection) => {
        assert_eq(
          request_header(request.headers, "x-lunanexa-gateway-token"),
          Some("fixture-token"),
        )
        let payload = @json.parse(@utf8.decode(limited(body, 32768)))
        if request.path == "/v1/workspace-delivery/starting" {
          assert_eq(
            request_header(request.headers, "authorization"),
            Some("Bearer " + grant.api_secret),
          )
          assert_true(
            payload
            is {
              "memory_mib": Number(2560.0, ..),
              "gpu_memory_mib": Number(0.0, ..),
              ..
            },
          )
          events.push("starting")
        } else {
          assert_eq(request.path, "/v1/workspace-delivery/stopped")
          assert_eq(request_header(request.headers, "authorization"), None)
          assert_true(
            payload is { "workspace_id": String(value), .. } && value == id,
          )
          assert_eq(events.last(), Some("pods-gone"))
          events.push("stopped")
        }
        connection.send_response(200, "OK")
        connection.write_string("{}")
        connection.end_response()
      })
    })
    host.report_delivery_starting(grant, None)
    try host.stop(id) catch {
      HostError::WorkspaceUnavailable => ()
      _ => fail("unexpected stop error")
    } noraise {
      _ => fail("unproven drain accepted")
    }
    assert_eq(events, ["starting", "scaled-zero"])
    state["drain_failed"] = false
    host.stop(id)
    assert_eq(events, [
      "starting", "scaled-zero", "scaled-zero", "pods-gone", "stopped",
    ])
  }
}
