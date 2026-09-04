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

///|
async test "enterprise invitation self-registration is hashed durable and role bounded" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-invitation-")
  let path = "\{directory}/accounts.json"
  let store = @account.AccountStore::open(
    path, "account-invitation-test-secret-more-than-32-bytes",
  )
  let issued = store.issue_invitation(
    {
      invitation_id: "invitation-one",
      email: "invited@example.invalid",
      organization_id: "organization-one",
      tenant_ref: "tenant-one",
      project_id: "project-one",
      created_by: "operator-one",
      expires_unix_ms: 200000L,
    },
    100000L,
  )
  assert_true(issued.secret.has_prefix("lnxi_"))
  assert_false(@fs.read_file(path).text().contains(issued.secret))
  let registered = store.register_with_invitation(
    issued.secret,
    "https://identity.example/realms/lunanexa",
    "provider-subject-invited",
    "invited@example.invalid",
    "assertion-invited-one",
    "Invited User",
    60000L,
    100001L,
  )
  assert_eq(registered.account.email, "invited@example.invalid")
  assert_eq(registered.account.roles, [EnterpriseUser])
  assert_eq(registered.account.state, Active)
  assert_eq(
    registered.invitation.consumed_account_id,
    Some(registered.account.account_id),
  )
  let authorized = store.authorize(
    registered.session.secret,
    100002L,
    required_role=EnterpriseUser,
  )
  assert_eq(authorized.account.account_id, registered.account.account_id)
  let reopened = @account.AccountStore::open(
    path, "account-invitation-test-secret-more-than-32-bytes",
  )
  assert_eq(reopened.views().length(), 1)
  assert_eq(reopened.invitation_views().length(), 1)
  try
    reopened.register_with_invitation(
      issued.secret,
      "https://identity.example/realms/lunanexa",
      "different-provider-subject",
      "invited@example.invalid",
      "assertion-invited-two",
      "Attacker",
      60000L,
      100003L,
    )
  catch {
    @account.AccountError::Unauthorized => ()
    _ => fail("unexpected invitation reuse error")
  } noraise {
    _ => fail("a consumed invitation registered a different identity")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "an existing account accepts one email-bound invitation idempotently" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-accept-invitation-")
  let store = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "account-existing-invitation-secret-more-than-32-bytes",
  )
  let owner = store.register_open(
    "https://identity.example/realms/lunanexa", "provider-subject-existing", "registration-existing",
    "Existing User", "existing@example.invalid", 60000L, 100000L,
  )
  let other = store.register_open(
    "https://identity.example/realms/lunanexa", "provider-subject-other", "registration-other",
    "Other User", "other@example.invalid", 60000L, 100000L,
  )
  let issued = store.issue_invitation(
    {
      invitation_id: "invitation-existing",
      email: "EXISTING@example.invalid",
      organization_id: "organization-existing",
      tenant_ref: "tenant-existing",
      project_id: "project-existing",
      created_by: "operator-one",
      expires_unix_ms: 200000L,
    },
    100001L,
  )
  let accepted = store.accept_invitation(
    issued.secret,
    owner.account.account_id,
    100002L,
  )
  assert_eq(accepted.consumed_account_id, Some(owner.account.account_id))
  assert_eq(
    store.accept_invitation(issued.secret, owner.account.account_id, 300000L),
    accepted,
  )
  try
    store.accept_invitation(issued.secret, other.account.account_id, 100003L)
  catch {
    @account.AccountError::Unauthorized => ()
    error => fail("unexpected cross-account invitation error: \{Repr(error)}")
  } noraise {
    _ => fail("a consumed invitation was replayed by another account")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "open registration is idempotent and grants no privileged role" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-open-registration-")
  let store = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "open-registration-session-secret-more-than-32-bytes",
  )
  let first = store.register_open(
    "https://identity.example/realms/lunanexa", "provider-subject-open", "registration-assertion-one",
    "Open User", "open@example.invalid", 60000L, 100000L,
  )
  assert_eq(first.account.roles, [EnterpriseUser])
  assert_eq(first.account.state, Active)
  let second = store.register_open(
    "https://identity.example/realms/lunanexa", "provider-subject-open", "registration-assertion-two",
    "Open User", "OPEN@example.invalid", 60000L, 100001L,
  )
  assert_eq(second.account.account_id, first.account.account_id)
  assert_true(second.session.secret != first.session.secret)
  assert_eq(store.views().length(), 1)
  try
    store.register_open(
      "https://identity.example/realms/lunanexa", "provider-subject-open", "registration-assertion-three",
      "Open User", "attacker@example.invalid", 60000L, 100002L,
    )
  catch {
    @account.AccountError::AlreadyExists(_) => ()
    _ => fail("unexpected open-registration identity conflict")
  } noraise {
    _ => fail("an existing identity changed its bound email")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "free trial is single use, bounded, durable, and key bound" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-trial-")
  let path = "\{directory}/accounts.json"
  let secret = "trial-account-session-secret-more-than-32-bytes"
  let store = @account.AccountStore::open(path, secret)
  let registered = store.register_open(
    "https://identity.example", "trial-subject", "trial-registration-assertion",
    "Trial User", "trial@example.invalid", 60000L, 100000L,
  )
  let trial = store.ensure_trial(
    {
      trial_id: "trial-one",
      account_id: registered.account.account_id,
      organization_id: "trial-org-one",
      tenant_ref: "trial-tenant-one",
      project_id: "trial-project-one",
      allowed_models: ["text.qwen"],
      maximum_requests: 100L,
      expires_unix_ms: 87400000L,
    },
    100000L,
  )
  assert_eq(trial.api_key_id, None)
  let bound = store.bind_trial_api_key(trial.trial_id, "trial-key-one", 100001L)
  assert_eq(bound.api_key_id, Some("trial-key-one"))
  assert_true(
    store.active_trial_for_subject(registered.account.subject_ref, 100002L)
    is Some(_),
  )
  assert_eq(
    store.ensure_trial(
      {
        trial_id: "trial-one",
        account_id: registered.account.account_id,
        organization_id: "trial-org-one",
        tenant_ref: "trial-tenant-one",
        project_id: "trial-project-one",
        allowed_models: ["text.qwen"],
        maximum_requests: 100L,
        expires_unix_ms: 99999999L,
      },
      100003L,
    ).expires_unix_ms,
    87400000L,
  )
  let reopened = @account.AccountStore::open(path, secret)
  assert_eq(
    reopened.trial_for_account(registered.account.account_id).unwrap().api_key_id,
    Some("trial-key-one"),
  )
  assert_eq(
    reopened.active_trial_for_subject(registered.account.subject_ref, 87400000L),
    None,
  )
  @fs.rmdir(directory, recursive=true)
}
