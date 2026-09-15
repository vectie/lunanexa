///|
async test "cancelled candidate never publishes and cannot strand the store mutex" {
  let directory = @fs.tmpdir(prefix="lunanexa-store-cancel-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/state.json"
  let store = FileStore::open(path)
  let before = store.backup_snapshot()
  let entered = Ref(false)
  try
    @async.with_timeout(20, () => {
      store.update(next => {
        next.set_controller_epoch(99L)
        entered.val = true
        @async.sleep(10000)
      })
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("candidate was not cancelled")
  }
  assert_true(entered.val)
  @async.with_timeout(1000, () => {
    assert_eq(store.backup_snapshot(), before)
    assert_eq(FileStore::open(path).backup_snapshot(), before)
    store.fence_controller(2L)
    assert_eq(store.controller_epoch(), 2L)
  })
}
