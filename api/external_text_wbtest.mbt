///|
/// A live model listing, not a static route declaration, unlocks handoff.
async test "external text route requires an approved alias and observed model" {
  let directory = @fs.tmpdir(prefix="lunanexa-external-text-")
  let adapter = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let model_present = [true]
  let saw_credential = [false]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      adapter.run_forever(allow_failure=true) <| ((request, payload, connection) => {
        let body = match request.path {
          "/v1/chat/completions" => {
            assert_eq(
              request.headers.get("authorization"),
              Some("Bearer native-backend-secret"),
            )
            let input = @json.parse(payload.read_all().text())
            assert_true(
              input
              is {
                "messages": Array(_),
                "max_tokens": 32,
                "model": "served-test",
                ..
              },
            )
            "{\"choices\":[{\"message\":{\"content\":\"323\"}}],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":2}}"
          }
          "/health" => "ok"
          "/v1/models" =>
            if model_present[0] {
              saw_credential[0] = request.headers.get("authorization") ==
                Some("Bearer native-backend-secret")
              "{\"data\":[{\"id\":\"other\",\"max_model_len\":8192},{\"id\":\"served-test\",\"max_model_len\":65536}]}"
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
      "",
      "sha256:" + "a".repeat(64),
      credential="native-backend-secret",
      native_revision="1".repeat(40),
      text_chat_completions=true,
    )
    assert_true(service.external_text_ready())
    assert_true(saw_credential[0])
    let route = service.external_text_route.unwrap()
    assert_eq(route.runtime.native_revision(), Some("1".repeat(40)))
    assert_eq(route.runtime.image_digest(), "")
    let reply = service.handle(
      Post,
      "/v1/chat/completions",
      {
        "Authorization": "Bearer inference-token",
        "X-LunaNexa-Tenant": "enterprise-tenant",
      },
      (
        {
          "model": "qwen.default",
          "messages": [{ "role": "user", "content": "17 times 19" }],
          "max_tokens": 32,
        } : Json).stringify(),
    )
    assert_eq(reply.status, 200)
    assert_true(
      @json.parse(reply.body)
      is { "choices": Array([{ "message": { "content": "323", .. }, .. }]), .. },
    )
    assert_eq(service.external_text_observation(), (true, Some(65536)))
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
    assert_eq(service.external_text_observation(), (false, None))
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
test "external context metadata rejects malformed and unbounded limits" {
  for value in [0.0, -1.0, 65536.5, 10485761.0] {
    assert_eq(external_model_context({ "max_model_len": value }), None)
  }
  assert_eq(external_model_context({ "max_model_len": "65536" }), None)
  assert_eq(external_model_context({ "id": "model" }), None)
  assert_eq(external_model_context({ "max_model_len": 65536 }), Some(65536))
}

///|
async test "shared Qwen handoff is listed only for its live trial organization" {
  let directory = @fs.tmpdir(prefix="lunanexa-shared-text-route-")
  let adapter = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let model_present = [true]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      adapter.run_forever(allow_failure=true) <| ((request, _, connection) => {
        let body = match request.path {
          "/health" => "ok"
          "/v1/models" =>
            if model_present[0] &&
              request.headers.get("authorization") ==
              Some("Bearer trial-secret") {
              "{\"data\":[{\"id\":\"served-qwen\",\"max_model_len\":65536}]}"
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
    store.put_heartbeat({
      node_id: "trial-node",
      state: Active,
      observed_generation: 1L,
      controller_epoch: 1L,
      inventory: {
        node_id: "trial-node",
        agent_version: "test",
        os_release: "test",
        runtime_names: ["vllm"],
        accelerators: [],
        labels: { "lunanexa.io/usage-pool": "trial" },
        taints: [],
      },
      running_deployments: [],
      runtime_endpoints: None,
      timestamp_unix_ms: @async.now(),
      signature: "",
    })
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
      )
      .with_shared_trial_offerings([
        {
          organization_id: "org-energy",
          tenant_ref: "tenant-energy",
          node_id: "trial-node",
          node_label: "Shared trial node",
          model_alias: "qwen.default",
          model_name: "Qwen",
          kind: "Text",
          health_url: "http://\{adapter.addr}/health",
          public_url: "https://example.test/user/",
        },
      ])
      .with_shared_trial_text_route(
        "qwen.default",
        "tenant-energy",
        "trial-node",
        "http://\{adapter.addr}",
        "served-qwen",
        "vllm-v1",
        "sha256:" + "b".repeat(64),
        "sha256:" + "a".repeat(64),
        "trial-secret",
      )
    assert_eq(
      service.serving_client_model_aliases(
        ["qwen.default"],
        tenant_ref="tenant-energy",
        organization_id="org-energy",
      ),
      ["qwen.default"],
    )
    assert_eq(
      service.serving_client_model_aliases(
        ["qwen.default"],
        tenant_ref="tenant-energy",
        organization_id="org-other",
      ),
      [],
    )
    model_present[0] = false
    assert_eq(
      service.serving_client_model_aliases(
        ["qwen.default"],
        tenant_ref="tenant-energy",
        organization_id="org-energy",
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
      {
        membership_id: "member-user",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        subject_ref: "user",
        roles: [Developer],
        active: true,
        created_unix_ms: @async.now(),
      },
      {
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
