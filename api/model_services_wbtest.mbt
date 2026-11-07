///|
async test "operator and portal share runtime identity and admission before adapter mutation" {
  let root = @fs.tmpdir(prefix="unified-services-api-")
  defer @fs.rmdir(root, recursive=true)
  let deployments = @deployment_store.FileDeploymentStore::open(
    root + "/deployments.json",
    "fixture-secret",
  )
  let portal = @portal_store.FilePortalStore::open(root + "/portal.json")
  for
    (subject, tenant, org, roles) in [
      (
        "admin",
        "tenant-a",
        "org-a",
        [@portal.EnterpriseRole::OrganizationAdministrator],
      ),
      ("member", "tenant-a", "org-a", [Developer]),
      ("other", "tenant-b", "org-b", [OrganizationAdministrator]),
    ] {
    ignore(
      portal.put_membership({
        membership_id: "membership-" + subject,
        subject_ref: subject,
        tenant_ref: tenant,
        organization_id: org,
        roles,
        active: true,
        created_unix_ms: @async.now(),
      }),
    )
  }
  let calls : Array[String] = []
  let running = Ref(true)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://fixture.invalid/v1/responses",
    "",
    "v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
  )
  let service = ApiService::new(
      @store.FileStore::open(root + "/state.json"),
      runtime,
      "operator",
      "inference",
      "node",
      "test",
    )
    .with_deployment_store(deployments)
    .with_portal_store(portal)
    .with_runtime_controls({
      "company-binding": action => {
        if action != "status" {
          calls.push("company-" + action)
          running.val = action == "start"
        }
        if running.val {
          "Running"
        } else {
          "Stopped"
        }
      },
      "platform-binding": action => {
        calls.push("platform-" + action)
        "Stopped"
      },
    })
  let company : @deployment.ModelServiceInstance = {
    service_id: "company-service",
    model_alias: "glm",
    artifact_digest: "sha256:" + "a".repeat(64),
    owner: {
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      reservation_id: None,
    },
    node_ids: ["node-a", "node-b"],
    runtime_kind: ProcessGroup,
    binding_ref: "company-binding",
    exclusive: true,
    generation: 1L,
    desired_running: true,
    observed: Running,
    updated_unix_ms: @async.now(),
  }
  deployments.adopt_service(company)
  deployments.adopt_service({
    ..company,
    service_id: "platform-service",
    model_alias: "qwen",
    owner: { tenant_ref: "", organization_id: "", reservation_id: None, },
    binding_ref: "platform-binding",
    desired_running: false,
    observed: Stopped,
  })
  let operator = { "Authorization": "Bearer operator" }
  deployments.adopt_service({
    ..company,
    service_id: "personal-replica",
    model_alias: "private-project-model",
    runtime_kind: NodeAssignment,
    node_ids: ["private-node"],
    binding_ref: "private-project-reference",
    owner: {
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      reservation_id: Some("private-project-reservation"),
    },
    desired_running: false,
    observed: Stopped,
  })
  let admin = {
    "Authorization": "Bearer inference",
    "X-LunaNexa-Subject": "admin",
  }
  let member_headers = {
    "Authorization": "Bearer inference",
    "X-LunaNexa-Subject": "member",
  }
  let other = {
    "Authorization": "Bearer inference",
    "X-LunaNexa-Subject": "other",
  }
  let public_list = service.handle(
    Get,
    "/v1/portal/self/model-services",
    admin,
    "",
  )
  assert_eq(public_list.status, 200)
  for
    private_field in [
      "binding_ref", "node_ids", "owner", "company-binding", "platform-service",
      "private-project", "personal-replica",
    ] {
    assert_false(public_list.body.contains(private_field))
  }
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/self/model-services/company-service:stop",
      other,
      "{}",
    ).status,
    404,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/self/model-services/company-service:stop",
      member_headers,
      "{}",
    ).status,
    403,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/model-services/platform-service:start",
      operator,
      "{}",
    ).status,
    409,
  )
  assert_true(calls.is_empty())
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/self/model-services/company-service:stop",
      admin,
      "{}",
    ).status,
    200,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/model-services/platform-service:start",
      operator,
      "{}",
    ).status,
    409,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/model-services/company-service:start",
      operator,
      "{}",
    ).status,
    200,
  )
  assert_eq(
    service.handle(
      Post,
      "/v1/portal/self/model-services/company-service:start",
      admin,
      "{}",
    ).status,
    200,
  )
  assert_eq(calls, ["company-stop", "company-start"])
  assert_eq(deployments.services().length(), 3)
}

///|
async test "runtime failure persists an unknown claim before another service may start" {
  let root = @fs.tmpdir(prefix="unified-services-failure-")
  defer @fs.rmdir(root, recursive=true)
  let path = root + "/deployments.json"
  let deployments = @deployment_store.FileDeploymentStore::open(
    path, "fixture-secret",
  )
  let model : @deployment.ModelServiceInstance = {
    service_id: "first",
    model_alias: "model-a",
    artifact_digest: "sha256:" + "a".repeat(64),
    owner: { tenant_ref: "", organization_id: "", reservation_id: None, },
    node_ids: ["node-a"],
    runtime_kind: ProcessGroup,
    binding_ref: "adapter",
    exclusive: true,
    generation: 1L,
    desired_running: false,
    observed: Stopped,
    updated_unix_ms: 1L,
  }
  deployments.adopt_service(model)
  deployments.adopt_service({
    ..model,
    service_id: "second",
    model_alias: "model-b",
  })
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://fixture.invalid/v1/responses",
    "",
    "v1",
    "sha256:" + "b".repeat(64),
    model.artifact_digest,
  )
  let service = ApiService::new(
      @store.FileStore::open(root + "/state.json"),
      runtime,
      "operator",
      "inference",
      "node",
      "test",
    )
    .with_deployment_store(deployments)
    .with_runtime_controls({
      "adapter": action => {
        if action == "status" {
          "Stopped"
        } else {
          raise Failure("fixture interrupted adapter")
        }
      },
    })
  try service.apply_model_service_action("first", "start") catch {
    _ => ()
  } noraise {
    _ => fail("failed adapter reported success")
  }
  let reopened = @deployment_store.FileDeploymentStore::open(
    path, "fixture-secret",
  )
  assert_true(reopened.service("first").unwrap().holds_resources())
  try reopened.set_service_desired("second", 1L, true, 2L) catch {
    _ => ()
  } noraise {
    _ => fail("failed start lost its claim")
  }
}
