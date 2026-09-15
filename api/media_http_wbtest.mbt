///|
async fn exercise_media_api(
  base : ApiService,
  root : String,
  secret : String,
  order : @machinecommerce.MachineOrder,
  now : Int64,
  private_cloud? : Bool = false,
) -> Unit {
  let root = if private_cloud { root + "/private-media" } else { root }
  if private_cloud {
    @fs.mkdir(root)
  }
  // This is an in-process node simulator. Keep its evidence fresh while the
  // HTTP fixture runs, just as a real node agent must. A one-shot heartbeat
  // must not accidentally make this test depend on suite execution speed.
  let fixture_heartbeat = base.store
    .heartbeats()
    .filter(value => value.node_id == "managed-node-a")[0]
  base.store.put_heartbeat({
    ..fixture_heartbeat,
    timestamp_unix_ms: @async.now(),
  })
  base.refresh_deployment_operations()
  let accounts = @account.AccountStore::open(
    root + "/media-accounts.json",
    "media-fixture-session-secret-longer-than-32-bytes",
  )
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "media-account",
      subject_ref: "subject-a",
      identity_issuer: "https://identity.example",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example", "fixture",
      ),
      display_name: "Media fixture",
      email: "media@example.invalid",
      identity_receipt: "fixture-identity",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  let commercial = @commercial.CommercialStore::new()
  commercial.add_organization({
    organization_id: "org-a",
    display_name: "Fixture",
    state: Active,
    verification_ref: Some("fixture-only"),
    legal_profile: None,
    created_unix_ms: now,
  })
  commercial.add_cost_center({
    cost_center_id: "media-cost",
    organization_id: "org-a",
    parent_cost_center_id: None,
    display_name: "Fixture",
    created_unix_ms: now,
  })
  commercial.add_project({
    project_id: "project-a",
    organization_id: "org-a",
    cost_center_id: "media-cost",
    display_name: "Fixture",
    created_unix_ms: now,
  })
  let jobs = @media_jobs.JobStore::restore(
    { schema_version: @media_jobs.schema_version, jobs: [], },
    _ => (),
  )
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let operation = base.deployment_store
    .unwrap()
    .deployment(order.target_deployment_ref.unwrap())
    .unwrap()
  let binding : MediaBinding = {
    instance_id: None,
    deployment_id: operation.deployment_id,
    deployment_generation: operation.generation,
    node_id: "managed-node-a",
    origin: "http://\{server.addr}",
    bearer: Some("fixture-provider-token"),
    profile: {
      model: "text.default",
      provider_model: "H3-fixture",
      widths: [512],
      heights: [512],
      maximum_frames: 121,
      maximum_fps: 24,
      maximum_steps: 50,
      sound_supported: true,
    },
  }
  let private_keys = @access.AccessStore::open(
    root + "/private-keys.json",
    "private-media-issuer-secret-longer-than-thirty-two-bytes",
  )
  let secret = if private_cloud {
    private_keys.issue(
      {
        key_id: "private-media-key",
        tenant_ref: "tenant-a",
        subject_ref: "subject-a",
        organization_id: "org-a",
        project_id: "project-a",
        display_name: "Private fixture",
        scopes: [Inference, ModelList],
        allowed_models: ["text.default"],
        expires_unix_ms: now + 3600000L,
        maximum_requests: 100L,
      },
      now,
    ).secret
  } else {
    secret
  }
  let base = if private_cloud {
    {
      ..base
      .with_private_cloud_workspace_access(true)
      .with_access_store(private_keys),
      machine_commerce_store: None,
      contract_document_store: None,
    }
  } else {
    base
  }
  let service = {
    ..base.with_account_store(
      accounts, "fixture-assertion-secret-longer-than-32-bytes",
    ),
    commercial_store: commercial,
  }.with_media_templates(jobs, [
    {
      template_id: operation.plan.template.unwrap().template_id,
      runtime_route: None,
      template_version: operation.plan.template.unwrap().version,
      node_id: binding.node_id,
      origin: binding.origin,
      bearer: binding.bearer,
      profile: binding.profile,
    },
  ])
  exercise_runtime_route_discovery(service, operation, binding)
  let headers = {
    "Authorization": "Bearer " + secret,
    "Content-Type": "application/x-www-form-urlencoded",
    "Idempotency-Key": "fixture-video-request",
  }
  let state = { "submits": 0, "deletes": 0 }
  let listener = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer listener.close()
  let request = "model=text.default&prompt=private-fixture-prompt&width=512&height=512&num_frames=25&fps=24"
  if private_cloud {
    assert_eq(
      service
      .with_private_cloud_workspace_access(false)
      .handle(Post, "/v1/videos", headers, request).status,
      403,
    )
    guard service.media_owner(headers) is Some((owner, None)) else {
      fail("private media unexpectedly depends on a commercial order")
    }
    assert_true(owner.authority is PrivateWorkspace(_))
    assert_true(service.media_authorized(owner, binding.profile.model, binding))
    assert_false(
      service.media_authorized(
        { ..owner, authority: PrivateWorkspace("different-lease"), },
        binding.profile.model,
        binding,
      ),
    )
    assert_false(
      service.media_authorized(
        { ..owner, tenant_ref: "different-tenant", },
        binding.profile.model,
        binding,
      ),
    )
  }
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, () => {
      for ;; {
        base.store.put_heartbeat({
          ..fixture_heartbeat,
          timestamp_unix_ms: @async.now(),
        })
        @async.sleep(1000)
      }
    })
    group.spawn_bg(no_wait=true, () => service.serve_on(listener))
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((req, body, connection) => {
        ignore(@io.Reader::read_all(body))
        assert_eq(
          req.headers.get("authorization"),
          Some("Bearer fixture-provider-token"),
        )
        if req.path.has_suffix("/content") {
          connection.send_response(200, "OK", extra_headers={
            "content-type": "video/mp4",
          })
          connection.write(b"fixture-video-bytes-not-gpu-evidence")
          connection.end_response()
          return
        }
        connection.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        if req.meth == Post {
          state["submits"] += 1
          connection.write_string(
            "{\"id\":\"provider-private-id\",\"status\":\"queued\",\"prompt\":\"private-fixture-prompt\"}",
          )
        } else if req.meth == Delete {
          state["deletes"] += 1
          connection.write_string(
            "{\"id\":\"provider-private-id\",\"deleted\":true}",
          )
        } else {
          connection.write_string(
            "{\"id\":\"provider-private-id\",\"status\":\"completed\",\"file_name\":\"/private/output.mp4\"}",
          )
        }
        connection.end_response()
      })
    })
    assert_eq(service.handle(Post, "/v1/videos", Map([]), request).status, 403)
    assert_eq(
      service.handle(
        Post,
        "/v1/videos",
        headers,
        request + "&image_reference=file%3A%2F%2Fetc%2Fpasswd",
      ).status,
      400,
    )
    let submitted = service.handle(Post, "/v1/videos", headers, request)
    assert_eq(submitted.status, 200)
    guard @json.parse(submitted.body)
      is { "id": String(id), "status": String("queued"), .. } else {
      fail("missing public video job")
    }
    assert_false(submitted.body.contains("private-fixture-prompt"))
    assert_false(submitted.body.contains("provider-private-id"))
    assert_eq(service.handle(Post, "/v1/videos", headers, request).status, 200)
    assert_eq(state["submits"], 1)
    assert_eq(
      service.handle(Get, "/v1/media/operator/jobs", headers, "").status,
      403,
    )
    let operator_headers = { "Authorization": "Bearer operator-token" }
    assert_eq(
      service.handle(Get, "/v1/media/operator/jobs", operator_headers, "").status,
      200,
    )
    let reconciliation_path = "/v1/media/operator/jobs/" + id + ":reconcile"
    let invalid_evidence : Json = {
      "expected_request_digest": "wrong",
      "provider_job_id": "provider-private-id",
      "evidence_ref": "fixture-evidence",
    }
    assert_eq(
      service.handle(
        Post,
        reconciliation_path,
        operator_headers,
        invalid_evidence.stringify(),
      ).status,
      409,
    )
    assert_eq(
      service.handle(
        Post,
        "/v1/videos",
        headers,
        request.replace(old="private-fixture-prompt", new="different-prompt"),
      ).status,
      409,
    )
    let finished = service.handle(Get, "/v1/videos/" + id, headers, "")
    assert_eq(finished.status, 200)
    assert_true(
      @json.parse(finished.body) is { "status": String("completed"), .. },
    )
    assert_false(finished.body.contains("/private/output.mp4"))
    ignore(service.handle(Get, "/v1/videos/" + id, headers, ""))
    let usage = commercial.durable_snapshot().commercial.usage_observations
    assert_eq(usage.length(), 1)
    assert_eq(
      usage[0].meter,
      if private_cloud {
        "private-workspace-video-job"
      } else {
        "prepaid-video-job"
      },
    )
    assert_eq(usage[0].quantity, 1L)
    let content_url = "http://\{listener.addr}/v1/videos/" + id + "/content"
    let (download, bytes) = @http.get(content_url, headers={
      "Authorization": "Bearer " + secret,
    })
    assert_eq(download.code, 200)
    assert_eq(download.headers.get("content-type"), Some("video/mp4"))
    assert_eq(download.headers.get("cache-control"), Some("no-store"))
    assert_eq(bytes.text(), "fixture-video-bytes-not-gpu-evidence")
    let (anonymous, _) = @http.get(content_url)
    assert_eq(anonymous.code, 403)
    assert_eq(
      service.handle(Delete, "/v1/videos/" + id, headers, "").status,
      200,
    )
    assert_eq(state["deletes"], 1)
    assert_eq(
      commercial.durable_snapshot().commercial.usage_observations.length(),
      1,
    )
    ignore(accounts.set_state("media-account", Suspended, @async.now()))
    assert_eq(service.handle(Get, "/v1/videos/" + id, headers, "").status, 403)
    let (revoked, _) = @http.get(content_url, headers={
      "Authorization": "Bearer " + secret,
    })
    assert_eq(revoked.code, 403)
  }
}
