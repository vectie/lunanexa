///|
fn active_lease(now : Int64) -> @nodelease.ExclusiveNodeLease {
  {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "credential-lease-request",
      lease_id: "credential-lease-1",
      node_id: "private-node-1",
      subject_ref: "subject-1",
      unix_username: "tenant_1",
      access_credential_ref: "ssh-cert:credential-lease-1",
      starts_unix_ms: now - 1000L,
      expires_unix_ms: now + 3600000L,
    },
    state: Active,
    generation: 4L,
    created_unix_ms: now - 2000L,
    updated_unix_ms: now - 1000L,
    evidence_receipt: "helper:provisioned",
    authority_receipt: "controller:signed",
  }
}

///|
async test "issuer outbox dispatch atomically creates one recoverable handoff" {
  let directory = @fs.tmpdir(prefix="lunanexa-credential-issuer-outbox-")
  let path = "\{directory}/handoffs.json"
  let secret = "credential-handoff-test-secret-with-more-than-32-bytes"
  let now = @async.now()
  let lease = active_lease(now)
  let store = ready_store(path, secret, now)
  let intent : @credential.CredentialIssuerRequestIntent = {
    request_id: "issuer-request-1",
    lease_id: lease.intent.lease_id,
    expected_generation: lease.generation,
    host_alias: "dgx-user-1.cluster.example",
    ssh_port: 2222,
    host_key_fingerprint: "SHA256:abcdefghijklmnopqrstuvwxyzABCDEFG1234567890_-",
  }
  let queued = store.queue_issuer_request(intent, lease, now)
  assert_eq(queued.issuer_redirect_url, None)
  assert_eq(store.pending_issuer_requests(now).length(), 1)
  let before = store.snapshot()
  let invalid : @credential.CredentialIssuerDispatchReceipt = {
    request_id: intent.request_id,
    issuer_redirect_url: "https://evil.example/redeem/request",
    accepted_unix_ms: now + 1L,
  }
  let mut rejected = false
  ignore(store.accept_issuer_dispatch(invalid, lease)) catch {
    @credential.CredentialHandoffError::InvalidInput(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
  assert_eq(store.snapshot(), before)
  assert_eq(store.view_for_lease(lease, lease.intent.subject_ref, now), None)
  let receipt : @credential.CredentialIssuerDispatchReceipt = {
    ..invalid,
    issuer_redirect_url: "https://ssh-ca.example/redeem/issuer-request-1",
  }
  let (dispatched, handoff) = store.accept_issuer_dispatch(receipt, lease)
  assert_eq(dispatched.issuer_redirect_url, Some(receipt.issuer_redirect_url))
  assert_eq(handoff.request_id, intent.request_id)
  assert_eq(store.pending_issuer_requests(now + 2L).length(), 0)
  assert_eq(store.accept_issuer_dispatch(receipt, lease), (dispatched, handoff))
  let restored = ready_store(path, secret, now)
  assert_eq(
    restored.accept_issuer_dispatch(receipt, lease),
    (dispatched, handoff),
  )
  @fs.rmdir(directory, recursive=true)
}

///|
fn issue_intent() -> @credential.CredentialHandoffIssueIntent {
  {
    request_id: "credential-request-1",
    lease_id: "credential-lease-1",
    expected_generation: 4L,
    host_alias: "dgx-user-1.cluster.example",
    ssh_port: 2222,
    host_key_fingerprint: "SHA256:abcdefghijklmnopqrstuvwxyzABCDEFG1234567890_-",
    issuer_redirect_url: "https://ssh-ca.example/redeem/credential-request-1",
  }
}

///|
async fn ready_store(
  path : String,
  secret : String,
  now : Int64,
) -> CredentialHandoffStore {
  CredentialHandoffStore::open(path, secret).with_issuer_readiness({
    version: @credential.issuer_readiness_contract_version,
    adapter_id: "ssh-ca-test",
    health_endpoint: "https://ssh-ca.example/healthz",
    evidence_ref: "store-test-evidence",
    checked_unix_ms: now,
    expires_unix_ms: now + 86400000L,
    healthy: true,
    signature: "a".repeat(64),
  })
}

///|
async test "handoff is subject node generation bound one time and restart safe" {
  let directory = @fs.tmpdir(prefix="lunanexa-credential-handoff-")
  let path = "\{directory}/handoffs.json"
  let secret = "credential-handoff-test-secret-with-more-than-32-bytes"
  let now = @async.now()
  let lease = active_lease(now)
  let store = ready_store(path, secret, now)
  let record = store.issue(issue_intent(), lease, now)
  assert_true(record.handoff_ref.has_prefix("lnxh_"))
  let view = store.view_for_lease(lease, "subject-1", now).unwrap()
  assert_eq(view.host_alias, "dgx-user-1.cluster.example")
  assert_eq(view.ssh_port, 2222)
  assert_eq(
    view.connection_command,
    "ssh -p 2222 tenant_1@dgx-user-1.cluster.example",
  )
  assert_true(view.can_redeem)
  assert_eq(store.view_for_lease(lease, "subject-other", now), None)
  try {
    ignore(
      store.redeem(record.handoff_ref, lease, "subject-other", 4L, now + 1L),
    )
    fail("cross-subject redemption was accepted")
  } catch {
    @credential.CredentialHandoffError::NotFound => ()
    _ => fail("unexpected cross-subject redemption error")
  }
  let redemption = store.redeem(
    record.handoff_ref,
    lease,
    "subject-1",
    4L,
    now + 1L,
  )
  assert_true(redemption.one_time)
  assert_true(redemption.redemption_receipt.has_prefix("lnxr_"))
  assert_false(redemption.raw_secret_included)
  assert_false(redemption.to_json().stringify().contains("private-node-1"))
  let reopened = CredentialHandoffStore::open(path, secret)
  let recovered_view = reopened
    .view_for_lease(lease, "subject-1", now + 2L)
    .unwrap()
  assert_false(recovered_view.can_redeem)
  assert_true(recovered_view.can_recover)
  let recovered = reopened.redeem(
    record.handoff_ref,
    lease,
    "subject-1",
    4L,
    now + 2L,
  )
  assert_eq(recovered, redemption)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "handoff rejects stale generation expiry and idempotency mutation" {
  let directory = @fs.tmpdir(prefix="lunanexa-credential-adversarial-")
  let path = "\{directory}/handoffs.json"
  let now = @async.now()
  let lease = active_lease(now)
  let store = ready_store(
    path, "credential-handoff-test-secret-with-more-than-32-bytes", now,
  )
  let first = store.issue(issue_intent(), lease, now)
  assert_eq(store.issue(issue_intent(), lease, now), first)
  try {
    ignore(
      store.issue(
        { ..issue_intent(), request_id: "duplicate-lease-generation" },
        lease,
        now + 1L,
      ),
    )
    fail("a second handoff for the same lease generation was accepted")
  } catch {
    @credential.CredentialHandoffError::IdempotencyConflict => ()
    _ => fail("unexpected duplicate lease-generation error")
  }
  try {
    ignore(
      store.issue(
        { ..issue_intent(), host_alias: "changed.example" },
        lease,
        now,
      ),
    )
    fail("mutated idempotency replay was accepted")
  } catch {
    @credential.CredentialHandoffError::IdempotencyConflict => ()
    _ => fail("unexpected idempotency error")
  }
  try {
    ignore(
      store.redeem(
        first.handoff_ref,
        { ..lease, generation: 5L },
        "subject-1",
        4L,
        now + 1L,
      ),
    )
    fail("stale generation was accepted")
  } catch {
    @credential.CredentialHandoffError::StaleGeneration => ()
    _ => fail("unexpected stale-generation error")
  }
  let expired = {
    ..lease,
    intent: { ..lease.intent, expires_unix_ms: now + 2L },
  }
  let expiring_store = ready_store(
    "\{directory}/expiring.json",
    "credential-handoff-expiry-secret-with-more-than-32-bytes",
    now,
  )
  let expiring_record = expiring_store.issue(
    { ..issue_intent(), request_id: "expiring-request" },
    expired,
    now,
  )
  try {
    ignore(
      expiring_store.redeem(
        expiring_record.handoff_ref,
        expired,
        "subject-1",
        4L,
        now + 2L,
      ),
    )
    fail("expired handoff was accepted")
  } catch {
    @credential.CredentialHandoffError::Expired => ()
    _ => fail("unexpected expiry error")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "revocation closes all unredeemed handoffs for the lease" {
  let directory = @fs.tmpdir(prefix="lunanexa-credential-revoke-")
  let now = @async.now()
  let lease = active_lease(now)
  let store = ready_store(
    "\{directory}/handoffs.json",
    "credential-handoff-revoke-secret-with-more-than-32-bytes",
    now,
  )
  let record = store.issue(issue_intent(), lease, now)
  assert_true(store.revoke_for_lease(lease.intent.lease_id, now + 1L))
  assert_false(
    store.view_for_lease(lease, "subject-1", now + 2L).unwrap().can_redeem,
  )
  try {
    ignore(store.redeem(record.handoff_ref, lease, "subject-1", 4L, now + 2L))
    fail("revoked handoff was accepted")
  } catch {
    @credential.CredentialHandoffError::Revoked => ()
    _ => fail("unexpected revoked error")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "external issuer readiness is explicit and expires in process" {
  let directory = @fs.tmpdir(prefix="lunanexa-credential-readiness-")
  let now = @async.now()
  let store = CredentialHandoffStore::open(
    "\{directory}/handoffs.json",
    "credential-readiness-secret-with-more-than-32-bytes",
  )
  assert_false(store.issuer_adapter_ready(now))
  let unsigned : @credential.CredentialIssuerReadinessEvidence = {
    version: @credential.issuer_readiness_contract_version,
    adapter_id: "ssh-ca-primary",
    health_endpoint: "https://ssh-ca.example/healthz",
    evidence_ref: "retained-issuer-health",
    checked_unix_ms: now,
    expires_unix_ms: now + 60000L,
    healthy: true,
    signature: "",
  }
  let evidence = {
    ..unsigned,
    signature: issuer_readiness_signature(
      unsigned, "issuer-evidence-signing-secret-more-than-32-bytes",
    ),
  }
  let configured = store.with_issuer_readiness(evidence)
  assert_true(configured.issuer_adapter_ready(now))
  assert_false(configured.issuer_adapter_ready(now + 60000L))
  let path = @fs.realpath(directory) + "/issuer-readiness.json"
  @fs.write_file(
    path,
    evidence.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  assert_eq(
    load_issuer_readiness_evidence(
      Some(path),
      Some("issuer-evidence-signing-secret-more-than-32-bytes"),
      now,
    ),
    Some(evidence),
  )
  let projected_directory = "\{directory}/..data"
  @fs.mkdir(projected_directory, permission=0o700)
  let projected_target = "\{projected_directory}/issuer-readiness.json"
  @fs.write_file(
    projected_target,
    evidence.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let projected_path = "\{directory}/projected-issuer-readiness.json"
  @fs.symlink(target=projected_target, projected_path)
  assert_eq(
    load_issuer_readiness_evidence(
      Some(projected_path),
      Some("issuer-evidence-signing-secret-more-than-32-bytes"),
      now,
    ),
    Some(evidence),
  )
  let outside = @fs.realpath(@fs.tmpdir(prefix="lunanexa-issuer-outside-"))
  let outside_target = "\{outside}/issuer-readiness.json"
  @fs.write_file(
    outside_target,
    evidence.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let escaping_path = "\{directory}/escaping-issuer-readiness.json"
  @fs.symlink(target=outside_target, escaping_path)
  ignore(
    load_issuer_readiness_evidence(
      Some(escaping_path),
      Some("issuer-evidence-signing-secret-more-than-32-bytes"),
      now,
    ),
  ) catch {
    @credential.CredentialHandoffError::InvalidInput(_) => ()
    _ => fail("issuer evidence symlink escaping its mount was accepted")
  }
  @fs.write_file(
    path,
    { ..evidence, adapter_id: "mutated-adapter" }.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  ignore(
    load_issuer_readiness_evidence(
      Some(path),
      Some("issuer-evidence-signing-secret-more-than-32-bytes"),
      now,
    ),
  ) catch {
    @credential.CredentialHandoffError::InvalidInput(_) => ()
    _ => fail("mutated issuer readiness evidence was accepted")
  }
  @fs.rmdir(directory, recursive=true)
  @fs.rmdir(outside, recursive=true)
}
