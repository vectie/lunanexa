///|
async test "operator model-source proxy authenticates adapter and rejects anonymous users" {
  let directory = @fs.tmpdir(prefix="lunanexa-model-source-proxy-")
  let adapter = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let saw_authority = [false]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      adapter.run_forever(allow_failure=true) <| ((request, body, connection) => {
        saw_authority[0] = request.headers
          .iter()
          .find_first(entry => entry.0.to_lower() == "authorization")
          .map(entry => entry.1) ==
          Some("Bearer model-source-adapter-test-token-more-than-32-bytes")
        assert_eq(request.path, "/internal/v1/modelscope/search")
        assert_true(body.read_all().text().contains("MiniCPM"))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json; charset=utf-8",
        })
        connection.write_string(
          "{\"models\":[],\"total_count\":0,\"page_number\":1,\"page_size\":12}",
        )
        connection.end_response()
      })
    }
    let store = @store.FileStore::open("\{directory}/state.json")
    store.fence_controller(1L)
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "https://runtime.invalid/v1/responses", "test-only-upstream-reference", "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
    let service = @api.ApiService::new(
      store, runtime, "operator-token", "inference-token", "node-token", "0.2.0",
    ).with_model_source_adapter(
      "http://\{adapter.addr}",
      "model-source-adapter-test-token-more-than-32-bytes",
    )
    assert_eq(
      service.handle(
        Post,
        "/v1/model-sources/modelscope/search",
        Map([]),
        "{\"query\":\"MiniCPM\",\"page_number\":1,\"page_size\":12}",
      ).status,
      401,
    )
    let reply = service.handle(
      Post,
      "/v1/model-sources/modelscope/search",
      { "Authorization": "Bearer operator-token" },
      "{\"query\":\"MiniCPM\",\"page_number\":1,\"page_size\":12}",
    )
    assert_eq(reply.status, 200)
    assert_true(saw_authority[0])
  }
}
