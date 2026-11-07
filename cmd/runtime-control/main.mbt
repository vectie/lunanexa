///|
priv struct Target {
  host : String
  container : String
  image : String
}

///|
fn targets() -> Array[Target] raise {
  runtime_group().targets.map(t => {
    host: t.host,
    container: t.container.unwrap(),
    image: t.image.unwrap(),
  })
}

///|
fn required(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure("missing runtime control configuration")
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
    raise Failure("runtime control target unavailable")
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
    id.all(c => c is ('0'..<='9' | 'a'..<='f')) &&
    (running_state is True || running_state is False) &&
    image == target.image else {
    raise Failure(
      "runtime control target does not match the approved container",
    )
  }
  (id, running_state is True)
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
async fn stop_runtime() -> String {
  let before = observe()
  // Worker first prevents a still-running rank 1 from outliving the head.
  for index in runtime_group().stop_order {
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
async fn start_runtime() -> String {
  let before = observe()
  for item in before {
    if item.2 || !gpu_idle(item.0) {
      raise Failure("runtime Spark pair is not idle")
    }
  }
  // The worker joins the distributed runtime before the head advertises it.
  for index in runtime_group().start_order {
    let (target, id, running) = before[index]
    if !running {
      ignore(docker(target, ["start", id]))
    }
  }
  state(observe())
}

///|
fn header(headers : @http.Headers, name : String) -> String? {
  headers.get(name)
}

///|
async fn reply(
  connection : @http.ServerConnection,
  code : Int32,
  value : String,
) -> Unit {
  connection.send_response(code, "runtime control", extra_headers={
    "content-type": "application/json",
    "cache-control": "no-store",
  })
  connection.write_string(({ "state": value } : Json).stringify())
  connection.end_response()
}

///|
async fn main {
  let bind = required("LUNANEXA_RUNTIME_CONTROL_BIND")
  let token = @fs.read_file(required("LUNANEXA_RUNTIME_CONTROL_TOKEN_FILE"))
    .text()
    .trim()
    .to_owned()
  if token.length() < 32 ||
    bind.has_prefix("0.0.0.0:") ||
    bind.has_prefix("[::]:") {
    raise Failure("invalid runtime control configuration")
  }
  let server = @http.Server(@socket.Addr::parse(bind), reuse_addr=true)
  defer server.close()
  let lock = @async.Mutex()
  let native = native_pair_enabled()
  @async.with_task_group(group => {
    if native {
      group.spawn_bg(() => {
        while true {
          @async.sleep(2000)
          lock.acquire()
          defer lock.release()
          native_monitor() catch {
            _ =>
              // A control-transport failure is not evidence that a runtime
              // stopped or violated its envelope. Preserve the existing service;
              // the deployment authority retains an unknown resource claim.
              println("runtime supervision observation unavailable")
          }
        }
      })
    }
    server.run_forever(max_connections=16, allow_failure=true, (
      request,
      _body,
      connection,
    ) => {
      if header(request.headers, "authorization") != Some("Bearer " + token) {
        return reply(connection, 401, "Unauthorized")
      }
      // A temporary host-configured alias allows replacing the adapter before
      // its controller, without a second process controlling the same runtime.
      let path = match
        @env.get_env_var("LUNANEXA_RUNTIME_CONTROL_LEGACY_PATH") {
        Some(base) if request.path == base => "/v1/runtime-control"
        Some(base) if request.path == base + ":start" =>
          "/v1/runtime-control:start"
        _ => request.path
      }
      if path != "/v1/runtime-control" &&
        path != "/v1/runtime-control:stop" &&
        path != "/v1/runtime-control:start" {
        return reply(connection, 404, "NotFound")
      }
      if (path != "/v1/runtime-control" && request.meth != Post) ||
        (
          path == "/v1/runtime-control" &&
          request.meth != Get &&
          request.meth != Post
        ) {
        return reply(connection, 405, "MethodNotAllowed")
      }
      lock.acquire()
      defer lock.release()
      let result = try {
        if native {
          if path == "/v1/runtime-control:start" {
            native_start()
          } else if request.meth == Post {
            native_stop()
          } else {
            native_state(native_observe())
          }
        } else if path == "/v1/runtime-control:start" {
          start_runtime()
        } else if request.meth == Post {
          stop_runtime()
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
  })
}
