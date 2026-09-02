///|
fn api_request() -> @contracts.WorkloadEnvelope {
  {
    version: @contracts.contract_version,
    idempotency_key: "api-idempotency-1",
    workload_id: "api-workload-1",
    tenant_ref: "opaque-tenant",
    credential_scope: "inference",
    capability: TextGenerate,
    model_selector: "text.default",
    payload: { "prompt": "hello through API" },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: @async.now() + 10000L,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: 10,
      max_output_units: 20,
      max_runtime_ms: 2000L,
      max_accelerator_memory_mib: 1000,
    },
    stream: false,
    output_format: "text",
    trace_token: "opaque-trace",
  }
}

///|
fn api_assignment() -> @contracts.DesiredAssignment {
  {
    assignment_id: "assignment-stop-1",
    deployment_id: "deployment-stop-1",
    node_id: "node-a",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model.text/v1",
      size_bytes: 1024L,
      signature_ref: "cosign:model",
    },
    runtime: {
      name: "text-runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "runtime-v1",
      architectures: ["nvidia-test"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 1000,
      cpu_millis: 1000,
      memory_mib: 2048,
    },
    devices: ["gpu-0"],
    network: {
      allow_controller: true,
      allow_artifact_store: true,
      allowed_egress: [],
    },
    health: {
      readiness_path: "/health",
      interval_ms: 1000,
      failure_threshold: 3,
      termination_grace_ms: 5000,
    },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    generation: 1L,
    lease_expires_unix_ms: @async.now() + 60000L,
    controller_epoch: 1L,
    signature: "signed",
  }
}

///|
async test "native HTTP API authenticates invokes persists and replays idempotently" {
  let directory = @fs.tmpdir(prefix="lunanexa-api-test-")
  let state_path = "\{directory}/control.json"
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let api_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let calls = [0]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever() <| ((_request, body, connection) => {
        calls[0] += 1
        assert_true(body.read_all().text().contains("api-workload-1"))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          "{\"output_text\":\"network result\",\"usage\":{\"input_tokens\":3,\"output_tokens\":2}}",
        )
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "upstream-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let durable = @store.FileStore::open(state_path)
    let registry = @registry.FileRegistry::open("\{directory}/registry.json")
    let enrollment = @node.FileEnrollmentService::open(
      "\{directory}/enrollment.json",
    )
    let service = @api.ApiService::with_services(
      durable, registry, enrollment, runtime, "operator-token", "inference-token",
      "node-token", "0.1.0",
    )
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      service.serve_on(api_server)
    }
    let (health_response, health_body) = @http.get(
      "http://\{api_server.addr}/health",
    )
    assert_eq(health_response.code, 200)
    assert_true(health_body.text().contains("LunaNexa"))
    let operator_headers = {
      "Authorization": "Bearer operator-token",
      "Content-Type": "application/json",
    }
    let (oversized_response, oversized_body) = @http.post(
      "http://\{api_server.addr}/v1/catalog/templates",
      "x".repeat(1048577),
      headers=operator_headers,
    )
    assert_eq(oversized_response.code, 413)
    assert_true(oversized_body.text().contains("PayloadTooLarge"))
    let invalid_utf8 : Bytes = [0xff, 0xfe, 0xfd]
    let (encoding_response, encoding_body) = @http.post(
      "http://\{api_server.addr}/v1/catalog/templates",
      invalid_utf8,
      headers=operator_headers,
    )
    assert_eq(encoding_response.code, 400)
    assert_true(encoding_body.text().contains("InvalidRequest"))
    let (unauthorized, _) = @http.post(
      "http://\{api_server.addr}/v1/workloads",
      api_request().to_json(),
    )
    assert_eq(unauthorized.code, 401)
    let headers = {
      "Authorization": "Bearer inference-token",
      "Content-Type": "application/json",
    }
    let (first_response, first_body) = @http.post(
      "http://\{api_server.addr}/v1/workloads",
      api_request().to_json(),
      headers~,
    )
    assert_eq(first_response.code, 200)
    let first : @contracts.WorkloadResponse = @json.from_json(
      @json.parse(first_body.text()),
    )
    assert_eq(first.workload_id, "api-workload-1")
    assert_eq(
      first.artifact_digest,
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
    assert_false(first_body.text().contains("upstream-secret"))
    let (second_response, second_body) = @http.post(
      "http://\{api_server.addr}/v1/workloads",
      api_request().to_json(),
      headers~,
    )
    assert_eq(second_response.code, 200)
    assert_eq(second_body.text(), first_body.text())
    assert_eq(calls[0], 1)
    let reopened = @store.FileStore::open(state_path)
    assert_eq(
      reopened.workload_result("api-workload-1").unwrap().audit_receipt,
      first.audit_receipt,
    )
    assert_eq(reopened.workload_result("api-workload-1").unwrap().output, None)
    assert_false(@fs.read_file(state_path).text().contains("network result"))
    assert_false(@fs.read_file(state_path).text().contains("hello through API"))
    assert_eq(reopened.audit_events().length(), 1)
    let token_secret = "one-use-bootstrap-secret-value"
    let token_body : Json = {
      "token_id": "bootstrap-1",
      "secret": token_secret,
      "expires_unix_ms": @async.now() + 60000L,
    }
    let (token_response, _) = @http.post(
      "http://\{api_server.addr}/v1/enrollment/tokens",
      token_body,
      headers=operator_headers,
    )
    assert_eq(token_response.code, 201)
    assert_false(
      @fs.read_file("\{directory}/enrollment.json")
      .text()
      .contains(token_secret),
    )
    let enrollment_body : Json = {
      "node_id": "node-1",
      "token_id": "bootstrap-1",
      "secret": token_secret,
      "node_auth_secret": "node-specific-token-value",
      "public_key_ref": "host-ref:node-1-key",
    }
    let (enroll_response, enroll_body) = @http.post(
      "http://\{api_server.addr}/v1/enrollment",
      enrollment_body,
    )
    assert_eq(enroll_response.code, 201)
    let certificate : @node.NodeCertificate = @json.from_json(
      @json.parse(enroll_body.text()),
    )
    assert_eq(certificate.node_id, "node-1")
    let unsigned_heartbeat = {
      ..schedulable_heartbeat(Active),
      node_id: "node-1",
      inventory: {
        ..schedulable_heartbeat(Active).inventory,
        node_id: "node-1",
      },
      signature: "",
    }
    let forged_headers = {
      "Authorization": "Node other-node-secret",
      "X-LunaNexa-Node-Id": "node-1",
      "Content-Type": "application/json",
    }
    let (forged_response, _) = @http.put(
      "http://\{api_server.addr}/v1/nodes/heartbeat",
      {
        ..unsigned_heartbeat,
        signature: @node.heartbeat_signature(
          unsigned_heartbeat, "other-node-secret",
        ),
      }.to_json(),
      headers=forged_headers,
    )
    assert_eq(forged_response.code, 401)
    let node_headers = {
      "Authorization": "Node node-specific-token-value",
      "X-LunaNexa-Node-Id": "node-1",
      "Content-Type": "application/json",
    }
    let rotation_body : Json = {
      "node_id": "node-1",
      "public_key_ref": "host-ref:node-1-key-rotated",
      "current_serial": certificate.serial,
    }
    let (forged_rotation, _) = @http.post(
      "http://\{api_server.addr}/v1/enrollment/rotate",
      rotation_body,
      headers=forged_headers,
    )
    assert_eq(forged_rotation.code, 401)
    let invalid_rotation_body : Json = {
      "node_id": "node-1",
      "public_key_ref": "host-ref:node-1\ninvalid",
      "current_serial": certificate.serial,
    }
    let (invalid_rotation, _) = @http.post(
      "http://\{api_server.addr}/v1/enrollment/rotate",
      invalid_rotation_body,
      headers=node_headers,
    )
    assert_eq(invalid_rotation.code, 400)
    let (rotation_response, rotation_response_body) = @http.post(
      "http://\{api_server.addr}/v1/enrollment/rotate",
      rotation_body,
      headers=node_headers,
    )
    assert_eq(rotation_response.code, 200)
    let rotated_certificate : @node.NodeCertificate = @json.from_json(
      @json.parse(rotation_response_body.text()),
    )
    assert_eq(rotated_certificate.serial, certificate.serial + 1L)
    let (replayed_rotation, replayed_rotation_body) = @http.post(
      "http://\{api_server.addr}/v1/enrollment/rotate",
      rotation_body,
      headers=node_headers,
    )
    assert_eq(replayed_rotation.code, 200)
    let replayed_certificate : @node.NodeCertificate = @json.from_json(
      @json.parse(replayed_rotation_body.text()),
    )
    assert_eq(replayed_certificate.serial, rotated_certificate.serial)
    let (heartbeat_response, _) = @http.put(
      "http://\{api_server.addr}/v1/nodes/heartbeat",
      {
        ..unsigned_heartbeat,
        signature: @node.heartbeat_signature(
          unsigned_heartbeat, "node-specific-token-value",
        ),
      }.to_json(),
      headers=node_headers,
    )
    assert_eq(heartbeat_response.code, 202)
    api_server.close()
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "unary invocation retries once before producing output" {
  let directory = @fs.tmpdir(prefix="lunanexa-retry-test-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let calls = [0]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever() <| ((_request, body, connection) => {
        ignore(body.read_all())
        calls[0] += 1
        if calls[0] == 1 {
          connection.send_response(503, "Unavailable")
          connection.write_string("temporarily unavailable")
        } else {
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write_string(
            "{\"output_text\":\"retried\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
          )
        }
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "upstream-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/control.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    let reply = service.handle(
      Post,
      "/v1/workloads",
      { "Authorization": "Bearer inference-token" },
      api_request().to_json().stringify(),
    )
    assert_eq(reply.status, 200)
    assert_eq(calls[0], 2)
    assert_true(reply.body.contains("retried"))
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "bounded retry does not repeat a non-retryable upstream rejection" {
  let directory = @fs.tmpdir(prefix="lunanexa-no-retry-test-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let calls = [0]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever() <| ((_request, body, connection) => {
        ignore(body.read_all())
        calls[0] += 1
        connection.send_response(400, "Bad Request")
        connection.write_string("invalid runtime request")
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "upstream-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/control.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    let reply = service.handle(
      Post,
      "/v1/workloads",
      { "Authorization": "Bearer inference-token" },
      { ..api_request(), idempotency_key: "no-retry-idem" }
      .to_json()
      .stringify(),
    )
    assert_eq(reply.status, 200)
    assert_eq(calls[0], 1)
    let failed : @contracts.WorkloadResponse = @json.from_json(
      @json.parse(reply.body),
    )
    assert_eq(failed.state, Failed)
    assert_eq(failed.error.unwrap().code, RuntimeUnavailable)
    assert_false(failed.retryable)
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "verification API rejects operator-authored verification claims" {
  let directory = @fs.tmpdir(prefix="lunanexa-verifier-api-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "unused",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::with_registry(
    @store.FileStore::open("\{directory}/control.json"),
    @registry.FileRegistry::open("\{directory}/registry.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  )
  let forged = service.handle(
    Post,
    "/v1/verifications",
    { "Authorization": "Bearer operator-token" },
    (
      #|{"digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","signature_verified":true,"provenance_verified":true,"verified_unix_ms":"1","verifier":"cosign-key:/pretend/key"}
    ),
  )
  assert_eq(forged.status, 400)
  let unavailable = service.handle(
    Post,
    "/v1/verifications",
    { "Authorization": "Bearer operator-token" },
    (
      #|{"kind":"image","subject":"registry.example/runtime","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","provenance_verified":true}
    ),
  )
  assert_eq(unavailable.status, 503)
  assert_true(unavailable.body.contains("VerifierUnavailable"))
  let scoped = service.with_role_tokens("audit-only", "monitoring-only")
  assert_eq(
    scoped.handle(
      Get,
      "/v1/audit",
      { "Authorization": "Bearer operator-token" },
      "",
    ).status,
    401,
  )
  assert_eq(
    scoped.handle(
      Get,
      "/v1/audit",
      { "Authorization": "Bearer audit-only" },
      "",
    ).status,
    200,
  )
  assert_eq(scoped.handle(Get, "/metrics", Map([]), "").status, 401)
  assert_eq(
    scoped.handle(
      Get,
      "/metrics",
      { "Authorization": "Bearer monitoring-only" },
      "",
    ).status,
    200,
  )
  let recovery = service.with_reconciliation_only(true)
  assert_eq(recovery.handle(Get, "/version", Map([]), "").status, 200)
  let mutation = recovery.handle(
    Post,
    "/v1/workloads",
    { "Authorization": "Bearer inference-token" },
    api_request().to_json().stringify(),
  )
  assert_eq(mutation.status, 503)
  assert_true(mutation.body.contains("ReconciliationOnly"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "controller signs validated desired assignments for nodes" {
  let directory = @fs.tmpdir(prefix="lunanexa-assignment-signer-")
  let store = @store.FileStore::open("\{directory}/control.json")
  let registry = @registry.FileRegistry::open("\{directory}/registry.json")
  configure_schedulable_model(registry)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "unused",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::with_registry(
    store, registry, runtime, "operator-token", "inference-token", "node-signing-secret",
    "0.1.0",
  )
  let unsigned = { ..api_assignment(), signature: "" }
  let reply = service.handle(
    Put,
    "/v1/assignments",
    { "Authorization": "Bearer operator-token" },
    unsigned.to_json().stringify(),
  )
  assert_eq(reply.status, 202)
  let stored = store.assignment(unsigned.assignment_id).unwrap()
  assert_eq(
    stored.signature,
    @node.assignment_signature(unsigned, "node-signing-secret"),
  )
  let pre_signed = service.handle(
    Put,
    "/v1/assignments",
    { "Authorization": "Bearer operator-token" },
    api_assignment().to_json().stringify(),
  )
  assert_eq(pre_signed.status, 400)
  let unsafe_identity = service.handle(
    Put,
    "/v1/assignments",
    { "Authorization": "Bearer operator-token" },
    { ..unsigned, assignment_id: "../runtime" }.to_json().stringify(),
  )
  assert_eq(unsafe_identity.status, 400)
  assert_eq(store.assignment("../runtime"), None)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "reconciliation-only recovery plan exposes missing and unreachable state" {
  let directory = @fs.tmpdir(prefix="lunanexa-recovery-plan-")
  let store = @store.FileStore::open("\{directory}/control.json")
  let assignment = api_assignment()
  store.put_assignment(assignment)
  store.put_heartbeat({
    ..schedulable_heartbeat(Active),
    running_deployments: [],
    timestamp_unix_ms: 1L,
  })
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "unused",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
    store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_reconciliation_only(true)
  let reply = service.handle(
    Get,
    "/v1/recovery/plan",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(reply.status, 200)
  let plan : @controller.RecoveryPlan = @json.from_json(@json.parse(reply.body))
  assert_true(
    plan.actions.any(action => action == StartMissing(assignment.assignment_id)),
  )
  assert_true(
    plan.actions.any(action => action == MarkNodeUnreachable("node-a")),
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "successor epoch rejects stale controller API mutations" {
  let directory = @fs.tmpdir(prefix="lunanexa-api-fence-")
  let path = "\{directory}/control.json"
  let stale_store = @store.FileStore::open(path)
  stale_store.fence_controller(2L)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "unused",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let stale_service = @api.ApiService::new(
    stale_store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  )
  let successor = @store.FileStore::open(path)
  successor.fence_controller(3L)
  let directive : @contracts.NodeDirective = {
    node_id: "node-a",
    desired_state: Cordoned,
    generation: 1L,
    issued_unix_ms: @async.now(),
    receipt: "stale-controller-receipt",
  }
  let reply = stale_service.handle(
    Put,
    "/v1/nodes/directive",
    { "Authorization": "Bearer operator-token" },
    directive.to_json().stringify(),
  )
  assert_eq(reply.status, 409)
  assert_true(reply.body.contains("StaleControllerEpoch"))
  assert_eq(stale_store.node_directive("node-a"), None)
  let inspected = @store.FileStore::open(path)
  assert_eq(inspected.controller_epoch(), 3L)
  assert_eq(inspected.node_directive("node-a"), None)
  assert_eq(inspected.audit_events().length(), 0)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "automation and Rabbita decode the same shared read contracts" {
  let directory = @fs.tmpdir(prefix="lunanexa-shared-read-contracts-")
  let store = @store.FileStore::open("\{directory}/control.json")
  let registry = @registry.FileRegistry::open("\{directory}/registry.json")
  let scheduler = @scheduler.FileScheduler::open(
    "\{directory}/scheduler.json",
    4,
  )
  let telemetry = @telemetry.FileTelemetry::open("\{directory}/telemetry.json")
  let enrollment = @node.FileEnrollmentService::open(
    "\{directory}/enrollment.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "unused",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::with_control_plane(
    store, registry, enrollment, scheduler, telemetry, runtime, "operator-token",
    "inference-token", "node-token", "0.1.0",
  )
  let headers = { "Authorization": "Bearer operator-token" }
  let registry_reply = service.handle(Get, "/v1/registry", headers, "")
  let registry_contract : @contracts.RegistryReadContract = @json.from_json(
    @json.parse(registry_reply.body),
  )
  assert_eq(registry_contract.models, [])
  assert_eq(registry_contract.runtimes, [])
  let scheduler_reply = service.handle(Get, "/v1/scheduler", headers, "")
  let scheduler_contract : @contracts.SchedulerReadContract = @json.from_json(
    @json.parse(scheduler_reply.body),
  )
  assert_eq(scheduler_contract.quotas, [])
  assert_eq(scheduler_contract.active, [])
  assert_eq(scheduler_contract.queued_count, Some(0))
  assert_eq(scheduler_contract.running_count, Some(0))
  let telemetry_reply = service.handle(Get, "/v1/telemetry", headers, "")
  let telemetry_contract : @contracts.TelemetryReadContract = @json.from_json(
    @json.parse(telemetry_reply.body),
  )
  assert_eq(telemetry_contract.benchmark_summaries, [])
  @fs.rmdir(directory, recursive=true)
}

///|
async test "cancellation aborts an active upstream invocation and persists receipt" {
  let directory = @fs.tmpdir(prefix="lunanexa-cancel-test-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let api_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever(allow_failure=true) <| ((
        _request,
        body,
        connection,
      ) => {
        ignore(body.read_all())
        @async.sleep(1000)
        connection.send_response(200, "OK")
        connection.write_string("{\"output_text\":\"too late\"}")
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "upstream-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let durable = @store.FileStore::open("\{directory}/control.json")
    let service = @api.ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      service.serve_on(api_server)
    }
    let headers = {
      "Authorization": "Bearer inference-token",
      "Content-Type": "application/json",
    }
    let invocation = group.spawn(allow_failure=true) <| () => {
      @http.post(
        "http://\{api_server.addr}/v1/workloads",
        api_request().to_json(),
        headers~,
      )
    }
    @async.sleep(50)
    let (cancel_response, _) = @http.post(
      "http://\{api_server.addr}/v1/workloads/api-workload-1/cancel",
      "",
      headers~,
    )
    assert_eq(cancel_response.code, 202)
    let (response, body) = invocation.wait()
    assert_eq(response.code, 200)
    let cancelled : @contracts.WorkloadResponse = @json.from_json(
      @json.parse(body.text()),
    )
    assert_eq(cancelled.state, Cancelled)
    assert_eq(
      durable.workload_result("api-workload-1").unwrap().state,
      Cancelled,
    )
    api_server.close()
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "runtime ceiling returns a durable typed deadline failure" {
  let directory = @fs.tmpdir(prefix="lunanexa-runtime-deadline-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever(allow_failure=true) <| ((
        _request,
        body,
        connection,
      ) => {
        ignore(body.read_all())
        @async.sleep(200)
        connection.send_response(200, "OK")
        connection.write_string("{\"output_text\":\"too late\"}")
        connection.end_response()
      })
    }
    let store = @store.FileStore::open("\{directory}/control.json")
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "runtime-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let service = @api.ApiService::new(
      store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    let request = {
      ..api_request(),
      workload_id: "deadline-workload",
      idempotency_key: "deadline-workload",
      deadline_unix_ms: @async.now() + 1000L,
      resource_ceiling: {
        ..api_request().resource_ceiling,
        max_runtime_ms: 20L,
      },
    }
    let reply = service.handle(
      Post,
      "/v1/workloads",
      { "Authorization": "Bearer inference-token" },
      request.to_json().stringify(),
    )
    assert_eq(reply.status, 200)
    let response : @contracts.WorkloadResponse = @json.from_json(
      @json.parse(reply.body),
    )
    assert_eq(response.state, Failed)
    assert_eq(response.error.unwrap().code, DeadlineExceeded)
    assert_false(response.retryable)
    assert_eq(store.workload_result("deadline-workload").unwrap().state, Failed)
    assert_eq(store.audit_events().last().unwrap().action, "workload.deadline")
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "streaming proxy emits bounded canonical chunks before completion" {
  let directory = @fs.tmpdir(prefix="lunanexa-stream-test-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let api_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever(allow_failure=true) <| ((
        _request,
        body,
        connection,
      ) => {
        assert_true(body.read_all().text().contains("\"stream\":true"))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write_string("data: {\"delta\":\"first\"}\n\n")
        connection.flush()
        @async.sleep(100)
        connection.write_string(
          "data: {\"delta\":\"second\",\"usage\":{\"input_tokens\":2,\"output_tokens\":2}}\n\n",
        )
        connection.write_string("data: [DONE]\n\n")
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "upstream-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let durable = @store.FileStore::open("\{directory}/control.json")
    let service = @api.ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      service.serve_on(api_server)
    }
    let client = @http.post_stream(
      "http://\{api_server.addr}/v1/workloads:stream",
      headers={
        "Authorization": "Bearer inference-token",
        "Content-Type": "application/json",
      },
    )
    defer client.close()
    client.write({ ..api_request(), idempotency_key: "stream-idem" }.to_json())
    let response = client.end_request()
    assert_eq(response.code, 200)
    let first = client.read_until("\n\n").unwrap()
    assert_true(first.contains("\"kind\":\"Chunk\""))
    assert_true(first.contains("first"))
    let rest = client.read_all().text()
    assert_true(rest.contains("second"))
    assert_true(rest.contains("\"kind\":\"Completed\""))
    assert_false(
      @fs.read_file("\{directory}/control.json")
      .text()
      .contains("\"text_delta\":\"first\""),
    )
    api_server.close()
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async fn configure_schedulable_model(registry : @registry.FileRegistry) -> Unit {
  let runtime_spec : @contracts.RuntimeSpec = {
    name: "text-runtime",
    image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    version: "runtime-v1",
    architectures: ["nvidia-test"],
    capabilities: [TextGenerate],
    supports_batching: false,
    supports_multi_node: false,
  }
  registry.register_runtime(runtime_spec)
  registry.register_model({
    model_id: "model.text",
    version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model.text/v1",
      size_bytes: 1024L,
      signature_ref: "cosign:model",
    },
    license_id: "license-1",
    provenance: "build:verified",
    compatible_architectures: ["nvidia-test"],
    minimum_memory_mib: 1000,
    state: Candidate,
  })
  registry.record_license({
    license_id: "license-1",
    model_id: "model.text",
    status: Accepted,
    accepted_by: "operator",
    evidence_ref: "evidence:license",
    expires_unix_ms: None,
  })
  registry.record_verification({
    digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    signature_verified: true,
    provenance_verified: true,
    verified_unix_ms: @async.now(),
    verifier: "test-verifier",
  })
  registry.record_verification({
    digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    signature_verified: true,
    provenance_verified: true,
    verified_unix_ms: @async.now(),
    verifier: "test-verifier",
  })
  registry.record_evaluation({
    evaluation_id: "evaluation-1",
    model_id: "model.text",
    model_version: "v1",
    suite_version: "suite-v1",
    passed: true,
    score: 1.0,
    benchmark: {
      profile_id: "benchmark-1",
      model_id: "model.text",
      model_version: "v1",
      runtime_version: "runtime-v1",
      hardware_profile: "nvidia-test",
      workload_profile: "short-text",
      p50_ms: 1.0,
      p95_ms: 2.0,
      p99_ms: 3.0,
      throughput_per_second: 10.0,
      peak_memory_mib: 1000,
    },
    evidence_ref: "evidence:evaluation",
  })
  ignore(registry.approve("model.text", "v1", @async.now()))
  ignore(
    registry.promote(
      "text.default",
      "model.text",
      "v1",
      Canary,
      "operator",
      @async.now(),
    ),
  )
}

///|
fn schedulable_heartbeat(
  state : @contracts.NodeState,
  node_id? : String = "node-a",
) -> @contracts.NodeHeartbeat {
  {
    node_id,
    state,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id,
      agent_version: "0.1.0",
      os_release: "test",
      runtime_names: ["text-runtime"],
      accelerators: [
        {
          device_id: "gpu-0",
          architecture: "nvidia-test",
          memory_total_mib: 16000,
          memory_free_mib: 12000,
          healthy: true,
        },
      ],
      labels: {
        "lunanexa.models": "model.text@v1",
        "lunanexa.warm-models": "model.text@v1",
        "lunanexa.data-classes": "Confidential",
      },
      taints: [],
    },
    running_deployments: ["deployment-1"],
    timestamp_unix_ms: @async.now(),
    signature: "",
  }
}

///|
async test "placement treats accelerator memory as a ceiling instead of node demand" {
  let directory = @fs.tmpdir(prefix="lunanexa-scheduled-api-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let calls = [0]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever() <| ((runtime_request, body, connection) => {
        calls[0] += 1
        assert_eq(
          runtime_request.headers.get("x-lunanexa-target-node"),
          Some("node-a"),
        )
        ignore(body.read_all())
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          "{\"output_text\":\"scheduled\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
        )
        connection.end_response()
      })
    }
    let store = @store.FileStore::open("\{directory}/control.json")
    let registry = @registry.FileRegistry::open("\{directory}/registry.json")
    configure_schedulable_model(registry)
    let scheduler = @scheduler.FileScheduler::open(
      "\{directory}/scheduler.json",
      4,
    )
    let telemetry = @telemetry.FileTelemetry::open(
      "\{directory}/telemetry.json",
    )
    scheduler.set_quota({
      tenant_ref: "opaque-tenant",
      max_inflight: 1,
      max_accelerator_ms: 10000L,
      window_ms: 60000L,
    })
    let enrollment = @node.FileEnrollmentService::open(
      "\{directory}/enrollment.json",
    )
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "runtime-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let service = @api.ApiService::with_control_plane(
      store, registry, enrollment, scheduler, telemetry, runtime, "operator-token",
      "inference-token", "node-token", "0.1.0",
    )
    let headers = {
      "Authorization": "Bearer inference-token",
      "Content-Type": "application/json",
    }
    store.put_heartbeat(schedulable_heartbeat(Draining))
    let rejected = service.handle(
      Post,
      "/v1/workloads",
      headers,
      api_request().to_json().stringify(),
    )
    assert_eq(rejected.status, 409)
    assert_true(rejected.body.contains("NoPlacement"))
    assert_eq(calls[0], 0)
    store.put_heartbeat(schedulable_heartbeat(Active))
    let below_model_ceiling = {
      ..api_request(),
      resource_ceiling: {
        ..api_request().resource_ceiling,
        max_accelerator_memory_mib: 999,
      },
    }
    let model_exceeds_ceiling = service.handle(
      Post,
      "/v1/workloads",
      headers,
      below_model_ceiling.to_json().stringify(),
    )
    assert_eq(model_exceeds_ceiling.status, 409)
    assert_true(
      model_exceeds_ceiling.body.contains(
        "model exceeds the request accelerator-memory ceiling",
      ),
    )
    assert_eq(calls[0], 0)
    let policy_maximum_ceiling = {
      ..api_request(),
      resource_ceiling: {
        ..api_request().resource_ceiling,
        max_accelerator_memory_mib: 1048576,
      },
    }
    let accepted = service.handle(
      Post,
      "/v1/workloads",
      headers,
      policy_maximum_ceiling.to_json().stringify(),
    )
    assert_eq(accepted.status, 200)
    assert_eq(calls[0], 1)
    let snapshot = scheduler.snapshot()
    assert_eq(snapshot.active.length(), 0)
    assert_eq(snapshot.decisions.length(), 2)
    assert_eq(snapshot.decisions[1].selected_node_id, Some("node-a"))
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "admitted work waits in a bounded runtime queue and reports queue time" {
  let directory = @fs.tmpdir(prefix="lunanexa-runtime-queue-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let running = [0]
  let peak_running = [0]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever() <| ((_request, body, connection) => {
        ignore(body.read_all())
        running[0] += 1
        peak_running[0] = peak_running[0].max(running[0])
        @async.sleep(100)
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          "{\"output_text\":\"queued\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
        )
        connection.end_response()
        running[0] -= 1
      })
    }
    let store = @store.FileStore::open("\{directory}/control.json")
    let registry = @registry.FileRegistry::open("\{directory}/registry.json")
    configure_schedulable_model(registry)
    let scheduler = @scheduler.FileScheduler::open(
      "\{directory}/scheduler.json",
      4,
    )
    scheduler.set_quota({
      tenant_ref: "opaque-tenant",
      max_inflight: 2,
      max_accelerator_ms: 10000L,
      window_ms: 60000L,
    })
    let telemetry = @telemetry.FileTelemetry::open(
      "\{directory}/telemetry.json",
    )
    let enrollment = @node.FileEnrollmentService::open(
      "\{directory}/enrollment.json",
    )
    store.put_heartbeat(schedulable_heartbeat(Active))
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "runtime-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let service = @api.ApiService::with_control_plane(
      store, registry, enrollment, scheduler, telemetry, runtime, "operator-token",
      "inference-token", "node-token", "0.1.0",
    ).with_runtime_concurrency(1)
    let headers = {
      "Authorization": "Bearer inference-token",
      "Content-Type": "application/json",
    }
    let first = group.spawn(() => {
      service.handle(
        Post,
        "/v1/workloads",
        headers,
        {
          ..api_request(),
          workload_id: "queued-1",
          idempotency_key: "queued-1",
        }
        .to_json()
        .stringify(),
      )
    })
    let second = group.spawn(() => {
      service.handle(
        Post,
        "/v1/workloads",
        headers,
        {
          ..api_request(),
          workload_id: "queued-2",
          idempotency_key: "queued-2",
        }
        .to_json()
        .stringify(),
      )
    })
    @async.sleep(25)
    let queued_snapshot = scheduler.snapshot()
    assert_eq(queued_snapshot.running_count, Some(1))
    assert_eq(queued_snapshot.queued_count, Some(1))
    let duplicate = service.handle(
      Post,
      "/v1/workloads",
      headers,
      { ..api_request(), workload_id: "queued-1", idempotency_key: "queued-1" }
      .to_json()
      .stringify(),
    )
    assert_eq(duplicate.status, 409)
    assert_true(duplicate.body.contains("WorkloadAlreadyActive"))
    let observed_states : Array[@contracts.WorkloadState] = []
    for workload_id in ["queued-1", "queued-2"] {
      let status = service.handle(
        Get,
        "/v1/workloads/\{workload_id}",
        headers,
        "",
      )
      assert_eq(status.status, 200)
      let observed : @contracts.WorkloadResponse = @json.from_json(
        @json.parse(status.body),
      )
      observed_states.push(observed.state)
    }
    assert_true(observed_states.any(state => state == Running))
    assert_true(observed_states.any(state => state == Queued))
    let responses = [first.wait(), second.wait()]
    let decoded : Array[@contracts.WorkloadResponse] = []
    for response in responses {
      assert_eq(response.status, 200)
      decoded.push(@json.from_json(@json.parse(response.body)))
    }
    assert_eq(peak_running[0], 1)
    assert_true(decoded.any(response => response.usage.queue_ms >= 50L))
    assert_true(
      decoded.all(response => {
        response.timing.accepted_unix_ms <= response.timing.started_unix_ms &&
        response.timing.started_unix_ms <= response.timing.completed_unix_ms &&
        response.usage.accelerator_ms ==
        response.timing.completed_unix_ms - response.timing.started_unix_ms
      }),
    )
    assert_eq(scheduler.snapshot().active.length(), 0)
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "bounded pre-output retry fails over to the next deterministic node" {
  let directory = @fs.tmpdir(prefix="lunanexa-failover-api-")
  let primary_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let alternate_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let routed_nodes : Array[String] = []
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      primary_server.run_forever() <| ((runtime_request, body, connection) => {
        ignore(body.read_all())
        routed_nodes.push(
          runtime_request.headers
          .get("x-lunanexa-target-node")
          .unwrap_or("missing"),
        )
        connection.send_response(503, "Unavailable")
        connection.write_string("primary unavailable")
        connection.end_response()
      })
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      alternate_server.run_forever() <| ((runtime_request, body, connection) => {
        ignore(body.read_all())
        routed_nodes.push(
          runtime_request.headers
          .get("x-lunanexa-target-node")
          .unwrap_or("missing"),
        )
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          "{\"output_text\":\"failed over\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
        )
        connection.end_response()
      })
    }
    let store = @store.FileStore::open("\{directory}/control.json")
    let registry = @registry.FileRegistry::open("\{directory}/registry.json")
    configure_schedulable_model(registry)
    let scheduler = @scheduler.FileScheduler::open(
      "\{directory}/scheduler.json",
      4,
    )
    scheduler.set_quota({
      tenant_ref: "opaque-tenant",
      max_inflight: 2,
      max_accelerator_ms: 10000L,
      window_ms: 60000L,
    })
    let telemetry = @telemetry.FileTelemetry::open(
      "\{directory}/telemetry.json",
    )
    let enrollment = @node.FileEnrollmentService::open(
      "\{directory}/enrollment.json",
    )
    store.put_assignment({
      ..api_assignment(),
      assignment_id: "assignment-a",
      deployment_id: "deployment-a",
      node_id: "node-a",
    })
    store.put_assignment({
      ..api_assignment(),
      assignment_id: "assignment-b",
      deployment_id: "deployment-b",
      node_id: "node-b",
    })
    store.put_heartbeat({
      ..schedulable_heartbeat(Active, node_id="node-a"),
      running_deployments: ["deployment-a"],
    })
    store.put_heartbeat({
      ..schedulable_heartbeat(Active, node_id="node-b"),
      running_deployments: ["deployment-b"],
    })
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{primary_server.addr}/v1/responses",
      "runtime-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    ).with_node_endpoints([
      {
        node_id: "node-a",
        endpoint: "http://\{primary_server.addr}/v1/responses",
      },
      {
        node_id: "node-b",
        endpoint: "http://\{alternate_server.addr}/v1/responses",
      },
    ])
    let service = @api.ApiService::with_control_plane(
      store, registry, enrollment, scheduler, telemetry, runtime, "operator-token",
      "inference-token", "node-token", "0.1.0",
    )
    let response = service.handle(
      Post,
      "/v1/workloads",
      {
        "Authorization": "Bearer inference-token",
        "Content-Type": "application/json",
      },
      { ..api_request(), idempotency_key: "failover-idem" }
      .to_json()
      .stringify(),
    )
    assert_eq(response.status, 200)
    assert_true(response.body.contains("failed over"))
    assert_eq(routed_nodes, ["node-a", "node-b"])
    let decision = scheduler.snapshot().decisions.last().unwrap()
    assert_eq([ for candidate in decision.candidates => candidate.node_id ], [
      "node-a", "node-b",
    ])
    primary_server.close()
    alternate_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "streaming retry fails over before emitting the first event" {
  let directory = @fs.tmpdir(prefix="lunanexa-stream-failover-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let api_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let routed_nodes : Array[String] = []
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever() <| ((runtime_request, body, connection) => {
        ignore(body.read_all())
        routed_nodes.push(
          runtime_request.headers
          .get("x-lunanexa-target-node")
          .unwrap_or("missing"),
        )
        if routed_nodes.length() == 1 {
          connection.send_response(503, "Unavailable")
          connection.write_string("primary unavailable")
        } else {
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write_string(
            "data: {\"delta\":\"alternate chunk\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}\n\n",
          )
          connection.write_string("data: [DONE]\n\n")
        }
        connection.end_response()
      })
    }
    let store = @store.FileStore::open("\{directory}/control.json")
    let registry = @registry.FileRegistry::open("\{directory}/registry.json")
    configure_schedulable_model(registry)
    let scheduler = @scheduler.FileScheduler::open(
      "\{directory}/scheduler.json",
      4,
    )
    scheduler.set_quota({
      tenant_ref: "opaque-tenant",
      max_inflight: 2,
      max_accelerator_ms: 10000L,
      window_ms: 60000L,
    })
    let telemetry = @telemetry.FileTelemetry::open(
      "\{directory}/telemetry.json",
    )
    let enrollment = @node.FileEnrollmentService::open(
      "\{directory}/enrollment.json",
    )
    store.put_heartbeat(schedulable_heartbeat(Active, node_id="node-a"))
    store.put_heartbeat(schedulable_heartbeat(Active, node_id="node-b"))
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "runtime-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let service = @api.ApiService::with_control_plane(
      store, registry, enrollment, scheduler, telemetry, runtime, "operator-token",
      "inference-token", "node-token", "0.1.0",
    )
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      service.serve_on(api_server)
    }
    let client = @http.post_stream(
      "http://\{api_server.addr}/v1/workloads:stream",
      headers={
        "Authorization": "Bearer inference-token",
        "Content-Type": "application/json",
      },
    )
    defer client.close()
    client.write(
      { ..api_request(), idempotency_key: "stream-failover-idem" }.to_json(),
    )
    let response = client.end_request()
    assert_eq(response.code, 200)
    let events = client.read_all().text()
    assert_true(events.contains("alternate chunk"))
    assert_true(events.contains("\"sequence\":1"))
    assert_true(events.contains("\"kind\":\"Chunk\""))
    assert_true(events.contains("\"kind\":\"Completed\""))
    assert_false(events.contains("primary unavailable"))
    assert_eq(routed_nodes, ["node-a", "node-b"])
    api_server.close()
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "concurrent operator mutations retain a contiguous durable audit chain" {
  let directory = @fs.tmpdir(prefix="lunanexa-audit-concurrency-")
  let store = @store.FileStore::open("\{directory}/control.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
    store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  )
  let headers = {
    "Authorization": "Bearer operator-token",
    "Content-Type": "application/json",
  }
  @async.with_task_group <| group => {
    let tasks = [
      for index = 0; index < 20; index = index + 1 => {
        group.spawn(() => {
          let directive : @contracts.NodeDirective = {
            node_id: "node-\{index}",
            desired_state: Cordoned,
            generation: 1L,
            issued_unix_ms: @async.now(),
            receipt: "concurrent-\{index}",
          }
          service.handle(
            Put,
            "/v1/nodes/directive",
            headers,
            directive.to_json().stringify(),
          ).status
        })
      }
    ]
    for task in tasks {
      assert_eq(task.wait(), 202)
    }
  }
  let events = store.audit_events()
  assert_eq(events.length(), 20)
  assert_true(@store.validate_audit_chain(events))
  let restored = @store.FileStore::open("\{directory}/control.json")
  assert_true(@store.validate_audit_chain(restored.audit_events()))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "node heartbeat requires a canonical message authentication code" {
  let directory = @fs.tmpdir(prefix="lunanexa-heartbeat-auth-")
  let store = @store.FileStore::open("\{directory}/control.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
    store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  )
  let unsigned = { ..schedulable_heartbeat(Active), signature: "" }
  let headers = {
    "Authorization": "Node node-token",
    "X-LunaNexa-Node-Id": "node-a",
    "Content-Type": "application/json",
  }
  let forged = service.handle(
    Put,
    "/v1/nodes/heartbeat",
    headers,
    { ..unsigned, signature: "present-but-forged" }.to_json().stringify(),
  )
  assert_eq(forged.status, 401)
  assert_eq(store.heartbeats().length(), 0)
  let signed = {
    ..unsigned,
    signature: @node.heartbeat_signature(unsigned, "node-token"),
  }
  let accepted = service.handle(
    Put,
    "/v1/nodes/heartbeat",
    headers,
    signed.to_json().stringify(),
  )
  assert_eq(accepted.status, 202)
  assert_eq(store.heartbeats().length(), 1)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "operator stop removes desired assignment with durable audit evidence" {
  let directory = @fs.tmpdir(prefix="lunanexa-assignment-stop-")
  let store = @store.FileStore::open("\{directory}/control.json")
  store.put_assignment(api_assignment())
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
    store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  )
  let stopped = service.handle(
    Post,
    "/v1/assignments/assignment-stop-1/stop",
    {
      "Authorization": "Bearer operator-token",
      "Content-Type": "application/json",
    },
    "",
  )
  assert_eq(stopped.status, 202)
  assert_eq(store.assignment("assignment-stop-1"), None)
  assert_true(@store.validate_audit_chain(store.audit_events()))
  let restored = @store.FileStore::open("\{directory}/control.json")
  assert_eq(restored.assignment("assignment-stop-1"), None)
  assert_eq(restored.audit_events()[0].action, "assignment.stop")
  @fs.rmdir(directory, recursive=true)
}

///|
async test "settings views preserve admin and enterprise authority boundaries" {
  let directory = @fs.tmpdir(prefix="lunanexa-settings-view-")
  let store = @store.FileStore::open("\{directory}/control.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let defaults = @settings.default_global_admin_settings()
  let configured = { ..defaults, generation: 7L }
  let service = @api.ApiService::new(
    store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_global_admin_settings(configured)
  let denied = service.handle(Get, "/v1/settings/effective", Map([]), "")
  assert_eq(denied.status, 401)
  let enterprise = service.handle(
    Get,
    "/v1/settings/effective",
    { "Authorization": "Bearer inference-token" },
    "",
  )
  assert_eq(enterprise.status, 200)
  let public_view : @settings.PublicSettingsView = @json.from_json(
    @json.parse(enterprise.body),
  )
  assert_eq(public_view.global_generation, 7L)
  assert_false(enterprise.body.contains("telemetry_safety"))
  let admin_denied = service.handle(
    Get,
    "/v1/settings/admin",
    { "Authorization": "Bearer inference-token" },
    "",
  )
  assert_eq(admin_denied.status, 401)
  let admin = service.handle(
    Get,
    "/v1/settings/admin",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(admin.status, 200)
  assert_true(admin.body.contains("telemetry_safety"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "enterprise workload cannot override administrator request budget" {
  let directory = @fs.tmpdir(prefix="lunanexa-settings-budget-")
  let store = @store.FileStore::open("\{directory}/control.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let defaults = @settings.default_global_admin_settings()
  let configured = {
    ..defaults,
    request_budgets: {
      ..defaults.request_budgets,
      openai_default_output_units: 8,
      openai_max_output_units: 8,
    },
  }
  let service = @api.ApiService::new(
    store, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_global_admin_settings(configured)
  let rejected = service.handle(
    Post,
    "/v1/workloads",
    {
      "Authorization": "Bearer inference-token",
      "Content-Type": "application/json",
    },
    api_request().to_json().stringify(),
  )
  assert_eq(rejected.status, 400)
  assert_true(rejected.body.contains("RequestBudgetExceeded"))
  @fs.rmdir(directory, recursive=true)
}
