///|
async fn expansion_service(path : String) -> @api.ApiService {
  let durable = @store.FileStore::open(path)
  durable.fence_controller(1L)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses", "test-only-upstream-reference", "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  @api.ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  )
}

///|
async test "operator-issued API key authorizes model discovery and revocation is immediate" {
  let directory = @fs.tmpdir(prefix="lunanexa-access-api-")
  let access = @access.AccessStore::open(
    "\{directory}/access.json",
    "0123456789abcdef0123456789abcdef",
  )
  let service = expansion_service("\{directory}/state.json")
    .with_access_store(access)
    .with_legacy_unbound_access_for_local_testing()
  let operator = { "Authorization": "Bearer operator-token" }
  let intent : @access.ApiKeyIssueIntent = {
    key_id: "key-api-test",
    tenant_ref: "tenant-api-test",
    subject_ref: "subject-api-test",
    organization_id: "organization-api-test",
    project_id: "project-api-test",
    display_name: "API test key",
    scopes: [ModelList, Inference],
    allowed_models: ["model-api-test"],
    expires_unix_ms: @async.now() + 60000L,
    maximum_requests: 10L,
  }
  let issued_reply = service.handle(
    Post,
    "/v1/access/api-keys",
    operator,
    intent.to_json().stringify(),
  )
  assert_eq(issued_reply.status, 201)
  assert_false(issued_reply.body.contains("secret_sha256"))
  let issued : @access.IssuedApiKeyView = @json.from_json(
    @json.parse(issued_reply.body),
  )
  assert_eq(
    service.handle(
      Get,
      "/v1/models",
      { "Authorization": "Bearer \{issued.secret}" },
      "",
    ).status,
    200,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/access/api-keys/key-api-test:revoke",
      operator,
      "",
    ).status,
    200,
  )
  assert_eq(
    service.handle(
      Get,
      "/v1/models",
      { "Authorization": "Bearer \{issued.secret}" },
      "",
    ).status,
    401,
  )
}

///|
async test "OpenAI chat does not mask a failed canonical workload as empty success" {
  let directory = @fs.tmpdir(prefix="lunanexa-openai-failure-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever() <| ((_request, body, connection) => {
        ignore(body.read_all())
        connection.send_response(400, "Bad Request", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string("{\"error\":{\"type\":\"validation_error\"}}")
        connection.end_response()
      })
    }
    let durable = @store.FileStore::open("\{directory}/state.json")
    durable.fence_controller(1L)
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "upstream-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let service = @api.ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    let reply = service.handle(
      Post,
      "/v1/chat/completions",
      { "Authorization": "Bearer inference-token" },
      (
        {
          "model": "tiny-bf16",
          "messages": [{ "role": "user", "content": "Moon pipeline" }],
        } : Json).stringify(),
    )
    assert_eq(reply.status, 502)
    assert_true(reply.body.contains("RuntimeUnavailable"))
    assert_false(reply.body.contains("choices"))
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "OpenAI chat bridges LunaFlux streaming Responses to non-stream content" {
  let directory = @fs.tmpdir(prefix="lunanexa-lunaflux-chat-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever() <| ((_request, body, connection) => {
        let encoded = @json.parse(body.read_all().text()).stringify()
        assert_true(encoded.contains("\"input\":\"Moon pipeline\""))
        assert_true(encoded.contains("\"stream\":true"))
        assert_false(encoded.contains("max_output_tokens"))
        assert_false(encoded.contains("metadata"))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write_string(
          "data: {\"type\":\"response.output_text.delta\",\"delta\":\"MOON\"}\n\n",
        )
        connection.write_string(
          "data: {\"type\":\"response.output_text.delta\",\"delta\":\"_OK\"}\n\n",
        )
        connection.write_string(
          "data: {\"type\":\"response.completed\",\"response\":{\"usage\":{\"input_tokens\":4,\"output_tokens\":2}}}\n\n",
        )
        connection.end_response()
      })
    }
    let durable = @store.FileStore::open("\{directory}/state.json")
    durable.fence_controller(1L)
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "upstream-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    ).with_lunaflux_streaming_responses()
    let service = @api.ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    let reply = service.handle(
      Post,
      "/v1/chat/completions",
      { "Authorization": "Bearer inference-token" },
      (
        {
          "model": "tiny-bf16",
          "messages": [{ "role": "user", "content": "Moon pipeline" }],
        } : Json).stringify(),
    )
    assert_eq(reply.status, 200)
    assert_true(reply.body.contains("\"content\":\"MOON_OK\""))
    assert_true(reply.body.contains("\"completion_tokens\":2"))
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "scoped API key preserves WebIDE tools across the streaming chat bridge" {
  let directory = @fs.tmpdir(prefix="lunanexa-openai-stream-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let api_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever(allow_failure=true) <| ((_, body, connection) => {
        let upstream = body.read_all().text()
        assert_true(upstream.contains("\"stream\":true"))
        assert_true(upstream.contains("\"name\":\"read_file\""))
        assert_true(upstream.contains("\"parallel_tool_calls\":false"))
        assert_false(upstream.contains("\"function\":{\"name\":\"read_file\""))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write_string(
          "data: {\"type\":\"response.output_text.delta\",\"delta\":\"hello\"}\n\n",
        )
        connection.write_string(
          "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"item-1\",\"call_id\":\"call-1\",\"name\":\"read_file\",\"arguments\":\"\"}}\n\n",
        )
        connection.write_string(
          "data: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"delta\":\"{\\\"path\\\":\\\"README.md\\\"}\"}\n\n",
        )
        connection.write_string(
          "data: {\"type\":\"response.completed\",\"response\":{\"usage\":{\"input_tokens\":2,\"output_tokens\":2}}}\n\n",
        )
        connection.end_response()
      })
    }
    let durable = @store.FileStore::open("\{directory}/state.json")
    durable.fence_controller(1L)
    let access = @access.AccessStore::open(
      "\{directory}/access.json",
      "0123456789abcdef0123456789abcdef",
    )
    let issued = access.issue(
      {
        key_id: "key-stream",
        tenant_ref: "tenant-stream",
        subject_ref: "subject-stream",
        organization_id: "organization-stream",
        project_id: "project-stream",
        display_name: "Stream key",
        scopes: [Inference],
        allowed_models: ["model-stream"],
        expires_unix_ms: @async.now() + 60000L,
        maximum_requests: 10L,
      },
      @async.now(),
    )
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{runtime_server.addr}/v1/responses",
      "upstream-secret",
      "runtime-v1",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allow_http_loopback=true,
    )
    let service = @api.ApiService::new(
        durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
      )
      .with_access_store(access)
      .with_legacy_unbound_access_for_local_testing()
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      service.serve_on(api_server)
    }
    let client = @http.post_stream(
      "http://\{api_server.addr}/v1/chat/completions",
      headers={
        "Authorization": "Bearer \{issued.secret}",
        "Content-Type": "application/json",
      },
    )
    defer client.close()
    let chat : Json = {
      "model": "model-stream",
      "messages": [{ "role": "user", "content": "hello" }],
      "tools": [
        {
          "type": "function",
          "function": {
            "name": "read_file",
            "description": "Read a workspace file",
            "parameters": {
              "type": "object",
              "properties": { "path": { "type": "string" } },
              "required": ["path"],
            },
          },
        },
      ],
      "tool_choice": "auto",
      "parallel_tool_calls": false,
      "stream": true,
    }
    client.write(chat)
    let response = client.end_request()
    assert_eq(response.code, 200)
    assert_true(
      response.headers
      .get("content-type")
      .unwrap_or("")
      .contains("text/event-stream"),
    )
    let stream = client.read_all().text()
    assert_true(stream.contains("chat.completion.chunk"))
    assert_true(stream.contains("\"content\":\"hello\""))
    assert_true(stream.contains("\"tool_calls\":["))
    assert_true(stream.contains("\"name\":\"read_file\""))
    assert_true(stream.contains("README.md"))
    assert_true(stream.contains("\"finish_reason\":\"tool_calls\""))
    assert_false(stream.contains("{\\\"text_delta\\\":\\\"hello\\\"}"))
    assert_true(stream.contains("lunanexa_receipt"))
    assert_true(stream.contains("data: [DONE]"))
    assert_false(stream.contains("WorkloadStreamEvent"))
    api_server.close()
    runtime_server.close()
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "commercial API exposes tenant-scoped cost ledger vertical slice" {
  let directory = @fs.tmpdir(prefix="lunanexa-commercial-api-")
  let service = expansion_service("\{directory}/state.json")
  let headers = { "Authorization": "Bearer operator-token" }
  let organization : @commercial.Organization = {
    organization_id: "org-one",
    display_name: "Organization One",
    state: Active,
    verification_ref: Some("opaque-verification-reference"),
    legal_profile: None,
    created_unix_ms: 1000L,
  }
  let organization_reply = service.handle(
    Post,
    "/v1/commercial/organizations",
    headers,
    organization.to_json().stringify(),
  )
  assert_eq(organization_reply.status, 201)
  let center : @commercial.CostCenter = {
    cost_center_id: "center-ai",
    organization_id: "org-one",
    parent_cost_center_id: None,
    display_name: "AI Platform",
    created_unix_ms: 1001L,
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/commercial/cost-centers",
      headers,
      center.to_json().stringify(),
    ).status,
    201,
  )
  let project : @commercial.Project = {
    project_id: "project-maas",
    organization_id: "org-one",
    cost_center_id: "center-ai",
    display_name: "Managed inference",
    created_unix_ms: 1002L,
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/commercial/projects",
      headers,
      project.to_json().stringify(),
    ).status,
    201,
  )
  let usage : @commercial.UsageObservation = {
    event_id: "usage-one",
    organization_id: "org-one",
    project_id: "project-maas",
    actor_ref: "opaque-user",
    workload_id: "deployment-one",
    node_id: "dgx-2",
    lease_epoch: 4L,
    meter: "node-second",
    quantity: 60L,
    unit: "second",
    started_unix_ms: 2000L,
    ended_unix_ms: 62000L,
    observed_unix_ms: 62001L,
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/commercial/usage",
      headers,
      usage.to_json().stringify(),
    ).status,
    201,
  )
  let rate : @commercial.RateCard = {
    rate_card_id: "rate-node-second",
    version: "v1",
    meter: "node-second",
    unit: "second",
    unit_price: @commercial.money(2L, "CNY", 2),
    effective_from_unix_ms: 1L,
    effective_until_unix_ms: 100000L,
  }
  let rated = service.handle(
    Post,
    "/v1/commercial/usage:rate",
    headers,
    (
      {
        "event_id": "usage-one",
        "entry_id": "entry-one",
        "rate": rate.to_json(),
        "recorded_unix_ms": 62002L.to_json(),
      } : Json).stringify(),
  )
  assert_eq(rated.status, 201)
  assert_true(rated.body.contains("entry-one"))
  let snapshot = service.handle(
    Get,
    "/v1/commercial/organizations/org-one/snapshot",
    headers,
    "",
  )
  assert_eq(snapshot.status, 200)
  assert_true(snapshot.body.contains("project-maas"))
  let unauthorized = service.handle(
    Get,
    "/v1/commercial/organizations/org-one/snapshot",
    {},
    "",
  )
  assert_eq(unauthorized.status, 401)
}

///|
async test "technical API has no autoscaling surface under fixed fleet policy" {
  let directory = @fs.tmpdir(prefix="lunanexa-technical-api-")
  let service = expansion_service("\{directory}/state.json")
  let headers = { "Authorization": "Bearer operator-token" }
  let reply = service.handle(
    Post,
    "/v1/technical/autoscale:decide",
    headers,
    "{}",
  )
  assert_eq(reply.status, 404)
  let unauthorized = service.handle(
    Post,
    "/v1/technical/autoscale:decide",
    {},
    "{}",
  )
  assert_eq(unauthorized.status, 401)
}
