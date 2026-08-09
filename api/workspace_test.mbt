///|
fn workspace_api_request(
  workload_id : String,
  idempotency_key : String,
) -> @contracts.WorkloadEnvelope {
  {
    version: @contracts.contract_version,
    idempotency_key,
    workload_id,
    tenant_ref: "tenant-workspace",
    credential_scope: "workspace-inference",
    capability: TextGenerate,
    model_selector: "text.default",
    payload: { "prompt": "workspace acceptance" },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: @async.now() + 10000L,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: 128,
      max_output_units: 16,
      max_runtime_ms: 2000L,
      max_accelerator_memory_mib: 1024,
    },
    stream: false,
    output_format: "text",
    trace_token: "workspace-trace",
  }
}

///|
fn workspace_api_user(
  subject_ref : String,
  now : Int64,
) -> @workspace.WorkspaceUser {
  {
    version: @workspace.contract_version,
    user_id: "user-workspace",
    subject_ref,
    display_name: "Workspace User",
    email: "workspace@example.invalid",
    state: UserActive,
    created_unix_ms: now,
    last_active_unix_ms: None,
    identity_receipt: "identity-workspace",
  }
}

///|
fn workspace_api_grant(now : Int64) -> @workspace.WorkspaceAccessGrant {
  {
    version: @workspace.contract_version,
    grant_id: "grant-workspace",
    user_id: "user-workspace",
    tenant_ref: "tenant-workspace",
    access: Developer,
    starts_unix_ms: now - 1000L,
    expires_unix_ms: now + 60000L,
    state: GrantActive,
    policy_receipt: "grant-policy-workspace",
  }
}

///|
fn workspace_api_lease(now : Int64) -> @workspace.WorkspaceLease {
  {
    version: @workspace.contract_version,
    lease_id: "lease-workspace",
    tenant_ref: "tenant-workspace",
    subject_ref: "subject-workspace",
    access: Developer,
    limits: {
      max_active_sessions: 2,
      max_session_duration_ms: 60000L,
      capabilities: [
        {
          capability: TextGenerate,
          max_concurrent_requests: 2,
          max_requests_per_hour: 100,
          max_input_units_per_request: 128,
          max_output_units_per_request: 128,
        },
      ],
    },
    starts_unix_ms: now - 1000L,
    expires_unix_ms: now + 60000L,
    state: Active,
    policy_receipt: "lease-policy-workspace",
  }
}

///|
fn workspace_api_runtime(
  endpoint : String,
) -> @runtimes.OpenAiTextRuntime raise {
  @runtimes.OpenAiTextRuntime::new(
    endpoint,
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
}

///|
async test "workspace API persists authority and enforces it before runtime" {
  let temp = @fs.tmpdir(prefix="lunanexa-workspace-api-")
  let workspace_path = "\{temp}/workspace.json"
  let state_path = "\{temp}/state.json"
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let api_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let runtime_calls = [0]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever() <| ((_request, body, connection) => {
        runtime_calls[0] += 1
        assert_true(body.read_all().text().contains("workspace acceptance"))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          "{\"output_text\":\"workspace result\",\"usage\":{\"input_tokens\":2,\"output_tokens\":2}}",
        )
        connection.end_response()
      })
    }
    let now = @async.now()
    let directory = @directory.FileWorkspaceDirectory::open(
      workspace_path,
      now_unix_ms=now,
    )
    let service = @api.ApiService::new(
      @store.FileStore::open(state_path),
      workspace_api_runtime("http://\{runtime_server.addr}/v1/responses"),
      "operator-token",
      "inference-token",
      "",
      "0.1.0",
    ).with_workspace_directory(directory, true)
    let operator_headers = {
      "Authorization": "Bearer operator-token",
      "Content-Type": "application/json",
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      service.serve_on(api_server)
    }
    assert_eq(service.handle(Get, "/v1/workspace", Map([]), "").status, 401)
    assert_eq(
      service.handle(
        Post,
        "/v1/workspace/users",
        operator_headers,
        workspace_api_user("subject-workspace", now).to_json().stringify(),
      ).status,
      201,
    )
    assert_eq(
      service.handle(
        Post,
        "/v1/workspace/access-grants",
        operator_headers,
        workspace_api_grant(now).to_json().stringify(),
      ).status,
      201,
    )
    let requested_lease : @workspace.WorkspaceLease = {
      ..workspace_api_lease(now),
      lease_id: "lease-requested",
      state: Requested,
    }
    assert_eq(
      service.handle(
        Post,
        "/v1/workspace/leases",
        operator_headers,
        requested_lease.to_json().stringify(),
      ).status,
      201,
    )
    let activated_lease = service.handle(
      Post,
      "/v1/workspace/leases/lease-requested:activate",
      operator_headers,
      "",
    )
    assert_eq(activated_lease.status, 200)
    let activated_lease_record : @workspace.WorkspaceLease = @json.from_json(
      @json.parse(activated_lease.body),
    )
    assert_eq(activated_lease_record.state, Active)
    assert_eq(
      service.handle(
        Post,
        "/v1/workspace/leases/lease-requested:end",
        operator_headers,
        "",
      ).status,
      200,
    )
    let suspended = service.handle(
      Post,
      "/v1/workspace/users/user-workspace:suspend",
      operator_headers,
      "",
    )
    assert_eq(suspended.status, 200)
    let suspended_user : @workspace.WorkspaceUser = @json.from_json(
      @json.parse(suspended.body),
    )
    assert_eq(suspended_user.state, UserSuspended)
    let activated_user = service.handle(
      Post,
      "/v1/workspace/users/user-workspace:activate",
      operator_headers,
      "",
    )
    assert_eq(activated_user.status, 200)
    let activated_user_record : @workspace.WorkspaceUser = @json.from_json(
      @json.parse(activated_user.body),
    )
    assert_eq(activated_user_record.state, UserActive)
    assert_eq(
      service.handle(
        Post,
        "/v1/workspace/leases",
        operator_headers,
        workspace_api_lease(now).to_json().stringify(),
      ).status,
      201,
    )
    let snapshot = service.handle(Get, "/v1/workspace", operator_headers, "")
    assert_eq(snapshot.status, 200)
    assert_true(snapshot.body.contains("grant-workspace"))
    assert_false(snapshot.body.contains("runtime-secret"))
    let self_headers = {
      "aUtHoRiZaTiOn": "Bearer inference-token",
      "X-LuNaNeXa-SuBjEcT": "subject-workspace",
    }
    let self_reply = service.handle(Get, "/v1/workspace/self", self_headers, "")
    assert_eq(self_reply.status, 200)
    let self_view : @workspace.WorkspaceSelfContract = @json.from_json(
      @json.parse(self_reply.body),
    )
    assert_true(self_view.authorized)
    assert_eq(self_view.active_lease.unwrap().lease_id, "lease-workspace")
    assert_eq(
      service.handle(
        Get,
        "/v1/workspace/self",
        {
          "Authorization": "Bearer inference-token",
          "X-LunaNexa-Subject": "forged-subject",
        },
        "",
      ).status,
      403,
    )
    let (stream_missing_subject, _) = @http.post(
      "http://\{api_server.addr}/v1/workloads:stream",
      workspace_api_request(
        "workspace-stream-missing", "workspace-stream-missing-key",
      ).to_json(),
      headers={
        "Authorization": "Bearer inference-token",
        "Content-Type": "application/json",
      },
    )
    assert_eq(stream_missing_subject.code, 401)
    let missing_subject = service.handle(
      Post,
      "/v1/workloads",
      { "Authorization": "Bearer inference-token" },
      workspace_api_request(
        "workspace-missing-subject", "workspace-missing-subject-key",
      )
      .to_json()
      .stringify(),
    )
    assert_eq(missing_subject.status, 401)
    assert_eq(runtime_calls[0], 0)
    let accepted = service.handle(
      Post,
      "/v1/workloads",
      self_headers,
      workspace_api_request("workspace-authorized", "workspace-authorized-key")
      .to_json()
      .stringify(),
    )
    assert_eq(accepted.status, 200)
    let response : @contracts.WorkloadResponse = @json.from_json(
      @json.parse(accepted.body),
    )
    assert_eq(response.state, Succeeded)
    assert_eq(runtime_calls[0], 1)
    assert_eq(
      service.handle(
        Get,
        "/v1/workloads/workspace-authorized",
        self_headers,
        "",
      ).status,
      200,
    )
    let wrong_subject_status = service.handle(
      Get,
      "/v1/workloads/workspace-authorized",
      {
        "Authorization": "Bearer inference-token",
        "X-LunaNexa-Subject": "subject-other",
      },
      "",
    )
    assert_eq(wrong_subject_status.status, 404)
    let ended = service.handle(
      Post,
      "/v1/workspace/leases/lease-workspace:end",
      operator_headers,
      "",
    )
    assert_eq(ended.status, 200)
    let denied = service.handle(
      Post,
      "/v1/workloads",
      self_headers,
      workspace_api_request("workspace-ended", "workspace-ended-key")
      .to_json()
      .stringify(),
    )
    assert_eq(denied.status, 403)
    assert_eq(runtime_calls[0], 1)
    let (stream_revoked, _) = @http.post(
      "http://\{api_server.addr}/v1/workloads:stream",
      workspace_api_request(
        "workspace-stream-revoked", "workspace-stream-revoked-key",
      ).to_json(),
      headers={
        "Authorization": "Bearer inference-token",
        "X-LunaNexa-Subject": "subject-workspace",
        "Content-Type": "application/json",
      },
    )
    assert_eq(stream_revoked.code, 403)
    let revoked_grant = service.handle(
      Post,
      "/v1/workspace/access-grants/grant-workspace:revoke",
      operator_headers,
      "",
    )
    assert_eq(revoked_grant.status, 200)
    assert_true(revoked_grant.body.contains("GrantRevoked"))
    let revoked_user = service.handle(
      Post,
      "/v1/workspace/users/user-workspace:revoke",
      operator_headers,
      "",
    )
    assert_eq(revoked_user.status, 200)
    assert_true(revoked_user.body.contains("UserRevoked"))
    assert_eq(
      service.handle(
        Post,
        "/v1/workspace/users/user-workspace:activate",
        operator_headers,
        "",
      ).status,
      409,
    )
    let audit = service.handle(Get, "/v1/audit", operator_headers, "")
    assert_eq(audit.status, 200)
    assert_true(audit.body.contains("workspace.user.suspend"))
    assert_true(audit.body.contains("workspace.user.activate"))
    assert_true(audit.body.contains("workspace.user.revoke"))
    assert_true(audit.body.contains("workspace.lease.activate"))
    let reopened = @directory.FileWorkspaceDirectory::open(
      workspace_path,
      now_unix_ms=@async.now(),
    )
    let restarted = @api.ApiService::new(
      @store.FileStore::open(state_path),
      workspace_api_runtime("http://\{runtime_server.addr}/v1/responses"),
      "operator-token",
      "inference-token",
      "",
      "0.1.0",
    ).with_workspace_directory(reopened, true)
    let restart_snapshot = restarted.handle(
      Get,
      "/v1/workspace",
      operator_headers,
      "",
    )
    assert_eq(restart_snapshot.status, 200)
    assert_true(restart_snapshot.body.contains("lease-workspace"))
    assert_true(restart_snapshot.body.contains("Revoked"))
    assert_eq(
      restarted.handle(
        Get,
        "/v1/workloads/workspace-authorized",
        self_headers,
        "",
      ).status,
      200,
    )
    api_server.close()
    runtime_server.close()
  }
  @fs.rmdir(temp, recursive=true)
}

///|
async test "expired workspace lease is reconciled before workload admission" {
  let temp = @fs.tmpdir(prefix="lunanexa-workspace-expiry-api-")
  let now = @async.now()
  let directory = @directory.FileWorkspaceDirectory::open(
    "\{temp}/workspace.json",
    now_unix_ms=now,
  )
  ignore(directory.create_user(workspace_api_user("subject-workspace", now)))
  ignore(directory.issue_access_grant(workspace_api_grant(now), now))
  ignore(
    directory.issue_lease(
      { ..workspace_api_lease(now), expires_unix_ms: now + 40L },
      now,
    ),
  )
  let service = @api.ApiService::new(
    @store.FileStore::open("\{temp}/state.json"),
    workspace_api_runtime("http://127.0.0.1:9/v1/responses"),
    "operator-token",
    "inference-token",
    "",
    "0.1.0",
  ).with_workspace_directory(directory, true)
  @async.sleep(60)
  let headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-workspace",
  }
  let self_reply = service.handle(Get, "/v1/workspace/self", headers, "")
  assert_eq(self_reply.status, 200)
  let self_view : @workspace.WorkspaceSelfContract = @json.from_json(
    @json.parse(self_reply.body),
  )
  assert_false(self_view.authorized)
  assert_eq(self_view.readiness, LeaseUnavailable)
  let denied = service.handle(
    Post,
    "/v1/workloads",
    headers,
    workspace_api_request("workspace-expired", "workspace-expired-key")
    .to_json()
    .stringify(),
  )
  assert_eq(denied.status, 403)
  @fs.rmdir(temp, recursive=true)
}

///|
async test "actual canonical payload bytes cannot bypass declared or lease input limits" {
  let temp = @fs.tmpdir(prefix="lunanexa-workspace-input-limit-api-")
  let now = @async.now()
  let directory = @directory.FileWorkspaceDirectory::open(
    "\{temp}/workspace.json",
    now_unix_ms=now,
  )
  ignore(directory.create_user(workspace_api_user("subject-workspace", now)))
  ignore(directory.issue_access_grant(workspace_api_grant(now), now))
  let base_lease = workspace_api_lease(now)
  let base_limit = base_lease.limits.capabilities[0]
  ignore(
    directory.issue_lease(
      {
        ..base_lease,
        limits: {
          ..base_lease.limits,
          capabilities: [{ ..base_limit, max_input_units_per_request: 64 }],
        },
      },
      now,
    ),
  )
  let service = @api.ApiService::new(
    @store.FileStore::open("\{temp}/state.json"),
    workspace_api_runtime("http://127.0.0.1:9/v1/responses"),
    "operator-token",
    "inference-token",
    "",
    "0.1.0",
  ).with_workspace_directory(directory, true)
  let headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-workspace",
  }
  let oversized_payload : Json = {
    "input": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
  }
  let under_declared : @contracts.WorkloadEnvelope = {
    ..workspace_api_request("workspace-under-declared", "workspace-under-key"),
    payload: oversized_payload,
    resource_ceiling: {
      ..workspace_api_request("unused-a", "unused-b").resource_ceiling,
      max_input_units: 1,
    },
  }
  let under_declared_reply = service.handle(
    Post,
    "/v1/workloads",
    headers,
    under_declared.to_json().stringify(),
  )
  assert_eq(under_declared_reply.status, 400)
  assert_true(under_declared_reply.body.contains("declared input ceiling"))
  let over_lease : @contracts.WorkloadEnvelope = {
    ..workspace_api_request("workspace-over-lease", "workspace-over-lease-key"),
    payload: oversized_payload,
    resource_ceiling: {
      ..workspace_api_request("unused-c", "unused-d").resource_ceiling,
      max_input_units: 512,
    },
  }
  let over_lease_reply = service.handle(
    Post,
    "/v1/workloads",
    headers,
    over_lease.to_json().stringify(),
  )
  assert_eq(over_lease_reply.status, 403)
  assert_true(over_lease_reply.body.contains("active workspace lease"))
  @fs.rmdir(temp, recursive=true)
}

///|
async test "active cancellation requires durable subject ownership" {
  let temp = @fs.tmpdir(prefix="lunanexa-workspace-cancel-owner-api-")
  let runtime_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      runtime_server.run_forever(allow_failure=true) <| ((
        _request,
        body,
        connection,
      ) => {
        ignore(body.read_all())
        @async.sleep(500)
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          "{\"output_text\":\"late result\",\"usage\":{\"input_tokens\":2,\"output_tokens\":2}}",
        )
        connection.end_response()
      })
    }
    let now = @async.now()
    let directory = @directory.FileWorkspaceDirectory::open(
      "\{temp}/workspace.json",
      now_unix_ms=now,
    )
    ignore(directory.create_user(workspace_api_user("subject-workspace", now)))
    ignore(directory.issue_access_grant(workspace_api_grant(now), now))
    ignore(directory.issue_lease(workspace_api_lease(now), now))
    let service = @api.ApiService::new(
      @store.FileStore::open("\{temp}/state.json"),
      workspace_api_runtime("http://\{runtime_server.addr}/v1/responses"),
      "operator-token",
      "inference-token",
      "",
      "0.1.0",
    ).with_workspace_directory(directory, true)
    let request = workspace_api_request(
      "workspace-cancel-owned", "workspace-cancel-owned-key",
    )
    let owner_headers = {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "subject-workspace",
    }
    let invocation = group.spawn(() => {
      service.handle(
        Post,
        "/v1/workloads",
        owner_headers,
        request.to_json().stringify(),
      )
    })
    @async.sleep(100)
    let wrong_subject = service.handle(
      Post,
      "/v1/workloads/workspace-cancel-owned/cancel",
      {
        "Authorization": "Bearer inference-token",
        "X-LunaNexa-Subject": "subject-other",
      },
      "",
    )
    assert_eq(wrong_subject.status, 404)
    assert_true(wrong_subject.body.contains("workload receipt was not found"))
    let cancelled = service.handle(
      Post,
      "/v1/workloads/workspace-cancel-owned/cancel",
      owner_headers,
      "",
    )
    assert_eq(cancelled.status, 202)
    let completed = invocation.wait()
    assert_eq(completed.status, 200)
    let response : @contracts.WorkloadResponse = @json.from_json(
      @json.parse(completed.body),
    )
    assert_eq(response.state, Cancelled)
    runtime_server.close()
  }
  @fs.rmdir(temp, recursive=true)
}

///|
async test "verified auth-TLS subject is opaque and failed verification denies" {
  let temp = @fs.tmpdir(prefix="lunanexa-workspace-mtls-api-")
  let now = @async.now()
  let raw_dn = "CN=developer,O=LunaNexa"
  let subject_ref = "mtls:sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(raw_dn)))}"
  let directory = @directory.FileWorkspaceDirectory::open(
    "\{temp}/workspace.json",
    now_unix_ms=now,
  )
  ignore(directory.create_user(workspace_api_user(subject_ref, now)))
  let service = @api.ApiService::new(
    @store.FileStore::open("\{temp}/state.json"),
    workspace_api_runtime("http://127.0.0.1:9/v1/responses"),
    "operator-token",
    "inference-token",
    "",
    "0.1.0",
  ).with_workspace_directory(directory, false)
  let verified = service.handle(
    Get,
    "/v1/workspace/self",
    {
      "Authorization": "Bearer inference-token",
      "SSL-CLIENT-VERIFY": "SUCCESS",
      "SSL-CLIENT-SUBJECT-DN": "  \{raw_dn}  ",
      "X-LunaNexa-Subject": "forged-fallback",
    },
    "",
  )
  assert_eq(verified.status, 200)
  assert_true(verified.body.contains(subject_ref))
  assert_false(verified.body.contains(raw_dn))
  let failed = service.handle(
    Get,
    "/v1/workspace/self",
    {
      "Authorization": "Bearer inference-token",
      "ssl-client-verify": "FAILED",
      "ssl-client-subject-dn": raw_dn,
      "X-LunaNexa-Subject": subject_ref,
    },
    "",
  )
  assert_eq(failed.status, 401)
  @fs.rmdir(temp, recursive=true)
}
