///|
async test "credential PostgreSQL restart preserves single-use redemption" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  database.save_opaque_snapshot(
    "credential_handoffs",
    @credential.snapshot_schema_version,
    @credential.CredentialHandoffSnapshot::{
      schema_version: @credential.snapshot_schema_version,
      records: [],
      issuer_requests: None,
    }
    .to_json()
    .stringify(),
  )
  let secret = "postgres-credential-issuer-secret-more-than-thirty-two-bytes"
  let now = @async.now()
  let lease = active_lease(now)
  let store = CredentialHandoffStore::open_postgres(database, secret).with_issuer_readiness({
      version: @credential.issuer_readiness_contract_version,
      adapter_id: "ssh-ca-postgres-test",
      health_endpoint: "https://ssh-ca.example/healthz",
      evidence_ref: "postgres-test-evidence",
      checked_unix_ms: now,
      expires_unix_ms: now + 86400000L,
      healthy: true,
      signature: "a".repeat(64),
    },
  )
  let record = store.issue(issue_intent(), lease, now)
  let redeemed = store.redeem(
    record.handoff_ref,
    lease,
    "subject-1",
    4L,
    now + 1L,
  )
  let reopened = CredentialHandoffStore::open_postgres(database, secret)
  assert_eq(
    reopened.redeem(record.handoff_ref, lease, "subject-1", 4L, now + 2L),
    redeemed,
  )
  database.close()
}
