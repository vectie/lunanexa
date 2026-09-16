///|
async test "cancelled audit operation releases its lock for subsequent receipts" {
  let root = @fs.tmpdir(prefix="lunanexa-audit-cancel-")
  defer @fs.rmdir(root, recursive=true)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "test-runtime-secret",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let service = ApiService::new(
    @store.FileStore::open(root + "/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "test",
  )
  let entered = Ref(false)
  let cancelled = @async.with_timeout_opt(50, () => {
    service.with_audit_lock(() => {
      entered.val = true
      @async.sleep(10000)
      true
    })
  })
  assert_true(entered.val)
  assert_eq(cancelled, None)
  assert_eq(
    @async.with_timeout_opt(2000, () => service.with_audit_lock(() => true)),
    Some(true),
  )
}
