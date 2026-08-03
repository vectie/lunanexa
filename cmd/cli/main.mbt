///|
fn environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required environment reference is missing: \{name}")
  }
  value
}

///|
fn endpoint(base : String, path : String) -> String {
  if base.has_suffix("/") {
    "\{base[:-1]}\{path}"
  } else {
    "\{base}\{path}"
  }
}

///|
fn bearer(token : String) -> Map[String, String] {
  {
    "Authorization": "Bearer \{token}",
    "Accept": "application/json",
    "Content-Type": "application/json",
  }
}

///|
async fn print_get(base : String, path : String, token? : String = "") -> Unit {
  let headers = if token == "" { Map([]) } else { bearer(token) }
  let (response, body) = @http.get(endpoint(base, path), headers~)
  let output = body.text()
  if response.code < 200 || response.code >= 300 {
    raise Failure::Failure(
      "request failed with status \{response.code}: \{output}",
    )
  }
  println(output)
}

///|
async fn print_put(
  base : String,
  path : String,
  token : String,
  body : String,
) -> Unit {
  let (response, response_body) = @http.put(
    endpoint(base, path),
    body,
    headers=bearer(token),
  )
  let output = response_body.text()
  if response.code < 200 || response.code >= 300 {
    raise Failure::Failure(
      "request failed with status \{response.code}: \{output}",
    )
  }
  println(output)
}

///|
async fn print_post_empty(base : String, path : String, token : String) -> Unit {
  let (response, response_body) = @http.post(
    endpoint(base, path),
    "",
    headers=bearer(token),
  )
  let output = response_body.text()
  if response.code < 200 || response.code >= 300 {
    raise Failure::Failure(
      "request failed with status \{response.code}: \{output}",
    )
  }
  println(output)
}

///|
fn usage() -> String {
  (
    #|usage: lunanexa <health|capabilities|invoke FILE|status ID|cancel ID|nodes|node-state ID active|cordoned|draining GENERATION|assignments|assign FILE|stop-assignment ID|registry|scheduler|recovery-plan|telemetry|set-quota FILE|capacity FILE|record-benchmark FILE|register-model FILE|register-runtime FILE|record-license FILE|record-verification FILE|record-evaluation FILE|approve FILE|promote FILE|rollback FILE|issue-enrollment-token FILE|audit>
  )
}

///|
async fn print_post_file(
  base : String,
  path : String,
  token : String,
  file : String,
) -> Unit {
  let body = @fs.read_file(file)
  let (response, response_body) = @http.post(
    endpoint(base, path),
    body,
    headers=bearer(token),
  )
  let output = response_body.text()
  if response.code < 200 || response.code >= 300 {
    raise Failure::Failure(
      "request failed with status \{response.code}: \{output}",
    )
  }
  println(output)
}

///|
async fn main {
  let args = @env.args()
  guard args.length() >= 2 else { raise Failure::Failure(usage()) }
  let base = @env.get_env_var("LUNANEXA_ENDPOINT").unwrap_or(
    "http://127.0.0.1:8080",
  )
  match args[1] {
    "health" => print_get(base, "/health")
    "capabilities" =>
      print_get(
        base,
        "/v1/capabilities",
        token=environment("LUNANEXA_INFERENCE_TOKEN"),
      )
    "nodes" =>
      print_get(base, "/v1/nodes", token=environment("LUNANEXA_OPERATOR_TOKEN"))
    "node-state" => {
      guard args.length() == 5 else { raise Failure::Failure(usage()) }
      let desired_state : @contracts.NodeState = match args[3] {
        "active" => Active
        "cordoned" => Cordoned
        "draining" => Draining
        _ =>
          raise Failure::Failure(
            "node state must be active, cordoned, or draining",
          )
      }
      let generation = @string.parse_int64(args[4])
      let directive : @contracts.NodeDirective = {
        node_id: args[2],
        desired_state,
        generation,
        issued_unix_ms: @async.now(),
        receipt: "node-state:\{args[2]}:\{generation}",
      }
      print_put(
        base,
        "/v1/nodes/directive",
        environment("LUNANEXA_OPERATOR_TOKEN"),
        directive.to_json().stringify(),
      )
    }
    "assignments" =>
      print_get(
        base,
        "/v1/assignments",
        token=environment("LUNANEXA_OPERATOR_TOKEN"),
      )
    "audit" =>
      print_get(base, "/v1/audit", token=environment("LUNANEXA_AUDIT_TOKEN"))
    "registry" =>
      print_get(
        base,
        "/v1/registry",
        token=environment("LUNANEXA_OPERATOR_TOKEN"),
      )
    "scheduler" =>
      print_get(
        base,
        "/v1/scheduler",
        token=environment("LUNANEXA_OPERATOR_TOKEN"),
      )
    "recovery-plan" =>
      print_get(
        base,
        "/v1/recovery/plan",
        token=environment("LUNANEXA_OPERATOR_TOKEN"),
      )
    "telemetry" =>
      print_get(
        base,
        "/v1/telemetry",
        token=environment("LUNANEXA_OPERATOR_TOKEN"),
      )
    "set-quota" => {
      guard args.length() == 3 else { raise Failure::Failure(usage()) }
      print_put(
        base,
        "/v1/quotas",
        environment("LUNANEXA_OPERATOR_TOKEN"),
        @fs.read_file(args[2]).text(),
      )
    }
    "register-model"
    | "register-runtime"
    | "record-license"
    | "record-verification"
    | "record-evaluation"
    | "approve"
    | "promote"
    | "rollback"
    | "issue-enrollment-token"
    | "capacity"
    | "record-benchmark" => {
      guard args.length() == 3 else { raise Failure::Failure(usage()) }
      let path = match args[1] {
        "register-model" => "/v1/models"
        "register-runtime" => "/v1/runtimes"
        "record-license" => "/v1/licenses"
        "record-verification" => "/v1/verifications"
        "record-evaluation" => "/v1/evaluations"
        "approve" => "/v1/models/approve"
        "promote" => "/v1/aliases/promote"
        "rollback" => "/v1/aliases/rollback"
        "issue-enrollment-token" => "/v1/enrollment/tokens"
        "capacity" => "/v1/capacity:forecast"
        "record-benchmark" => "/v1/benchmarks"
        _ => abort("unreachable")
      }
      print_post_file(
        base,
        path,
        environment("LUNANEXA_OPERATOR_TOKEN"),
        args[2],
      )
    }
    "status" => {
      guard args.length() == 3 else { raise Failure::Failure(usage()) }
      print_get(
        base,
        "/v1/workloads/\{args[2]}",
        token=environment("LUNANEXA_INFERENCE_TOKEN"),
      )
    }
    "invoke" => {
      guard args.length() == 3 else { raise Failure::Failure(usage()) }
      let body = @fs.read_file(args[2]).text()
      let request = @contracts.decode_workload(body)
      let transport = @client.HttpTransport::new(
        environment("LUNANEXA_INFERENCE_TOKEN"),
      )
      let provider = @client.Client::new(
        {
          endpoint: base,
          inference_credential_ref: "environment:LUNANEXA_INFERENCE_TOKEN",
          timeout_ms: request.resource_ceiling.max_runtime_ms,
        },
        transport,
      )
      println(provider.invoke(request).to_json().stringify())
    }
    "cancel" => {
      guard args.length() == 3 else { raise Failure::Failure(usage()) }
      let transport = @client.HttpTransport::new(
        environment("LUNANEXA_INFERENCE_TOKEN"),
      )
      let provider = @client.Client::new(
        {
          endpoint: base,
          inference_credential_ref: "environment:LUNANEXA_INFERENCE_TOKEN",
          timeout_ms: 30000L,
        },
        transport,
      )
      if provider.cancel(args[2]) {
        println("{\"accepted\":true}")
      } else {
        raise Failure::Failure("cancellation was rejected")
      }
    }
    "assign" => {
      guard args.length() == 3 else { raise Failure::Failure(usage()) }
      let assignment : @contracts.DesiredAssignment = @json.from_json(
        @json.parse(@fs.read_file(args[2]).text()),
      )
      print_put(
        base,
        "/v1/assignments",
        environment("LUNANEXA_OPERATOR_TOKEN"),
        { ..assignment, signature: "" }.to_json().stringify(),
      )
    }
    "stop-assignment" => {
      guard args.length() == 3 else { raise Failure::Failure(usage()) }
      print_post_empty(
        base,
        "/v1/assignments/\{args[2]}/stop",
        environment("LUNANEXA_OPERATOR_TOKEN"),
      )
    }
    _ => raise Failure::Failure(usage())
  }
}
