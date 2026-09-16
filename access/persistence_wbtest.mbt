///|
async test "failed credential writes restore quota and revocations and release lock" {
  let directory = @fs.tmpdir(prefix="lunanexa-access-rollback-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/keys.json"
  let store = AccessStore::open(
    path, "test-only-issuer-secret-0123456789abcdef",
  )
  let intent : ApiKeyIssueIntent = {
    key_id: "rollback-key",
    tenant_ref: "tenant-a",
    subject_ref: "subject-a",
    organization_id: "organization-a",
    project_id: "project-a",
    display_name: "Rollback fixture",
    scopes: [Inference],
    allowed_models: ["model-a"],
    expires_unix_ms: 200000L,
    maximum_requests: 2L,
  }
  let issued = store.issue(intent, 100000L)
  let before = ToJson::to_json(store.snapshot()).stringify()
  // A directory at the temporary-file path deterministically rejects writes.
  @fs.mkdir(path + ".next")
  for operation in 0..<4 {
    try {
      match operation {
        0 => ignore(store.issue({ ..intent, key_id: "retry-key", }, 100001L))
        1 => ignore(store.revoke(issued.credential.key_id, 100001L))
        2 => ignore(store.revoke_subject("subject-a", 100001L))
        _ => ignore(store.authorize(issued.secret, Inference, 100001L, true))
      }
    } catch {
      _ => ()
    } noraise {
      _ => fail("write unexpectedly succeeded")
    }
    @async.with_timeout(1000, () => {
      assert_eq(ToJson::to_json(store.snapshot()).stringify(), before)
      let reopened = AccessStore::open(
        path, "test-only-issuer-secret-0123456789abcdef",
      )
      assert_eq(ToJson::to_json(reopened.snapshot()).stringify(), before)
      ignore(store.authorize(issued.secret, Inference, 100002L, false))
    })
  }
  @fs.rmdir(path + ".next")
  ignore(store.issue({ ..intent, key_id: "retry-key", }, 100003L))
  ignore(store.authorize(issued.secret, Inference, 100003L, true))
  assert_eq(store.credentials[issued.credential.key_id].consumed_requests, 1L)
  assert_eq(store.revoke_subject("subject-a", 100004L), 2)
}

///|
async test "cancelled API authorization waiter leaves owner lock and quota intact" {
  let directory = @fs.tmpdir(prefix="lunanexa-access-cancel-waiter-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/keys.json"
  let store = AccessStore::open(
    path, "test-only-issuer-secret-0123456789abcdef",
  )
  let issued = store.issue(
    {
      key_id: "cancel-key",
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      organization_id: "organization-a",
      project_id: "project-a",
      display_name: "Cancellation fixture",
      scopes: [Inference],
      allowed_models: ["model-a"],
      expires_unix_ms: 200000L,
      maximum_requests: 2L,
    },
    100000L,
  )
  let before = ToJson::to_json(store.snapshot()).stringify()
  let entered = Ref(false)
  {
    store.mutex.acquire()
    defer store.mutex.release()
    try
      @async.with_timeout(20, () => {
        entered.val = true
        ignore(store.authorize(issued.secret, Inference, 100001L, true))
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("authorization bypassed held mutex")
    }
    assert_true(entered.val)
    assert_eq(ToJson::to_json(store.snapshot_unlocked()).stringify(), before)
  }
  @async.with_timeout(1000, () => {
    assert_eq(ToJson::to_json(store.snapshot()).stringify(), before)
    ignore(store.authorize(issued.secret, Inference, 100002L, true))
    let reopened = AccessStore::open(
      path, "test-only-issuer-secret-0123456789abcdef",
    )
    assert_eq(reopened.credentials["cancel-key"].consumed_requests, 1L)
  })
}
