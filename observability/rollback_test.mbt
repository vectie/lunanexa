///|
async test "failed snapshot writes roll back counters and release the operational lock" {
  let root = @fs.tmpdir(prefix="lunanexa-observability-rollback-")
  defer @fs.rmdir(root, recursive=true)
  let path = root + "/events.json"
  let store = @observability.ObservabilityStore::open(path)
  store.record(event("event-baseline", 1L))
  let before = store.snapshot()
  let durable_before = @fs.read_file(path).text()
  // A directory at the exact staging-file path deterministically rejects the
  // write without changing permissions or touching another test's files.
  @fs.mkdir(path + ".next")
  for _ in 0..<2 {
    let completed = @async.with_timeout_opt(2000, () => {
      try store.record(event("event-failed", 2L)) catch {
        _ => ()
      } noraise {
        _ => fail("blocked snapshot write unexpectedly succeeded")
      }
      try store.record_generated(event("ignored", 3L)) catch {
        _ => ()
      } noraise {
        _ => fail("blocked generated-event write unexpectedly succeeded")
      }
      true
    })
    assert_eq(completed, Some(true))
    assert_eq(store.snapshot(), before)
    assert_eq(@fs.read_file(path).text(), durable_before)
  }
  @fs.rmdir(path + ".next")
  let recovered = @async.with_timeout_opt(2000, () => {
    store.record(event("event-recovered", 4L))
    store.record_generated(event("ignored", 5L))
  })
  assert_true(recovered is Some(_))
  let reopened = @observability.ObservabilityStore::open(path)
  assert_eq(reopened.snapshot(), store.snapshot())
  assert_eq(store.snapshot().events.length(), 3)
}
