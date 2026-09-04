///|
async test "journal survives restart and resumes without skipping steps" {
  let temp = @fs.tmpdir(prefix="lunanexa-onboarding-journal-")
  let path = "\{temp}/journal.json"
  let intent : @onboarding.AccessOnboardingIntent = {
    operation_id: "access-account-demo",
    fingerprint: "0123456789abcdef01234567",
    requested_by: "operator-demo",
    account_id: "account-demo",
    subject_ref: "subject-demo",
    identity_issuer: "https://identity.example",
    identity_subject_sha256: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    display_name: "Demo User",
    email: "demo@example.com",
    organization_id: "org-demo",
    tenant_ref: "tenant-demo",
    membership_id: "membership-demo",
    user_id: "user-demo",
    grant_id: "grant-demo",
    lease_id: "lease-demo",
    identity_receipt: "oidc-verified-demo",
    expires_unix_ms: 200000L,
  }
  let first = @onboarding.AccessOnboardingStore::open(path)
  ignore(first.begin(intent, 1000L))
  ignore(first.advance(intent.operation_id, AccountReady, 1001L))
  let failed = first.fail(
    intent.operation_id,
    "PortalUnavailable",
    "portal write failed",
    false,
    1002L,
  )
  assert_eq(failed.status, RecoverableFailure)
  let reopened = @onboarding.AccessOnboardingStore::open(path)
  assert_eq(reopened.pending().length(), 1)
  let resumed = reopened.retry(intent.operation_id, 1003L)
  assert_eq(resumed.step, AccountReady)
  assert_eq(resumed.attempts, 2)
  ignore(reopened.advance(intent.operation_id, MembershipReady, 1004L))
  ignore(reopened.advance(intent.operation_id, WorkspaceUserReady, 1005L))
  ignore(reopened.advance(intent.operation_id, GrantReady, 1006L))
  ignore(reopened.advance(intent.operation_id, LeaseReady, 1007L))
  let prepared = reopened.advance(intent.operation_id, Prepared, 1008L)
  assert_eq(prepared.status, PreparedForEnablement)
  let completed = reopened.advance(intent.operation_id, Enabled, 1009L)
  assert_eq(completed.status, Completed)
  assert_eq(reopened.pending().length(), 0)
}

///|
async test "journal rejects conflicting replay and terminal conflict is visible" {
  let temp = @fs.tmpdir(prefix="lunanexa-onboarding-conflict-")
  let store = @onboarding.AccessOnboardingStore::open("\{temp}/journal.json")
  let intent : @onboarding.AccessOnboardingIntent = {
    operation_id: "access-account-demo",
    fingerprint: "0123456789abcdef01234567",
    requested_by: "operator-demo",
    account_id: "account-demo",
    subject_ref: "subject-demo",
    identity_issuer: "https://identity.example",
    identity_subject_sha256: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    display_name: "Demo User",
    email: "demo@example.com",
    organization_id: "org-demo",
    tenant_ref: "tenant-demo",
    membership_id: "membership-demo",
    user_id: "user-demo",
    grant_id: "grant-demo",
    lease_id: "lease-demo",
    identity_receipt: "oidc-verified-demo",
    expires_unix_ms: 200000L,
  }
  ignore(store.begin(intent, 1000L))
  try store.begin({ ..intent, tenant_ref: "tenant-other" }, 1001L) catch {
    @onboarding.AccessOnboardingError::IdempotencyConflict(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected conflict")
  }
  let conflicted = store.fail(
    intent.operation_id,
    "ResourceConflict",
    "derived membership belongs to another tenant",
    true,
    1002L,
  )
  assert_eq(conflicted.status, Conflicted)
  assert_eq(store.pending().length(), 0)
}

///|
async test "PostgreSQL journal survives a store restart" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let now = @async.now()
  let suffix = now.to_string()
  let database = @database.PostgresDatabase::open(url)
  let first = @onboarding.AccessOnboardingStore::open_postgres(database)
  let intent : @onboarding.AccessOnboardingIntent = {
    operation_id: "access-account-pg-\{suffix}",
    fingerprint: "pg-\{suffix}",
    requested_by: "operator-pg",
    account_id: "account-pg-\{suffix}",
    subject_ref: "subject-pg-\{suffix}",
    identity_issuer: "https://identity.example",
    identity_subject_sha256: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    display_name: "Postgres User",
    email: "postgres@example.com",
    organization_id: "org-pg",
    tenant_ref: "tenant-pg",
    membership_id: "membership-pg-\{suffix}",
    user_id: "user-pg-\{suffix}",
    grant_id: "grant-pg-\{suffix}",
    lease_id: "lease-pg-\{suffix}",
    identity_receipt: "oidc-pg-\{suffix}",
    expires_unix_ms: now + 86400000L,
  }
  ignore(first.begin(intent, now))
  ignore(first.advance(intent.operation_id, AccountReady, now + 1L))
  let reopened = @onboarding.AccessOnboardingStore::open_postgres(database)
  guard reopened.record(intent.operation_id) is Some(record) else {
    fail("PostgreSQL onboarding journal was not restored")
  }
  assert_eq(record.step, AccountReady)
  database.close()
}
