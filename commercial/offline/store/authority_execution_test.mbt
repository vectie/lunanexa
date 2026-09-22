///|
async test "authority execution holds order fence and releases it after failure" {
  let path = temp_path("authority-fence")
  let store = @store.OfflineCommerceStore::open(path)
  let order = ready_for_upload(store, "authority-fence")
  let events : Array[String] = []
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      store.with_authority_execution((snapshot, _, _) => {
        assert_true(
          snapshot.orders.any(value => value.order_id == order.order_id),
        )
        events.push("execution-start")
        @async.sleep(30)
        events.push("execution-end")
      })
    })
    group.spawn_bg(() => {
      @async.sleep(5)
      ignore(store.cancel_order(order.order_id, order.generation, 2200L))
      events.push("cancellation")
    })
  })
  assert_eq(events, ["execution-start", "execution-end", "cancellation"])
  try {
    let _ : Unit = store.with_authority_execution((_, _, _) => {
      raise Failure::Failure("injected authority failure")
    })
  } catch {
    _ => ()
  } noraise {
    _ => fail("expected injected failure")
  }
  assert_eq(store.order_for_operator(order.order_id).state, Cancelled)
  @fs.remove(path)
}
