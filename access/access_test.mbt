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

///|
async test "subject revocation invalidates only that account's API keys" {
  let path = "/tmp/lunanexa-access-subject-revoke-test-\{@async.now()}.json"
  let store = @access.AccessStore::open(
    path, "subject-revoke-secret-0123456789abcdef",
  )
  let first = store.issue(
    {
      key_id: "key-subject-a-first",
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      display_name: "First personal key",
      scopes: [Inference],
      allowed_models: [],
      expires_unix_ms: 200000L,
      maximum_requests: 10L,
    },
    100000L,
  )
  ignore(
    store.issue(
      {
        key_id: "key-subject-a-second",
        tenant_ref: "tenant-b",
        subject_ref: "subject-a",
        display_name: "Second personal key",
        scopes: [ModelList],
        allowed_models: [],
        expires_unix_ms: 200000L,
        maximum_requests: 10L,
      },
      100001L,
    ),
  )
  let other = store.issue(
    {
      key_id: "key-subject-b",
      tenant_ref: "tenant-a",
      subject_ref: "subject-b",
      display_name: "Other account key",
      scopes: [Inference],
      allowed_models: [],
      expires_unix_ms: 200000L,
      maximum_requests: 10L,
    },
    100002L,
  )
  assert_eq(store.revoke_subject("subject-a", 100003L), 2)
  assert_eq(store.revoke_subject("subject-a", 100004L), 0)
  try
    store.authorize(
      first.secret,
      Inference,
      tenant_ref="tenant-a",
      100005L,
      false,
    )
  catch {
    @access.AccessError::Unauthorized => ()
    _ => fail("unexpected subject-revocation authorization error")
  } noraise {
    _ => fail("revoked account key remained authorized")
  }
  let authorization = store.authorize(
    other.secret,
    Inference,
    tenant_ref="tenant-a",
    100005L,
    false,
  )
  assert_eq(authorization.subject_ref, "subject-b")
}
