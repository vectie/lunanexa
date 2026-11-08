///|
fn page_query(
  list : String,
  query~ : String = "",
  account_id~ : String = "",
  cursor~ : String = "",
) -> @operator_read.PageQuery {
  { list, query, account_id, cursor, }
}

///|
test "operator cursors bind list search person and dataset without granting authority" {
  let query = page_query("accounts")
  let ids = [ for n in 0..<61 => "person-\{n}" ]
  let (_, fingerprint) = operator_page_window(query, ids).unwrap()
  let next = { ..query, cursor: "25:\{fingerprint}", }
  assert_eq(operator_page_window(next, ids).unwrap().0, 25)
  for
    changed in [
      { ..next, list: "access-grants", },
      { ..next, query: "alice", },
      { ..next, account_id: "another-person", },
      { ..next, cursor: "-25:\{fingerprint}", },
      { ..next, cursor: "1:\{fingerprint}", },
      { ..next, cursor: "100:\{fingerprint}", },
    ] {
    assert_eq(operator_page_window(changed, ids), None)
  }
  assert_eq(operator_page_window(next, ids + ["new-person"]), None)
}

///|
test "audit paging remains stable while new traffic appends events" {
  let events : Array[@contracts.AuditEvent] = [
    for n in 1..<62 => {
      {
        sequence: n.to_int64(),
        event_id: "event-\{n}",
        timestamp_unix_ms: n.to_int64(),
        actor: "operator",
        policy_version: "v1",
        action: "workload.invoke",
        target: "model-a",
        prior_state: "",
        next_state: "",
        result: "accepted",
        correlation_receipt: "receipt-\{n}",
        previous_hash: "previous",
        event_hash: "hash-\{n}",
      }
    }
  ]
  let query = page_query("audit-events")
  let (first, _, fingerprint) = operator_audit_window(query, events).unwrap()
  let appended = events +
    [{ ..events[60], sequence: 62L, event_id: "event-62", }]
  let (second, offset, _) = operator_audit_window(
    { ..query, cursor: "25:\{fingerprint}", },
    appended,
  ).unwrap()
  assert_eq(offset, 25)
  assert_eq(second.length(), 61)
  assert_eq(second[offset].sequence, first[25].sequence)
  assert_false(second.any(event => event.sequence == 62L))
  assert_eq(
    operator_audit_window(
      { ..query, list: "request-receipts", cursor: "25:\{fingerprint}", },
      appended,
    ),
    None,
  )
}

///|
async test "operator pages bound results preserve choices and authorize every read during reconciliation" {
  let root = @fs.tmpdir(prefix="lunanexa-operator-pages-")
  defer @fs.rmdir(root, recursive=true)
  let now = @async.now()
  let accounts = @account.AccountStore::open(
    root + "/accounts",
    "operator-pages-session-secret-over-32-bytes",
  )
  let directory = @directory.FileWorkspaceDirectory::open(
    root + "/workspace",
    now_unix_ms=now,
  )
  let portal = @portal_store.FilePortalStore::open(root + "/portal")
  for n in 0..<61 {
    let id = n.to_string().pad_start(3, '0')
    ignore(
      accounts.create({
        version: @account.contract_version,
        account_id: "account-" + id,
        subject_ref: "subject-" + id,
        identity_issuer: "https://identity.example/realm",
        identity_subject_sha256: @account.identity_subject_digest(
          "https://identity.example/realm", id,
        ),
        display_name: "人员 " + id,
        email: id + "@example.invalid",
        identity_receipt: "identity-evidence-" + id,
        roles: if n == 0 {
          [EnterpriseUser, PlatformOperator, AuditReader]
        } else {
          [EnterpriseUser]
        },
        state: Active,
        created_unix_ms: now - 1L,
        updated_unix_ms: now - 1L,
      }),
    )
    ignore(
      directory.create_user({
        version: @workspace.contract_version,
        user_id: "user-" + id,
        subject_ref: "subject-" + id,
        display_name: "人员 " + id,
        email: id + "@example.invalid",
        state: UserActive,
        created_unix_ms: now - 1L,
        last_active_unix_ms: None,
        identity_receipt: "workspace-evidence-" + id,
      }),
    )
    ignore(
      directory.issue_access_grant(
        {
          version: @workspace.contract_version,
          grant_id: "grant-" + id,
          user_id: "user-" + id,
          tenant_ref: "tenant-a",
          access: Developer,
          starts_unix_ms: now - 1L,
          expires_unix_ms: now + 60000L,
          state: GrantActive,
          policy_receipt: "grant-evidence-" + id,
        },
        now,
      ),
    )
    if n < 28 {
      ignore(
        portal.put_membership({
          membership_id: "membership-" + id,
          subject_ref: "subject-000",
          tenant_ref: "tenant-" + id,
          organization_id: "organization-" + id,
          roles: [Developer],
          active: true,
          created_unix_ms: now,
        }),
      )
    }
  }
  let store = @store.FileStore::open(root + "/control")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses",
    "never-return-this-secret",
    "v1",
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
  )
  let service = ApiService::new(
      store, runtime, "operator-token", "inference-token", "node-token", "test",
    )
    .with_account_store(
      accounts, "operator-pages-assertion-secret-over-32-bytes",
    )
    .with_workspace_directory(directory, false)
    .with_portal_store(portal)
    .with_reconciliation_only(true)
  let session = accounts.issue_session(
    "https://identity.example/realm", "000", "operator-pages-login", 60000L, now,
  )
  let headers = { "Authorization": "Bearer " + session.secret }
  let path = "/v1/operator/list-page"
  for
    kind in [
      "accounts", "workspace-profiles", "access-grants", "access-records",
    ] {
    let query = page_query(
      kind,
      account_id=if kind == "access-records" { "account-000" } else { "" },
    )
    let first_reply = service.handle(
      Post,
      path,
      headers,
      Json(query).stringify(),
    )
    assert_eq(first_reply.status, 200)
    let first : @operator_read.ReadPage = @json.from_json(
      @json.parse(first_reply.body),
    )
    assert_eq(first.items.length(), 25)
    assert_eq(first.total, if kind == "access-records" { 28 } else { 61 })
    assert_eq(first.page, 0)
    let next_query = { ..query, cursor: first.next_cursor, }
    let next_reply = service.handle(
      Post,
      path,
      headers,
      Json(next_query).stringify(),
    )
    assert_eq(next_reply.status, 200)
    let next : @operator_read.ReadPage = @json.from_json(
      @json.parse(next_reply.body),
    )
    assert_eq(
      next.items.length(),
      if kind == "access-records" {
        3
      } else {
        25
      },
    )
    assert_eq(next.page, 1)
    assert_false(first.items.any(item => next.items.contains(item)))
    let back : @operator_read.ReadPage = @json.from_json(
      @json.parse(
        service.handle(
          Post,
          path,
          headers,
          Json({ ..query, cursor: next.previous_cursor, }).stringify(),
        ).body,
      ),
    )
    assert_eq(back.items, first.items)
    assert_eq(
      service.handle(
        Post,
        path,
        { "Authorization": "Bearer inference-token" },
        Json(next_query).stringify(),
      ).status,
      401,
    )
  }
  let searched : @operator_read.ReadPage = @json.from_json(
    @json.parse(
      service.handle(
        Post,
        path,
        headers,
        Json(page_query("accounts", query=" 人员 060 ")).stringify(),
      ).body,
    ),
  )
  assert_eq(searched.total, 1)
  assert_eq(searched.items.length(), 1)
  let context = service.handle(
    Post,
    "/v1/operator/access-context",
    headers,
    "{}",
  )
  assert_eq(context.status, 200)
  assert_false(context.body.contains("identity-evidence"))
  assert_false(context.body.contains("workspace-evidence"))
  assert_false(context.body.contains("grant-evidence"))
  assert_true(context.body.contains("account-060"))
  assert_false(context.body.contains("never-return-this-secret"))
  assert_eq(store.audit_events().length(), 0)
  let audit_only = { ..service, audit_token: "audit-only", }
  assert_eq(
    audit_only.handle(
      Post,
      path,
      { "Authorization": "Bearer audit-only" },
      Json(page_query("accounts")).stringify(),
    ).status,
    401,
  )
  assert_eq(
    audit_only.handle(
      Post,
      path,
      { "Authorization": "Bearer audit-only" },
      Json(page_query("audit-events")).stringify(),
    ).status,
    200,
  )
  assert_eq(service.handle(Get, path, headers, "").status, 405)
  assert_eq(
    service.handle(
      Post,
      path,
      headers,
      Json(page_query("accounts", query="a".repeat(257))).stringify(),
    ).status,
    400,
  )
}

///|
async test "node ownership retains stopped fixed allocations without probing runtime adapters" {
  let root = @fs.tmpdir(prefix="lunanexa-ownership-read-")
  defer @fs.rmdir(root, recursive=true)
  let deployments = @deployment_store.FileDeploymentStore::open(
    root + "/deployments",
    "ownership-fixture-secret",
  )
  ignore(
    deployments.adopt_service({
      service_id: "fixed-company-service",
      model_alias: "model.chat",
      artifact_digest: "sha256:" + "a".repeat(64),
      owner: {
        tenant_ref: "tenant-company",
        organization_id: "company",
        reservation_id: None,
      },
      node_ids: ["node-a", "node-b"],
      runtime_kind: ProcessGroup,
      binding_ref: "private-binding",
      exclusive: true,
      generation: 1L,
      desired_running: false,
      observed: Stopped,
      updated_unix_ms: 1L,
    }),
  )
  let calls = Ref(0)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "https://runtime.invalid/v1/responses",
    "private-runtime-credential",
    "v1",
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
  )
  let service = ApiService::new(
      @store.FileStore::open(root + "/control"),
      runtime,
      "operator",
      "inference",
      "node",
      "test",
    )
    .with_deployment_store(deployments)
    .with_runtime_controls({
      "private-binding": _ => {
        calls.val += 1
        "Stopped"
      },
    })
  let response = service.handle(
    Post,
    "/v1/operator/node-ownership",
    { "Authorization": "Bearer operator" },
    "{}",
  )
  assert_eq(response.status, 200)
  let items : Array[Json] = @json.from_json(@json.parse(response.body))
  assert_eq(items.length(), 2)
  for item in items {
    assert_true(
      item is { "tenant_ref": "tenant-company", "fixed_company": True, .. },
    )
  }
  assert_eq(calls.val, 0)
  assert_false(response.body.contains("private-binding"))
  assert_false(response.body.contains("private-runtime-credential"))
  assert_eq(
    service.handle(
      Post,
      "/v1/operator/node-ownership",
      { "Authorization": "Bearer inference" },
      "{}",
    ).status,
    401,
  )
}
