///|
suberror WaitCancelled

///|
async test "cancelled telemetry waiters preserve the owner lock and durable history" {
  let directory = @fs.tmpdir(prefix="lunanexa-telemetry-cancel-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/telemetry.json"
  let store = FileTelemetry::open(path)
  let sample : @contracts.TelemetrySample = {
    node_id: "fixture-node",
    deployment_id: "fixture-deployment",
    metric: "accelerator_utilization_per_mille",
    value: 123.0,
    timestamp_unix_ms: 1000L,
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
            store.record_sample(sample)
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
    store.record_sample(sample)
    let reopened = FileTelemetry::open(path)
    assert_eq(reopened.snapshot().samples, [sample])
    assert_eq(reopened.snapshot(), store.snapshot())
  })
}
