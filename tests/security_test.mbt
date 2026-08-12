///|
test "least privilege separates administrative and inference authority" {
  assert_true(@policy.authorized(Administrator, ChangePolicy))
  assert_true(@policy.authorized(InferenceCaller, InvokeModel))
  assert_false(@policy.authorized(InferenceCaller, EnrollNode))
  assert_false(@policy.authorized(Auditor, InvokeModel))
  assert_true(@policy.authorized(Auditor, ReadAudit))
  assert_false(@policy.authorized(Operator, ReadAudit))
}

///|
test "request logs structurally exclude raw content" {
  let request = workload()
  let secret_marker = "do-not-log-this-content"
  let sensitive : @contracts.WorkloadEnvelope = {
    ..request,
    payload: { "input": secret_marker },
  }
  let encoded = @policy.redacted_request_log(sensitive).to_json().stringify()
  assert_false(encoded.contains(secret_marker))
  assert_false(encoded.contains("input"))
  assert_true(encoded.contains("workload-1"))
}

///|
test "retention is explicit and expiry emits deletion receipt" {
  let ledger = @policy.RetentionLedger::new()
  try ledger.retain("ephemeral", Ephemeral, "encrypted:1") catch {
    RetentionNotPermitted => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("ephemeral content must not be retained")
  }
  ledger.retain("retained", RetainUntil(100L), "encrypted:object")
  assert_eq(ledger.active_count(), 1)
  let receipts = ledger.expire(101L)
  assert_eq(receipts.length(), 1)
  assert_eq(receipts[0].workload_id, "retained")
  assert_eq(ledger.active_count(), 0)
}

///|
test "signer allowlist and digest pinning reject forged subjects" {
  let trust : @policy.TrustPolicy = {
    allowed_signers: ["release-signer"],
    require_sha256: true,
  }
  assert_true(
    @policy.trusted(
      {
        digest: "sha256:5555555555555555555555555555555555555555555555555555555555555555",
        signer: "release-signer",
        signature_ref: "sig:1",
      },
      trust,
    ),
  )
  assert_false(
    @policy.trusted(
      { digest: "latest", signer: "release-signer", signature_ref: "sig:1" },
      trust,
    ),
  )
  assert_false(
    @policy.trusted(
      {
        digest: "sha256:not-a-digest",
        signer: "release-signer",
        signature_ref: "sig:1",
      },
      trust,
    ),
  )
  assert_false(
    @policy.trusted(
      {
        digest: "sha256:5555555555555555555555555555555555555555555555555555555555555555",
        signer: "forged",
        signature_ref: "sig:2",
      },
      trust,
    ),
  )
}

///|
test "restart recovery starts missing desired state and stops orphans" {
  let desired = assignment()
  let plan = @controller.recovery_plan(2L, [desired], ["orphan-runtime"], 1000L)
  assert_true(
    plan.actions.any(action => action == StartMissing("assignment-1")),
  )
  assert_true(
    plan.actions.any(action => action == StopOrphan("orphan-runtime")),
  )
  assert_true(@controller.node_unreachable(1L, 100L, 50L))
  let expired = @controller.recovery_plan(
    2L,
    [{ ..desired, lease_expires_unix_ms: 999L }],
    ["assignment-1"],
    1000L,
  )
  assert_true(
    expired.actions.any(action => action == ExpireLease("assignment-1")),
  )
  let verifier = @node.TestAssignmentVerifier::new("valid-test-signature")
  let agent = @node.NodeAgent::new("node-1")
  agent.activate()
  ignore(agent.reconcile(desired, verifier, 1L))
  assert_eq(agent.reap_expired(20001L), ["assignment-1"])
}

///|
test "malicious model metadata is rejected before persistence" {
  let registry = @registry.ModelRegistry::new()
  let malicious : @contracts.ModelRecord = {
    model_id: "model.bad",
    version: "v1",
    artifact: {
      digest: "sha256:abababababababababababababababababababababababababababababababab",
      uri: "file://../secret\n<script>",
      size_bytes: 1L,
      signature_ref: "sig",
    },
    license_id: "license",
    provenance: "untrusted",
    compatible_architectures: ["nvidia-gb10"],
    minimum_memory_mib: 1,
    state: Candidate,
  }
  try registry.register_model(malicious) catch {
    InvalidMetadata(_) => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected malicious metadata rejection")
  }
}

///|
test "signed backup restores durable snapshots and audit chain" {
  let control = @controller.ControlPlane::new("0.1.0", 1L)
  let backup = @store.create_backup(
    control.snapshot(),
    "{\"registry\":[]}",
    "audit-tail",
    "signature:backup-1",
    100L,
  )
  let inspected = @store.inspect_backup(backup)
  assert_eq(inspected.controller_snapshot, control.snapshot())
  let full = @store.create_full_backup(
    control.snapshot(),
    "{\"registry\":[]}",
    "{\"enrollment\":[]}",
    "{\"scheduler\":[]}",
    "{\"telemetry\":[]}",
    "audit-tail",
    "cosign:backup-2",
    101L,
  )
  let inspected_full = @store.inspect_full_backup(full)
  assert_eq(inspected_full.version, "lunanexa.backup.v2")
  assert_eq(inspected_full.scheduler_snapshot, "{\"scheduler\":[]}")
  let tampered = full.replace(
    old="{\\\"scheduler\\\":[]}",
    new="{\\\"scheduler\\\":[1]}",
  )
  try @store.inspect_full_backup(tampered) catch {
    @store.BackupError::ManifestDigestMismatch => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("tampered backup manifest was accepted")
  }
  let unsigned : @contracts.AuditEvent = {
    sequence: 1L,
    event_id: "e1",
    timestamp_unix_ms: 1L,
    actor: "operator",
    policy_version: "p1",
    action: "backup",
    target: "controller",
    prior_state: "ready",
    next_state: "ready",
    result: "accepted",
    correlation_receipt: "r1",
    previous_hash: "genesis",
    event_hash: "",
  }
  let events : Array[@contracts.AuditEvent] = [
    { ..unsigned, event_hash: @store.audit_event_hash(unsigned) },
  ]
  assert_true(@store.validate_audit_chain(events))
  assert_false(
    @store.validate_audit_chain([
      { ..events[0], policy_version: "tampered-policy" },
    ]),
  )
  assert_false(
    @store.validate_audit_chain([{ ..events[0], previous_hash: "forged" }]),
  )
}
