///|
fn environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required environment reference is missing: \{name}")
  }
  value
}

///|
async fn host_secret(
  environment_name : String,
  path_environment_name : String,
  default_path : String,
) -> String {
  if @env.get_env_var(environment_name) is Some(value) && value != "" {
    return value
  }
  let path = @env.get_env_var(path_environment_name).unwrap_or(default_path)
  let value = @fs.read_file(path).text().trim().to_owned()
  if value == "" {
    raise Failure::Failure("required host credential reference is empty")
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
/// Node-enforced policy is distributed by the administrator as the same
/// validated document used by the management node. It is never supplied by a
/// lease holder or workload request.
async fn load_global_admin_settings() -> @settings.GlobalAdminSettings {
  let configured = match @env.get_env_var("LUNANEXA_ADMIN_SETTINGS_PATH") {
    Some(path) if path != "" =>
      @settings.parse_global_admin_settings(@fs.read_file(path).text())
    _ => @settings.default_global_admin_settings()
  }
  @settings.validate_global_admin_settings(configured)
  configured
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
    raise Failure::Failure("node state belongs to a different node identity")
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
async fn load_lease_guard(
  path : String,
  node_id : String,
) -> @nodelease.LeaseAgentGuard {
  if !@fs.exists(path) {
    return @nodelease.LeaseAgentGuard::new(node_id)
  }
  let snapshot : @nodelease.LeaseAgentSnapshot = @json.from_json(
    @json.parse(@fs.read_file(path).text()),
  )
  if snapshot.node_id != node_id {
    raise Failure::Failure("exclusive lease state belongs to a different node")
  }
  @nodelease.LeaseAgentGuard::from_snapshot(snapshot)
}

///|
async fn persist_lease_guard(
  path : String,
  lease_guard : @nodelease.LeaseAgentGuard,
) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    lease_guard.snapshot().to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
fn valid_helper_path(path : String) -> Bool {
  path.has_prefix("/") &&
  path.length() <= 512 &&
  path.all(character => character.is_printable() && !character.is_whitespace())
}

///|
async fn execute_lease_action(
  helper : String,
  action : @nodelease.LeaseAgentAction,
  authorization : String,
) -> String? {
  if action is NoAction {
    return None
  }
  if !valid_helper_path(helper) {
    return None
  }
  if !@nodelease.helper_authorization_framed(authorization, @async.now()) {
    return None
  }
  let action_args = match action {
    ProvisionAccess(
      lease_id~,
      username~,
      credential_ref~,
      expires_unix_ms~,
      generation~
    ) =>
      [
        "provision",
        "--lease-id",
        lease_id,
        "--username",
        username,
        "--credential-ref",
        credential_ref,
        "--expires-unix-ms",
        expires_unix_ms.to_string(),
        "--generation",
        generation.to_string(),
      ]
    RevokeAccess(lease_id~, username~, generation~) =>
      [
        "revoke",
        "--lease-id",
        lease_id,
        "--username",
        username,
        "--generation",
        generation.to_string(),
      ]
    SanitizeLease(lease_id~, username~, generation~) =>
      [
        "sanitize",
        "--lease-id",
        lease_id,
        "--username",
        username,
        "--generation",
        generation.to_string(),
      ]
    QuarantineNode(lease_id~, username~, generation~) =>
      [
        "quarantine",
        "--lease-id",
        lease_id,
        "--username",
        username,
        "--generation",
        generation.to_string(),
      ]
    NoAction => []
  }
  let args = [..action_args, "--authorization", authorization]
  let (status, stdout) = @process.collect_stdout(
    helper,
    args,
    inherit_env=false,
  )
  if status != 0 {
    return None
  }
  let receipt = stdout.text().trim().to_owned()
  if @nodelease.valid_helper_receipt(action, receipt) {
    Some(receipt)
  } else {
    None
  }
}

///|
async fn flush_lease_observation(
  base : String,
  node_id : String,
  token : String,
  lease_guard : @nodelease.LeaseAgentGuard,
) -> (Bool, Bool) {
  guard lease_guard.pending_observation(@async.now()) is Some(observation) else {
    return (false, false)
  }
  try {
    let (response, _) = @http.post(
      endpoint(base, "/v1/nodes/\{node_id}/exclusive-lease:observe"),
      observation.to_json(),
      headers=node_headers(node_id, token),
    )
    if response.code >= 200 && response.code < 300 {
      lease_guard.acknowledge_observation(observation.receipt)
      (true, true)
    } else {
      (true, false)
    }
  } catch {
    _ => (true, false)
  }
}

///|
async fn reconcile_exclusive_lease(
  base : String,
  node_id : String,
  token : String,
  helper : String,
  lease_guard : @nodelease.LeaseAgentGuard,
  state_path : String,
  receipt_stale_after_ms : Int64,
) -> Unit {
  let now = @async.now()
  let mut control_available = true
  let mut action = try {
    let (response, body) = @http.get(
      endpoint(base, "/v1/nodes/\{node_id}/exclusive-lease"),
      headers=node_headers(node_id, token),
    )
    if response.code == 200 {
      let lease : @nodelease.ExclusiveNodeLease = @json.from_json(
        @json.parse(body.text()),
      )
      if @nodelease.valid_node_transport_lease(lease, node_id, token) {
        lease_guard.observe_remote(Some(lease), now)
      } else {
        // An authenticated transport is insufficient: fail closed if the
        // directive body is stale, cross-node, or modified in transit.
        control_available = false
        lease_guard.tick(now)
      }
    } else if response.code == 404 {
      lease_guard.observe_remote(None, now)
    } else {
      control_available = false
      lease_guard.tick(now)
    }
  } catch {
    _ => {
      // A transport or decoding failure must not bypass the local expiry fence.
      control_available = false
      lease_guard.tick(now)
    }
  } noraise {
    value => value
  }
  if control_available {
    let (had_pending, accepted) = flush_lease_observation(
      base, node_id, token, lease_guard,
    )
    if had_pending {
      if accepted {
        persist_lease_guard(state_path, lease_guard)
        return
      }
      let pending_action = lease_guard.pending_helper_action()
      let stale = @nodelease.helper_receipt_timestamp_unverified(
          pending_action,
          lease_guard.snapshot().last_receipt,
        )
        .map(timestamp => now - timestamp >= receipt_stale_after_ms)
        .unwrap_or(false)
      if !stale {
        persist_lease_guard(state_path, lease_guard)
        return
      }
      action = pending_action
    }
  }
  if action is NoAction {
    persist_lease_guard(state_path, lease_guard)
    return
  }
  let authorization = lease_guard
    .helper_authorization(action, now)
    .unwrap_or("")
  if execute_lease_action(helper, action, authorization) is Some(receipt) {
    lease_guard.record_success(action, receipt)
    if control_available {
      ignore(flush_lease_observation(base, node_id, token, lease_guard))
    }
  } else {
    let quarantine = lease_guard.record_failure(action)
    let quarantine_authorization = lease_guard
      .helper_authorization(quarantine, now)
      .unwrap_or("")
    if execute_lease_action(helper, quarantine, quarantine_authorization)
      is Some(receipt) {
      lease_guard.record_success(quarantine, receipt)
      if control_available {
        ignore(flush_lease_observation(base, node_id, token, lease_guard))
      }
    }
  }
  persist_lease_guard(state_path, lease_guard)
}

///|
async fn ensure_certificate(
  base : String,
  node_id : String,
  node_token : String,
  certificate_path : String,
  public_key_ref : String,
  renewal_lead_ms : Int64,
) -> Unit {
  if !@fs.exists(certificate_path) {
    let bootstrap_id = host_secret(
      "LUNANEXA_BOOTSTRAP_TOKEN_ID", "LUNANEXA_BOOTSTRAP_TOKEN_ID_PATH", "/etc/lunanexa/bootstrap-token-id",
    )
    let bootstrap_secret = host_secret(
      "LUNANEXA_BOOTSTRAP_TOKEN", "LUNANEXA_BOOTSTRAP_TOKEN_PATH", "/etc/lunanexa/bootstrap-token",
    )
    let body : Json = {
      "node_id": node_id,
      "token_id": bootstrap_id,
      "secret": bootstrap_secret,
      "node_auth_secret": node_token,
      "public_key_ref": public_key_ref,
    }
    let (response, response_body) = @http.post(
      endpoint(base, "/v1/enrollment"),
      body,
    )
    if response.code != 201 {
      raise Failure::Failure("node enrollment was rejected")
    }
    let certificate : @node_agent.NodeCertificate = @json.from_json(
      @json.parse(response_body.text()),
    )
    persist_certificate(certificate_path, certificate)
    return
  }
  let current : @node_agent.NodeCertificate = @json.from_json(
    @json.parse(@fs.read_file(certificate_path).text()),
  )
  if current.node_id != node_id {
    raise Failure::Failure("certificate belongs to a different node identity")
  }
  if current.expires_unix_ms <= @async.now() + renewal_lead_ms {
    let body : Json = {
      "node_id": node_id,
      "public_key_ref": public_key_ref,
      "current_serial": current.serial,
    }
    let (response, response_body) = @http.post(
      endpoint(base, "/v1/enrollment/rotate"),
      body,
      headers=node_headers(node_id, node_token),
    )
    if response.code != 200 {
      raise Failure::Failure("node certificate rotation was rejected")
    }
    let certificate : @node_agent.NodeCertificate = @json.from_json(
      @json.parse(response_body.text()),
    )
    persist_certificate(certificate_path, certificate)
  }
}

///|
async fn send_heartbeat(
  base : String,
  node_id : String,
  token : String,
  inventory : @contracts.NodeInventory,
  agent : @node_agent.NodeAgent,
) -> Unit {
  let unsigned : @contracts.NodeHeartbeat = {
    node_id,
    state: agent.state(),
    observed_generation: agent.observed_generation(),
    controller_epoch: agent.controller_epoch(),
    inventory,
    running_deployments: agent.running_deployments(),
    timestamp_unix_ms: @async.now(),
    signature: "",
  }
  let heartbeat = {
    ..unsigned,
    signature: @node_agent.heartbeat_signature(unsigned, token),
  }
  let (response, _) = @http.put(
    endpoint(base, "/v1/nodes/heartbeat"),
    heartbeat.to_json(),
    headers=node_headers(node_id, token),
  )
  if response.code != 202 {
    raise Failure::Failure("heartbeat was rejected")
  }
}

///|
async fn materialize_while_heartbeating(
  base : String,
  node_id : String,
  token : String,
  inventory : @contracts.NodeInventory,
  agent : @node_agent.NodeAgent,
  materializer : @node_agent.ArtifactMaterializer,
  artifact_verifier : @node_agent.CosignArtifactSignatureVerifier,
  assignment : @contracts.DesiredAssignment,
  heartbeat_interval_ms : Int,
) -> @node_agent.MaterializedArtifact {
  @async.with_task_group <| group => {
    let task = group.spawn(() => {
      materializer.materialize(assignment, artifact_verifier)
    })
    for ;; {
      send_heartbeat(base, node_id, token, inventory, agent)
      match task.try_wait() {
        Some(artifact) => return artifact
        None => @async.sleep(heartbeat_interval_ms)
      }
    }
  }
}

///|
async fn reconcile_once(
  base : String,
  node_id : String,
  token : String,
  inventory : @contracts.NodeInventory,
  agent : @node_agent.NodeAgent,
  verifier : @node_agent.SharedSecretAssignmentVerifier,
  supervisor : @node_agent.OciRuntimeSupervisor,
  materializer : @node_agent.ArtifactMaterializer,
  artifact_verifier : @node_agent.CosignArtifactSignatureVerifier,
  state_path : String,
  lease_helper : String,
  exclusive_leases_enabled : Bool,
  lease_guard : @nodelease.LeaseAgentGuard,
  lease_state_path : String,
  materialization_heartbeat_interval_ms : Int,
  lease_receipt_stale_after_ms : Int64,
  telemetry_limits : @settings.TelemetrySafetySettings,
) -> Unit {
  if exclusive_leases_enabled {
    reconcile_exclusive_lease(
      base, node_id, token, lease_helper, lease_guard, lease_state_path, lease_receipt_stale_after_ms,
    )
  }
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
    raise Failure::Failure(
      "node directive fetch failed with status \{directive_response.code}",
    )
  }
  let (assignment_response, assignment_body) = @http.get(
    endpoint(base, "/v1/nodes/\{node_id}/assignments"),
    headers~,
  )
  if assignment_response.code < 200 || assignment_response.code >= 300 {
    raise Failure::Failure(
      "assignment fetch failed with status \{assignment_response.code}",
    )
  }
  let assignments : Array[@contracts.DesiredAssignment] = @json.from_json(
    @json.parse(assignment_body.text()),
  )
  let now = @async.now()
  for assignment_id in agent.reap_expired(now) {
    supervisor.stop(assignment_id)
  }
  let desired_ids = [
    for assignment in assignments => assignment.assignment_id
  ]
  for assignment_id in agent.remove_absent(desired_ids) {
    supervisor.stop(assignment_id)
  }
  for assignment in assignments {
    if agent.reconcile(assignment, verifier, now) {
      try {
        let artifact = materialize_while_heartbeating(
          base, node_id, token, inventory, agent, materializer, artifact_verifier,
          assignment, materialization_heartbeat_interval_ms,
        )
        if assignment.lease_expires_unix_ms <= @async.now() {
          agent.observe_runtime(assignment.assignment_id, Failed)
        } else {
          let instance = supervisor.ensure_started(assignment, artifact)
          agent.observe_runtime(
            assignment.assignment_id,
            instance.observed_state,
          )
        }
      } catch {
        _ => agent.observe_runtime(assignment.assignment_id, Failed)
      }
    }
  }
  materializer.prune_unassigned(
    [
      for assignment in assignments => assignment.artifact.digest
    ],
  )
  persist_agent(state_path, agent)
  send_heartbeat(base, node_id, token, inventory, agent)
  let timestamp_unix_ms = @async.now()
  let samples : Array[@contracts.TelemetrySample] = []
  let sensor_binary = @env.get_env_var("LUNANEXA_NVIDIA_SMI_BINARY").unwrap_or(
    "/usr/bin/nvidia-smi",
  )
  let mut sensors : @node_agent.AcceleratorSensorSnapshot? = None
  try
    @node_agent.collect_accelerator_sensors(
      sensor_binary,
      limits=telemetry_limits,
    )
  catch {
    _ => ()
  } noraise {
    sensor => sensors = Some(sensor)
  }
  match sensors {
    Some(sensor) => {
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_memory_total_mib",
        value: sensor.memory_total_mib,
        timestamp_unix_ms,
      })
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_memory_used_mib",
        value: sensor.memory_used_mib,
        timestamp_unix_ms,
      })
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_memory_free_mib",
        value: sensor.memory_total_mib - sensor.memory_used_mib,
        timestamp_unix_ms,
      })
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_healthy_count",
        value: sensor.accelerator_count.to_double(),
        timestamp_unix_ms,
      })
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_utilization_per_mille",
        value: sensor.utilization_per_mille,
        timestamp_unix_ms,
      })
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_temperature_celsius",
        value: sensor.maximum_temperature_celsius,
        timestamp_unix_ms,
      })
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_power_watts",
        value: sensor.power_watts,
        timestamp_unix_ms,
      })
    }
    None => {
      // Inventory values remain a conservative fallback when the host sensor
      // executable is unavailable. Utilization is never accepted from labels.
      let mut total_memory = 0
      let mut free_memory = 0
      let mut healthy_accelerators = 0
      for accelerator in inventory.accelerators {
        total_memory += accelerator.memory_total_mib
        free_memory += accelerator.memory_free_mib
        if accelerator.healthy {
          healthy_accelerators += 1
        }
      }
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_memory_total_mib",
        value: total_memory.to_double(),
        timestamp_unix_ms,
      })
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_memory_free_mib",
        value: free_memory.to_double(),
        timestamp_unix_ms,
      })
      samples.push({
        node_id,
        deployment_id: "",
        metric: "accelerator_healthy_count",
        value: healthy_accelerators.to_double(),
        timestamp_unix_ms,
      })
    }
  }
  for sample in samples {
    try {
      let (response, _) = @http.put(
        endpoint(base, "/v1/telemetry"),
        sample.to_json(),
        headers~,
      )
      if response.code != 202 {
        raise Failure::Failure("telemetry sample was rejected")
      }
    } catch {
      _ => ()
    }
  }
}

///|
async fn main {
  let global_settings = load_global_admin_settings()
  let base = environment("LUNANEXA_ENDPOINT")
  if !base.has_prefix("https://") &&
    !base.has_prefix("http://127.0.0.1:") &&
    !base.has_prefix("http://localhost:") {
    raise Failure::Failure(
      "node control endpoint must use HTTPS outside loopback",
    )
  }
  let node_id = environment("LUNANEXA_NODE_ID")
  let token = host_secret(
    "LUNANEXA_NODE_TOKEN", "LUNANEXA_NODE_TOKEN_PATH", "/etc/lunanexa/node-token",
  )
  let certificate_path = @env.get_env_var("LUNANEXA_NODE_CERTIFICATE_PATH").unwrap_or(
    "lunanexa-node-certificate.json",
  )
  let public_key_ref = environment("LUNANEXA_NODE_PUBLIC_KEY_REF")
  let inventory : @contracts.NodeInventory = @json.from_json(
    @json.parse(
      @fs.read_file(environment("LUNANEXA_NODE_INVENTORY_PATH")).text(),
    ),
  )
  if inventory.node_id != node_id {
    raise Failure::Failure("inventory belongs to a different node identity")
  }
  let state_path = @env.get_env_var("LUNANEXA_NODE_STATE_PATH").unwrap_or(
    "lunanexa-node-state.json",
  )
  let agent = load_agent(state_path, node_id)
  let verifier = @node_agent.SharedSecretAssignmentVerifier::new(
    host_secret(
      "LUNANEXA_ASSIGNMENT_SIGNING_SECRET", "LUNANEXA_ASSIGNMENT_SIGNING_SECRET_PATH",
      "/etc/lunanexa/assignment-verification-key",
    ),
  )
  let supervisor = @node_agent.OciRuntimeSupervisor::new(
    environment("LUNANEXA_CONTAINER_ENGINE"),
    environment("LUNANEXA_RUNTIME_NETWORK"),
    environment("LUNANEXA_CONTAINER_ENGINE_ENDPOINT"),
    pid_limit=global_settings.node_runtime.container_pid_limit,
  )
  let maximum_artifact_size_bytes = @env.get_env_var(
      "LUNANEXA_ARTIFACT_MAX_SIZE_BYTES",
    )
    .map(value => @string.parse_int64(value))
    .unwrap_or(1099511627776L)
  let materializer = @node_agent.ArtifactMaterializer::open(
    @env.get_env_var("LUNANEXA_MODEL_CACHE_PATH").unwrap_or(
      "/var/lib/lunanexa/models",
    ),
    environment("LUNANEXA_ARTIFACT_ENDPOINT"),
    host_secret(
      "LUNANEXA_ARTIFACT_CREDENTIAL", "LUNANEXA_ARTIFACT_CREDENTIAL_PATH", "/etc/lunanexa/artifact-credential",
    ),
    node_id~,
    maximum_artifact_size_bytes~,
    io_chunk_bytes=global_settings.node_runtime.artifact_io_chunk_bytes,
    signature_maximum_bytes=global_settings.node_runtime.signature_artifact_maximum_bytes,
    allow_http_loopback=@env.get_env_var("LUNANEXA_ALLOW_HTTP_LOOPBACK") ==
      Some("1"),
  )
  let artifact_verifier = @node_agent.CosignArtifactSignatureVerifier::new(
    environment("LUNANEXA_COSIGN_BINARY"),
    environment("LUNANEXA_COSIGN_PUBLIC_KEY_PATH"),
  )
  let lease_state_path = @env.get_env_var("LUNANEXA_LEASE_STATE_PATH").unwrap_or(
    "lunanexa-exclusive-lease-agent.json",
  )
  let lease_guard = load_lease_guard(lease_state_path, node_id)
  let lease_helper = @env.get_env_var("LUNANEXA_LEASE_HELPER").unwrap_or(
    "/usr/libexec/lunanexa-lease-helper",
  )
  let exclusive_leases_enabled = match
    @env.get_env_var("LUNANEXA_EXCLUSIVE_LEASES_ENABLED") {
    Some("1") => true
    None | Some("") | Some("0") => false
    Some(_) =>
      raise Failure::Failure(
        "LUNANEXA_EXCLUSIVE_LEASES_ENABLED must be exactly 0 or 1",
      )
  }
  while true {
    try {
      ensure_certificate(
        base,
        node_id,
        token,
        certificate_path,
        public_key_ref,
        global_settings.control_timing.node_certificate_renewal_lead_ms,
      )
      reconcile_once(
        base,
        node_id,
        token,
        inventory,
        agent,
        verifier,
        supervisor,
        materializer,
        artifact_verifier,
        state_path,
        lease_helper,
        exclusive_leases_enabled,
        lease_guard,
        lease_state_path,
        global_settings.control_timing.materialization_heartbeat_interval_ms,
        global_settings.control_timing.lease_receipt_stale_after_ms,
        global_settings.telemetry_safety,
      )
    } catch {
      _ => println("LunaNexa node reconciliation failed; retrying")
    }
    @async.sleep(global_settings.control_timing.node_reconcile_interval_ms)
  }
}
