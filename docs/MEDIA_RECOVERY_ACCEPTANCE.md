# Media job recovery acceptance — 2026-09-15

## Scope and result

The media recovery feature preserves immutable execution attribution across
controller restarts and separates unavailable authority/readiness from an
explicit revocation. This is an isolated Linux/Kubernetes/PostgreSQL acceptance
result with a **TEST ONLY** video provider, not GPU inference or Spark hardware
qualification.

The controller now durably records the logical deployment, generation and node
alongside a job's immutable provider-binding identity before submission. These
fields contain neither a route nor a credential. Only fresh evidence for the
original runtime instance permits provider traffic. Missing endpoint evidence
does not itself cancel an unexpired job or release its capacity reservation.
Known revocation or a durable local deadline requests cancellation; release and
settlement still require a terminal result or an acknowledged deletion.

Legacy snapshots without the optional placement field remain readable. Legacy
placement may only be backfilled from a currently verified original binding;
missing historical placement is not guessed. Conflicting placement and failed
persistence are rejected without publishing a partial in-memory update.

## Live acceptance

The isolated user service `lunanexa-acceptance-controller-20260915.service`
was updated with controller SHA-256
`6a7efc9dad36e85f52dfb12d717d7c226cadc2d7a12cf4dc4be4d65f902f1155`.
The previous executable and the original protected configuration were retained.
No production controller, GPU identity, host trust or model weights changed.

The run used the existing private workspace authorization and deployment
`managed-test-video-20260915-r9`. Its provider Pod remained on the actual AMD64
compute node `lunanexa-gpu-180`; it was not represented as an ARM64 Spark.

Observed sequence:

1. Submit a marked test video through MoonGate with a fresh idempotency key.
2. Observe queued job
   `video-30b9cdf1dec44d3983651cd85b882911f60ea399b93c85d275e8bf95321a1b47`.
3. Stop the isolated controller and confirm its health endpoint is unavailable.
   Wait five seconds and compare the provider Pod UID, container ID and restart
   count with their pre-outage values; all remain unchanged.
4. Restore the controller with the same PostgreSQL/configuration. Retry the same
   request key against the controller; receive the same job ID. Poll through
   MoonGate and observe `in_progress`, then `completed`.
5. Download through MoonGate and verify the test MP4 SHA-256:
   `100f5f75c28643c855e503d16b0a1b6941fbfceb2d0b0881f16d7a420df54f91`.
6. Verify exactly one commercial usage observation for the job, with meter
   `private-workspace-video-job` and quantity `1`.
7. Submit another test job and explicitly cancel it. Job
   `video-7a18f8dce183c35b179805232a6596374dc2321d854a823bd1016f595e6e1ce0`
   returns `video.deleted`, `deleted: true`.

The controller startup path requires PostgreSQL for configured media bindings
and restores the `media_jobs` snapshot via `media/jobs/store`. This run proves
controller-process recovery against that persistent database, **not PostgreSQL
server failover**.

An initial fault-injection attempt failed because stopping a transient systemd
unit can remove its definition. The acceptance helper was corrected to recreate
the exact isolated unit from the original configuration when necessary. The
failed attempt is not counted as a pass; the subsequent full run passed.

Temporary downloads and the successful run's scoped handoff/session were
cleaned. A follow-up cleanup selected only recovery-test handoffs; no active
matching handoff remained. The operator pending-job endpoint returned
`{"data":[],"truncated":false}` after the run. Durable audit/usage records,
user workspace files, and rollback/build artifacts were intentionally retained.

## Automated verification

- Linux native API + media jobs + media runtime: **146/146 passed**.
- Local native media jobs + runtime, including the new public API test:
  **19/19 passed** (these overlap the Linux total).
- Local native media persistence-driver tests: **2/2 passed**.
- Native controller release build succeeded; the built executable was used in
  the live run above.
- Generated public interfaces and feature formatting were refreshed; the
  optional context and `AuthorityUnavailable` error are intentional API changes.

Regressions cover legacy snapshots, failed writes, immutable placement,
authority outages, unsubmitted expiry, recovery from cancellation-in-progress,
capacity held until deletion acknowledgment, exactly-once settlement, missing
endpoint evidence, replacement-instance rejection, and explicit owner denial.
Provider submission/deletion/settlement counts are asserted in local fixtures;
the live run verifies stable job identity and a single billing observation.

## Limits and outstanding gates

- The CPU test provider stores its own jobs in memory. Provider-process restart
  and recovery of a lost provider job are not proven by this controller restart.
- Endpoint-loss/replacement and authority-outage distinctions have regression
  coverage; this run did not perform a live replacement of the provider Pod.
- No ARM64/CUDA/SM121, model load, generation quality, performance, VRAM or
  dual-Spark evidence is claimed.
- The laboratory route still depends on temporary forwarding and a local
  MoonGate process. It is not a production availability qualification.
- The full repository native release gate has pre-existing MoonLeaf compiler
  compatibility/warning failures. Linux staging includes earlier compatibility
  adjustments and is not evidence of a pristine whole-repository release.
- The existing dependency-isolation gate rejects the literal `moongate`
  selector in workspace host manifests. This feature does not waive that gate.
