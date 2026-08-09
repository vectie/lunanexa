///|
fn response() -> @contracts.WorkloadResponse {
  {
    version: @contracts.contract_version,
    workload_id: "workload-1",
    state: Succeeded,
    output: Some({ "text": "done" }),
    error: None,
    usage: { input_units: 1, output_units: 1, accelerator_ms: 2L, queue_ms: 0L },
    artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    runtime_version: "runtime-1",
    timing: {
      accepted_unix_ms: 1L,
      started_unix_ms: 1L,
      first_output_unix_ms: 2L,
      completed_unix_ms: 3L,
    },
    retryable: false,
    audit_receipt: "receipt-1",
  }
}

///|
fn request() -> @contracts.WorkloadEnvelope {
  {
    version: @contracts.contract_version,
    idempotency_key: "idem-1",
    workload_id: "workload-1",
    tenant_ref: "opaque-tenant",
    credential_scope: "inference",
    capability: TextGenerate,
    model_selector: "text.default",
    payload: { "input": "hello" },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: 1000L,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: 10,
      max_output_units: 10,
      max_runtime_ms: 100L,
      max_accelerator_memory_mib: 1000,
    },
    stream: true,
    output_format: "text",
    trace_token: "opaque-trace",
  }
}

///|
test "HTTP subject assertions accept only canonical loopback origins" {
  for
    endpoint in [
      "http://localhost", "http://localhost:8080/", "http://127.0.0.1:1", "http://[::1]:65535",
    ] {
    assert_true(@client.canonical_http_loopback_endpoint(endpoint))
  }
  for
    endpoint in [
      "https://localhost:8080", "http://LOCALHOST:8080", "http://localhost:08080",
      "http://localhost:0", "http://localhost:65536", "http://localhost:8080/path",
      "http://localhost:8080?subject=x", "http://localhost:8080#fragment", "http://localhost@evil.example:8080",
      "http://127.0.0.1.example:8080", "http://[::1]@evil.example:8080",
    ] {
    assert_false(@client.canonical_http_loopback_endpoint(endpoint))
  }
}

///|
async test "published client covers discovery invocation usage cancellation and health" {
  let transport = @client.FixtureTransport::new(response(), [
    {
      capability: TextGenerate,
      selectors: ["text.default"],
      streaming: true,
      cancellation: true,
      healthy: true,
    },
  ])
  let client = @client.Client::new(
    {
      endpoint: "https://lunanexa.invalid",
      inference_credential_ref: "secret-ref:inference",
      timeout_ms: 1000L,
    },
    transport,
  )
  assert_true(client.healthy())
  assert_eq(client.discover().length(), 1)
  let result = client.invoke(request())
  assert_eq(result.usage.accelerator_ms, 2L)
  assert_eq(result.audit_receipt, "receipt-1")
  assert_true(client.cancel("workload-1"))
  assert_eq(transport.cancelled_workload(), Some("workload-1"))
  try client.cancel("../audit") catch {
    @client.ClientError::ClientError(code~, message=_, retryable~) => {
      assert_eq(code, Contract)
      assert_false(retryable)
    }
  } noraise {
    _ => fail("unsafe cancellation path identifier was accepted")
  }
  assert_eq(transport.cancelled_workload(), Some("workload-1"))
  let events : Array[@contracts.WorkloadStreamEvent] = []
  client.stream(request(), event => events.push(event))
  assert_eq(events.length(), 2)
  assert_eq(events[0].kind, Chunk)
  assert_eq(events[1].kind, Completed)
}

///|
async test "HTTP client crosses the native API and normalized stream boundary" {
  let directory = @fs.tmpdir(prefix="lunanexa-client-test-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let api_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever(allow_failure=true) <| ((
        _request,
        body,
        connection,
      ) => {
        let text = body.read_all().text()
        if text.contains("\"stream\":true") {
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write_string("data: {\"delta\":\"network chunk\"}\n\n")
          connection.write_string("data: [DONE]\n\n")
        } else {
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write_string(
            "{\"output_text\":\"network result\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2}}",
          )
        }
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "runtime-token",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      service.serve_on(api_server)
    }
    let provider = @client.Client::new(
      {
        endpoint: "http://\{api_server.addr}",
        inference_credential_ref: "test-ref",
        timeout_ms: 2000L,
      },
      @client.HttpTransport::new("inference-token"),
    )
    assert_true(provider.healthy())
    assert_eq(provider.discover().length(), 1)
    let invoked = provider.invoke({
      ..request(),
      idempotency_key: "http-invoke",
      workload_id: "http-invoke",
      deadline_unix_ms: @async.now() + 2000L,
    })
    assert_eq(invoked.usage.output_units, 2)
    let stream_events : Array[@contracts.WorkloadStreamEvent] = []
    provider.stream(
      {
        ..request(),
        idempotency_key: "http-stream",
        workload_id: "http-stream",
        deadline_unix_ms: @async.now() + 2000L,
      },
      event => stream_events.push(event),
    )
    assert_eq(stream_events.length(), 2)
    assert_eq(stream_events[0].kind, Chunk)
    assert_eq(stream_events[1].kind, Completed)
    api_server.close()
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "HTTP client rejects a stream without a canonical terminal event" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((_request, body, connection) => {
        ignore(body.read_all())
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        let event : @contracts.WorkloadStreamEvent = {
          workload_id: "workload-1",
          sequence: 1,
          kind: Chunk,
          output: Some({ "text_delta": "partial" }),
          response: None,
        }
        connection.write_string("data: \{event.to_json().stringify()}\n\n")
        connection.end_response()
      })
    }
    let provider = @client.Client::new(
      {
        endpoint: "http://\{server.addr}",
        inference_credential_ref: "test-ref",
        timeout_ms: 2000L,
      },
      @client.HttpTransport::new("inference-token"),
    )
    try provider.stream(request(), _ => ()) catch {
      @client.ClientError::ClientError(code~, message~, retryable~) => {
        assert_eq(code, Contract)
        assert_true(message.contains("terminal event"))
        assert_false(retryable)
      }
    } noraise {
      _ => fail("truncated provider stream was accepted")
    }
    server.close()
  }
}

///|
test "HTTP transport rejects an unsafe asserted workspace subject" {
  try
    @client.HttpTransport::new("inference-token").with_subject_ref("../admin")
  catch {
    @client.ClientError::ClientError(code~, message~, retryable~) => {
      assert_eq(code, Contract)
      assert_true(message.contains("subject"))
      assert_false(retryable)
    }
  } noraise {
    _ => fail("unsafe workspace subject was accepted")
  }
}

///|
async test "HTTP transport sends the workspace subject on invoke and cancel" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let received : Array[(String, String?)] = []
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, body, connection) => {
        ignore(body.read_all())
        received.push((request.path, request.headers.get("x-lunanexa-subject")))
        if request.path == "/v1/workloads" {
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write_string(response().to_json().stringify())
        } else if request.path == "/v1/workloads/subject-cancel/cancel" {
          connection.send_response(202, "Accepted", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write_string("{\"accepted\":true}")
        } else {
          connection.send_response(404, "Not Found")
        }
        connection.end_response()
      })
    }
    let transport = @client.HttpTransport::new("inference-token").with_subject_ref(
      "subject:opaque-01",
    )
    let provider = @client.Client::new(
      {
        endpoint: "http://\{server.addr}/",
        inference_credential_ref: "test-ref",
        timeout_ms: 2000L,
      },
      transport,
    )
    ignore(
      provider.invoke({
        ..request(),
        idempotency_key: "subject-invoke",
        workload_id: "subject-invoke",
        deadline_unix_ms: @async.now() + 2000L,
      }),
    )
    assert_true(provider.cancel("subject-cancel"))
    assert_eq(received.length(), 2)
    assert_eq(received[0], ("/v1/workloads", Some("subject:opaque-01")))
    assert_eq(
      received[1],
      ("/v1/workloads/subject-cancel/cancel", Some("subject:opaque-01")),
    )
    server.close()
  }
}
