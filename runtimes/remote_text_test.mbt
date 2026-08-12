///|
fn remote_request() -> @contracts.WorkloadEnvelope {
  {
    version: @contracts.contract_version,
    idempotency_key: "remote-idem-1",
    workload_id: "remote-workload-1",
    tenant_ref: "opaque-tenant",
    credential_scope: "inference",
    capability: TextGenerate,
    model_selector: "text.default",
    payload: { "prompt": "hello" },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: 10000L,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: 10,
      max_output_units: 20,
      max_runtime_ms: 1000L,
      max_accelerator_memory_mib: 1000,
    },
    stream: false,
    output_format: "text",
    trace_token: "opaque-trace",
  }
}

///|
test "runtime routing configuration rejects ambiguous or credential-bearing endpoints" {
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses", "runtime-credential", "runtime-v1", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let cases : Array[Array[@runtimes.NodeRuntimeEndpoint]] = [
    [
      { node_id: "node-a", endpoint: "https://one.invalid/v1/responses" },
      { node_id: "node-a", endpoint: "https://two.invalid/v1/responses" },
    ],
    [
      {
        node_id: "node-a",
        endpoint: "https://authority@runtime.invalid/v1/responses",
      },
    ],
    [{ node_id: "../node-a", endpoint: "https://runtime.invalid" }],
  ]
  for entries in cases {
    try runtime.with_node_endpoints(entries) catch {
      InvalidNodeRouting(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("unsafe runtime routing configuration was accepted")
    }
  }
}

///|
async test "approved text adapter invokes a digest-pinned upstream runtime" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, body, connection) => {
        assert_eq(request.meth, Post)
        assert_eq(request.path, "/v1/responses")
        assert_eq(
          request.headers.get("idempotency-key"),
          Some("opaque-tenant:inference:remote-idem-1"),
        )
        let received = @json.parse(body.read_all().text())
        assert_true(received.stringify().contains("remote-workload-1"))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          "{\"output_text\":\"ok\",\"usage\":{\"input_tokens\":3,\"output_tokens\":2}}",
        )
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{server.addr}/v1/responses",
      "runtime-credential",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let result = runtime.invoke(remote_request())
    assert_eq(
      result.artifact_digest,
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
    assert_eq(result.input_units, 3)
    assert_eq(result.output_units, 2)
    assert_true(result.output.stringify().contains("ok"))
    server.close()
  }
}

///|
async test "scheduler node selection resolves to a concrete runtime endpoint" {
  let primary_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let alternate_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let calls = [0, 0]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      primary_server.run_forever() <| ((_request, body, connection) => {
        calls[0] += 1
        ignore(body.read_all())
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string("{\"output_text\":\"primary\"}")
        connection.end_response()
      })
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      alternate_server.run_forever() <| ((request, body, connection) => {
        calls[1] += 1
        assert_eq(request.headers.get("x-lunanexa-target-node"), Some("node-b"))
        ignore(body.read_all())
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string("{\"output_text\":\"alternate\"}")
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{primary_server.addr}/v1/responses",
      "runtime-credential",
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
    let result = runtime.invoke_at(remote_request(), "node-b")
    assert_true(result.output.stringify().contains("alternate"))
    assert_eq(calls, [0, 1])
    try runtime.invoke_at(remote_request(), "node-c") catch {
      @runtimes.RemoteRuntimeError::RoutingTargetUnavailable(node_id) =>
        assert_eq(node_id, "node-c")
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("unmapped scheduler target used the fallback endpoint")
    }
    assert_eq(calls, [0, 1])
    primary_server.close()
    alternate_server.close()
  }
}

///|
async test "approved text adapter normalizes an upstream SSE stream" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, body, connection) => {
        assert_eq(request.headers.get("x-lunanexa-target-node"), Some("node-b"))
        assert_eq(
          request.headers.get("idempotency-key"),
          Some("opaque-tenant:inference:remote-idem-1"),
        )
        assert_true(body.read_all().text().contains("\"stream\":true"))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write_string("data: {\"delta\":\"hel\"}\n\n")
        connection.flush()
        connection.write_string(
          "data: {\"delta\":\"lo\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2}}\n\n",
        )
        connection.write_string("data: [DONE]\n\n")
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://127.0.0.1:1/v1/responses",
      "runtime-credential",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    ).with_node_endpoints([
      { node_id: "node-b", endpoint: "http://\{server.addr}/v1/responses" },
    ])
    let chunks : Array[Json] = []
    let result = runtime.invoke_stream_at(remote_request(), "node-b", chunk => {
      chunks.push(chunk)
    })
    assert_eq(chunks.length(), 2)
    assert_eq(result.input_units, 1)
    assert_eq(result.output_units, 2)
    server.close()
  }
}

///|
async test "approved text adapter rejects a truncated SSE stream" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((_request, body, connection) => {
        ignore(body.read_all())
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write_string("data: {\"delta\":\"partial\"}\n\n")
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{server.addr}/v1/responses",
      "runtime-credential",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    try runtime.invoke_stream(remote_request(), _ => ()) catch {
      @runtimes.RemoteRuntimeError::InvalidUpstreamResponse(message) =>
        assert_true(message.contains("completion marker"))
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("truncated stream was accepted")
    }
    server.close()
  }
}
