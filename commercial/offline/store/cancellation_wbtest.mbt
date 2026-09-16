///|
suberror WaitCancelled

///|
async test "cancelled commerce writer cannot release another task's mutex or alter health" {
  let directory = @fs.tmpdir(prefix="lunanexa-commerce-cancel-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/store.json"
  let store = OfflineCommerceStore::open(path)
  let before = store.snapshot()
  let disk = @fs.read_file(path).text()
  {
    store.mutex.acquire()
    defer store.mutex.release()
    // A second waiter must also time out: cancellation of the first must not
    // release the mutex owned by this task.
    for now in [1000L, 2000L] {
      let entered = Ref(false)
      try
        @async.with_timeout(
          20,
          () => {
            entered.val = true
            store.record_reconciler_attempt(now)
          },
          error=WaitCancelled,
        )
      catch {
        WaitCancelled => ()
        error => fail("unexpected cancellation error: \{Repr(error)}")
      } noraise {
        _ => fail("writer bypassed the owner's lock")
      }
      assert_true(entered.val)
      assert_eq(store.snapshot_unlocked(), before)
      assert_eq(@fs.read_file(path).text(), disk)
    }
  }
  @async.with_timeout(1000, () => {
    store.record_reconciler_attempt(3000L)
    store.record_reconciler_success(3001L)
    let reopened = OfflineCommerceStore::open(path)
    assert_eq(reopened.snapshot(), store.snapshot())
    assert_eq(
      reopened.snapshot().worker_health.reconciler_success_unix_ms,
      Some(3001L),
    )
  })
}
