///|
async test "private company administrators use equivalent pool access with individual leases" {
  let root = @fs.tmpdir(prefix="private-company-pool-")
  defer @fs.rmdir(root, recursive=true)
  let now = @async.now()
  let portal = @portal_store.FilePortalStore::open(root + "/portal.json")
  let scheduler = @scheduler.FileScheduler::open(root + "/scheduler.json", 4)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "",
    "fixture",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let base = ApiService::new(
      @store.FileStore::open(root + "/state.json"),
      runtime,
      "operator",
      "inference",
      "node",
      "test",
    )
    .with_portal_store(portal)
    .with_delivery_store(
      @delivery.DeliveryStore::open(root + "/deliveries.json"),
    )
  let fixture = machine_webide_fixture(
    { ..base, scheduler: Some(scheduler), },
    root,
    now,
  )
  let service = fixture
    .with_client_handoff_store(fixture.client_handoff_store.unwrap(), {
      ..fixture.client_launch_config.unwrap(),
      client_id: "gpu-terminal",
      display_name: "GPU terminal",
    })
    .with_private_cloud_workspace_access(true)
    .with_gpu_container_offering({
      template_id: "gpu-python",
      version: "v1",
      display_name: "GPU container",
      client_id: "gpu-terminal",
      image_digest: "sha256:" + "b".repeat(64),
      cpu_millis: 4000,
      memory_mib: 8192,
    })
  service.commercial_store.add_organization({
    organization_id: "org-a",
    display_name: "Company",
    state: Active,
    verification_ref: None,
    legal_profile: None,
    created_unix_ms: now,
  })
  service.commercial_store.add_cost_center({
    cost_center_id: "cost-a",
    organization_id: "org-a",
    parent_cost_center_id: None,
    display_name: "Default",
    created_unix_ms: now,
  })
  service.commercial_store.add_project({
    project_id: "project-a",
    organization_id: "org-a",
    cost_center_id: "cost-a",
    display_name: "Default",
    created_unix_ms: now,
  })
  let directory = service.workspace_directory.unwrap()
  let snapshot = directory.snapshot(now)
  let original_user = snapshot.users[0]
  let original_grant = snapshot.access_grants[0]
  let original_lease = snapshot.leases[0]
  for suffix in ["a", "b", "c"] {
    ignore(
      portal.put_membership({
        membership_id: "member-" + suffix,
        subject_ref: "subject-" + suffix,
        organization_id: "org-a",
        tenant_ref: "tenant-a",
        roles: [OrganizationAdministrator, Developer],
        active: true,
        created_unix_ms: now,
      }),
    )
    if suffix != "a" {
      ignore(
        directory.create_user({
          ..original_user,
          user_id: "webide-user-" + suffix,
          subject_ref: "subject-" + suffix,
          email: suffix + "@example.invalid",
        }),
      )
      ignore(
        directory.issue_access_grant(
          {
            ..original_grant,
            grant_id: "webide-grant-" + suffix,
            user_id: "webide-user-" + suffix,
          },
          now,
        ),
      )
      ignore(
        directory.issue_lease(
          {
            ..original_lease,
            lease_id: "webide-lease-" + suffix,
            subject_ref: "subject-" + suffix,
          },
          now,
        ),
      )
    }
  }
  let reservation = scheduler.reserve_nodes(
    {
      reservation_id: "company-annual-reservation",
      idempotency_key: "company-annual-reservation",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      authority_ref: "webide-grant-a",
      lease_id: "webide-lease-a",
      node_ids: ["node-a", "node-b"],
      starts_unix_ms: now,
      expires_unix_ms: now + 3600000L,
      memory_mib_per_node: 32768,
      gpu_memory_mib_per_node: 32768,
      max_concurrency_per_node: 4,
    },
    ["node-a", "node-b"],
    now,
  )
  for suffix in ["a", "b", "c"] {
    assert_true(
      service.private_company_reservation_authorized(
        reservation,
        "subject-" + suffix,
        now,
      ),
    )
    assert_true(
      service.delivery_reservation_authorized(
        reservation,
        "tenant-a",
        "org-a",
        "webide-lease-" + suffix,
        "webide-grant-" + suffix,
        now,
      ),
    )
    let response = service.handle_delivery(
      Get,
      "/v1/portal/self/delivery-options",
      {
        "Authorization": "Bearer inference",
        "X-LunaNexa-Subject": "subject-" + suffix,
        "X-LunaNexa-Organization": "org-a",
      },
      "",
      true,
    )
    assert_eq(response.status, 200)
    guard @json.parse(response.body)
      is { "reservations": Array([resource]), .. } else {
      fail("company pool must be visible to every administrator")
    }
    assert_true(
      resource
      is { "reservation_id": "company-annual-reservation", "node_count": 2, .. },
    )
    let request : Json = {
      "project_id": "project-a",
      "idempotency_key": "start-" + suffix,
      "reservation_id": "company-annual-reservation",
      "template_id": "gpu-python",
      "template_version": "v1",
      "kind": "GpuContainer",
    }
    let created = service.handle_delivery(
      Post,
      "/v1/portal/self/deliveries",
      {
        "Authorization": "Bearer inference",
        "X-LunaNexa-Subject": "subject-" + suffix,
        "X-LunaNexa-Organization": "org-a",
      },
      request.stringify(),
      true,
    )
    assert_eq(created.status, 202)
    let operation = service.delivery_store
      .unwrap()
      .operations()
      .iter()
      .find_first(operation => {
        operation.intent.idempotency_key == "start-" + suffix
      })
      .unwrap()
    assert_eq(operation.intent.lease_id, "webide-lease-" + suffix)
    assert_eq(operation.intent.authorization_ref, "webide-grant-" + suffix)
    assert_false(
      delivery_visible_to_member(operation, "tenant-a", "org-a", false),
    )
  }
  let restarted = service
    .with_portal_store(
      @portal_store.FilePortalStore::open(root + "/portal.json"),
    )
    .with_workspace_directory(
      @directory.FileWorkspaceDirectory::open(root + "/webide-workspace.json"),
      true,
    )
  assert_true(
    restarted.delivery_reservation_authorized(
      reservation, "tenant-a", "org-a", "webide-lease-b", "webide-grant-b", now,
    ),
  )
  assert_false(
    service
    .with_private_cloud_workspace_access(false)
    .delivery_reservation_authorized(
      reservation, "tenant-a", "org-a", "webide-lease-b", "webide-grant-b", now,
    ),
  )
  assert_false(
    service.delivery_reservation_authorized(
      reservation, "tenant-a", "other-org", "webide-lease-b", "webide-grant-b", now,
    ),
  )
  assert_false(
    service.delivery_reservation_authorized(
      reservation, "tenant-a", "org-a", "webide-lease-b", "webide-grant-a", now,
    ),
  )
  assert_false(
    service.private_company_reservation_authorized(
      {
        ..reservation,
        request: { ..reservation.request, lease_id: "missing-sponsor", },
      },
      "subject-b",
      now,
    ),
  )
  let membership = portal.snapshot().memberships
    .iter()
    .find_first(value => value.subject_ref == "subject-b")
    .unwrap()
  let developer_portal = @portal_store.FilePortalStore::open(
    root + "/developer-portal.json",
  )
  ignore(developer_portal.put_membership({ ..membership, roles: [Developer], }))
  assert_false(
    service
    .with_portal_store(developer_portal)
    .delivery_reservation_authorized(
      reservation, "tenant-a", "org-a", "webide-lease-b", "webide-grant-b", now,
    ),
  )
  ignore(portal.revoke_membership(membership.membership_id))
  assert_false(
    service.private_company_reservation_authorized(
      reservation, "subject-b", now,
    ),
  )
  assert_false(
    service.private_company_reservation_authorized(
      reservation,
      "subject-c",
      now + 7200001L,
    ),
  )
}
