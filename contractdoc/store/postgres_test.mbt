///|
/// The database these tests write to must be a disposable one. They overwrite
/// snapshot rows and truncate projection tables, so pointing them at a live
/// deployment silently destroys its state: that is exactly how the production
/// `accounts`, `commercial`, `commercial_integrations` and `client_handoffs`
/// snapshots were replaced with fixtures and the control plane refused to start.
///
/// Set `LUNANEXA_TEST_DATABASE_URL` to a database whose name ends in `_test`.
/// A URL that does not is refused loudly rather than damaging the deployment.
fn test_database_url() -> String? {
  let url = @env.get_env_var("LUNANEXA_TEST_DATABASE_URL")
  match url {
    None => None
    Some(value) => {
      // Database name: the last path segment, before any query string.
      let mut name = ""
      for segment in value.split("/") {
        name = segment.to_owned()
      }
      let mut base = ""
      let mut first = true
      for part in name.split("?") {
        if first {
          base = part.to_owned()
          first = false
        }
      }
      if !base.has_suffix("_test") {
        abort(
          "LUNANEXA_TEST_DATABASE_URL must name a *_test database; refusing to run against \{base}",
        )
      }
      Some(value)
    }
  }
}

///|
async test "undertaking PostgreSQL reopen and failed write preserve packet audit and idempotency" {
  guard test_database_url() is Some(url) else { return }
  let database = @database.PostgresDatabase::open(url)
  let store = ContractDocumentStore::open_postgres(database)
  let manifest = @contractdoc.undertaking_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "pg-undertaking",
    "pg-undertaking-key",
    "tenant-pg",
    "org-pg",
    "subject-pg",
    "order-pg",
    None,
    [MasterLease],
    1000L,
  )
  ignore(store.create_packet(packet, packet.subject_ref))
  let updated = store.update_information(
    manifest,
    packet.packet_id,
    packet.revision,
    [
      { field_id: "lessee.name", value: "数据库验收单位" },
      { field_id: "undertaking.signed_date", value: "2026-09-16" },
    ],
    CustomerMessenger,
    packet.subject_ref,
    "postgres-acceptance",
    2000L,
  )
  let before = store.snapshot()
  let reopened = ContractDocumentStore::open_postgres(database)
  assert_eq(reopened.snapshot(), before)
  assert_eq(reopened.packet(packet.packet_id), Some(updated))
  assert_false(
    before.events.to_json().stringify().contains("数据库验收单位"),
  )
  database.close()
  for _ in 0..<2 {
    try
      reopened.update_information(
        manifest,
        packet.packet_id,
        updated.revision,
        [{ field_id: "lessee.name", value: "must-not-persist" }],
        CustomerMessenger,
        packet.subject_ref,
        "postgres-acceptance",
        3000L,
      )
    catch {
      @database.DatabaseError::QueryFailed(_) => ()
      error => fail("unexpected database failure: \{Repr(error)}")
    } noraise {
      _ => fail("closed database accepted undertaking mutation")
    }
    assert_eq(reopened.snapshot(), before)
  }
  let successor = @database.PostgresDatabase::open(url)
  defer successor.close()
  let recovered = ContractDocumentStore::open_postgres(successor)
  assert_eq(recovered.snapshot(), before)
  assert_eq(recovered.create_packet(updated, packet.subject_ref), updated)
  try recovered.create_packet(packet, packet.subject_ref) catch {
    @contractdoc.ContractDocumentError::IdempotencyConflict(_) => ()
    error => fail("unexpected stale creation replay: \{Repr(error)}")
  } noraise {
    _ => fail("stale creation payload replaced updated undertaking")
  }
  assert_eq(recovered.snapshot(), before)
  let retry = recovered.update_information(
    manifest,
    packet.packet_id,
    updated.revision,
    [{ field_id: "lessee.name", value: "retry-persisted" }],
    CustomerMessenger,
    packet.subject_ref,
    "postgres-acceptance",
    4000L,
  )
  assert_eq(retry.revision, updated.revision + 1L)
  assert_eq(
    ContractDocumentStore::open_postgres(successor).packet(packet.packet_id),
    Some(retry),
  )
}
