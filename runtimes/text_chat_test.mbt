///|
async test "text Chat transport preserves conversation budget usage JSON and SSE" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((request, body, connection) => {
        assert_eq(request.path, "/v1/chat/completions")
        assert_eq(
          request.headers.get("authorization"),
          Some("Bearer test-backend"),
        )
        let text = body.read_all().text()
        assert_eq(request.headers.get("transfer-encoding"), None)
        assert_eq(
          request.headers.get("content-length"),
          Some(@utf8.encode(text).length().to_string()),
        )
        let value = @json.parse(text)
        guard value is Object(fields) else { fail("request object") }
        assert_eq(fields.get("max_tokens"), Some(Json::number(20)))
        assert_false(fields.contains("metadata"))
        assert_false(fields.contains("input"))
        assert_eq(
          fields.get("messages"),
          Some([
            { "role": "system", "content": "Be precise 精确" },
            { "role": "user", "content": "17 times 19" },
          ]),
        )
        let streaming = fields.get("stream") is Some(True)
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": if streaming {
            "text/event-stream"
          } else {
            "application/json"
          },
        })
        connection.write_string(
          if streaming {
            "data: {\"choices\":[{\"delta\":{\"content\":\"323\"}}]}\n\ndata: {\"choices\":[],\"usage\":{\"prompt_tokens\":9,\"completion_tokens\":2}}\n\ndata: [DONE]\n\n"
          } else {
            "{\"choices\":[{\"message\":{\"content\":\"323\"}}],\"usage\":{\"prompt_tokens\":9,\"completion_tokens\":2}}"
          },
        )
        connection.end_response()
      })
    })
    let runtime = @runtimes.OpenAiTextRuntime::native(
        "http://\{server.addr}/v1/chat/completions",
        "test-backend",
        "native-v1",
        "1".repeat(40),
        "sha256:" + "a".repeat(64),
        allow_http_loopback=true,
      )
      .with_text_chat_completions()
      .with_served_model_name("glm-5.3")
    let request = {
      ..remote_request(),
      payload: {
        "messages": [
          { "role": "system", "content": "Be precise 精确" },
          {
            "role": "user",
            "content": [{ "type": "text", "text": "17 times 19" }],
          },
        ],
      },
    }
    let result = runtime.invoke(request)
    assert_eq(result.output, { "output_text": "323" })
    assert_eq((result.input_units, result.output_units), (9, 2))
    let chunks = []
    let result = runtime.invoke_stream(request, chunk => chunks.push(chunk))
    assert_eq(result.output, { "output_text": "323" })
    assert_eq(chunks, [{ "text_delta": "323" }])
    assert_eq((result.input_units, result.output_units), (9, 2))
    let unsupported : Array[Json] = [
      { "messages": [{ "role": "tool", "content": "x", "tool_call_id": "a" }] },
      { "prompt": "x", "tools": [] },
    ]
    for payload in unsupported {
      try runtime.invoke({ ..request, payload, }) catch {
        @runtimes.RemoteRuntimeError::UnsupportedCapability => ()
        e => fail("unexpected error \{Repr(e)}")
      } noraise {
        _ => fail("unsupported input silently accepted")
      }
    }
    server.close()
  })
}

///|
async test "text Chat transport rejects truncated stream" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((_request, body, connection) => {
        ignore(body.read_all())
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write_string(
          "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n",
        )
        connection.end_response()
      })
    })
    let runtime = @runtimes.OpenAiTextRuntime::native(
      "http://\{server.addr}/v1/chat/completions",
      "",
      "native-v1",
      "1".repeat(40),
      "sha256:" + "a".repeat(64),
      allow_http_loopback=true,
    ).with_text_chat_completions()
    try runtime.invoke_stream(remote_request(), _ => ()) catch {
      @runtimes.RemoteRuntimeError::InvalidUpstreamResponse(_) => ()
      e => fail("unexpected error \{Repr(e)}")
    } noraise {
      _ => fail("missing DONE accepted")
    }
    server.close()
  })
}
