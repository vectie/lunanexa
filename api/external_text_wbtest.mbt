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

///|
async test "only the owning company administrator can start and stop its shared external model" {
  let root = @fs.tmpdir(prefix="lunanexa-external-control-")
  let durable = @store.FileStore::open("\{root}/state.json")
  durable.fence_controller(1L)
  let portal = @portal_store.FilePortalStore::open("\{root}/portal.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses",
    "",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
  )
  let calls : Array[String] = []
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.2.0",
    )
    .with_portal_store(portal)
    .with_external_text_route(
      "glm-5.3.flash",
      "tenant-a",
      "spark-a",
      "http://127.0.0.1:19091",
      "GLM-5.3-Flash-EXL3",
      "runtime-v1",
      "sha256:" + "b".repeat(64),
      "sha256:" + "a".repeat(64),
    )
    .with_external_text_control(action => {
      calls.push(action)
      if action == "stop" {
        "Stopped"
      } else {
        "Running"
      }
    })
  let operator = { "Authorization": "Bearer operator-token" }
  for
    membership in [
      @portal.EnterpriseMembership::{
        membership_id: "member-admin",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "admin",
        roles: [OrganizationAdministrator, Developer],
        active: true,
        created_unix_ms: @async.now(),
      },
      @portal.EnterpriseMembership::{
        membership_id: "member-user",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "user",
        roles: [Developer],
        active: true,
        created_unix_ms: @async.now(),
      },
      @portal.EnterpriseMembership::{
        membership_id: "member-other",
        tenant_ref: "tenant-b",
        organization_id: "org-b",
        subject_ref: "other",
        roles: [OrganizationAdministrator, Developer],
        active: true,
        created_unix_ms: @async.now(),
      },
    ] {
    assert_eq(
      service.handle(
        Post,
        "/v1/portal/operator/memberships",
        operator,
        membership.to_json().stringify(),
      ).status,
      201,
    )
  }
  let path = "/v1/portal/self/external-model-service"
  let admin = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "admin",
  }
  let user = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "user",
  }
  let other = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "other",
  }
  let listed = service.handle(Get, path, admin, "")
  assert_eq(listed.status, 200)
  assert_true(listed.body.contains("\"can_stop\":true"))
  assert_eq(service.handle(Get, path, other, "").status, 404)
  assert_eq(service.handle(Post, path + ":start", other, "").status, 404)
  assert_eq(service.handle(Post, path + ":stop", user, "").status, 403)
  assert_eq(service.handle(Post, path + ":start", user, "").status, 403)
  assert_eq(calls, ["status"])
  let stopped = service.handle(Post, path + ":stop", admin, "")
  assert_eq(stopped.status, 200)
  assert_true(stopped.body.contains("\"state\":\"Stopped\""))
  let started = service.handle(Post, path + ":start", admin, "")
  assert_eq(started.status, 200)
  assert_true(started.body.contains("\"state\":\"Running\""))
  assert_eq(calls, ["status", "stop", "start"])
}
