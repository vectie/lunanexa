///|
/// A live model listing, not a static route declaration, unlocks handoff.
async test "external text route requires an approved alias and observed model" {
  let directory = @fs.tmpdir(prefix="lunanexa-external-text-")
  let adapter = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let model_present = [true]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      adapter.run_forever(allow_failure=true) <| ((request, _, connection) => {
        let body = match request.path {
          "/health" => "ok"
          "/v1/models" =>
            if model_present[0] {
              "{\"data\":[{\"id\":\"served-test\"}]}"
            } else {
              "{\"data\":[]}"
            }
          _ => "{}"
        }
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(body)
        connection.end_response()
      })
    }
    let store = @store.FileStore::open("\{directory}/state.json")
    store.fence_controller(1L)
    let registry = @registry.FileRegistry::open("\{directory}/registry.json")
    seed_access_package_model(registry)
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "https://runtime.invalid/v1/responses",
      "",
      "runtime-v1",
      "sha256:" + "b".repeat(64),
      "sha256:" + "a".repeat(64),
    )
    let service = ApiService::with_registry(
      store, registry, runtime, "operator-token", "inference-token", "node-token",
      "0.2.0",
    ).with_external_text_route(
      "qwen.default",
      "enterprise-tenant",
      "enterprise-node",
      "http://\{adapter.addr}",
      "served-test",
      "external-v1",
      "sha256:" + "b".repeat(64),
      "sha256:" + "a".repeat(64),
    )
    assert_true(service.external_text_ready())
    assert_eq(
      service.serving_client_model_aliases(
        ["qwen.default"],
        tenant_ref="enterprise-tenant",
      ),
      ["qwen.default"],
    )
    assert_eq(
      service.serving_client_model_aliases(
        ["qwen.default"],
        tenant_ref="trial-tenant",
      ),
      [],
    )
    model_present[0] = false
    assert_true(!service.external_text_ready())
    assert_eq(
      service.serving_client_model_aliases(
        ["qwen.default"],
        tenant_ref="enterprise-tenant",
      ),
      [],
    )
  }
}

///|
/// An operator cannot turn arbitrary public HTTP into a model route.
async test "external text route rejects non-loopback origins" {
  let directory = @fs.tmpdir(prefix="lunanexa-external-text-invalid-")
  let store = @store.FileStore::open("\{directory}/state.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses",
    "",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
  )
  let service = ApiService::new(
    store, runtime, "operator-token", "inference-token", "node-token", "0.2.0",
  )
  let rejected = try {
    ignore(
      service.with_external_text_route(
        "qwen.default",
        "enterprise-tenant",
        "enterprise-node",
        "http://example.com",
        "served-test",
        "external-v1",
        "sha256:" + "b".repeat(64),
        "sha256:" + "a".repeat(64),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
