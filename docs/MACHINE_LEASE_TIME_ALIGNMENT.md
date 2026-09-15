# Bare-machine lease and order time alignment — open defect

## Live evidence (2026-09-16 acceptance)

The sandbox order `test-only-active-metering-20260916` purchases 300 seconds.
The isolated helper really provisioned a fake-host account and its authenticated
receipt activated the lease. No actual SSH credential or physical account is
claimed.

Observed authoritative times:

- Lease starts: 1789496425061; expires: 1789496725061.
- Lease Active receipt accepted: 1789496462895.
- Customer order Active start: 1789496488665.
- Order-derived contracted end: 1789496788665.

The order's derived end is 63604 ms after the lease's enforced expiry. The
customer therefore does not receive the full advertised interval under this
combination. Final usage/cleanup has not yet been observed for this order, so
actual post-expiry metering or overcharging is not claimed here.

## Source cause

`start_paid_machine_order` issues the exclusive lease using reservation time
plus purchased duration. `reconcile_provisioning_machine_order` later calls
`complete_provisioning` with coordinator observation time. The latter sets both
active_started and last_metered to that later time; periodic and terminal usage
derive a separate end from active_started plus purchased duration.

## Required fix boundaries

- Define a single customer entitlement interval aligned with usable access.
- Preserve separate reservation/provisioning/cleanup occupancy timestamps.
- Bind credential expiry and node helper authorization to the same interval;
  changing an order timestamp alone must not falsely extend an SSH credential.
- Persist the interval across coordinator restart/replay and delayed receipts.
- Do not mutate already-expired historical leases or rewrite past receipts to
  make evidence appear consistent.
- Add delayed-provisioning and delayed-coordinator regression cases, then repeat
  live activation, expiry, cleanup and usage inspection.

This is an open correctness defect, not a completed implementation plan or a
production acceptance claim. It applies to commercial bare-machine delivery;
private-cloud workspace authorization remains a separate path.

## In-flight database checkpoint

PostgreSQL currently contains consecutive usage intervals
1789496488665–1789496551820 and 1789496551820–1789496614991, each rounded
to 64 seconds. These are before the enforced lease expiry and do not themselves
prove post-expiry usage. The intervals share an endpoint without overlapping;
rounding each interval independently may also accumulate excess whole seconds,
which requires a separate total-duration regression before making a claim.

## Live expiry follow-up

The controller moved the lease to Expiring generation 4 at 1789496741548.
Actual isolated helper revoke/sanitize receipts then completed the lease at
1789496788365, generation 8. PostgreSQL usage receipt ending 1789496741537
crosses the enforced lease expiry 1789496725061 by 16476 ms. Post-expiry usage
evidence is therefore confirmed; this prepaid evidence is not itself proof of
an additional monetary debit. Order final reconciliation remains to be checked.

Full current native tests passed 783/783 with warning classes 92 and 20 excluded.
This demonstrates that the existing suite does not catch this live interval
mismatch; it is not a reason to dismiss the defect or claim production readiness.

## Separate cumulative-rounding correction (local, not deployed)

A new regression reproduced two adjacent 1 ms intervals yielding two seconds.
Periodic and terminal usage now subtract rounded cumulative elapsed seconds
from the same active anchor, instead of independently rounding each interval.
The test covers snapshot restoration, replay of a zero-increment receipt and
terminal completion: a total six-second duration remains six seconds regardless
of the intermediate polling boundaries. Machinecommerce tests pass 7/7.

This local correction does not align credential/lease expiry with the order,
and does not rewrite historical receipts created by the previous algorithm.
Integration tests and deployment verification remain before completion.

Final live order reconciliation reached Terminated generation 11 and released
capacity. The pre-fix receipts sum to 64+64+64+64+48+0 = 304 seconds for the
300-second order interval. The final meter endpoint is 1789496788665, confirming
the separate 63604 ms expiry mismatch persists. Actual polling boundaries were
added to the rounding regression, which requires a cumulative total of 300.

Additional partition tests cover 1 ms, 999 ms, whole seconds and uneven polling
through 300 seconds, including maximum Int64 elapsed rounding without addition
overflow. Native and JavaScript machinecommerce tests both pass 8/8; native
`moon check machinecommerce --target native --deny-warn` passes.

The customer credential projection explicitly closes access when
now >= lease.intent.expires_unix_ms, and credential issuer requests/handoffs
persist their own expiry and generation bindings. A fix limited to the order's
displayed expiry cannot correct actual customer access. These bindings must be
included in the interval alignment change and its recovery tests.

The API regression now creates real positive and zero fractional receipts
through the durable machine store, imports the snapshot twice, and verifies two
nonzero usage observations with no payable ledger entries. All four machine
commerce API reconciliation tests pass; the persistence package test also
passes. Unrelated formatter-only API changes were reverted, retaining only
the metering implementation, its tests and this defect record.

## Interval alignment implementation in progress (not deployed)

The lease store now supports an explicit paid activation duration during the
Provisioning-to-Active transition. It signs and persists the new start/end in
the same mutation, rejects expired reservations, invalid duration/overflow and
stale generations, and leaves ordinary transitions unchanged. A durable-store
regression checks delayed preparation, full duration, reopen and stale replay;
all seven lease-store tests pass.

Authenticated provision observation resolves the exact provisioning bare-machine
order and passes its purchased duration. The order coordinator uses the resulting
lease start instead of its later polling time. API type checking passes.
Integration, credential expiry and agent recovery tests remain in progress;
this does not yet establish deployed correctness or legacy-order migration.

Agent interval/restart regression passes (nodelease package 22/22): receiving
the activated generation preserves access past the preparation deadline and
revokes exactly at the new expiry after snapshot restoration. API activation
test now uses the authenticated signed helper observation route instead of a
direct store transition. Its fixture needed an explicit independent helper
receipt key; the corrected integration run remains pending.

The corrected signed-observation integration passes 4/4: the resulting paid
lease begins at the accepted observation time, expires one purchased duration
later, and order activation uses the same anchor. Added duration-boundary and
expired-preparation rollback cases pass in the seven lease-store tests. The API
also rejects paid activation when actual controller receive time has already
passed preparation expiry, preventing a backdated observation from reviving it.
Customer projection/credential valid-until are checked against the new expiry.
No deployment or full post-change hardware/provider acceptance is implied.

Full native regression after the receive-time guard passes 786/786 with warning
classes 92 and 20 excluded. This is not the strict warning-free release gate.
The existing PostgreSQL matrix passed all 19 fixture files (36 tests) against
isolated scratch databases, and every temporary database was dropped. Its
exclusive-lease fixture was subsequently extended with delayed paid activation,
reopen, stale-generation replay rejection, survival of the original preparation
expiry, and expiry/reopen at the new paid deadline. The extended PostgreSQL
matrix again passed all 19 fixture files (36 tests); scratch databases were
dropped. The lease-store package also passes 7/7. Linux deployment-candidate
construction is underway; live acceptance still runs the previous binary.

The Linux candidate subsequently built successfully (with an upstream async C
prototype warning) and replaced only the isolated acceptance controller. Its
SHA-256 is f0ced20a902f841148c02f431b2d65aab6981cb90fc79684d44bc0b7dde4b492;
health passed, PostgreSQL/configuration were retained, and the old binary was
backed up. A new TEST ONLY 300-second order,
`test-only-aligned-metering-20260916`, has sandbox settlement Applied/Replayed.
Provisioning and final duration/metering verification are still in progress;
this is not real payment or physical-machine access evidence.

The actual isolated helper observation activated generation 3 with start
1789499243211 and expiry 1789499543211: exactly 300000 ms after activation,
instead of the earlier reservation time 1789499205249. Final order anchor,
expiry cleanup and cumulative usage still need the completed live interval.

While the order was Active, the isolated controller was restarted (PID 834943
to 841778) and health recovered. PostgreSQL retained the exact order activation
anchor and lease interval above; the next usage checkpoint ends at
1789499315413 with cumulative quantity 73 seconds. This proves live restart did
not restart the purchased clock, but final expiry/cleanup remains pending.

Additional gate checks: JavaScript machine-access UI tests pass 6/6 with
`--deny-warn`; `git diff --check` passes. The existing static isolation script
fails on `container_id` in the private Kubernetes journal and a parser parameter
(`node/kubernetes/journal.mbt`, `termination.mbt`). These hits are not themselves
public-response exposure evidence. Scanner boundary correction and corresponding
negative fixtures remain required; the isolation gate is not reported passed.

## Completed live paid-interval campaign

The aligned order reached Terminated generation 11 with capacity_reserved=false.
Its lease reached Completed generation 8 after actual isolated helper revoke
and sanitize receipts. Usage quantities are 73+63+63+64+37+0 = 300 seconds.
The last metered endpoint equals the lease expiry, 1789499543211; cleanup delay
did not add usage. The controller restart preserved the common activation anchor.
This verifies the two fixes in the deployed TEST ONLY workflow with PostgreSQL;
it does not prove real SSH access, physical sanitization or production payments.
Natural expiry is currently labelled CustomerTermination in the order's reason,
which remains a separate lifecycle-reason accuracy issue to investigate.

The reason issue is now corrected locally: termination derives elapsed status
from the persisted activation anchor and purchased duration, not untrusted
reason text. Tests verify natural expiry survives cleanup and early termination
cannot be mislabelled by supplying ContractDurationElapsed. Native machine
commerce tests pass 8/8 with --deny-warn. This follow-up reason-only correction
has not yet replaced the deployed candidate or rewritten historical orders.
