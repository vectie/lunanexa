# Running-provider loss: required recovery boundary

Status: integrated implementation with scoped live exit/cleanup acceptance.
The sections below preserve chronological checkpoints; later evidence supersedes
earlier deployment status. Remaining acceptance gaps are explicitly retained.
Baseline `d51f5e1`; implementation checkpoint 2026-09-16.

In-progress implementation: `ExecutionContext` now has optional `instance_id`.
New discovered bindings populate it; missing legacy JSON decodes as None.
Verified same-binding backfill enriches unknown identity but refuses conflicting
known identity. Snapshot restoration and reservation compatibility permit legacy
unknown records without treating them as termination proof. Job tests pass
18/18 with existing warning 20 excluded. The identity is used by the durable
evidence matcher and admission/submission fences.

The terminal storage primitive is implemented:
`acknowledge_instance_termination` matches owner, binding and exact known
execution context, persists a termination evidence reference with a non-success
terminal result, and preserves idempotent replay. Snapshot validation rejects
evidence on nonterminal/unknown-instance records. Tests cover mismatched
instance/node/generation, serialization and replay, and persistence failure
without capacity release. It assumes a trusted caller has independently verified
the evidence. It is reached through normal runtime reconciliation of evidence
previously accepted by the authenticated node report endpoint.

Runtime integration now provides `reconcile_verified_termination` for that
trusted recovery caller. It persists termination first, then invokes the
existing idempotent settlement path. Runtime strict tests pass 9/9, including a
failed ledger call followed by snapshot restoration, successful retry and no
duplicate settlement. The resolver is deliberately made to fail in this test,
proving no replacement provider is contacted. The node sender, authenticated
receiver, durable evidence store and automatic sweep are connected in source.
Successful HTTP-ingestion coverage and a real running-provider-loss campaign
are required before deployment or completion claims. Current strict checks do
not establish that the full repository passes its strict release gate.

## Baseline code path (before this batch)

- `api/media_http.mbt` hashes deployment, generation, node, origin, profile and
  optional instance ID into a binding identity. Discovery resolves only exact
  matching identities; a replacement cannot impersonate the original runtime.
- `media/jobs/types.mbt` persists that hash plus `ExecutionContext` containing
  deployment/generation/node. The original runtime instance is not available as
  an explicit field for matching independent termination evidence.
- `media/runtime/runtime.mbt` requires a positive provider deletion acknowledgement
  before terminal cancellation. An unavailable original binding leaves the
  execution nonterminal and its capacity reserved, correctly failing closed.
- The operator reconcile endpoint only associates a provider job ID with an
  ambiguous submission. It does not accept verified runtime termination.
- `node/kubernetes/supervisor.mbt` derives instance identity from Pod UID plus
  container ID. Its resource reconciliation clears a missing resource UID before
  replacement; no durable original-instance termination record reaches the
  media controller through this path.

Therefore idle replacement and control-plane restart tests do not establish
automatic completion of running-provider-loss cleanup. Keeping an old task busy
forever is not a complete product outcome, but releasing it merely on 404 is not
safe either.

## Required implementation, as one recovery feature

1. Persist original instance identity with each admitted execution, maintaining
   backward reading of existing snapshots. Never infer an old job's instance
   from the current replacement. Legacy unknown identity remains fail-closed.
2. Capture durable instance termination evidence before overwriting an old
   identity. Match assignment, deployment generation, controller epoch, node,
   instance, Pod UID and container identity. API disappearance alone is not proof
   a process has stopped after node partition or forced Pod deletion. Prefer
   local container-runtime termination observation or an explicit fenced-node
   recovery procedure, not only control-plane 404.
3. Deliver evidence through authenticated node/control-plane channels, with
   bounded validation, replay protection and durable audit. Customer requests
   cannot assert execution termination. A new instance or same-name Pod is not
   termination evidence for the old instance.
4. Reconcile only matching old executions to failed/cancelled/expired as
   appropriate, never completed. Persist terminal state before releasing
   reservations. Preserve exactly-once settlement and distinguish failed work
   from successful generated output under the existing charging policy.
5. Make evidence ingestion and settlement restart-safe and idempotent. Retain
   evidence until all dependent executions have reached durable terminal state;
   bound retention and expose actionable pending-recovery status.

## Acceptance required before closing this gap

- Local tests: mismatched node/epoch/instance/job, stale evidence, replay,
  replacement address reuse, legacy snapshots and database failure at each write.
- Live TEST ONLY run: submit, confirm the original provider accepted it, lose the
  process, observe verified termination, and prove the original job closes without
  a request to the replacement. Prove quota recovers and settlement is singular.
- Negative live case: loss of contact without termination proof remains pending,
  does not claim completion and does not release capacity.
- Controller restart between evidence ingestion, terminal persistence and
  settlement must not resubmit the job or double charge.

## Node journal implementation checkpoint

The Kubernetes supervisor now checkpoints every advertised Pod/container identity
before returning its route. An explicit current-container termination observation
is recorded once against that identity; repeated observations and supervisor
restart preserve the first observation. A recorded exited incarnation cannot be
advertised again. Missing Pods, Failed phase alone, old-container records and
contradictory running/terminated states do not establish termination.

Exit observations are now copied atomically into a separate bounded journal
outbox. Resource cleanup and restart retain these records independently of runtime
records and model-cache references. A full outbox refuses new evidence rather
than silently discarding old evidence. Exact-record acknowledgement can retire
outbox entries durably; mismatched records and failed checkpoint writes leave
them pending, and duplicate acknowledgements are safe. The caller must verify
controller acceptance before invoking this local primitive. The independent
node delivery loop signs bounded batches and validates exact acknowledgements.
The receiver requires node credentials, a report MAC, bounded send time, an
active durable controller and matching original assignment (or exact previously
accepted evidence for retries). It persists before responding. Evidence received
for an already-removed assignment without prior acceptance currently fails closed
and remains pending; this recovery case is not yet solved.
The journal timestamp is the observation time, not the process exit time. It must
not be used as a claim of hardware fencing or an externally verified exit time.
Existing successful acceptance records remain limited to their tested scenarios.

## Linux candidate smoke, 2026-09-16

A fresh 565-file source staging tree at
`/tmp/lunanexa-termination-build.mfJxPh/source` passed Linux native check with
warnings 92/20 excluded. MoonLeaf resolved to 0.1.15. macOS AppleDouble sidecars
were removed from staging and excluded from future archives. The cancellation
fixture's tuple loop was rewritten for the Linux compiler's supported syntax.

The node candidate image digest is
`sha256:adb9880ea77046f864ff916cd3ea2e490d65d481fd0007c34ca06bc41a665e31`;
node binary SHA-256 is
`ba3602791cba4e4c9835c4af7da5bef0c4739655c8f87d4dbe200e6e7e2021ae`.
Pod `termination-node-smoke-20260916` ran on actual `lunanexa-gpu-180`, completed
with zero restarts, and reported CPU count 20 and memory total 128499 MiB through
`--inspect-host-resources`. It had no credentials, service-account token or GPU
request. This proves candidate image startup and resource inspection only, not
runtime-loss recovery or Spark hardware compatibility. The completed probe was
deleted after inspection. The isolated acceptance node agent was subsequently
updated to this digest and verified Running/Ready, with one expected container
restart. The isolated acceptance controller was also updated and `/health`
returned 200. These rollout checks do not prove running-provider-loss recovery.

## Current-version regression checkpoint

The macOS native functional suite passed 778/778 on 2026-09-16 with existing
warnings 92/20 excluded. Linux targeted tests passed 63/63 earlier in this batch.
Neither result establishes the strict release gate or actual Spark compatibility.

A current-version live controller-outage replay preserved the provider and
workspace identities during a 45-second stop, but its immediate post-health
request returned retryable `VideoUnavailable` (503). That run is **not a pass**.
The controller recovered health and the operator pending-job view was empty
after the script's cleanup. The acceptance script now distinguishes process
liveness from discovery recovery and retries only this documented transient
error, with the original idempotency key and a bounded retry window. A rerun
must establish recovery rather than assuming the 503 was harmless.

The bounded-retry rerun also failed: same-key creation replay returned the
original job successfully, but the following MoonGate status poll returned
`VideoUnavailable` (503). Thus admission replay and controller liveness recover;
end-to-end status recovery is not yet established. Both runs restored the
controller via the script's cleanup guard. Investigate the original job's
provider binding and gateway status path before repeating destructive faults.

Follow-up isolation checks (same binaries, no additional restart): direct access
to the managed TEST ONLY provider passed authorization, queue/progress/completion,
marked-content digest and deletion checks with unchanged Pod UID and zero
restarts. A controller-first end-to-end attempt initially returned
`MediaProfileUnavailable`; a later fresh attempt passed controller admission,
same-job idempotency, MoonGate progress/completion and content digest validation
(job `video-49e177e67b5f64abe2a70c9e43f68fe273d6f91d5dbb09b3359853edb3d6ac7c`).
The verifier removed its temporary download, provider job and handoff. This
establishes intermittent route/profile availability rather than permanent
provider failure; it does not close the outage-recovery acceptance gap.

The next full outage replay passed (job
`video-6b83aa3fd3787c0326707b739944aa0d4f63f311a6cce01c48376e100949102b`):
45-second controller stop, unchanged provider/workspace identities, original
job replay, MoonGate progress then completion, marked MP4 digest verification,
exactly one usage observation, and separate cancellation acknowledged deleted.
The verifier now permits bounded same-job status reads on explicitly retryable
`VideoUnavailable` only; this successful run needed no such retries. Earlier
failed runs remain evidence of intermittent availability, not retroactive passes.
Twenty read-only freshness samples before this replay all included the runtime
endpoint; maximum sampled heartbeat/endpoint ages were 9545/9815 ms, below the
15000 ms endpoint expiry. This sample does not explain every earlier 503.
No endpoint expiry or security check was relaxed. Running-provider loss, client
handling of transient status failures, and repeated recovery stability still
need acceptance. All observations are TEST ONLY, not model inference evidence.

Snapshot-invariant follow-up: a regression test first demonstrated that restore
accepted duplicate/conflicting evidence for one node/incarnation, although online
ingestion rejects changed replays. Restore now rejects such snapshots before
publishing state; the same instance ID on distinct nodes remains valid. The jobs
and runtime suites passed 27/27 with existing warnings 92/20 excluded. `moon info`
completed with 174 existing warnings and no errors. This additional source fix
is not yet included in the deployed acceptance binaries. Unrelated formatting
changes were removed; no user state or test artifacts were deleted by that cleanup.

## Live process-exit campaign (incomplete)

Job `video-c775afd9511b8d3a4b9d4c2ef04b278a43364f6089d4b76efc026aa1a46eb42a`
was admitted before setting activeDeadlineSeconds=1 on the exact TEST ONLY Pod
with a JSON-patch UID precondition. Pod UID
`4cce6332-021c-4525-b227-6eacbb8d673e` remained present with Failed /
DeadlineExceeded; original container `b99f3fb42af4fffbeda8d38cc67f879207e1a5522f5d02ad57d6a5a9dbdb96d1`
reported explicit termination at 2026-09-15T16:58:09Z. The original job became
failed and the workspace identity remained unchanged. The Pod is deliberately
retained stopped for evidence; the test provider is currently unavailable.

Cleanup exposed a real bug: DELETE changed an evidenced terminal failure into
Cancelling and returned 409. A regression reproduced `Cancelling != Cancelled`.
Source now completes cancellation/expiry locally when durable exit evidence is
already present, preserving evidence and existing settlement. Restore also
normalizes the legacy evidenced-terminal Cancelling state after validation,
persisting recovery before publication. These fixes are not deployed yet.
Do not restart the old acceptance binary against that legacy state or call this
campaign fully passed. Still required: updated controller, exact evidence and
single-settlement verification, cleanup and replacement/quota acceptance.

Follow-up: the live commercial snapshot contains exactly one observation for
the process-exit job, meter `private-workspace-video-job`, quantity 1. This
counts a private-workspace request, not successful generation or GPU time.
The operator pending view still confirms Cancelling before the fix rollout.
Linux jobs/runtime tests passed 27/27 for duplicate-evidence validation, terminal
cleanup and legacy-state restoration. The updated control binary is building;
no controller restart has yet been performed for this cleanup fix.

### Cleanup fix deployed and recovery verified

The Linux release build completed; isolated controller binary SHA-256 is now
`66608db7f96cc90021ccbe783fcaad77c2e2c693434cb62cb422bd5b111b4a4a`.
The acceptance unit restarted healthy (PID 595796, restart counter 0). Its
PostgreSQL database is `acceptance_controller`; the similarly named older
`acceptance_media_recovery_20260915` database is not the live job store.
Read-only SQL verified the exact original job as Cancelled / execution terminal,
with termination reference, observation timestamp and usage receipt retained.
The operator pending-job list is empty and commercial usage remains singular.

After saving sanitized Kubernetes termination evidence, the stopped Pod was
deleted using an explicit UID precondition. No other resource was deleted.
The supervisor recreated the desired test runtime: Running/Ready, zero restarts,
address 10.42.1.37. A subsequent private request
`video-2481dffdff03f496cc854791d65c89c958e7458dcb08452b417524105cde4301`
passed admission, same-job replay, MoonGate progress/completion and marked-video
digest verification; its test download, provider job and handoff were cleaned.
This demonstrates recovered admission capacity and a usable replacement. The
old job was rechecked afterward and remained terminal with exactly one usage
observation. Latest local native functional suite: 778/778, warnings 92/20
excluded. This does not complete the negative-partition, UI transient-retry,
broader account/commercial/browser matrix, or real hardware acceptance items.

### Expanded negative and PostgreSQL regression

The unavailable-authority/route fixture now runs with both a legacy unknown
instance and a known immutable instance. Both preserve busy capacity across
restart and deadline expiry, create no termination evidence or settlement, and
finish only after an actual provider deletion acknowledgement. Runtime tests
passed 10/10; Kubernetes supervisor + jobs + runtime passed 64/64. These are
in-process negative cases, not a live network-partition campaign.

The real PostgreSQL matrix then passed 19/19 fixture files (36 tests), including
accounts, directory, onboarding, lease/credential, commercial, registry,
scheduler/deployment, enrollment, telemetry, notifications, observability,
media jobs, controller store and inference-billing fixtures. Each fixture used
a new database; all 19 temporary databases were dropped by the verifier. This
is database integration evidence, not browser or real payment-provider evidence.

The earlier historical-assignment limitation above has been addressed in source:
reports may carry the original controller-signed assignment, verified against
every binding field with a controller signing key distinct from the node key.
In-process authenticated ingestion tests cover this path; live running-process
loss remains unverified.
