# Scheduler and telemetry write recovery — 2026-09-16

This checkpoint covers local persistence failure and successful retry, not
PostgreSQL ambiguous-commit recovery, cancellation during a database commit,
or a deployed controller upgrade.

Telemetry's new regression first failed against the prior implementation:
after a rejected temporary-file write, memory contained the new sample and had
already discarded the old bounded-history sample. Sample and benchmark writes
now restore their previous arrays on unsuccessful completion, including scoped
unwind, before releasing the mutex. Tests cover history pruning, both write
paths, unchanged disk state, retry, and reopening the final persisted state.
The strict native telemetry suite passes 6/6.

Scheduler mutations now release their mutex through scoped cleanup and restore
the prior snapshot on unsuccessful persistence. Rejected admission no longer
updates the in-memory usage window without persisting it. A regression injects
temporary-file write failure into quota changes, admission, start attribution,
completion, cancellation and placement history. Each failure preserves both the
in-memory snapshot and disk bytes; removing the fault permits retry. Completion
replay records only one completion and 125 accelerator milliseconds. Reopening
the final store matches the in-memory snapshot. The strict native scheduler
suite passes 8/8.

These targeted runs use `--deny-warn` without exclusions. Generated public
interfaces are unchanged. Broader strict-gate failures in other packages remain
separate work, and conditional database cases are not fresh live PostgreSQL
evidence merely because their test runner exits successfully.

The full native functional suite passed 794/794 with
`moon test --target native --warn-list -92-20`. A subsequent strict scheduler
rerun also passed 8/8 after adding an assertion that quota rejection in a new
usage window leaves both memory and disk unchanged. The full run's warning
exclusions are required by other packages and do not satisfy the strict
repository gate. No cluster service was upgraded in this batch.

## Offline commercial store follow-up

The offline commerce store's 23 rollback handlers now use scoped mutex release
and error cleanup instead of catch-and-rethrow cleanup. Existing per-operation
rollback fields, validations and replay decisions are retained. The strict
native store suite passes 14/14 with no warning exclusions; interface generation
reports zero warnings and no public interface change.

File-fault regressions reject temporary writes during template registration,
order creation, quote replacement, upload callback, entitlement activation
callback and entitlement reversal callback. Each compares the full in-memory
snapshot and original disk bytes, removes the injected fault, and completes
the original operation. Existing activation/reversal replay checks and final
reopen-to-Revoked checks also pass. These tests do not inject cancellation at
the commit boundary or prove recovery from an ambiguous PostgreSQL commit.
The remaining callback and worker transitions retain their existing functional
tests, not exhaustive new persistence-fault coverage.

The follow-up `moon test commercial/offline api --target native --warn-list
-92-20` run passed 130/130. This selected-package API/contract regression is
separate from the 14 strict store tests above; it is not a full repository or
live external-provider acceptance run. This batch has not been deployed.

At commit `548e686`, the real PostgreSQL acceptance matrix passed 19/19 fixture
files, each with an explicitly configured connection and a separate fresh
database. An independent catalog query afterwards found zero
`lnx_acceptance_*` databases; the run's loopback-only SSH tunnel was closed.
This exercises the existing database fixtures, not database failover. In
particular, the scheduler fixture currently restores capacity only and the
telemetry fixture restores an empty snapshot. Nonempty state across newly
established database connections remains a coverage gap for those two fixtures.

That narrow nonempty-recovery gap was subsequently covered and the real matrix
rerun passed 19/19. Scheduler coverage now persists quota and a started workload,
closes its connection, restores through a new connection, rejects duplicate
admission, completes the workload twice, then opens a third connection and
verifies exactly one completion/125 accelerator milliseconds and available
capacity for a new workload. Telemetry persists a bounded sample, closes its
connection, and restores the exact snapshot/value through a new connection.
Both packages also pass their 14 local strict tests; those local runs alone
skip environment-conditional database execution. Interface generation passes.
An independent database catalog query again found zero temporary acceptance
databases, and the test tunnel was closed. Database-server failover and ambiguous
commit recovery remain separate unproven scenarios.

## Cancellation boundary

New white-box tests hold the commerce/telemetry mutex in an owner task and
cancel two consecutive waiting writers using an explicitly identified timeout
error. Both waiters must enter and time out; neither can release the owner's
lock, mutate the snapshot or alter disk bytes. After the owner releases its
lock, a bounded new write and reopen succeed. Combined strict package tests
pass 22/22. This is lock-wait cancellation coverage, not cancellation during
persistence.

Source inspection confirms `PostgresDatabase::save_opaque_snapshot` acquires
its async mutex and then performs BEGIN, snapshot write and COMMIT through the
synchronous native `PQexec`/`PQexecParams` adapter. There is no asynchronous
yield between these transaction calls. Consequently an async timeout in that
task is not an adequate commit-interruption test, and synchronous database I/O
may delay other work on the same execution thread. Independent connection or
server fault injection and an explicit ambiguous-outcome recovery design remain
necessary; the passing tests do not establish those properties.

The scheduler and telemetry real-database fixtures subsequently added two
consecutive writes after explicitly closing their original connection. Both
reject with QueryFailed and preserve their entire in-memory snapshot; a fresh
connection restores exactly the pre-failure data. Scheduler completion then
recovers and remains exactly once. The selected real PostgreSQL matrix passes
2/2 fixture files, deletes its two temporary databases, and its SSH tunnel was
closed. This is a known disconnection before a write, not a server kill,
database failover or an ambiguous COMMIT outcome.

The commercial PostgreSQL fixture also rejects two order-creation attempts
after closing its connection, retaining the complete snapshot. A new connection
restores that snapshot, accepts the same order/key, and returns the same order
on replay without a duplicate. Its selected real-database run passes 1/1 and
the strict local commerce store suite passes 15/15. The temporary database was
dropped by the runner and the tunnel was closed. Together these three domain
fixtures cover known-disconnected writes, not interruption during COMMIT.

## Account authority cleanup

All thirteen account-store write/authorization cleanup handlers now use scoped
mutex release and error rollback rather than catch-and-rethrow cleanup. Invited
registration releases its scoped lock before issuing the browser session, so
the later operation can reacquire the same mutex. Existing identity, invitation,
trial and session validation rules and public interfaces are unchanged.

The new account fixture cancels two consecutive mutex waiters while an owner
holds the lock, checks unchanged memory/disk, then injects two file-write
failures through the snapshot staging path. Timed reads prove failed writers
release the mutex; a retry and reopen persist exactly one account. It also
injects failure while suspending an account with a live session: account and
session snapshots roll back together. A successful retry survives reopen and
the old session is rejected. Test directories are removed by scoped cleanup.

Account strict native tests pass 11/11; the account/API functional selection
passes 140/140 with warning classes 92 and 20 disabled for still-unmigrated
packages. Interface generation and formatting completed. This is local
file-failure and lock-wait coverage, not in-flight database commit cancellation,
real identity-provider registration, or evidence that the running controller
has been upgraded to this source revision.

## Prewarm and one-time transfer cleanup

The technical store uses scoped mutex release for prewarm creation, state
advancement and transfer-grant consumption. Failed prewarm writes restore the
previous operation map; failed nonce persistence removes only the nonce added
by that attempt. Public contracts and transfer validation remain unchanged.

The file fixture injects two consecutive staging-write failures into each of
these three paths, verifies complete snapshot/disk equality and bounded lock
reacquisition, then retries successfully. Reopening the store rejects the
successfully consumed nonce as `NonceReplayed`. A separate cancellation fixture
holds the mutex while two waiting consumers time out, proves neither releases
the owner lock nor consumes the nonce, and then consumes/reopens/rejects replay
after release. Temporary directories are removed on exit, including the older
restart fixture that previously left its snapshot in `/tmp`.

Strict native tests pass 11/11 for the technical policy package and 2/2 for its
store package. Interface generation and scoped formatting pass without public
interface changes. This is file-failure and mutex-wait evidence only; it does
not claim an actual model transfer, PostgreSQL commit interruption, or deployment
of the modified binary on the acceptance controller.

## Workspace handoff lifecycle rollback

Client handoff issue, redeem, quota-consuming authorization and subject-scoped
revocation now use scoped lock release and error rollback. The fixture forces
two staging-write failures at each of those four stages, verifies complete
memory/disk equality and bounded lock reacquisition, then retries and reopens.
Recovery retains exactly one handoff and one credential; successful consumption
charges exactly one request. A redeemed code rejects replay after reopen and
a revoked credential rejects authorization after reopen. Neither plaintext
handoff code nor API secret appears in the persisted snapshot.

All four strict native handoff-store tests pass. Interface generation and
scoped formatting pass without public interface changes. The three older
handoff fixtures now also remove their temporary directories on exit. These
tests establish file-failure/retry behavior, not mid-write cancellation,
database failover or live controller rollout of this source change.

## Account, transfer and handoff fresh-connection PostgreSQL follow-up

The live acceptance PostgreSQL matrix now includes dedicated technical-store
and client-handoff-store fixtures, rather than only their snapshot-domain
allowlist. Three selected fixture files passed against isolated fresh databases;
the subsequently strengthened account fixture also passed its separate rerun.

- Account registration/invitation/session state survives a fresh connection.
  Two suspension writes on the closed original connection fail with QueryFailed
  without changing either account or session snapshots. Retried suspension on
  a fresh connection persists, and a third connection rejects the old session.
- Handoff redemption and one consumed request survive a fresh connection.
  Two closed-connection revocations fail without changing state; the redeemed
  code still rejects replay. Retried revocation persists and a third connection
  rejects credential authorization.
- A consumed transfer nonce survives reconnect. Two failed attempts to consume
  another nonce on the closed connection leave the snapshot unchanged. The new
  connection rejects the first nonce, accepts the second, and a third connection
  observes exactly two consumed nonces and rejects the second nonce's replay.

The combined strict local package suite passes 19/19 (its conditional database
tests alone are not the live evidence). Interface generation and formatting
pass. Every matrix database was dropped, an independent catalog query found
zero `lnx_acceptance_%` databases, and the dedicated SSH tunnel was closed.
The acceptance PostgreSQL service was not stopped. These tests do not establish
server failover, interruption during COMMIT, or actual model transfer.

## Machine-order payment and provisioning rollback

The durable machine-commerce adapter now releases every acquired mutex through
scoped cleanup and restores its prior typed snapshot on errors in fourteen
mutation paths, including cross-store compensation replacement. Business
validation, signing, contract/payment requirements and public APIs are unchanged.

The file fixture forces two consecutive write failures during settled-payment
activation and two during provisioning startup. Complete snapshots and disk
bytes remain unchanged after each failure; bounded snapshot reads prove the
mutex is available. Retrying and reopening preserves one capacity reservation,
and repeating the original payment and provisioning requests returns Replayed.
The fixture now removes its temporary directory on exit. The machine-commerce
core/store strict native selection passes 9/9; interface generation and scoped
formatting pass without public interface changes. This does not represent real
payment settlement, real machine provisioning or live controller rollout.

The selected reconciler, customer machine HTTP and inference-billing fixtures
also pass 10/10 with warnings 92/20 disabled for remaining dependencies. They
cover bare-machine provisioning, dedicated endpoint separation, the paid video
test path, capacity-timeout compensation, tenant/organization authorization,
termination confirmation, expiry recovery and billing receipt behavior. Any
environment-conditional database branch in this local run is not fresh live
PostgreSQL evidence.

## Access-onboarding journal recovery

The onboarding journal's begin, advance, failure-record and retry operations
now use scoped mutex release and error rollback without changing step ordering,
terminal conflict handling, authority prerequisites or public interfaces.
The file fixture injects two consecutive staging-write failures at each of
those four stages and verifies complete memory/disk equality and bounded lock
reacquisition. Successful retries survive reopen, preserve the AccountReady
resume point and exactly two recorded attempts, then progress through each
remaining step to Completed with no pending operation. Both local journal
fixtures remove their temporary directories on exit.

The strict native onboarding suite passes 3/3; its conditional PostgreSQL test
is not fresh live database evidence in this local run. Interface generation and
scoped formatting pass without public interface changes. Cross-store atomicity
and actual user-facing identity-provider activation are not implied by journal
rollback alone.

The access-onboarding and API-key HTTP regression selection passes 5/5 with
warnings 92/20 disabled for remaining dependencies. It includes the resumable
access-package path, cross-store crash/restart recovery and current-account
revalidation before API-key quota consumption. These are repository integration
tests, not a new public IdP/browser acceptance result.

## Exclusive-lease and machine-credential cleanup

The lease store's issue, transition and expiry-reconciliation paths and the
credential store's five write handlers now use scoped mutex release and error
rollback. Public APIs, signatures, lease lifecycle and issuer-readiness checks
remain unchanged.

A new lease fixture fails reservation, provisioning transition and expiry
persistence twice each, verifying all lease records, disk bytes and placement
blocking remain unchanged. Each successful retry survives reopen. Expiry reaches
generation 3/Expiring, repeated reconciliation makes no further transition,
and the node remains blocked from managed placement: expiry is not proof of
access revocation or sanitization.

The credential outbox fixture fails both queue creation and dispatch acceptance
twice, preserving the complete request/record snapshot and disk bytes. Recovery
creates exactly the same replayable dispatch and handoff across reopen. All
new temporary directories are removed by scoped cleanup. Combined strict native
store tests pass 14/14; interface generation and scoped formatting pass without
public interface changes. No actual host account, SSH credential or leased
machine was changed by these fixture tests.

The selected lease HTTP, lease-billing and credential-handoff HTTP fixtures pass
8/8 with warnings 92/20 disabled for still-unmigrated dependencies. This local
integration run does not replace external SSH issuer, actual host cleanup or
physical sanitization acceptance.

## Enterprise portal persistence recovery

The portal store now uses scoped mutex release in its two authorized self-view
paths and scoped release/error rollback in seven mutation paths. Organization
membership, trial replacement, agreement signing and lease-review authorization
rules and public interfaces are unchanged.

The signature/approval fixture injects two consecutive staging-write failures
for signature requests and for lease approval. Each failure preserves the full
in-memory snapshot and disk bytes; a bounded snapshot read verifies lock release.
Removing the injected fault permits normal retry, and reopen retains the executed
agreement and approved request. Temporary files are removed on fixture exit.
The strict native portal and portal-store selection passes 12/12; scoped
interface generation and formatting pass without generated interface changes.
This is local persistence evidence, not an external signing-provider result or
a deployment of the new controller binary.

The portal HTTP selection also passes 2/2 with warnings 92/20 disabled for
remaining dependencies. No live signing, lease provisioning or user membership
is changed by this local regression run.

A fresh full native strict check still reports 63 errors, including deprecated
trait-method calls and remaining fragile async cleanup handlers. Passing the
targeted suite does not imply that the repository-wide strict gate has passed.

The subsequent full native functional run passes 803/803 with warnings 92/20
disabled. Environment-conditional PostgreSQL branches in this local run are
not fresh live database evidence. This functional result does not override
the remaining strict-check errors or qualify real hardware/model inference.
