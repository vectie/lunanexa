///|
fn account_fixture(
  account_id : String,
  subject_ref : String,
  provider_subject : String,
  roles : Array[@account.AccountRole],
  now_unix_ms : Int64,
) -> @account.HumanAccount {
  {
    version: @account.contract_version,
    account_id,
    subject_ref,
    identity_issuer: "https://identity.example/realms/lunanexa",
    identity_subject_sha256: @account.identity_subject_digest(
      "https://identity.example/realms/lunanexa", provider_subject,
    ),
    display_name: "Human \{account_id}",
    email: "\{account_id}@example.invalid",
    identity_receipt: "identity-proof:\{account_id}",
    roles,
    state: Active,
    created_unix_ms: now_unix_ms,
    updated_unix_ms: now_unix_ms,
  }
}

///|
async test "account sessions are hashed, restart durable, and assertion bound" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-")
  let path = "\{directory}/accounts.json"
  let issuer_secret = "account-session-issuer-secret-more-than-32-bytes"
  let store = @account.AccountStore::open(path, issuer_secret)
  let now = 100000L
  ignore(
    store.create(
      account_fixture(
        "account-one",
        "account:one",
        "provider-subject-one",
        [EnterpriseUser],
        now,
      ),
    ),
  )
  let issued = store.issue_session(
    "https://identity.example/realms/lunanexa",
    "provider-subject-one",
    "assertion-jti-one",
    60000L,
    now + 1L,
  )
  assert_true(issued.secret.has_prefix("lnxs_"))
  let persisted = @fs.read_file(path).text()
  assert_false(persisted.contains(issued.secret))
  assert_false(persisted.contains("provider-subject-one"))
  assert_true(persisted.contains("sha256:"))
  let reopened = @account.AccountStore::open(path, issuer_secret)
  let authorization = reopened.authorize(
    issued.secret,
    now + 2L,
    required_role=EnterpriseUser,
  )
  assert_eq(authorization.account.subject_ref, "account:one")
  try
    reopened.issue_session(
      "https://identity.example/realms/lunanexa",
      "provider-subject-one",
      "assertion-jti-one",
      60000L,
      now + 3L,
    )
  catch {
    @account.AccountError::AssertionReplayed => ()
    _ => fail("unexpected replay error")
  } noraise {
    _ => fail("identity assertion replay issued another session")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "roles stay server-side and suspension invalidates sessions immediately" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-state-")
  let store = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "another-account-session-issuer-secret-more-than-32-bytes",
  )
  let now = 200000L
  ignore(
    store.create(
      account_fixture(
        "account-operator",
        "account:operator",
        "external-operator",
        [PlatformOperator],
        now,
      ),
    ),
  )
  let issued = store.issue_session(
    "https://identity.example/realms/lunanexa",
    "external-operator",
    "assertion-operator-one",
    60000L,
    now + 1L,
  )
  ignore(
    store.authorize(issued.secret, now + 2L, required_role=PlatformOperator),
  )
  ignore(store.set_state("account-operator", Suspended, now + 3L))
  try
    store.authorize(issued.secret, now + 4L, required_role=PlatformOperator)
  catch {
    @account.AccountError::Unauthorized => ()
    _ => fail("unexpected suspended-session error")
  } noraise {
    _ => fail("suspended account retained an authorized session")
  }
  ignore(store.set_state("account-operator", Active, now + 5L))
  let replacement = store.issue_session(
    "https://identity.example/realms/lunanexa",
    "external-operator",
    "assertion-operator-two",
    60000L,
    now + 6L,
  )
  ignore(store.set_roles("account-operator", [AuditReader], now + 7L))
  try
    store.authorize(replacement.secret, now + 8L, required_role=AuditReader)
  catch {
    @account.AccountError::Unauthorized => ()
    _ => fail("unexpected role-change session error")
  } noraise {
    _ => fail("role mutation did not revoke existing sessions")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "session listing and revoke-all expose no credential material" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-revoke-")
  let store = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "revoke-account-session-issuer-secret-more-than-32-bytes",
  )
  let now = 300000L
  ignore(
    store.create(
      account_fixture(
        "account-user",
        "account:user",
        "external-user",
        [EnterpriseUser],
        now,
      ),
    ),
  )
  let first = store.issue_session(
    "https://identity.example/realms/lunanexa",
    "external-user",
    "assertion-user-one",
    60000L,
    now + 1L,
  )
  ignore(
    store.issue_session(
      "https://identity.example/realms/lunanexa",
      "external-user",
      "assertion-user-two",
      60000L,
      now + 2L,
    ),
  )
  let views = store.sessions_for_account("account-user")
  assert_eq(views.length(), 2)
  assert_false(views.to_json().stringify().contains("sha256"))
  assert_false(views.to_json().stringify().contains("lnxs_"))
  assert_eq(store.revoke_all_sessions("account-user", now + 3L), 2)
  try store.authorize(first.secret, now + 4L) catch {
    @account.AccountError::Unauthorized => ()
    _ => fail("unexpected revoked-session error")
  } noraise {
    _ => fail("revoked session remained authorized")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "active sessions are capped and use cannot extend past expiry" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-cap-")
  let store = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "capped-account-session-issuer-secret-more-than-32-bytes",
  )
  let now = 400000L
  ignore(
    store.create(
      account_fixture(
        "account-capped",
        "account:capped",
        "external-capped",
        [EnterpriseUser],
        now,
      ),
    ),
  )
  let mut first_secret = ""
  let mut first_session_id = ""
  for index in 0..<8 {
    let issued = store.issue_session(
      "https://identity.example/realms/lunanexa",
      "external-capped",
      "assertion-capped-\{index}",
      30000L,
      now + index.to_int64() + 1L,
    )
    if index == 0 {
      first_secret = issued.secret
      first_session_id = issued.session.session_id
    }
  }
  try
    store.issue_session(
      "https://identity.example/realms/lunanexa",
      "external-capped",
      "assertion-capped-over-limit",
      30000L,
      now + 10L,
    )
  catch {
    @account.AccountError::InvalidInput(_) => ()
    _ => fail("unexpected active-session-cap error")
  } noraise {
    _ => fail("ninth active session was issued")
  }
  try store.authorize(first_secret, now + 30001L) catch {
    @account.AccountError::Unauthorized => ()
    _ => fail("unexpected expired-session error")
  } noraise {
    _ => fail("expired session was authorized")
  }
  guard store
    .sessions_for_account("account-capped")
    .iter()
    .find_first(session => session.session_id == first_session_id)
    is Some(first) else {
    fail("first session disappeared")
  }
  assert_eq(first.last_used_unix_ms, now + 1L)
  assert_true(first.last_used_unix_ms <= first.expires_unix_ms)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "completed browser sessions are pruned after bounded retention" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-prune-")
  let store = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "pruned-account-session-issuer-secret-more-than-32-bytes",
  )
  let now = 100000L
  ignore(
    store.create(
      account_fixture(
        "account-pruned",
        "account:pruned",
        "external-pruned",
        [EnterpriseUser],
        now,
      ),
    ),
  )
  let first = store.issue_session(
    "https://identity.example/realms/lunanexa",
    "external-pruned",
    "assertion-pruned-one",
    30000L,
    now + 1L,
  )
  ignore(
    store.revoke_session(first.session.session_id, "account-pruned", now + 2L),
  )
  ignore(
    store.issue_session(
      "https://identity.example/realms/lunanexa",
      "external-pruned",
      "assertion-pruned-two",
      30000L,
      now + 2L + 2592000000L,
    ),
  )
  let sessions = store.sessions_for_account("account-pruned")
  assert_eq(sessions.length(), 1)
  assert_false(
    sessions.any(session => session.session_id == first.session.session_id),
  )
  @fs.rmdir(directory, recursive=true)
}
