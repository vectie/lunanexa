# Recovery runbook

## Controller restart

1. Fence the prior leader and increment the durable controller epoch.
2. Verify the external signature and manifest digest, then restore the full
   `lunanexa.backup.v2` bundle into a clean management host. Version 2 contains
   controller, registry, enrollment, scheduler and telemetry snapshots.
3. Validate the audit chain and compare the restored registry and assignment
   counts with the backup manifest.
4. Start the controller in reconciliation-only mode. Inspect the typed recovery
   plan for missing desired runtimes, expired leases, orphan runtimes, and
   unreachable nodes:

   ```sh
   lunanexa recovery-plan
   ```

   This calls `GET /v1/recovery/plan` with operator authority. It is a dry,
   typed reconciliation plan; it does not renew expired leases or mutate node
   state.
5. Enable mutations only after every connected node reports the new epoch.
6. Reissue short leases; never extend an assignment signed by a stale epoch.

## Node-agent or runtime restart

The agent reconnects outbound through the deployment mTLS boundary, proves its
per-node hashed authority, requires a non-expired rotated certificate, reports
inventory and observed assignments, and reconciles only HMAC-authenticated
desired state. Expired assignments are removed. A runtime absent from desired
state is stopped as an orphan; there is no remote shell recovery path.

`scripts/process-recovery-test.sh` exercises the locally owned portion of this
campaign against compiled native binaries: it enrolls a node agent, kills and
restarts it from its certificate and state snapshot, kills the controller after
a durable mutation, restarts at a higher epoch in reconciliation-only mode, and
rejects a concurrent same-epoch controller. Runtime-container kill/restart is
performed with the approved third-party image during cluster acceptance.

## Backup and restore drill

Create an encrypted, signed v2 bundle containing all five durable snapshots,
alias generations, placement/quota state and the audit tail hash. Store artifacts
separately by immutable digest. On a clean controller, verify the external
signature and manifest digest, restore snapshots with mode `0600`, recompute the
audit chain, and run reconciliation in dry mode before enabling traffic. Record
RTO, RPO, operator, evidence reference, and result in the audit log.

The native recovery tool performs the manifest and clean-restore mechanics:

```sh
lunanexa-recovery export /secure/backup.v2.json /secure/backup.v2.sig
cosign sign-blob --key "$PRIVATE_SIGNING_KEY_PATH" --output-signature /secure/backup.v2.sig /secure/backup.v2.json
LUNANEXA_COSIGN_BINARY=/usr/bin/cosign \
LUNANEXA_COSIGN_PUBLIC_KEY_PATH=/etc/lunanexa/trust/cosign.pub \
  lunanexa-recovery restore /secure/backup.v2.json /secure/backup.v2.sig /var/lib/lunanexa-restored
```

The export recomputes the manifest digest. Restore verifies the external
signature, recomputes the manifest, validates every schema and the audit chain,
and refuses to replace any target file. Point a fenced controller at the five
restored files with `LUNANEXA_RECONCILIATION_ONLY=1`; `/version` reports this
mode and inference/operator mutations return `ReconciliationOnly`. Raise the
epoch and set the mode to `0` only after node reconciliation is accepted.

An active admission surviving a crash remains fenced until it completes or its
canonical request deadline expires. Do not delete scheduler state merely to
clear a quota. Reconcile workload receipts and upstream idempotency before
manually repairing an admission.
