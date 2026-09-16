///|
fn rollback_fixture() -> @contractdoc.ContractPacket raise {
  @contractdoc.new_packet(
    @contractdoc.youthpolicy_remote_lease_manifest(),
    "rollback-packet",
    "rollback-key",
    "tenant-a",
    "org-a",
    "subject-a",
    "order-a",
    None,
    [ReservationApplication],
    1000L,
  )
}

///|
async test "persistence failures restore packet indexes events and number sequences before unlock" {
  let dir = @fs.tmpdir(prefix="contract-rollback-")
  // Missing parent makes the write fail before any snapshot can be committed.
  let store = ContractDocumentStore::empty(
    ContractFile("\{dir}/missing/state.json"),
  )
  let packet = rollback_fixture()
  let before = store.snapshot()
  for _ in 0..<2 {
    try store.create_packet(packet, "subject-a") catch {
      _ => assert_eq(store.snapshot(), before)
    } noraise {
      _ => fail("unwritable snapshot unexpectedly persisted")
    }
    assert_eq(store.idempotency_keys.length(), 0)
  }
  store.packets[packet.packet_id] = packet
  let seeded = store.snapshot()
  for _ in 0..<2 {
    try
      store.allocate_contract_number("tenant-a", packet.packet_id, 2000L)
    catch {
      _ => assert_eq(store.snapshot(), seeded)
    } noraise {
      _ => fail("unwritable number unexpectedly persisted")
    }
    assert_eq(store.number_sequences.length(), 0)
  }
  @fs.remove(dir)
}

///|
async test "cancelled lock waiter neither mutates state nor releases another transaction lock" {
  let dir = @fs.tmpdir(prefix="contract-cancel-")
  let path = "\{dir}/state.json"
  let store = ContractDocumentStore::open(path)
  let packet = rollback_fixture()
  let before = store.snapshot()
  store.mutex.acquire()
  let cancelled = @async.with_timeout_opt(10, () => {
    store.create_packet(packet, "subject-a")
  })
  assert_eq(cancelled, None)
  assert_eq(store.snapshot_unlocked(), before)
  // A second waiter must still block: the first cancellation did not unlock.
  assert_eq(@async.with_timeout_opt(10, () => store.snapshot()), None)
  store.mutex.release()
  ignore(store.create_packet(packet, "subject-a"))
  assert_eq(store.packet(packet.packet_id), Some(packet))
  @fs.remove(path)
  @fs.remove(dir)
}
