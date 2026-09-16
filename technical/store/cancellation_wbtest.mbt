///|
suberror TransferWaitCancelled

///|
async test "cancelled transfer waiters cannot consume a nonce or release the owner lock" {
  let directory = @fs.tmpdir(prefix="lunanexa-transfer-cancel-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/technical.json"
  let store = TechnicalStore::open(path)
  let grant : @technical.TransferGrant = {
    grant_id: "grant-cancel",
    nonce: "cancelled-nonce-0123456789",
    node_id: "node-fixture",
    deployment_id: "deployment-fixture",
    model_digest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    scope: ModelRead,
    issued_unix_ms: 1000L,
    expires_unix_ms: 2000L,
  }
  let requested : @technical.TransferGrantUse = {
    node_id: grant.node_id,
    deployment_id: grant.deployment_id,
    model_digest: grant.model_digest,
    scope: ModelRead,
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
            ignore(
              store.validate_and_consume_transfer(
                grant,
                requested,
                Verified,
                1100L,
                900000L,
              ),
            )
          },
          error=TransferWaitCancelled,
        )
      catch {
        TransferWaitCancelled => ()
        error => fail("unexpected cancellation: \{Repr(error)}")
      } noraise {
        _ => fail("transfer bypassed owner lock")
      }
      assert_true(entered.val)
      assert_eq(store.snapshot_unlocked(), before)
      assert_eq(@fs.read_file(path).text(), disk)
    }
  }
  @async.with_timeout(1000, () => {
    assert_true(
      store.validate_and_consume_transfer(
        grant,
        requested,
        Verified,
        1100L,
        900000L,
      )
      is Accepted(_),
    )
    let reopened = TechnicalStore::open(path)
    assert_eq(reopened.snapshot(), store.snapshot())
    assert_true(
      reopened.validate_and_consume_transfer(
        grant,
        requested,
        Verified,
        1101L,
        900000L,
      )
      is Rejected(NonceReplayed),
    )
  })
}
