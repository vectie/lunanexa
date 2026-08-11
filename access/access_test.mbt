///|
async test "API credentials are hashed, scoped, quota bounded, and restart durable" {
  let path = "/tmp/lunanexa-access-test-\{@async.now()}.json"
  let store = @access.AccessStore::open(
    path, "0123456789abcdef0123456789abcdef",
  )
  let issued = store.issue(
    {
      key_id: "key-1",
      tenant_ref: "tenant-1",
      subject_ref: "subject-1",
      display_name: "Workbench key",
      scopes: [ModelList, Inference],
      allowed_models: ["model-a"],
      expires_unix_ms: 200000L,
      maximum_requests: 1L,
    },
    100000L,
  )
  assert_true(issued.secret.has_prefix("lnx_"))
  assert_false(issued.credential.secret_sha256.contains(issued.secret))
  let authorized = store.authorize(
    issued.secret,
    Inference,
    tenant_ref="tenant-1",
    model="model-a",
    100001L,
    true,
  )
  assert_eq(authorized.subject_ref, "subject-1")
  try
    store.authorize(
      issued.secret,
      Inference,
      tenant_ref="tenant-1",
      model="model-a",
      100002L,
      true,
    )
  catch {
    @access.AccessError::QuotaExceeded => ()
    _ => fail("unexpected authorization error")
  } noraise {
    _ => fail("quota bypassed")
  }
  let reopened = @access.AccessStore::open(
    path, "0123456789abcdef0123456789abcdef",
  )
  assert_eq(reopened.snapshot().credentials[0].consumed_requests, 1L)
}

///|
async test "API credentials reject cross-tenant and cross-model use" {
  let path = "/tmp/lunanexa-access-scope-test-\{@async.now()}.json"
  let store = @access.AccessStore::open(
    path, "fedcba9876543210fedcba9876543210",
  )
  let issued = store.issue(
    {
      key_id: "key-scope",
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      display_name: "Scoped key",
      scopes: [Inference],
      allowed_models: ["model-a"],
      expires_unix_ms: 200000L,
      maximum_requests: 2L,
    },
    100000L,
  )
  for pair in [("tenant-b", "model-a"), ("tenant-a", "model-b")] {
    let (tenant, model) = pair
    try
      store.authorize(
        issued.secret,
        Inference,
        tenant_ref=tenant,
        model~,
        100001L,
        true,
      )
    catch {
      @access.AccessError::Unauthorized => ()
      _ => fail("unexpected authorization error")
    } noraise {
      _ => fail("scope boundary bypassed")
    }
  }
  assert_eq(store.snapshot().credentials[0].consumed_requests, 0L)
}
