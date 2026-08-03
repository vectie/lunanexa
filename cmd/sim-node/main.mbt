///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required simulator environment is missing: \{name}")
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
fn node_headers(node_id : String, token : String) -> Map[String, String] {
  {
    "Authorization": "Node \{token}",
    "X-LunaNexa-Node-Id": node_id,
    "Accept": "application/json",
    "Content-Type": "application/json",
  }
}

///|
async fn load_agent(path : String, node_id : String) -> @node_agent.NodeAgent {
  if !@fs.exists(path) {
    let agent = @node_agent.NodeAgent::new(node_id)
    agent.activate()
    return agent
  }
  let snapshot : @node_agent.NodeAgentSnapshot = @json.from_json(
    @json.parse(@fs.read_file(path).text()),
  )
  if snapshot.node_id != node_id {
    raise Failure::Failure("simulated node state has the wrong identity")
  }
  @node_agent.NodeAgent::from_snapshot(snapshot)
}

///|
async fn persist_agent(path : String, agent : @node_agent.NodeAgent) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    agent.snapshot().to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
async fn persist_certificate(
  path : String,
  certificate : @node_agent.NodeCertificate,
) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    certificate.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
async fn ensure_certificate(
  base : String,
  node_id : String,
  node_token : String,
  certificate_path : String,
) -> Unit {
  if @fs.exists(certificate_path) {
    let certificate : @node_agent.NodeCertificate = @json.from_json(
      @json.parse(@fs.read_file(certificate_path).text()),
    )
    if certificate.node_id != node_id {
      raise Failure::Failure(
        "simulated node certificate has the wrong identity",
      )
    }
    return
  }
  let body : Json = {
    "node_id": node_id,
    "token_id": required_environment("LUNANEXA_BOOTSTRAP_TOKEN_ID"),
    "secret": required_environment("LUNANEXA_BOOTSTRAP_TOKEN"),
    "node_auth_secret": node_token,
    "public_key_ref": "simulator-only:\{node_id}",
  }
  let (response, response_body) = @http.post(
    endpoint(base, "/v1/enrollment"),
    body,
  )
  if response.code != 201 {
    raise Failure::Failure("simulated node enrollment was rejected")
  }
  let certificate : @node_agent.NodeCertificate = @json.from_json(
    @json.parse(response_body.text()),
  )
  persist_certificate(certificate_path, certificate)
}

///|
async fn reconcile_once(
  base : String,
  node_id : String,
  token : String,
  inventory : @contracts.NodeInventory,
  agent : @node_agent.NodeAgent,
  verifier : @node_agent.SharedSecretAssignmentVerifier,
  runtime_health_endpoint : String,
  state_path : String,
) -> Unit {
  let headers = node_headers(node_id, token)
  let (directive_response, directive_body) = @http.get(
    endpoint(base, "/v1/nodes/\{node_id}/directive"),
    headers~,
  )
  if directive_response.code == 200 {
    let directive : @contracts.NodeDirective = @json.from_json(
      @json.parse(directive_body.text()),
    )
    agent.apply_directive(directive)
  } else if directive_response.code != 404 {
    raise Failure::Failure("simulated node directive fetch failed")
  }
  let (assignment_response, assignment_body) = @http.get(
    endpoint(base, "/v1/nodes/\{node_id}/assignments"),
    headers~,
  )
  if assignment_response.code < 200 || assignment_response.code >= 300 {
    raise Failure::Failure("simulated node assignment fetch failed")
  }
  let assignments : Array[@contracts.DesiredAssignment] = @json.from_json(
    @json.parse(assignment_body.text()),
  )
  let now = @async.now()
  ignore(agent.reap_expired(now))
  ignore(
    agent.remove_absent(
      [
        for assignment in assignments => assignment.assignment_id
      ],
    ),
  )
  for assignment in assignments {
    if agent.reconcile(assignment, verifier, now) {
      let runtime_ready = try {
        let (response, response_body) = @http.get(runtime_health_endpoint)
        ignore(response_body.text())
        response.code == 200
      } catch {
        _ => false
      } noraise {
        value => value
      }
      agent.observe_runtime(
        assignment.assignment_id,
        if runtime_ready {
          Ready
        } else {
          Failed
        },
      )
    }
  }
  persist_agent(state_path, agent)
  let unsigned : @contracts.NodeHeartbeat = {
    node_id,
    state: agent.state(),
    observed_generation: agent.observed_generation(),
    controller_epoch: agent.controller_epoch(),
    inventory,
    running_deployments: agent.running_deployments(),
    timestamp_unix_ms: now,
    signature: "",
  }
  let heartbeat = {
    ..unsigned,
    signature: @node_agent.heartbeat_signature(unsigned, token),
  }
  let (heartbeat_response, _) = @http.put(
    endpoint(base, "/v1/nodes/heartbeat"),
    heartbeat.to_json(),
    headers~,
  )
  if heartbeat_response.code != 202 {
    raise Failure::Failure("simulated node heartbeat was rejected")
  }
}

///|
async fn main {
  if @env.get_env_var("LUNANEXA_SIMULATION_ONLY") != Some("1") {
    raise Failure::Failure(
      "the simulated node requires explicit simulation-only mode",
    )
  }
  let base = required_environment("LUNANEXA_ENDPOINT")
  if !base.has_prefix("http://127.0.0.1:") &&
    !base.has_prefix("http://localhost:") {
    raise Failure::Failure(
      "the simulator only connects to a loopback controller",
    )
  }
  let node_id = required_environment("LUNANEXA_NODE_ID")
  let token = required_environment("LUNANEXA_NODE_TOKEN")
  let inventory : @contracts.NodeInventory = @json.from_json(
    @json.parse(
      @fs.read_file(required_environment("LUNANEXA_NODE_INVENTORY_PATH")).text(),
    ),
  )
  if inventory.node_id != node_id {
    raise Failure::Failure("simulated inventory has the wrong node identity")
  }
  let state_path = required_environment("LUNANEXA_NODE_STATE_PATH")
  let agent = load_agent(state_path, node_id)
  let verifier = @node_agent.SharedSecretAssignmentVerifier::new(
    required_environment("LUNANEXA_ASSIGNMENT_SIGNING_SECRET"),
  )
  let runtime_health_endpoint = required_environment(
    "LUNANEXA_SIM_RUNTIME_HEALTH_ENDPOINT",
  )
  if !runtime_health_endpoint.has_prefix("http://127.0.0.1:") &&
    !runtime_health_endpoint.has_prefix("http://localhost:") {
    raise Failure::Failure("simulated runtime health must use loopback")
  }
  ensure_certificate(
    base,
    node_id,
    token,
    required_environment("LUNANEXA_NODE_CERTIFICATE_PATH"),
  )
  let poll_ms = @string.parse_int64(
    @env.get_env_var("LUNANEXA_SIM_POLL_MS").unwrap_or("250"),
  ).to_int()
  if poll_ms < 25 {
    raise Failure::Failure("simulator poll interval must be at least 25 ms")
  }
  println("simulated DGX node \{node_id} connected to \{base}")
  while true {
    reconcile_once(
      base, node_id, token, inventory, agent, verifier, runtime_health_endpoint,
      state_path,
    ) catch {
      _ => println("simulated node reconciliation failed; retrying")
    }
    @async.sleep(poll_ms)
  }
}
