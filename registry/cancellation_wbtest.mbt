///|
suberror RegistryWaitCancelled

///|
async test "cancelled registry waiters do not release the owner's lock" {
  let directory = @fs.tmpdir(prefix="lunanexa-registry-cancel-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/registry.json"
  let store = FileRegistry::open(path)
  let before = store.registry.snapshot()
  {
    store.mutex.acquire()
    defer store.mutex.release()
    for _ in 0..<2 {
      let entered = Ref(false)
      try
        @async.with_timeout(
          20,
          () => store.update(_ => entered.val = true),
          error=RegistryWaitCancelled,
        )
      catch {
        RegistryWaitCancelled => ()
        error => fail("unexpected error: \{Repr(error)}")
      } noraise {
        _ => fail("waiter bypassed owner lock")
      }
      assert_false(entered.val)
      assert_eq(store.registry.snapshot(), before)
      assert_eq(@fs.read_file(path).text(), before)
    }
  }
  @async.with_timeout(1000, () => {
    store.update(_ => ())
    assert_eq(store.snapshot(), FileRegistry::open(path).snapshot())
  })
}
