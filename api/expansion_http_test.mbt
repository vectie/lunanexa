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
  let service = expansion_service("\{directory}/state.json").with_access_store(
    access,
  )
  let operator = { "Authorization": "Bearer operator-token" }
  let intent : @access.ApiKeyIssueIntent = {
    key_id: "key-api-test",
    tenant_ref: "tenant-api-test",
    subject_ref: "subject-api-test",
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
  let issued : @access.IssuedApiKey = @json.from_json(
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
async test "scoped API key receives OpenAI-compatible SSE without platform batching" {
  let directory = @fs.tmpdir(prefix="lunanexa-openai-stream-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let api_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever(allow_failure=true) <| ((_, body, connection) => {
        assert_true(body.read_all().text().contains("\"stream\":true"))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write_string("data: {\"delta\":\"hello\"}\n\n")
        connection.write_string(
          "data: {\"delta\":\" world\",\"usage\":{\"input_tokens\":2,\"output_tokens\":2}}\n\n",
        )
        connection.write_string("data: [DONE]\n\n")
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
    ).with_access_store(access)
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
    assert_true(stream.contains("hello"))
    assert_true(stream.contains(" world"))
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
