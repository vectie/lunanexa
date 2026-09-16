///|
async test "failed import writes restore every mutation and release the lock" {
  let dir = @fs.tmpdir(prefix="import-write-failure-")
  let seed = FileImportStore::open("\{dir}/seed.json")
  let request : ImportRequest = { model_id: "test/model", revision: "main", }
  let record = seed.create(request, "apache-2.0", 1000L)
  let store : FileImportStore = {
    path: "\{dir}/missing/state.json",
    operations: seed.operations.copy(),
    mutex: Mutex(),
  }
  for _ in 0..<2 {
    let before = store.list()
    try
      store.create(
        { model_id: "test/another", revision: "main", },
        "apache-2.0",
        2000L,
      )
    catch {
      _ => assert_eq(store.list(), before)
    } noraise {
      _ => fail("write must fail")
    }
    try store.next_queued() catch {
      _ => assert_eq(store.list(), before)
    } noraise {
      _ => fail("claim must roll back")
    }
    try store.replace({ ..record, state: Failed, }) catch {
      _ => assert_eq(store.list(), before)
    } noraise {
      _ => fail("replace must roll back")
    }
    try store.cancel(record.import_id, 2000L) catch {
      _ => assert_eq(store.list(), before)
    } noraise {
      _ => fail("cancel must roll back")
    }
  }
  store.operations[record.import_id] = { ..record, state: Failed, }
  let before_retry = store.list()
  try store.retry(record.import_id, 3000L) catch {
    _ => assert_eq(store.list(), before_retry)
  } noraise {
    _ => fail("retry must roll back")
  }
  store.mutex.acquire()
  assert_eq(@async.with_timeout_opt(10, () => store.next_queued()), None)
  assert_eq(@async.with_timeout_opt(10, () => store.list()), None)
  store.mutex.release()
  assert_eq(store.list(), before_retry)
  @fs.remove("\{dir}/seed.json")
  @fs.remove(dir)
}

///|
async test "failed snapshot rename removes only its incomplete temporary file" {
  let dir = @fs.tmpdir(prefix="import-temporary-")
  let destination = "\{dir}/occupied"
  @fs.mkdir(destination)
  try write_snapshot(destination, Map([])) catch {
    _ => {
      assert_false(@fs.exists("\{destination}.next"))
      assert_true(@fs.exists(destination))
    }
  } noraise {
    _ => fail("directory destination must reject snapshot rename")
  }
  @fs.remove(destination)
  @fs.remove(dir)
}

///|
async test "cached model verification cancellation performs no network download" {
  let dir = @fs.tmpdir(prefix="modelscope-cache-cancel-")
  let path = "\{dir}/fixture"
  @fs.write_file(path, "fixture", create_mode=CreateOrTruncate)
  let client = ModelScopeClient::new()
  let file : ModelScopeFile = {
    path: "fixture",
    revision: "main",
    sha256: @crypto.bytes_to_hex_string(@crypto.sha256(b"fixture")),
    size: 7L,
    lfs: false,
  }
  assert_eq(
    @async.with_timeout_opt(10, () => {
      client.download_file(
        "test/model",
        "main",
        file,
        path,
        _ => @async.sleep(1000),
        () => false,
      )
    }),
    None,
  )
  client.download_file("test/model", "main", file, path, _ => (), () => false)
  assert_eq(@fs.read_file(path).text(), "fixture")
  @fs.remove(path)
  @fs.remove(dir)
}
