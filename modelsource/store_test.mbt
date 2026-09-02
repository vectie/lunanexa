///|
async test "model import recovery and retry transitions are durable" {
  let directory = @fs.tmpdir(prefix="lunanexa-modelsource-store-")
  let path = "\{directory}/imports.json"
  let store = FileImportStore::open(path)
  let created = store.create(
    { model_id: "OpenBMB/MiniCPM5-1B", revision: "master" },
    "apache-2.0",
    1000L,
  )
  guard store.next_queued() is Some(downloading) else {
    fail("expected the queued import to be claimed")
  }
  assert_eq(downloading.state, Downloading)
  ignore(
    store.replace({
      ..downloading,
      files_total: 11,
      files_completed: 2,
      bytes_total: 2171355326L,
      bytes_completed: 1048576L,
      updated_unix_ms: 1100L,
    }),
  )

  let recovered = FileImportStore::open(path)
  guard recovered.get(created.import_id) is Some(after_restart) else {
    fail("expected the import to survive restart")
  }
  assert_eq(after_restart.state, Queued)
  assert_eq(after_restart.error_code, "recovered-after-restart")
  assert_eq(after_restart.bytes_completed, 1048576L)

  guard recovered.next_queued() is Some(reclaimed) else {
    fail("expected the recovered import to be claimable")
  }
  ignore(
    recovered.replace({
      ..reclaimed,
      state: Failed,
      error_code: "digest-mismatch",
      updated_unix_ms: 1200L,
    }),
  )
  let retried = recovered.retry(created.import_id, 1300L)
  assert_eq(retried.state, Queued)
  assert_eq(retried.error_code, "")
  assert_false(retried.cancel_requested)

  let nonterminal_rejected = try {
    ignore(recovered.retry(created.import_id, 1400L))
    false
  } catch {
    @modelsource.ModelSourceError::ImportNotRetryable => true
    _ => false
  } noraise {
    value => value
  }
  assert_true(nonterminal_rejected)
}

///|
async test "cancelled imports can retry without creating a duplicate identity" {
  let directory = @fs.tmpdir(prefix="lunanexa-modelsource-cancel-")
  let path = "\{directory}/imports.json"
  let store = FileImportStore::open(path)
  let first = store.create(
    { model_id: "OpenBMB/MiniCPM5-1B", revision: "master" },
    "apache-2.0",
    2000L,
  )
  let cancelled = store.cancel(first.import_id, 2100L)
  assert_eq(cancelled.state, Cancelled)
  let retried = store.retry(first.import_id, 2200L)
  assert_eq(retried.import_id, first.import_id)
  assert_eq(retried.state, Queued)
  assert_eq(store.list().length(), 1)
}
