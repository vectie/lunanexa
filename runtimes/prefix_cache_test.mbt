///|
async test "prefix reuse requires opt-in and preserves tenant isolation" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let salts : Array[String] = []
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((_, body, connection) => {
        guard @json.parse(body.read_all().text())
          is { "cache_salt": String(salt), "input": "hello", .. } else {
          fail("cache scope missing or input changed")
        }
        salts.push(salt)
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          "{\"output_text\":\"ok\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
        )
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{server.addr}/v1/responses",
      "backend-scope-secret",
      "test",
      "sha256:" + "b".repeat(64),
      "sha256:" + "a".repeat(64),
      allow_http_loopback=true,
    ).with_prefix_cache_isolation()
    let base = remote_request()
    ignore(runtime.invoke(base))
    ignore(runtime.invoke({ ..base, workload_id: "second", }))
    let opted = {
      ..base,
      payload: { "prompt": "hello", "runtime_prefix_cache": true },
    }
    ignore(runtime.invoke(opted))
    ignore(runtime.invoke({ ..opted, workload_id: "third", }))
    ignore(runtime.invoke({ ..opted, tenant_ref: "another-tenant", }))
    assert_false(salts[0] == salts[1])
    assert_eq(salts[2], salts[3])
    assert_false(salts[2] == salts[4])
    assert_false(salts[2].contains("opaque-tenant"))
    server.close()
  }
}
