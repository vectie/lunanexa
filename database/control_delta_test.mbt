///|
async test "workload delta is atomic preserves snapshot and rejects stale epoch" {
  guard test_database_url() is Some(url) else { return }
  let database = @database.PostgresDatabase::open(url)
  defer database.close()
  let initial : Json = {
    "controller_epoch": "7",
    "assignments": [{ "id": "keep" }],
    "heartbeats": [{ "id": "keep-heartbeat" }],
    "workload_results": [],
    "audits": [],
  }
  database.save_opaque_snapshot(
    "control",
    "lunanexa.store.v1",
    initial.stringify(),
  )
  let record : Json = {
    "idempotency_key": "request-one",
    "response": { "workload_id": "one", "state": "Succeeded" },
  }
  database.commit_control_workload(
    7L,
    "one",
    record.stringify(),
    "{\"sequence\":1}",
  )
  let saved = database.load_snapshot("control", "lunanexa.store.v1").unwrap()
  assert_eq(@json.parse(saved), {
    "controller_epoch": "7",
    "assignments": [{ "id": "keep" }],
    "heartbeats": [{ "id": "keep-heartbeat" }],
    "workload_results": Json([record]),
    "audits": [{ "sequence": 1 }],
  })
  for (epoch, audit) in [(6L, "{\"sequence\":2}"), (7L, "not-json")] {
    try
      database.commit_control_workload(epoch, "one", record.stringify(), audit)
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid commit accepted")
    }
    assert_eq(
      database.load_snapshot("control", "lunanexa.store.v1"),
      Some(saved),
    )
  }
  database.commit_control_workload(
    7L,
    "one",
    record.stringify(),
    "{\"sequence\":2}",
  )
  guard @json.parse(
      database.load_snapshot("control", "lunanexa.store.v1").unwrap(),
    )
    is { "workload_results": Array(records), "audits": Array(audits), .. } else {
    fail("snapshot shape changed")
  }
  assert_eq(records, [record])
  assert_eq(audits.length(), 2)
}
