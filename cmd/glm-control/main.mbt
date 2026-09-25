///|
priv struct Target {
  host : String
  container : String
}

///|
fn targets() -> Array[Target] {
  [
    { host: "wlc003s@192.168.2.178", container: "glm53-exl3-head", },
    { host: "wlc004s@192.168.2.179", container: "glm53-exl3-worker", },
  ]
}

///|
fn required(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure("missing GLM control configuration")
  }
  value
}

///|
async fn docker(target : Target, args : Array[String]) -> String {
  let (code, output, _error) = @process.collect_output(
    "ssh",
    ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", target.host, "docker"] +
    args,
  )
  if code != 0 || output.text().length() > 1048576 {
    raise Failure("GLM control target unavailable")
  }
  output.text()
}

///|
fn inspected_container(
  document : String,
  target : Target,
) -> (String, Bool) raise {
  guard @json.parse(document)
    is Array(
      [
        {
          "Id": String(id),
          "Name": String(name),
          "Config": { "Image": String(image), .. },
          "State": { "Running": running_state, .. },
          ..
        },
      ]
    ) &&
    name == "/" + target.container &&
    id.length() == 64 &&
    id.all(c => c is ('0'..='9' | 'a'..='f')) &&
    (running_state == true.to_json() || running_state == false.to_json()) &&
    image.contains("glm-5.3-flash-2x-dgx-sparks") else {
    raise Failure("GLM control target does not match the approved container")
  }
  (id, running_state == true.to_json())
}

///|
async fn observe() -> Array[(Target, String, Bool)] {
  let observed = []
  for target in targets() {
    let (id, running) = inspected_container(
      docker(target, ["inspect", target.container]),
      target,
    )
    observed.push((target, id, running))
  }
  observed
}

///|
async fn gpu_idle(target : Target) -> Bool {
  let (code, output, _error) = @process.collect_output("ssh", [
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=10",
    target.host,
    "nvidia-smi",
    "--query-compute-apps=pid",
    "--format=csv,noheader,nounits",
  ])
  code == 0 && output.text().trim() == ""
}

///|
fn state(observed : Array[(Target, String, Bool)]) -> String {
  if observed.all(item => item.2) {
    "Running"
  } else if observed.all(item => !item.2) {
    "Stopped"
  } else {
    "Partial"
  }
}

///|
async fn stop_glm() -> String {
  let before = observe()
  // Worker first prevents a still-running rank 1 from outliving the head.
  for index in [1, 0] {
    let (target, id, running) = before[index]
    if running {
      ignore(docker(target, ["stop", "--time=60", id])) catch {
        _ => ()
      }
    }
  }
  state(observe())
}

///|
async fn start_glm() -> String {
  let before = observe()
  for item in before {
    if item.2 || !gpu_idle(item.0) {
      raise Failure("GLM Spark pair is not idle")
    }
  }
  // The worker joins the distributed runtime before the head advertises it.
  for index in [1, 0] {
    let (target, id, running) = before[index]
    if !running {
      ignore(docker(target, ["start", id]))
    }
  }
  state(observe())
}

///|
fn header(headers : Map[String, String], name : String) -> String? {
  headers
  .iter()
  .find_first(pair => pair.0.to_lower() == name)
  .map(pair => pair.1)
}

///|
async fn reply(
  connection : @http.ServerConnection,
  code : Int,
  value : String,
) -> Unit {
  connection.send_response(code, "GLM control", extra_headers={
    "content-type": "application/json",
    "cache-control": "no-store",
  })
  connection.write_string(({ "state": value } : Json).stringify())
  connection.end_response()
}

///|
async fn main {
  let bind = required("LUNANEXA_GLM_CONTROL_BIND")
  let token = @fs.read_file(required("LUNANEXA_GLM_CONTROL_TOKEN_FILE"))
    .text()
    .trim()
    .to_owned()
  if token.length() < 32 || !bind.has_prefix("192.168.2.175:") {
    raise Failure("invalid GLM control configuration")
  }
  let server = @http.Server(@socket.Addr::parse(bind), reuse_addr=true)
  defer server.close()
  let lock = @async.Mutex()
  server.run_forever(max_connections=16, allow_failure=true, (
    request,
    _body,
    connection,
  ) => {
    if header(request.headers, "authorization") != Some("Bearer " + token) {
      return reply(connection, 401, "Unauthorized")
    }
    if request.path != "/v1/glm-control" &&
      request.path != "/v1/glm-control:start" {
      return reply(connection, 404, "NotFound")
    }
    if (request.path == "/v1/glm-control:start" && request.meth != Post) ||
      (
        request.path == "/v1/glm-control" &&
        request.meth != Get &&
        request.meth != Post
      ) {
      return reply(connection, 405, "MethodNotAllowed")
    }
    lock.acquire()
    defer lock.release()
    let result = try {
      if request.path == "/v1/glm-control:start" {
        start_glm()
      } else if request.meth == Post {
        stop_glm()
      } else {
        state(observe())
      }
    } catch {
      _ => "Unavailable"
    } noraise {
      value => value
    }
    reply(connection, if result == "Unavailable" { 503 } else { 200 }, result)
  })
}
