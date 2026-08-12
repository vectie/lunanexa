///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required environment reference is missing: \{name}")
  }
  value
}

///|
fn cors_headers(origin : String) -> Map[String, String] {
  {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  }
}

///|
async fn json_response(
  connection : @http.ServerConnection,
  status : Int,
  reason : String,
  origin : String,
  payload : Json,
) -> Unit {
  let headers = cors_headers(origin)
  headers["Content-Type"] = "application/json; charset=utf-8"
  connection.send_response(status, reason, extra_headers=headers)
  connection.write_string(payload.stringify())
  connection.end_response()
}

///|
fn process_arguments(
  request : @install_contract.InstallRequest,
) -> Array[String] {
  let arguments = [
    "--mode",
    if request.apply {
      "apply"
    } else {
      "preview"
    },
    "--ssh-user",
    request.ssh_user,
    "--ssh-key",
    request.ssh_key_path,
    "--known-hosts",
    request.known_hosts_path,
    "--management-node",
    request.management_node,
    "--management-host",
    request.management_host,
    "--namespace",
    request.cluster_namespace,
    "--kubeconfig",
    request.kubeconfig_path,
    "--rendered-directory",
    request.rendered_directory,
    "--secret-directory",
    request.secret_directory,
    "--cli-path",
    request.cli_path,
    "--confirmation",
    request.confirmation,
  ]
  for target in request.compute_nodes {
    arguments.push("--compute")
    arguments.push("\{target.node_name}=\{target.ssh_host}")
  }
  arguments
}

///|
fn public_line(line : String) -> String {
  let lowered = line.to_lower()
  let sensitive = lowered.contains("authorization:") ||
    lowered.contains("bearer ") ||
    lowered.contains("password=") ||
    lowered.contains("password:") ||
    lowered.contains("private-key") ||
    lowered.contains("private_key") ||
    lowered.contains("node-token") ||
    lowered.contains("bootstrap-token") ||
    lowered.contains("operator-token") ||
    lowered.contains("\"secret\"") ||
    lowered.contains("secret=")
  let safe = if sensitive { "[redacted sensitive output]" } else { line }
  let bounded = if safe.length() > 4096 { "\{safe[:4096]}…" } else { safe }
  ({ "kind": "line", "text": bounded } : Json).stringify()
}

///|
async fn stream_install(
  connection : @http.ServerConnection,
  origin : String,
  script : String,
  request : @install_contract.InstallRequest,
) -> Unit {
  let headers = cors_headers(origin)
  headers["Content-Type"] = "text/event-stream; charset=utf-8"
  headers["X-Accel-Buffering"] = "no"
  connection.send_response(200, "OK", extra_headers=headers)
  connection.write_string(
    "data: \{public_line(if request.apply { "Starting confirmed deployment" } else { "Starting dry-run preview" })}\n\n",
  )
  connection.flush()
  @async.with_task_group() <| group => {
    let (reader, writer) = @process.read_from_process()
    defer reader.close()
    let environment : Map[String, String] = {
      "PATH": @env.get_env_var("PATH").unwrap_or("/usr/local/bin:/usr/bin:/bin"),
      "LC_ALL": "C",
      "LUNANEXA_ENDPOINT": @env.get_env_var("LUNANEXA_ENDPOINT").unwrap_or(""),
      "LUNANEXA_OPERATOR_TOKEN": @env.get_env_var("LUNANEXA_OPERATOR_TOKEN").unwrap_or(
        "",
      ),
    }
    let child = @process.spawn(
      group,
      script,
      process_arguments(request),
      stdout=writer,
      stderr=writer,
      extra_env=environment,
      inherit_env=false,
    )
    let mut rows = 0
    while reader.read_until("\n") is Some(line) {
      rows += 1
      if rows > 4096 {
        child.cancel()
        connection.write_string(
          "data: \{public_line("[blocked] terminal output limit exceeded")}\n\n",
        )
        connection.flush()
        break
      }
      connection.write_string(
        "data: \{public_line(line.trim_end().to_owned())}\n\n",
      )
      connection.flush()
    }
    let status = child.wait()
    let terminal : Json = {
      "kind": "complete",
      "ok": status == 0,
      "exit_code": status,
    }
    connection.write_string("data: \{terminal.stringify()}\n\n")
    connection.flush()
  }
  connection.end_response()
}

///|
async fn main {
  let address = @env.get_env_var("LUNANEXA_INSTALLER_LISTEN_ADDRESS").unwrap_or(
    "127.0.0.1:4198",
  )
  guard address.has_prefix("127.0.0.1:") || address.has_prefix("[::1]:") else {
    raise Failure::Failure("deployment companion must listen on loopback")
  }
  let token = required_environment("LUNANEXA_INSTALLER_TOKEN")
  guard token.length() >= 32 else {
    raise Failure::Failure(
      "deployment companion token must be at least 32 characters",
    )
  }
  let allowed_origin = @env.get_env_var("LUNANEXA_INSTALLER_ALLOWED_ORIGIN").unwrap_or(
    "http://127.0.0.1:4173",
  )
  let script = @env.get_env_var("LUNANEXA_INSTALLER_SCRIPT").unwrap_or(
    "scripts/deploy/run-cluster-install.sh",
  )
  let server = @http.Server(@socket.Addr::parse(address))
  println("LunaNexa deployment companion listening on \{server.addr}")
  server.run_forever(max_connections=8) <| ((request, body, connection) => {
    let origin = request.headers.get("origin").unwrap_or("")
    if origin != allowed_origin {
      ignore(body.read_all())
      json_response(connection, 403, "Forbidden", allowed_origin, {
        "error": "origin rejected",
      })
      return
    }
    if request.meth == Options {
      ignore(body.read_all())
      connection.send_response(
        204,
        "No Content",
        extra_headers=cors_headers(allowed_origin),
      )
      connection.end_response()
      return
    }
    if request.meth != Post || request.path != "/v1/install:run" {
      ignore(body.read_all())
      json_response(connection, 404, "Not Found", allowed_origin, {
        "error": "route not found",
      })
      return
    }
    if request.headers.get("authorization") != Some("Bearer \{token}") {
      ignore(body.read_all())
      json_response(connection, 401, "Unauthorized", allowed_origin, {
        "error": "invalid installer session",
      })
      return
    }
    let text = body.read_all().text()
    if text.length() > 65536 {
      json_response(connection, 413, "Content Too Large", allowed_origin, {
        "error": "request is too large",
      })
      return
    }
    let install_request : @install_contract.InstallRequest = @json.from_json(
      @json.parse(text),
    ) catch {
      _ => {
        json_response(connection, 400, "Bad Request", allowed_origin, {
          "error": "invalid install request",
        })
        return
      }
    }
    try @install_contract.validate_request(install_request) catch {
      InvalidField(field) => {
        json_response(connection, 400, "Bad Request", allowed_origin, {
          "error": "invalid field",
          "field": field,
        })
        return
      }
    } noraise {
      _ => ()
    }
    stream_install(connection, allowed_origin, script, install_request)
  })
}
