///|
async test "shared quota reservation follows live key checks and serializes concurrent use" {
  let directory = @fs.tmpdir(prefix="lunanexa-shared-quota-")
  defer @fs.rmdir(directory, recursive=true)
  let store = @access.AccessStore::open(
    "\{directory}/keys.json",
    "shared-quota-secret-more-than-32-bytes",
  )
  let intent : @access.ApiKeyIssueIntent = {
    key_id: "key-shared",
    tenant_ref: "tenant-a",
    subject_ref: "subject-a",
    organization_id: "org-a",
    project_id: "project-a",
    display_name: "Shared quota",
    scopes: [Inference],
    allowed_models: ["text.qwen"],
    expires_unix_ms: 200000L,
    maximum_requests: 1L,
  }
  let issued = store.issue(intent, 100000L)
  let reserved = Ref(0)
  let reserve = async fn(_legacy : Int64) -> Bool {
    @async.sleep(1)
    reserved.val += 1
    true
  }
  // Expired and revoked credentials never reach the shared authority.
  try
    store.authorize(
      issued.secret,
      Inference,
      200000L,
      true,
      reserve_quota=reserve,
    )
  catch {
    @access.AccessError::Unauthorized => ()
    _ => fail("unexpected expired key outcome")
  } noraise {
    _ => fail("expired key admitted")
  }
  let revoked = store.issue({ ..intent, key_id: "key-revoked", }, 100000L)
  ignore(store.revoke("key-revoked", 100001L))
  try
    store.authorize(
      revoked.secret,
      Inference,
      100002L,
      true,
      reserve_quota=reserve,
    )
  catch {
    @access.AccessError::Unauthorized => ()
    _ => fail("unexpected revoked key outcome")
  } noraise {
    _ => fail("revoked key admitted")
  }
  assert_eq(reserved.val, 0)
  // Failed shared admission does not consume the individual key quota.
  try
    store.authorize(issued.secret, Inference, 100002L, true, reserve_quota=_legacy => {
      false
    })
  catch {
    @access.AccessError::QuotaExceeded => ()
    _ => fail("unexpected shared rejection")
  } noraise {
    _ => fail("shared rejection bypassed")
  }
  assert_eq(
    store.views().filter(key => key.key_id == "key-shared")[0].consumed_requests,
    0L,
  )
  try
    store.authorize(issued.secret, Inference, 100002L, true, reserve_quota=_legacy => {
      raise Failure("shared persistence failed")
    })
  catch {
    Failure(message) => assert_eq(message, "shared persistence failed")
    _ => fail("unexpected shared persistence failure")
  } noraise {
    _ => fail("shared persistence failure ignored")
  }
  assert_eq(
    store.views().filter(key => key.key_id == "key-shared")[0].consumed_requests,
    0L,
  )
  let admitted = Ref(0)
  let exhausted = Ref(0)
  @async.with_task_group(group => {
    for _ in 0..<2 {
      group.spawn_bg(() => {
        try
          store.authorize(
            issued.secret,
            Inference,
            100002L,
            true,
            reserve_quota=reserve,
          )
        catch {
          @access.AccessError::QuotaExceeded => exhausted.val += 1
          _ => fail("unexpected concurrent key outcome")
        } noraise {
          _ => admitted.val += 1
        }
      })
    }
  })
  assert_eq(admitted.val, 1)
  assert_eq(exhausted.val, 1)
  assert_eq(reserved.val, 1)
  // Read/replay checks remain valid but never call the reservation callback.
  ignore(
    store.authorize(
      issued.secret,
      Inference,
      100003L,
      false,
      reserve_quota=reserve,
    ),
  )
  assert_eq(reserved.val, 1)
}
