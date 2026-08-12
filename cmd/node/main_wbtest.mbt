///|
async test "controller transport failure cannot bypass offline lease expiry" {
  let now = @async.now()
  let lease : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "offline-node-key",
      lease_id: "offline-node-lease",
      node_id: "dgx-offline-node",
      subject_ref: "subject-offline-node",
      unix_username: "tenant_offline",
      access_credential_ref: "ssh-cert:offline-node-lease",
      starts_unix_ms: now - 10000L,
      expires_unix_ms: now - 1000L,
    },
    state: Active,
    generation: 3L,
    created_unix_ms: now - 11000L,
    updated_unix_ms: now - 10000L,
    evidence_receipt: "controller:active",
    authority_receipt: "signed:offline-node-lease",
  }
  let lease_guard = @nodelease.LeaseAgentGuard::new("dgx-offline-node")
  let provision = lease_guard.observe_remote(Some(lease), now - 9000L)
  lease_guard.record_success(
    provision,
    @nodelease.helper_receipt(provision, now - 9000L),
  )
  lease_guard.acknowledge_observation(lease_guard.snapshot().last_receipt)
  let directory = @fs.tmpdir(prefix="lunanexa-node-offline-expiry-")
  let state_path = "\{directory}/lease-agent.json"
  reconcile_exclusive_lease(
    "http://127.0.0.1:1", "dgx-offline-node", "node-token", "/usr/bin/false", lease_guard,
    state_path,
  )
  assert_eq(lease_guard.snapshot().state, QuarantinedAgent)
  assert_true(@fs.exists(state_path))
  let persisted : @nodelease.LeaseAgentSnapshot = @json.from_json(
    @json.parse(@fs.read_file(state_path).text()),
  )
  assert_eq(persisted.state, QuarantinedAgent)
  @fs.rmdir(directory, recursive=true)
}
