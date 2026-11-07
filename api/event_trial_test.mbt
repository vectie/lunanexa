///|
async fn exercise_event_trial(
  external~ : Bool,
  private_enroll~ : Bool = false,
  ongoing~ : Bool = false,
) -> Unit {
  let directory = @fs.tmpdir(prefix="event-trial-api-")
  let servers = [
    for _ in 0..<4 => @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  ]
  let routed : Array[String] = []
  let nodes = ["node-a", "node-b", "node-c", "node-d"]
  let unhealthy : Array[String] = []
  @async.with_task_group <| group => {
    for index, server in servers {
      group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
        server.run_forever() <| ((request, body, connection) => {
          ignore(body.read_all())
          let path = request.path
          if path == "/health" || path == "/v1/models" {
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write_string(
              if path == "/health" {
                "{}"
              } else {
                (
                  {
                    "data": [
                      {
                        "id": if unhealthy.contains(nodes[index]) {
                          "wrong-model"
                        } else {
                          "text-served"
                        },
                      },
                    ],
                  } : Json).stringify()
              },
            )
            connection.end_response()
            return
          }
          routed.push(
            if external {
              nodes[index]
            } else {
              request.headers.get("x-lunanexa-target-node").unwrap_or("missing")
            },
          )
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write_string(
            "{\"output_text\":\"event model result\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2}}",
          )
          connection.end_response()
        })
      }
    }
    let store = @store.FileStore::open("\{directory}/control.json")
    store.fence_controller(1L)
    let registry = @registry.FileRegistry::open("\{directory}/registry.json")
    configure_schedulable_model(registry)
    let scheduler = @scheduler.FileScheduler::open(
      "\{directory}/scheduler.json",
      16,
    )
    let telemetry = @telemetry.FileTelemetry::open(
      "\{directory}/telemetry.json",
    )
    let enrollment = @node.FileEnrollmentService::open(
      "\{directory}/enrollment.json",
    )
    let accounts = @account.AccountStore::open(
      "\{directory}/accounts.json",
      "event-account-secret-over-thirty-two-bytes",
    )
    let access = @access.AccessStore::open(
      "\{directory}/access.json",
      "event-api-key-secret-over-thirty-two-bytes",
    )
    let workspace = @directory.FileWorkspaceDirectory::open(
      "\{directory}/workspace.json",
    )
    let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://\{servers[0].addr}/v1/responses",
      "runtime-secret",
      "runtime-v1",
      "sha256:" + "b".repeat(64),
      "sha256:" + "a".repeat(64),
      allow_http_loopback=true,
    ).with_node_endpoints(
      [
        for i, node in nodes => {
          { node_id: node, endpoint: "http://\{servers[i].addr}/v1/responses", }
        }
      ],
    )
    let service = @api.ApiService::with_control_plane(
        store, registry, enrollment, scheduler, telemetry, runtime, "operator-token",
        "inference-token", "node-token", "test",
      )
      .with_account_store(
        accounts, "event-assertion-secret-over-thirty-two-bytes",
      )
      .with_portal_store(portal)
      .with_workspace_directory(workspace, true)
      .with_access_store(access)
      .with_private_cloud_workspace_access(ongoing)
    let service = if external {
      service.with_event_text_pool(
        {
          model_alias: "text.default",
          served_model: "text-served",
          runtime_version: "external-vllm-v1",
          image_digest: "sha256:" + "c".repeat(64),
          artifact_digest: "sha256:" + "a".repeat(64),
          replicas: nodes.mapi((i, node_id) => {
            node_id,
            origin: "http://\{servers[i].addr}",
          }),
        },
        "external-test-credential",
      )
    } else {
      service
    }
    let now = @async.now()
    let policy : @event_trial.Policy = {
      event_id: "weekend",
      title: "未来社区 weekend",
      starts_unix_ms: now - 1000L,
      expires_unix_ms: if ongoing {
        0L
      } else {
        now + 86400000L
      },
      maximum_users: if ongoing {
        0
      } else {
        2
      },
      maximum_requests: if ongoing {
        0L
      } else {
        20L
      },
      allowed_models: ["text.default"],
      node_ids: nodes,
      per_node_concurrency: 0,
      max_input_bytes: Some(32768),
      max_output_tokens: None,
      registration_open: false,
    }
    let operator = { "Authorization": "Bearer operator-token" }
    assert_eq(
      service.handle(
        Post,
        "/v1/accounts/event-trials",
        Map([]),
        Json(policy).stringify(),
      ).status,
      401,
    )
    assert_eq(
      service.handle(
        Post,
        "/v1/accounts/event-trials",
        operator,
        Json(policy).stringify(),
      ).status,
      200,
    )
    let open = { ..policy, registration_open: true, }
    assert_eq(
      service.handle(
        Post,
        "/v1/accounts/event-trials",
        operator,
        Json(open).stringify(),
      ).status,
      409,
    )
    for node in nodes {
      if !external {
        store.put_assignment({
          ..api_assignment(),
          assignment_id: "assignment-\{node}",
          deployment_id: "deployment-\{node}",
          node_id: node,
        })
      }
      let heartbeat = schedulable_heartbeat(Active, node_id=node)
      heartbeat.inventory.labels["lunanexa.io/usage-pool"] = "trial"
      store.put_heartbeat({
        ..heartbeat,
        // Accepted clock skew must not flap readiness on either routing path.
        timestamp_unix_ms: @async.now() + 1000L,
        running_deployments: if external {
          []
        } else {
          ["deployment-\{node}"]
        },
      })
    }
    let opening = service.handle(
      Post,
      "/v1/accounts/event-trials",
      operator,
      Json(open).stringify(),
    )
    assert_eq(opening.status, 200, msg=opening.body)
    if private_enroll {
      assert_eq(
        service.handle(
          Post,
          "/v1/accounts/event-trials",
          operator,
          Json(policy).stringify(),
        ).status,
        200,
      )
    }
    let registered = accounts.register_open(
      "https://identity.example", "visitor", "visitor-event-assertion", "Visitor",
      "visitor@example.invalid", 60000L, now,
    )
    let headers = { "Authorization": "Bearer \{registered.session.secret}" }
    if private_enroll {
      let invite_path = "/v1/accounts/event-trials/weekend/participants"
      let invite_body = (
        { "account_id": Json(registered.account.account_id) } : Json).stringify()
      assert_eq(
        service.handle(Post, invite_path, headers, invite_body).status,
        401,
      )
      assert_eq(
        service.handle(Post, "/v1/auth/event-trial:redeem", headers, "{}").status,
        409,
      )
      let invited = service.handle(Post, invite_path, operator, invite_body)
      assert_eq(invited.status, 201, msg=invited.body)
      assert_eq(
        service.handle(Post, invite_path, operator, invite_body).body,
        invited.body,
      )
      assert_true(
        accounts.snapshot().events.unwrap().all(e => !e.registration_open),
      )
    }
    assert_eq(
      service.handle(
        Post,
        "/v1/accounts/event-trials",
        headers,
        Json(open).stringify(),
      ).status,
      401,
    )
    let redeemed = service.handle(
      Post,
      "/v1/auth/event-trial:redeem",
      headers,
      "{}",
    )
    assert_eq(redeemed.status, 200, msg=redeemed.body)
    let trial : @account.TrialEntitlement = @json.from_json(
      @json.parse(redeemed.body),
    )
    assert_eq(trial.event_id, Some("weekend"))
    assert_eq(trial.expires_unix_ms, policy.grant_expires(trial.starts_unix_ms))
    assert_false(redeemed.body.contains("node-a"))
    let granted = workspace.snapshot(now)
    assert_eq(granted.leases.length(), 1)
    assert_eq(
      granted.leases[0].limits.capabilities[0].max_concurrent_requests,
      1,
    )
    assert_eq(
      granted.leases[0].limits.capabilities[0].max_input_units_per_request,
      32768,
    )
    assert_eq(granted.leases[0].expires_unix_ms, trial.expires_unix_ms)
    let self_view = service.handle(Get, "/v1/workspace/self", headers, "")
    assert_eq(self_view.status, 200, msg=self_view.body)
    let self_contract : @workspace.WorkspaceSelfContract = @json.from_json(
      @json.parse(self_view.body),
    )
    assert_true(self_contract.authorized)
    assert_true(self_contract.readiness is WorkspaceReady)
    let effective_settings = service.handle(
      Get,
      "/v1/settings/effective",
      headers,
      "",
    )
    assert_eq(effective_settings.status, 200, msg=effective_settings.body)
    assert_eq(
      service.handle(Get, "/v1/settings/admin", headers, "").status,
      401,
    )
    assert_eq(
      service.handle(Get, "/v1/settings/effective", Map([]), "").status,
      401,
    )
    if ongoing {
      assert_eq(
        granted.leases[0].limits.capabilities[0].max_requests_per_hour,
        0,
      )
    }
    let request = {
      ..api_request(),
      tenant_ref: trial.tenant_ref,
      resource_ceiling: {
        ..api_request().resource_ceiling,
        max_input_units: 24576,
      },
    }
    for i in 0..<8 {
      let workload = {
        ..request,
        workload_id: "event-work-\{i}",
        idempotency_key: "event-request-\{i}",
      }
      let response = service.handle(
        Post,
        "/v1/portal/self/trial/workloads",
        headers,
        Json(workload).stringify(),
      )
      assert_eq(response.status, 200, msg=response.body)
      assert_true(response.body.contains("event model result"))
    }
    for node in nodes {
      assert_eq(routed.count(node), 2)
    }
    if external {
      // A responsive endpoint advertising another model is not a healthy replica.
      unhealthy.push("node-d")
      let degraded = service.handle(
        Get,
        "/v1/accounts/event-trials",
        operator,
        "",
      )
      assert_eq(degraded.status, 200)
      assert_true(
        degraded.body.contains(
          "node-d: runtime health or served model verification failed",
        ),
      )
      assert_false(
        degraded.body.contains(
          "\"ready_nodes\":[\"node-a\",\"node-b\",\"node-c\",\"node-d\"]",
        ),
      )
      assert_eq(
        service.handle(
          Post,
          "/v1/accounts/event-trials",
          operator,
          Json(open).stringify(),
        ).status,
        409,
      )
      unhealthy.clear()
    }
    let issued_reply = service.handle(
      Post,
      "/v1/portal/self/api-keys",
      headers,
      (
        {
          "key_id": "event-visitor-key",
          "project_id": trial.project_id,
          "display_name": "Event model access",
          "scopes": ["ModelList", "Inference"],
          "allowed_models": ["text.default"],
          "expires_unix_ms": Json(trial.expires_unix_ms),
          "lifetime_days": 7,
          "maximum_requests": Json(trial.maximum_requests),
        } : Json).stringify(),
    )
    assert_eq(issued_reply.status, 201, msg=issued_reply.body)
    let issued : @access.IssuedApiKeyView = @json.from_json(
      @json.parse(issued_reply.body),
    )
    assert_eq(issued.credential.expires_unix_ms, trial.expires_unix_ms)
    assert_eq(
      accounts.trial_for_account(registered.account.account_id).unwrap().api_key_id,
      Some(issued.credential.key_id),
    )
    let chat = service.handle(
      Post,
      "/v1/chat/completions",
      { "Authorization": "Bearer \{issued.secret}" },
      (
        {
          "model": "text.default",
          "messages": [{ "role": "user", "content": "Hello" }],
        } : Json).stringify(),
    )
    assert_eq(chat.status, 200, msg=chat.body)
    assert_true(chat.body.contains("event model result"))
    // Cordon one replica: the next call must stay in the remaining pool.
    let hb = schedulable_heartbeat(Cordoned, node_id="node-a")
    hb.inventory.labels["lunanexa.io/usage-pool"] = "trial"
    store.put_heartbeat({ ..hb, running_deployments: ["deployment-node-a"], })
    let after_cordon = service.handle(
      Post,
      "/v1/portal/self/trial/workloads",
      headers,
      Json({
        ..request,
        workload_id: "after-cordon",
        idempotency_key: "after-cordon",
      }).stringify(),
    )
    assert_eq(after_cordon.status, 200, msg=after_cordon.body)
    assert_true(routed.last() != Some("node-a"))
    if ongoing {
      let summary = service.handle(
        Get,
        "/v1/accounts/trial-summary",
        operator,
        "",
      )
      assert_eq(summary.status, 200)
      guard @json.parse(summary.body)
        is {
          "participants": Array(
            [{ "requests": "10", "display_name": "Visitor", .. }]
          ),
          ..
        } else {
        fail(
          "trial calls were not attributed to the individual: " + summary.body,
        )
      }
      assert_false(summary.body.contains(issued.secret))
      assert_eq(
        service.handle(Get, "/v1/accounts/trial-summary", headers, "").status,
        401,
      )
    }
    // A degraded event may continue serving but cannot enroll a new visitor.
    let next = accounts.register_open(
      "https://identity.example",
      "visitor-two",
      "visitor-event-assertion-two",
      "Next",
      "next@example.invalid",
      60000L,
      now + 1L,
    )
    assert_eq(
      service.handle(
        Post,
        "/v1/auth/event-trial:redeem",
        { "Authorization": "Bearer \{next.session.secret}" },
        "{}",
      ).status,
      409,
    )
    let wrong_model = service.handle(
      Post,
      "/v1/portal/self/trial/workloads",
      headers,
      Json({
        ..request,
        model_selector: "foreign.model",
        workload_id: "wrong-model",
        idempotency_key: "wrong-model",
      }).stringify(),
    )
    assert_eq(wrong_model.status, 403)
    let oversized = service.handle(
      Post,
      "/v1/portal/self/trial/workloads",
      headers,
      Json({
        ..request,
        workload_id: "oversized",
        idempotency_key: "oversized",
        resource_ceiling: {
          ..request.resource_ceiling,
          max_output_units: 1025,
        },
      }).stringify(),
    )
    assert_eq(oversized.status, 400)
    assert_true(oversized.body.contains("WorkspaceLimitExceeded"))
    assert_true(oversized.body.contains("output maximum 1024 tokens"))
    let oversized_api = service.handle(
      Post,
      "/v1/chat/completions",
      { "Authorization": "Bearer \{issued.secret}" },
      (
        {
          "model": "text.default",
          "messages": [{ "role": "user", "content": "Hello" }],
          "max_tokens": 4096,
        } : Json).stringify(),
    )
    assert_eq(oversized_api.status, 400, msg=oversized_api.body)
    assert_true(oversized_api.body.contains("WorkspaceLimitExceeded"))
    let oversized_input = service.handle(
      Post,
      "/v1/chat/completions",
      { "Authorization": "Bearer \{issued.secret}" },
      (
        {
          "model": "text.default",
          "messages": [{ "role": "user", "content": "a".repeat(32769) }],
          "max_tokens": 512,
        } : Json).stringify(),
    )
    assert_eq(oversized_input.status, 400, msg=oversized_input.body)
    assert_true(
      oversized_input.body.contains("input maximum 32768 UTF-8 bytes"),
    )
    let unplaceable = service.handle(
      Post,
      "/v1/portal/self/trial/workloads",
      headers,
      Json({
        ..request,
        workload_id: "unplaceable",
        idempotency_key: "unplaceable",
        data_policy: { ..request.data_policy, classification: Restricted, },
      }).stringify(),
    )
    assert_eq(unplaceable.status, 503, msg=unplaceable.body)
    assert_false(unplaceable.body.contains("node-a"))
    assert_false(unplaceable.body.contains("placement"))
    assert_eq(
      service.handle(
        Post,
        "/v1/accounts/event-trials",
        operator,
        Json(policy).stringify(),
      ).status,
      200,
    )
    let retry = service.handle(
      Post,
      "/v1/auth/event-trial:redeem",
      headers,
      "{}",
    )
    assert_eq(retry.status, 200)
    assert_eq(
      (@json.from_json(@json.parse(retry.body)) : @account.TrialEntitlement).expires_unix_ms,
      trial.expires_unix_ms,
    )
    assert_eq(scheduler.snapshot().active.length(), 0)
    let reopened = @account.AccountStore::open(
      "\{directory}/accounts.json",
      "event-account-secret-over-thirty-two-bytes",
    )
    assert_eq(reopened.event_for_tenant(trial.tenant_ref), Some(policy))
    // Editing only output length updates an already-issued lease and leaves
    // trial dates, key scope, counters and concurrency exactly intact.
    let before_trial = accounts
      .trial_for_account(registered.account.account_id)
      .unwrap()
    let enlarged = {
      ..policy,
      max_output_tokens: Some(8192),
      max_input_bytes: Some(65536),
    }
    assert_eq(
      service.handle(
        Post,
        "/v1/accounts/event-trials",
        headers,
        Json(enlarged).stringify(),
      ).status,
      401,
    )
    let changed = service.handle(
      Post,
      "/v1/accounts/event-trials",
      operator,
      Json(enlarged).stringify(),
    )
    assert_eq(changed.status, 200, msg=changed.body)
    assert_eq(
      accounts.trial_for_account(registered.account.account_id),
      Some(before_trial),
    )
    let updated_lease = workspace.snapshot(@async.now()).leases[0]
    assert_eq(updated_lease.expires_unix_ms, granted.leases[0].expires_unix_ms)
    assert_eq(updated_lease.limits.capabilities[0], {
      ..granted.leases[0].limits.capabilities[0],
      max_output_units_per_request: 8192,
      max_input_units_per_request: 65536,
    })
    let trial_projection = service.handle(Get, "/v1/auth/trial", headers, "")
    assert_eq(trial_projection.status, 200, msg=trial_projection.body)
    assert_true(
      @json.parse(trial_projection.body) is [{ "max_output_tokens": 8192, .. }],
      msg=trial_projection.body,
    )
    let long_request = service.handle(
      Post,
      "/v1/chat/completions",
      { "Authorization": "Bearer \{issued.secret}" },
      (
        {
          "model": "text.default",
          "messages": [{ "role": "user", "content": "a".repeat(32769) }],
          "max_tokens": 4096,
        } : Json).stringify(),
    )
    assert_eq(long_request.status, 200, msg=long_request.body)
    let too_long = service.handle(
      Post,
      "/v1/chat/completions",
      { "Authorization": "Bearer \{issued.secret}" },
      (
        {
          "model": "text.default",
          "messages": [{ "role": "user", "content": "Over configured budget" }],
          "max_tokens": 8193,
        } : Json).stringify(),
    )
    assert_eq(too_long.status, 400)
    let restored_workspace = @directory.FileWorkspaceDirectory::open(
      "\{directory}/workspace.json",
    )
    assert_eq(
      restored_workspace.snapshot(@async.now()).leases[0].limits.capabilities[0].max_output_units_per_request,
      8192,
    )
    for server in servers {
      server.close()
    }
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "event operator draft readiness registration model calls and replica fail closed" {
  exercise_event_trial(external=false)
}

///|
async test "external event replicas enforce real model health and balance without managed assignments" {
  exercise_event_trial(external=true)
}

///|
async test "event operator invitations exercise normal user access while public registration stays closed" {
  exercise_event_trial(external=true, private_enroll=true)
}

///|
async test "ongoing seven day trial supports uncapped key issuance and real gateway routes" {
  exercise_event_trial(external=true, ongoing=true)
}
