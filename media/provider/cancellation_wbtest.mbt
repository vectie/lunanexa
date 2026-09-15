///|
async test "cancellation requires positive acknowledgement for the exact upstream job" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let provider = Provider::new("http://\{server.addr}", profile())
  let code = Ref(200)
  let payload = Ref("{}")
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((request, body, connection) => {
        assert_eq(request.meth, Delete)
        ignore(@io.Reader::read_all(body))
        connection.send_response(code.val, "fixture", extra_headers={
          "content-type": "application/json",
        })
        connection.write_string(payload.val)
        connection.end_response()
      })
    })
    for
      (status, text, accepted) in [
        (404, "{\"id\":\"job-1\",\"deleted\":true}", false),
        (409, "{\"id\":\"job-1\",\"deleted\":true}", false),
        (200, "{\"id\":\"other-job\",\"deleted\":true}", false),
        (200, "{\"id\":\"job-1\",\"deleted\":false}", false),
        (200, "{\"id\":\"job-1\",\"deleted\":true}", true),
      ] {
      code.val = status
      payload.val = text
      assert_eq(provider.delete("job-1"), accepted)
    }
  }
}
