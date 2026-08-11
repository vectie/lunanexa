///|
async test "prewarm and transfer replay fences survive restart" {
  let path = "/tmp/lunanexa-technical-store-\{@async.now()}.json"
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
  let operation = store.begin_prewarm(intent, 1000L)
  assert_eq(store.begin_prewarm(intent, 1001L), operation)
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
