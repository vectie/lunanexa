///|
fn lunaflux_ready_output(
  runtime_origin? : String = "http://127.0.0.1:43120",
  control_origin? : String = runtime_origin,
  runtime_protocol? : String = "openai-responses-v1",
) -> String {
  let prefix =
    #|LunaFlux OpenAI Responses service
    #|health: healthy
    #|readiness: true
  prefix +
  "\n" +
  "runtime_origin=\{runtime_origin}\n" +
  "control_origin=\{control_origin}\n" +
  "runtime_protocol=\{runtime_protocol}\n" +
  "cold_start_latency_millis: 41\n" +
  "startup_measurement_readiness: true\n"
}

///|
fn expect_lunaflux_discovery_rejection(output : String) -> Unit raise {
  let adapter = verifier_only_authority_fixture().opaque_adapter()
  try adapter.parse_ready_publication(output) catch {
    _ => ()
  } noraise {
    _ => fail("hostile LunaFlux publication was accepted")
  }
}

///|
test "opaque adapter accepts exactly one adjacent ready publication" {
  let discovery = verifier_only_authority_fixture()
    .opaque_adapter()
    .parse_ready_publication(lunaflux_ready_output())
  assert_eq(discovery.runtime_origin(), "http://127.0.0.1:43120")
  assert_eq(discovery.runtime_protocol(), "openai-responses-v1")
  assert_eq(discovery.control_origin(), "http://127.0.0.1:43120")
}

///|
test "opaque adapter maps only wildcard publication to inspected private address" {
  let adapter = verifier_only_authority_fixture().opaque_adapter()
  let discovery = adapter.parse_private_ready_publication(
    lunaflux_ready_output(
      runtime_origin="http://0.0.0.0:43120",
      control_origin="http://0.0.0.0:43120",
    ),
    "10.88.0.14",
  )
  assert_eq(discovery.runtime_origin(), "http://10.88.0.14:43120")
  assert_eq(discovery.control_origin(), discovery.runtime_origin())
  for address in ["127.0.0.1", "8.8.8.8", "10.bad", ""] {
    try
      adapter.parse_private_ready_publication(
        lunaflux_ready_output(
          runtime_origin="http://0.0.0.0:43120",
          control_origin="http://0.0.0.0:43120",
        ),
        address,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("hostile container address was accepted")
    }
  }
}

///|
test "opaque adapter consumes the OCI-supervised private address" {
  let instance : @node.RuntimeInstance = {
    assignment_id: "assignment-1",
    container_name: "lunanexa-assignment-1",
    image_ref: "lunaflux@sha256:" + "a".repeat(64),
    artifact_digest: "b".repeat(64),
    observed_state: Ready,
    container_address: "172.19.0.8",
  }
  let discovery = verifier_only_authority_fixture()
    .opaque_adapter()
    .parse_private_ready_publication_from_instance(
      lunaflux_ready_output(
        runtime_origin="http://0.0.0.0:43120",
        control_origin="http://0.0.0.0:43120",
      ),
      instance,
    )
  assert_eq(discovery.runtime_origin(), "http://172.19.0.8:43120")
  assert_eq(discovery.control_origin(), discovery.runtime_origin())
}

///|
test "opaque adapter rejects duplicate missing stale and late publications" {
  let exact = lunaflux_ready_output()
  for
    hostile in [
      exact + "runtime_origin=http://127.0.0.1:43122\n",
      exact + "control_origin=http://127.0.0.1:43123\n",
      exact + "runtime_protocol=openai-responses-v1\n",
      "readiness: true\n" + exact,
      exact.replace(old="runtime_origin=http://127.0.0.1:43120\n", new=""),
      "runtime_origin=http://127.0.0.1:43120\nreadiness: true\ncontrol_origin=http://127.0.0.1:43121\nruntime_protocol=openai-responses-v1\n",
      exact.replace(
        old="readiness: true\nruntime_origin=",
        new="readiness: true\nlate diagnostic\nruntime_origin=",
      ),
      exact.replace(
        old="runtime_origin=http://127.0.0.1:43120\ncontrol_origin=http://127.0.0.1:43120\n",
        new="control_origin=http://127.0.0.1:43120\nruntime_origin=http://127.0.0.1:43120\n",
      ),
    ] {
    expect_lunaflux_discovery_rejection(hostile)
  }
}

///|
test "opaque adapter rejects malformed schemes control authority and protocol" {
  for
    hostile in [
      lunaflux_ready_output(runtime_origin="https://127.0.0.1:43120"),
      lunaflux_ready_output(runtime_origin="tcp://127.0.0.1:43120"),
      lunaflux_ready_output(runtime_origin="http://127.0.0.1:43120/path"),
      lunaflux_ready_output(control_origin="https://127.0.0.1:43121"),
      lunaflux_ready_output(control_origin="http://0.0.0.0:43121"),
      lunaflux_ready_output(control_origin="http://192.168.2.180:43121"),
      lunaflux_ready_output(control_origin="http://localhost:43121"),
      lunaflux_ready_output(runtime_protocol="native-framed-v1"),
      lunaflux_ready_output(runtime_protocol="OpenAI-Responses-v1"),
    ] {
    expect_lunaflux_discovery_rejection(hostile)
  }
}

///|
async test "discovered loopback control probes exact live health and readiness" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let paths : Array[String] = []
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, _body, connection) => {
        paths.push(request.path)
        match request.path {
          "/healthz" => {
            connection.send_response(200, "OK")
            connection.write_string("{\"status\":\"healthy\"}\n")
          }
          "/readyz" => {
            connection.send_response(200, "OK")
            connection.write_string("{\"status\":\"ready\"}\n")
          }
          _ => connection.send_response(404, "Not Found")
        }
        connection.end_response()
      })
    }
    let origin = "http://\{server.addr}"
    let discovery = verifier_only_authority_fixture()
      .opaque_adapter()
      .parse_ready_publication(
        lunaflux_ready_output(runtime_origin=origin, control_origin=origin),
      )
    discovery.probe_control(timeout_milliseconds=1000)
    assert_eq(paths, ["/healthz", "/readyz"])
    server.close()
  }
}

///|
async test "control probe rejects false readiness and invalid timeout" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, _body, connection) => {
        if request.path == "/healthz" {
          connection.send_response(200, "OK")
          connection.write_string("{\"status\":\"healthy\"}\n")
        } else {
          connection.send_response(503, "Unavailable")
          connection.write_string("{\"status\":\"not_ready\"}\n")
        }
        connection.end_response()
      })
    }
    let discovery = verifier_only_authority_fixture()
      .opaque_adapter()
      .parse_ready_publication(
        lunaflux_ready_output(
          runtime_origin="http://\{server.addr}",
          control_origin="http://\{server.addr}",
        ),
      )
    try discovery.probe_control(timeout_milliseconds=1000) catch {
      LunaFluxRuntimeDiscoveryError::ControlProbeFailed => ()
      error => fail("unexpected probe error: \{Repr(error)}")
    } noraise {
      _ => fail("false readiness was accepted")
    }
    try discovery.probe_control(timeout_milliseconds=0) catch {
      LunaFluxRuntimeDiscoveryError::InvalidControlProbeTimeout => ()
      error => fail("unexpected timeout error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid timeout was accepted")
    }
    server.close()
  }
}
