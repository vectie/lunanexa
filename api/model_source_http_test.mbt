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

///|
async test "verified S3 import is atomically adopted as gated registry candidate" {
  let directory = @fs.tmpdir(prefix="lunanexa-model-source-adopt-")
  let adapter = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let operation : @modelsource.ImportOperation = {
    import_id: "ms-0123456789abcdef",
    source: "modelscope",
    model_id: "OpenBMB/MiniCPM5-1B",
    revision: "main",
    state: Verified,
    files_total: 4,
    files_completed: 4,
    bytes_total: 4096L,
    bytes_completed: 4096L,
    manifest_digest: "sha256:" + "a".repeat(64),
    artifact_uri: "s3://models/modelscope/ms-0123456789abcdef/lunanexa-source-manifest.json",
    license: "apache-2.0",
    error_code: "",
    cancel_requested: false,
    created_unix_ms: 1L,
    updated_unix_ms: 2L,
  }
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      adapter.run_forever(allow_failure=true) <| ((request, _, connection) => {
        assert_eq(request.meth, Get)
        assert_eq(request.path, "/internal/v1/modelscope/imports")
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json; charset=utf-8",
        })
        connection.write_string([operation].to_json().stringify())
        connection.end_response()
      })
    }
    let store = @store.FileStore::open("\{directory}/state.json")
    store.fence_controller(1L)
    let registry = @registry.FileRegistry::open("\{directory}/registry.json")
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "https://runtime.invalid/v1/responses",
      "test-only-upstream-reference",
      "runtime-v1",
      "sha256:" + "b".repeat(64),
      "sha256:" + "a".repeat(64),
    )
    let service = @api.ApiService::with_registry(
      store, registry, runtime, "operator-token", "inference-token", "node-token",
      "0.2.0",
    ).with_model_source_adapter(
      "http://\{adapter.addr}",
      "model-source-adapter-test-token-more-than-32-bytes",
    )
    let reply = service.handle(
      Post,
      "/v1/model-sources/modelscope/imports/ms-0123456789abcdef:adopt",
      { "Authorization": "Bearer operator-token" },
      (
        #|{"model_id":"model.minicpm5-1b","version":"modelscope-main","license_id":"license.minicpm5-apache","compatible_architectures":["nvidia-gb10","nvidia-ampere"],"minimum_memory_mib":8192}
      ),
    )
    assert_eq(reply.status, 201)
    assert_true(reply.body.contains("LicenseReviewRequired"))
    let snapshot = registry.snapshot()
    assert_eq(snapshot.models.length(), 1)
    assert_eq(snapshot.models[0].state, Candidate)
    assert_eq(snapshot.models[0].artifact.uri, operation.artifact_uri)
    assert_eq(snapshot.licenses.length(), 1)
    assert_eq(snapshot.licenses[0].status, Pending)
    adapter.close()
  }
  @fs.rmdir(directory, recursive=true)
}
