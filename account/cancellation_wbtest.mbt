///|
suberror AccountWaitCancelled

///|
async test "cancelled account writers and failed persistence preserve state and lock ownership" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-cleanup-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/accounts.json"
  let issuer = "account-cleanup-test-only-issuer-secret-32-bytes"
  let store = AccountStore::open(path, issuer)
  let account : HumanAccount = {
    version: contract_version,
    account_id: "cleanup-account",
    subject_ref: "cleanup-subject",
    identity_issuer: "https://identity.example/realms/lunanexa",
    identity_subject_sha256: identity_subject_digest(
      "https://identity.example/realms/lunanexa", "cleanup-provider-subject",
    ),
    display_name: "Cleanup fixture",
    email: "cleanup@example.invalid",
    identity_receipt: "cleanup-proof",
    roles: [EnterpriseUser],
    state: Active,
    created_unix_ms: 1000L,
    updated_unix_ms: 1000L,
  }
  let before = store.snapshot()
  let disk = @fs.read_file(path).text()
  {
    store.mutex.acquire()
    defer store.mutex.release()
    for _ in 0..<2 {
      let entered = Ref(false)
      try
        @async.with_timeout(
          20,
          () => {
            entered.val = true
            ignore(store.create(account))
          },
          error=AccountWaitCancelled,
        )
      catch {
        AccountWaitCancelled => ()
        error => fail("unexpected cancellation: \{Repr(error)}")
      } noraise {
        _ => fail("writer bypassed the owner lock")
      }
      assert_true(entered.val)
      assert_eq(store.snapshot_unlocked(), before)
      assert_eq(@fs.read_file(path).text(), disk)
    }
  }
  @fs.mkdir(path + ".next")
  for _ in 0..<2 {
    try @async.with_timeout(1000, () => store.create(account)) catch {
      _ => ()
    } noraise {
      _ => fail("blocked snapshot write unexpectedly succeeded")
    }
    // A separate timed read proves the failed writer released its lock.
    assert_eq(@async.with_timeout(1000, () => store.snapshot()), before)
    assert_eq(@fs.read_file(path).text(), disk)
  }
  @fs.rmdir(path + ".next")
  @async.with_timeout(1000, () => {
    ignore(store.create(account))
    let reopened = AccountStore::open(path, issuer)
    assert_eq(reopened.snapshot(), store.snapshot())
    assert_eq(reopened.snapshot().accounts.length(), 1)
  })
  let session = store.issue_session(
    account.identity_issuer,
    "cleanup-provider-subject",
    "cleanup-assertion",
    60000L,
    1001L,
  )
  let active = store.snapshot()
  let active_disk = @fs.read_file(path).text()
  @fs.mkdir(path + ".next")
  try store.set_state(account.account_id, Suspended, 1002L) catch {
    _ => ()
  } noraise {
    _ => fail("suspension unexpectedly persisted")
  }
  assert_eq(@async.with_timeout(1000, () => store.snapshot()), active)
  assert_eq(@fs.read_file(path).text(), active_disk)
  @fs.rmdir(path + ".next")
  @async.with_timeout(1000, () => {
    ignore(store.authorize(session.secret, 1003L, required_role=EnterpriseUser))
    ignore(store.set_state(account.account_id, Suspended, 1004L))
    let reopened = AccountStore::open(path, issuer)
    assert_eq(reopened.snapshot(), store.snapshot())
    try
      reopened.authorize(session.secret, 1005L, required_role=EnterpriseUser)
    catch {
      AccountError::Unauthorized => ()
      error => fail("unexpected authorization error: \{Repr(error)}")
    } noraise {
      _ => fail("suspended account retained session authority")
    }
  })
}
