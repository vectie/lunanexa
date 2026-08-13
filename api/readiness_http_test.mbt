///|
async test "management readiness is protected, fail-closed, and component explicit" {
  let directory = @fs.tmpdir(prefix="lunanexa-management-readiness-")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let durable = @store.FileStore::open("\{directory}/state.json")
  let registry = @registry.FileRegistry::open("\{directory}/registry.json")
  let enrollment = @node.FileEnrollmentService::open(
    "\{directory}/enrollment.json",
  )
  let enrollment_now = @async.now()
  ignore(
    enrollment.issue_token(
      "readiness-bootstrap",
      "readiness-bootstrap-secret",
      enrollment_now + 600000L,
    ),
  )
  ignore(
    enrollment.enroll(
      "node-a", "readiness-bootstrap", "readiness-bootstrap-secret", "readiness-node-authority",
      "key:node-a", enrollment_now,
    ),
  )
  durable.put_heartbeat({
    node_id: "node-a",
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: "node-a",
      agent_version: "0.1.0",
      os_release: "test",
      runtime_names: ["text-runtime"],
      accelerators: [],
      labels: Map([]),
      taints: [],
    },
    running_deployments: [],
    timestamp_unix_ms: enrollment_now,
    signature: "",
  })
  let degraded = @api.ApiService::with_services(
    durable, registry, enrollment, runtime, "operator-token", "inference-token",
    "node-token", "0.1.0",
  )
  assert_eq(degraded.handle(Get, "/v1/readiness", Map([]), "").status, 401)
  assert_eq(degraded.handle(Get, "/health", Map([]), "").status, 200)
  assert_eq(degraded.handle(Get, "/ready", Map([]), "").status, 503)
  let unavailable = degraded.handle(
    Get,
    "/v1/readiness",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(unavailable.status, 503)
  assert_true(unavailable.body.contains("NotificationStoreUnavailable"))
  assert_true(unavailable.body.contains("ObservabilityStoreUnavailable"))
  assert_true(unavailable.body.contains("CredentialBrokerUnavailable"))
  assert_true(unavailable.body.contains("GuideDiagnosticsUnavailable"))

  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let operational = @observability.ObservabilityStore::open(
    "\{directory}/observability.json",
    emit_json_lines=true,
  )
  let issuer_evidence_secret = "issuer-readiness-signature-secret-more-than-32-bytes"
  let unsigned_issuer_evidence : @credential.CredentialIssuerReadinessEvidence = {
    version: @credential.issuer_readiness_contract_version,
    adapter_id: "ssh-ca-primary",
    health_endpoint: "https://ssh-ca.example/healthz",
    evidence_ref: "retained-issuer-readiness",
    checked_unix_ms: @async.now(),
    expires_unix_ms: @async.now() + 600000L,
    healthy: true,
    signature: "",
  }
  let issuer_evidence = {
    ..unsigned_issuer_evidence,
    signature: @credential_store.issuer_readiness_signature(
      unsigned_issuer_evidence, issuer_evidence_secret,
    ),
  }
  let credentials = @credential_store.CredentialHandoffStore::open(
    "\{directory}/credential.json",
    "credential-readiness-secret-1234567890",
  ).with_issuer_readiness(issuer_evidence)
  let leases = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{directory}/leases.json",
    "lease-readiness-secret",
  )
  let offline = @offline_store.OfflineCommerceStore::open(
    "\{directory}/offline.json",
  )
  let offline_proof_now = @async.now()
  offline.record_worker_acceptance(ArtifactDispatcher, offline_proof_now)
  offline.record_worker_acceptance(EntitlementDispatcher, offline_proof_now)
  offline.record_reconciler_attempt(offline_proof_now)
  offline.record_reconciler_success(offline_proof_now)
  let capabilities : Array[@offline.OfflineCommerceCapabilityEvidence] = [
    {
      capability: ApprovedLegalTemplates,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:legal"),
    },
    {
      capability: ObjectStorage,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:storage"),
    },
    {
      capability: MalwareScanner,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:scanner"),
    },
    {
      capability: OoxmlWorker,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:ooxml"),
    },
    {
      capability: PdfRenderer,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:pdf"),
    },
    {
      capability: SpreadsheetFormulaEngine,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:formula"),
    },
    {
      capability: CjkFonts,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:fonts"),
    },
    {
      capability: MachineCallbackIdentity,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:machine"),
    },
    {
      capability: EntitlementAuthority,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:entitlement"),
    },
    {
      capability: FinanceLegalPolicy,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:finance"),
    },
  ]
  let proof_now = @async.now()
  let helper_evidence : @nodelease.MachineHelperAdapterReadinessEvidence = {
    version: @nodelease.helper_adapter_readiness_contract_version,
    adapter_id: "readiness-helper",
    node_scope: "readiness-fleet",
    covered_node_ids: ["node-a"],
    evidence_ref: "retained-helper-readiness",
    checked_unix_ms: proof_now,
    expires_unix_ms: proof_now + 600000L,
    provision_verified: true,
    revoke_verified: true,
    sanitize_verified: true,
    quarantine_verified: true,
    signature: "0000000000000000000000000000000000000000000000000000000000000000",
  }
  ignore(notifications.record_worker_pass(proof_now, 1, 1, 0, 0))
  ignore(
    operational.record_external_export_proof({
      proof_receipt: "readiness-export-proof",
      exported_unix_ms: proof_now,
    }),
  )
  operational.record_component_event(
    "event-guide-proof",
    proof_now,
    Information,
    "guide-monitor",
    "GuideDiagnosticsProbeCompleted",
    "guide-proof",
    "guide",
    "healthy",
    200,
    1L,
  )
  operational.record_component_event(
    "event-expiry-proof",
    proof_now,
    Information,
    "controller",
    "ExclusiveLeaseExpiryReconciliationCompleted",
    "expiry-proof",
    "exclusive_lease",
    "healthy",
    200,
    1L,
  )
  let ready_service = degraded
    .with_notification_store(notifications)
    .with_notification_delivery_adapter_configured(true)
    .with_observability_store(operational)
    .with_external_observability_collector_configured(true)
    .with_credential_handoff_store(credentials)
    .with_exclusive_lease_store(leases)
    .with_offline_commerce_store(offline)
    .with_lease_helper_receipt_secret("helper-readiness-secret-123456789012345")
    .with_machine_helper_adapter_evidence(helper_evidence)
    .with_offline_artifact_callback_tokens(
      "readiness-artifact-worker-token-more-than-32-bytes", "readiness-artifact-scanner-token-more-than-32-bytes",
    )
    .with_entitlement_authority_callback_token(
      "readiness-entitlement-authority-token-more-than-32-bytes",
    )
    .with_offline_transfer_adapter(
      "https://object-transfer.example/v1/offline-transfers", "readiness-transfer-adapter-token-more-than-32-bytes",
      "readiness-transfer-session-secret-more-than-32-bytes",
    )
    .with_signature_verifier(
      @registry.CosignVerifier::new("/usr/bin/cosign", "/trust/cosign.pub"),
    )
    .with_guide_diagnostics_token("guide-readiness-token-1234567890123456")
    .with_offline_commerce_capabilities(capabilities, @async.now() + 3600000L)
  let ready = ready_service.handle(
    Get,
    "/v1/readiness",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(ready_service.handle(Get, "/ready", Map([]), "").status, 200)
  assert_eq(ready.status, 200)
  assert_true(ready.body.contains("\"ready\":true"))
  assert_true(ready.body.contains("DeliveryReady"))
  assert_true(ready.body.contains("LocalJsonReady"))
  assert_true(ready.body.contains("OfflineCommerceReady"))
  assert_false(ready.body.contains("guide-readiness-token"))
  operational.record_component_event(
    "event-guide-proof-newer-failure",
    proof_now + 1L,
    Error,
    "guide-monitor",
    "GuideDiagnosticsProbeCompleted",
    "guide-proof-newer-failure",
    "guide",
    "degraded",
    503,
    1L,
  )
  let guide_failed = ready_service.management_readiness(proof_now + 2L)
  assert_false(guide_failed.guide_diagnostics_configured)
  assert_true(
    guide_failed.blocker_codes.contains("GuideDiagnosticsUnavailable"),
  )
  let issuer_expired = ready_service.management_readiness(
    @async.now() + 600001L,
  )
  assert_false(issuer_expired.credential_broker_configured)
  assert_false(issuer_expired.machine_helper_adapter_verified)
  assert_true(
    issuer_expired.blocker_codes.contains("CredentialBrokerUnavailable"),
  )
  assert_true(
    issuer_expired.blocker_codes.contains("MachineHelperAdapterUnverified"),
  )
  @fs.rmdir(directory, recursive=true)
}
