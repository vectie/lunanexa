///|
async test "S3-compatible verifier streams and checks the pinned artifact digest" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, _, connection) => {
        assert_eq(request.path, "/models/model.bin")
        connection.send_response(200, "OK")
        connection.write_string("artifact-bytes")
        connection.end_response()
      })
    }
    let verifier = @registry.S3HttpVerifier::new(
      "http://\{server.addr}/models",
      "artifact-credential",
      allow_http_loopback=true,
    )
    let verified = verifier.verify(
      "model.bin", "sha256:6521df166eb07efaf36eba5b6bedefd9d6a252e9c80bab1c99653700ec71473c",
      1024L,
    )
    assert_eq(verified.size_bytes, 14L)
    try
      verifier.verify(
        "model.bin", "sha256:6666666666666666666666666666666666666666666666666666666666666666",
        1024L,
      )
    catch {
      @registry.StorageError::DigestMismatch => ()
      error => fail("unexpected error: \{to_repr(error)}")
    } noraise {
      _ => fail("digest mismatch was accepted")
    }
    server.close()
  }
}
