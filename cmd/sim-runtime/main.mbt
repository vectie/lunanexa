///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required simulator environment is missing: \{name}")
  }
  value
}

///|
async fn simulation_mode(path : String) -> (String, Int) {
  if !@fs.exists(path) {
    return ("ready", 0)
  }
  let value = @fs.read_file(path).text().trim().to_owned()
  if value.has_prefix("delay:") {
    let delay = @string.parse_int64(value["delay:".length():]).to_int() catch {
      _ => 0
    }
    ("ready", delay.max(0))
  } else {
    (value, 0)
  }
}

///|
async fn record_invocation(path : String, node_id : String) -> Unit {
  @fs.write_file(
    path,
    "\{node_id}\n",
    create_mode=OpenOrCreate,
    permission=0o600,
    append=true,
  )
}

///|
async fn main {
  if @env.get_env_var("LUNANEXA_SIMULATION_ONLY") != Some("1") {
    raise Failure::Failure(
      "the simulated runtime requires explicit simulation-only mode",
    )
  }
  let node_id = required_environment("LUNANEXA_SIM_NODE_ID")
  let address = required_environment("LUNANEXA_SIM_LISTEN_ADDRESS")
  let control_path = required_environment("LUNANEXA_SIM_CONTROL_PATH")
  let invocation_path = required_environment("LUNANEXA_SIM_INVOCATION_PATH")
  let credential = required_environment("LUNANEXA_SIM_RUNTIME_CREDENTIAL")
  let server = @http.Server(@socket.Addr::parse(address), reuse_addr=true)
  println("simulated DGX runtime \{node_id} listening on \{server.addr}")
  server.run_forever(max_connections=64) <| ((request, body, connection) => {
    if request.meth == Get && request.path == "/health" {
      let (mode, _) = simulation_mode(control_path)
      if mode == "down" {
        connection.send_response(503, "Unavailable", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string("{\"status\":\"unavailable\"}")
      } else {
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string("{\"status\":\"ready\",\"simulated\":true}")
      }
      connection.end_response()
      return
    }
    if request.meth != Post || request.path != "/v1/responses" {
      ignore(body.read_all())
      connection.send_response(404, "Not Found")
      connection.end_response()
      return
    }
    let request_body = body.read_all().text()
    if request.headers.get("authorization") != Some("Bearer \{credential}") ||
      request.headers.get("x-lunanexa-target-node") != Some(node_id) {
      connection.send_response(401, "Unauthorized", extra_headers={
        "Content-Type": "application/json",
      })
      connection.write_string("{\"error\":\"unauthorized\"}")
      connection.end_response()
      return
    }
    let (mode, delay_ms) = simulation_mode(control_path)
    if delay_ms > 0 {
      @async.sleep(delay_ms)
    }
    if mode == "fail" || mode == "down" {
      connection.send_response(503, "Unavailable", extra_headers={
        "Content-Type": "application/json",
      })
      connection.write_string("{\"error\":\"simulated runtime unavailable\"}")
      connection.end_response()
      return
    }
    record_invocation(invocation_path, node_id)
    if request_body.contains("\"stream\":true") {
      connection.send_response(200, "OK", extra_headers={
        "Content-Type": "text/event-stream",
      })
      connection.write_string("data: {\"delta\":\"simulated \"}\n\n")
      connection.flush()
      connection.write_string(
        "data: {\"delta\":\"response\",\"usage\":{\"input_tokens\":2,\"output_tokens\":2}}\n\n",
      )
      connection.write_string("data: [DONE]\n\n")
    } else {
      connection.send_response(200, "OK", extra_headers={
        "Content-Type": "application/json",
      })
      connection.write_string(
        "{\"output_text\":\"simulated response\",\"usage\":{\"input_tokens\":2,\"output_tokens\":2}}",
      )
    }
    connection.end_response()
  })
}
