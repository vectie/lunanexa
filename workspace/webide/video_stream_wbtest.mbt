///|
async test "personal video proxy preserves byte ranges and survives an interrupted reader" {
  let public = @http.Server(@socket.Addr::parse("127.0.0.1:0"), reuse_addr=true)
  let backend = @http.Server(
    @socket.Addr::parse("127.0.0.1:0"),
    reuse_addr=true,
  )
  defer public.close()
  defer backend.close()
  let origin = "http://\{public.addr}"
  let bridge = Bridge::new(
    test_config(origin),
    _ => test_grant("alice"),
    _ => true,
    (_, _) => {
      http_url: "http://\{backend.addr}",
      websocket_url: "ws://\{backend.addr}",
    },
  )
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      public.run_forever((req, body, conn) => bridge.handle(req, body, conn))
    })
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      backend.run_forever((req, _, conn) => {
        assert_eq(header(req.headers, "range"), Some("bytes=0-"))
        conn.send_response(206, "Partial Content", extra_headers={
          "content-type": "video/mp4",
          "accept-ranges": "bytes",
          "content-range": "bytes 0-5242879/5242880",
          "content-length": "5242880",
        })
        let chunk = Bytes::make(65536, b'x')
        for _ in 0..<80 {
          conn.write(chunk)
        }
        conn.end_response()
      })
    })
    let (cookies, _) = launch_test(origin, "lnxc_alice")
    let headers : @http.Headers = { "cookie": cookies, "range": "bytes=0-" }
    let interrupted = @http.Client(origin)
    interrupted.request(
      Get,
      "/view?filename=video.mp4&type=output",
      extra_headers=headers,
    )
    assert_eq(interrupted.end_request().code, 206)
    ignore(interrupted.read_some(max_len=4096))
    interrupted.close()
    let (response, body) = @http.get(
      origin + "/view?filename=video.mp4&type=output",
      headers~,
    )
    assert_eq(response.code, 206)
    assert_eq(
      header(response.headers, "content-range"),
      Some("bytes 0-5242879/5242880"),
    )
    assert_eq(body.binary().length(), 5242880)
  }
}
