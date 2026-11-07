///|
test "decode speed excludes first-token wait and uses usage tokens" {
  assert_eq(@benchmark.decode_rate(301, 1000L, 11000L), 30.0)
  assert_eq(@benchmark.decode_rate(301, 0L, 11000L), 0.0)
  assert_eq(@benchmark.decode_rate(1, 1000L, 1000L), 0.0)
  assert_eq(@benchmark.decode_rate(301, 11000L, 1000L), 0.0)
}

///|
async test "stream metrics use reported usage and do not retain text or credentials" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, body, connection) => {
        ignore(body.read_all())
        assert_eq(request.path, "/trial/v1/chat/completions")
        assert_eq(
          request.headers.get("authorization"),
          Some("Bearer private-test-key"),
        )
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write_string(
          "data: {\"id\":\"sample-1\",\"choices\":[{\"delta\":{\"content\":\"private text\"}}]}\n\n",
        )
        connection.flush()
        @async.sleep(20)
        connection.write_string(
          "data: {\"choices\":[{\"delta\":{\"content\":\"more\"}}]}\n\n",
        )
        connection.flush()
        @async.sleep(35)
        connection.write_string(
          "data: {\"usage\":{\"completion_tokens\":301},\"lunanexa_receipt\":\"workload:test:digest\"}\n\ndata: [DONE]\n\n",
        )
        connection.end_response()
      })
    }
    let result = @benchmark.sample(
      "http://\{server.addr}",
      "private-test-key",
      "test-model",
      user=1,
      concurrency=1,
      round=1,
      nonce="test",
    )
    assert_true(result.valid)
    assert_eq(result.output_tokens, 301)
    assert_true(result.decode_tokens_per_second > 0.0)
    assert_true(result.timings.get("stream_tail_ms").unwrap() >= 25L)
    assert_true(result.timings.contains("connect_ms"))
    assert_true(result.timings.contains("headers_ms"))
    assert_true(result.timings.contains("close_ms"))
    assert_true(
      result.end_to_end_tokens_per_second < result.decode_tokens_per_second,
    )
    let evidence = Json(result).stringify()
    assert_false(evidence.contains("private-test-key"))
    assert_false(evidence.contains("private text"))
  }
}
