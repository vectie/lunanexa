///|
async test "proxy forwards SSE before upstream completion and keeps JSON framing" {
  let upstream = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let proxy = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer upstream.close()
  defer proxy.close()
  let continue_stream = @async.Semaphore(1, initial_value=0)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        upstream.run_forever(
          (request, reader, connection) => {
            ignore(reader.read_all())
            if request.path == "/stream" {
              connection.send_response(200, "OK", extra_headers={
                "Content-Type": "text/event-stream; charset=utf-8",
              })
              connection.write_string("data: first\n\n")
              connection.flush()
              continue_stream.acquire()
              connection.write_string("data: [DONE]\n\n")
              connection.end_response()
            } else {
              connection.send_response(200, "OK", extra_headers={
                "Content-Type": "application/json",
              })
              connection.write_string("{\"answer\":42}")
              connection.end_response()
            }
          },
          allow_failure=true,
        )
      })
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        proxy.run_forever(
          (request, reader, connection) => {
            proxy_request(
              request,
              reader,
              connection,
              "http://\{upstream.addr}",
              no_store=true,
            ) catch {
              _ => send_error(connection, 503, "identity-gateway-unavailable")
            }
          },
          allow_failure=true,
        )
      })
      let client = @http.Client("http://\{proxy.addr}")
      defer client.close()
      let response = client.get("/stream")
      assert_eq(response.code, 200)
      assert_eq(header(response.headers, "X-Accel-Buffering"), Some("no"))
      assert_eq(header(response.headers, "Cache-Control"), Some("no-store"))
      assert_eq(header(response.headers, "Content-Length"), None)
      assert_eq(client.read_exactly(13), b"data: first\n\n")
      // The upstream cannot finish until the public first event is received.
      continue_stream.release()
      assert_eq(client.read_all().text(), "data: [DONE]\n\n")
      let response = client.get("/json")
      assert_eq(response.code, 200)
      assert_eq(header(response.headers, "Content-Length"), Some("13"))
      assert_eq(client.read_all().text(), "{\"answer\":42}")
    })
  })
}

///|
async test "proxy closes upstream when a streaming consumer disconnects" {
  let upstream = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let proxy = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer upstream.close()
  defer proxy.close()
  let continue_stream = @async.Semaphore(1, initial_value=0)
  let closed = @async.Semaphore(1, initial_value=0)
  let mut upstream_finished = false
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        upstream.run_forever(
          (_, reader, connection) => {
            ignore(reader.read_all())
            defer closed.release()
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "text/event-stream",
            })
            connection.write_string("data: first\n\n")
            connection.flush()
            continue_stream.acquire()
            // A bounded stream larger than socket buffers exposes a closed peer;
            // it is never allowed to complete successfully in this test.
            let chunk = "data: " + "x".repeat(16384) + "\n\n"
            for _ in 0..<1024 {
              connection.write_string(chunk)
              connection.flush()
            }
            upstream_finished = true
            connection.end_response()
          },
          allow_failure=true,
        )
      })
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        proxy.run_forever(
          (request, reader, connection) => {
            proxy_request(
              request,
              reader,
              connection,
              "http://\{upstream.addr}",
              no_store=true,
            ) catch {
              _ => send_error(connection, 503, "identity-gateway-unavailable")
            }
          },
          allow_failure=true,
        )
      })
      let client = @http.Client("http://\{proxy.addr}")
      defer client.close()
      ignore(client.get("/stream"))
      assert_eq(client.read_exactly(13), b"data: first\n\n")
      client.close()
      continue_stream.release()
      closed.acquire()
      assert_false(upstream_finished)
    })
  })
}
