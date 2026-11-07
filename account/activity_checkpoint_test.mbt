///|
async test "twenty live identities share one activity checkpoint without caching authority" {
  let dir = @fs.tmpdir(prefix="account-activity-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/accounts.json"
  let issuer = "activity-checkpoint-test-issuer-at-least-32-bytes"
  let store = @account.AccountStore::open(path, issuer)
  let secrets : Array[String] = []
  for i in 0..<20 {
    let id = "activity-\{i}"
    ignore(store.create(account_fixture(id, id, id, [EnterpriseUser], 100000L)))
    secrets.push(
      store.issue_session(
        "https://identity.example/realms/lunanexa", id, id, 60000L, 100001L,
      ).secret,
    )
  }
  ignore(store.authorize(secrets[0], 100002L))
  let checkpoint = @fs.read_file(path).text()
  @async.with_task_group(group => {
    for i in 0..<20 {
      group.spawn_bg(() => {
        let auth = store.authorize(secrets[i], 100003L)
        assert_eq(auth.account.account_id, "activity-\{i}")
      })
    }
  })
  assert_eq(@fs.read_file(path).text(), checkpoint)
  assert_true(
    store.snapshot().sessions.all(s => s.last_used_unix_ms == 100003L),
  )
  ignore(store.authorize(secrets[1], 130002L))
  assert_false(@fs.read_file(path).text() == checkpoint)
  let reopened = @account.AccountStore::open(path, issuer)
  assert_eq(reopened.snapshot(), store.snapshot())
  ignore(store.set_state("activity-0", Suspended, 130003L))
  try store.authorize(secrets[0], 130004L) catch {
    @account.AccountError::Unauthorized => ()
    e => fail("unexpected rejection: \{Repr(e)}")
  } noraise {
    _ => fail("activity checkpoint cached a suspended identity")
  }
}

///|
async test "failed activity checkpoint rolls back the touch and remains retryable" {
  let dir = @fs.tmpdir(prefix="account-activity-failure-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/accounts.json"
  let store = @account.AccountStore::open(
    path, "activity-failure-test-issuer-at-least-32-bytes",
  )
  ignore(
    store.create(
      account_fixture("one", "one", "one", [EnterpriseUser], 100000L),
    ),
  )
  let issued = store.issue_session(
    "https://identity.example/realms/lunanexa", "one", "one", 60000L, 100001L,
  )
  let before = store.snapshot()
  @fs.mkdir(path + ".next")
  try store.authorize(issued.secret, 100002L) catch {
    _ => ()
  } noraise {
    _ => fail("blocked checkpoint unexpectedly succeeded")
  }
  assert_eq(@async.with_timeout(1000, () => store.snapshot()), before)
  @fs.rmdir(path + ".next")
  ignore(store.authorize(issued.secret, 100003L))
  assert_true(@fs.read_file(path).text().contains("100003"))
}
