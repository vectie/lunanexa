///|
async test "prewarm and transfer replay fences survive restart" {
  let directory = @fs.tmpdir(prefix="lunanexa-technical-store-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/technical.json"
  let store = @store.TechnicalStore::open(path)
  let intent : @technical.PrewarmIntent = {
    operation_id: "prewarm-1",
    deployment_id: "deploy-1",
    node_id: "dgx-1",
    model_digest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    size_bytes: 1024L,
    created_unix_ms: 1000L,
    expires_unix_ms: 2000L,
  }
  let empty = store.snapshot()
  let empty_disk = @fs.read_file(path).text()
  @fs.mkdir(path + ".next")
  for _ in 0..<2 {
    try store.begin_prewarm(intent, 1000L) catch {
      _ => ()
    } noraise {
      _ => fail("prewarm write unexpectedly succeeded")
    }
    assert_eq(@async.with_timeout(1000, () => store.snapshot()), empty)
    assert_eq(@fs.read_file(path).text(), empty_disk)
  }
  @fs.rmdir(path + ".next")
  let operation = store.begin_prewarm(intent, 1000L)
  assert_eq(store.begin_prewarm(intent, 1001L), operation)
  guard operation is Accepted(candidate) else { fail("prewarm not accepted") }
  let pending = store.snapshot()
  let pending_disk = @fs.read_file(path).text()
  @fs.mkdir(path + ".next")
  for _ in 0..<2 {
    try store.advance_prewarm(candidate, Reserve, 1002L) catch {
      _ => ()
    } noraise {
      _ => fail("prewarm transition unexpectedly persisted")
    }
    assert_eq(@async.with_timeout(1000, () => store.snapshot()), pending)
    assert_eq(@fs.read_file(path).text(), pending_disk)
  }
  @fs.rmdir(path + ".next")
  assert_true(store.advance_prewarm(candidate, Reserve, 1002L) is Accepted(_))
  let grant : @technical.TransferGrant = {
    grant_id: "grant-1",
    nonce: "0123456789abcdef",
    node_id: "dgx-1",
    deployment_id: "deploy-1",
    model_digest: intent.model_digest,
    scope: ModelRead,
    issued_unix_ms: 1000L,
    expires_unix_ms: 2000L,
  }
  let requested : @technical.TransferGrantUse = {
    node_id: "dgx-1",
    deployment_id: "deploy-1",
    model_digest: intent.model_digest,
    scope: ModelRead,
  }
  let before_transfer = store.snapshot()
  let before_transfer_disk = @fs.read_file(path).text()
  @fs.mkdir(path + ".next")
  for _ in 0..<2 {
    try
      store.validate_and_consume_transfer(
        grant,
        requested,
        Verified,
        1100L,
        900000L,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("transfer consumption unexpectedly persisted")
    }
    assert_eq(
      @async.with_timeout(1000, () => store.snapshot()),
      before_transfer,
    )
    assert_eq(@fs.read_file(path).text(), before_transfer_disk)
  }
  @fs.rmdir(path + ".next")
  debug_inspect(
    store.validate_and_consume_transfer(
      grant,
      requested,
      Verified,
      1100L,
      900000L,
    ),
    content="Accepted(consumed_nonce=\"0123456789abcdef\")",
  )
  let reopened = @store.TechnicalStore::open(path)
  debug_inspect(
    reopened.validate_and_consume_transfer(
      grant,
      requested,
      Verified,
      1101L,
      900000L,
    ),
    content="Rejected(NonceReplayed)",
  )
}
