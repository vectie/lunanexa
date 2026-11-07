///|
async test "inference delta atomically preserves history and replay semantics" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let name = url.split("/").to_array().last().unwrap().split("?").to_array()[0]
  guard name.has_suffix("_test") else {
    fail("isolated test database required")
  }
  let db = PostgresDatabase::open(url)
  let original : Json = {
    "schema_version": "test-v1",
    "signature_callbacks": [],
    "commercial": {
      "usage_observations": [],
      "ledger_entries": [],
      "history": "keep-".repeat(50000),
    },
  }
  db.save_opaque_snapshot("commercial", "test-v1", original.stringify())
  db.save_opaque_snapshot(
    "commercial_integrations", "test-v1", "{\"untouched\":true}",
  )
  let observation = "{\"event_id\":\"one\",\"quantity\":7}"
  let entry = "{\"entry_id\":\"charge-one\",\"source_event_id\":\"one\",\"amount\":7}"
  db.commit_inference_usage("test-v1", observation, Some(entry))
  db.commit_inference_usage("test-v1", observation, Some(entry))
  let saved = db.load_snapshot("commercial", "test-v1").unwrap()
  let expected : Json = {
    "schema_version": "test-v1",
    "signature_callbacks": [],
    "commercial": {
      "usage_observations": [@json.parse(observation)],
      "ledger_entries": [@json.parse(entry)],
      "history": "keep-".repeat(50000),
    },
  }
  assert_eq(@json.parse(saved), expected)
  for
    (event, charge) in [
      ("{\"event_id\":\"one\",\"quantity\":8}", entry),
      (
        "{\"event_id\":\"two\",\"quantity\":7}", "{\"entry_id\":\"charge-one\",\"source_event_id\":\"two\",\"amount\":7}",
      ),
    ] {
    try db.commit_inference_usage("test-v1", event, Some(charge)) catch {
      _ => ()
    } noraise {
      _ => fail("conflicting replay committed")
    }
    assert_eq(db.load_snapshot("commercial", "test-v1"), Some(saved))
  }
  db.commit_inference_usage(
    "test-v1",
    "{\"event_id\":\"prepaid\",\"quantity\":3}",
    None,
  )
  let latest = db.load_snapshot("commercial", "test-v1").unwrap()
  assert_eq(
    @json.parse(db.load_snapshot("commercial_integrations", "test-v1").unwrap()),
    { "untouched": true },
  )
  db.close()
  let reopened = PostgresDatabase::open(url)
  defer reopened.close()
  assert_eq(reopened.load_snapshot("commercial", "test-v1"), Some(latest))
  // Legacy full-snapshot writes retain the exact same storage contract.
  reopened.save_opaque_snapshot("commercial", "test-v1", latest)
  assert_eq(reopened.load_snapshot("commercial", "test-v1"), Some(latest))
}
