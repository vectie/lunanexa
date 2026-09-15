///|
async test "model registration POST is not shadowed by OpenAI model listing" {
  let directory = @fs.tmpdir(prefix="lunanexa-model-route-")
  defer @fs.rmdir(directory, recursive=true)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
    @store.FileStore::open(directory + "/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  )
  let denied = service.handle(Post, "/v1/models", Map([]), "{}")
  assert_eq(denied.status, 401)
  let registration = service.handle(
    Post,
    "/v1/models",
    { "Authorization": "Bearer operator-token" },
    "{}",
  )
  assert_eq(registration.status, 503)
  assert_true(registration.body.contains("RegistryUnavailable"))
  let listing = service.handle(Get, "/v1/models", Map([]), "")
  assert_true(listing.status != 404)
  assert_false(listing.body.contains("RegistryUnavailable"))
  let registry = @registry.FileRegistry::open(directory + "/registry.json")
  let registered_service = ApiService::with_registry(
    @store.FileStore::open(directory + "/registered-state.json"),
    registry,
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  )
  let model : @contracts.ModelRecord = {
    model_id: "route-test-model",
    version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://test-only/route-test-model",
      size_bytes: 1L,
      signature_ref: "s3://test-only/route-test-model.sig",
    },
    license_id: "test-license",
    provenance: "test-only",
    compatible_architectures: ["test-only"],
    minimum_memory_mib: 1,
    state: Candidate,
  }
  let accepted = registered_service.handle(
    Post,
    "/v1/models",
    { "Authorization": "Bearer operator-token" },
    model.to_json().stringify(),
  )
  assert_eq(accepted.status, 202)
  let reopened = @registry.FileRegistry::open(directory + "/registry.json")
  assert_true(reopened.snapshot().models.any(value => value == model))
  assert_eq(
    registered_service.handle(
      Post,
      "/v1/models",
      Map([]),
      model.to_json().stringify(),
    ).status,
    401,
  )
}
