# Offline entitlement execution

The entitlement dispatcher invokes `POST
/v1/offline-commerce/operator/entitlement-execute` using the separate entitlement
authority bearer credential. The body contains exactly one `activation` or
`reversal`, copied unchanged from claimed durable work. Browser credentials and
the platform bootstrap operator token do not authorize this machine endpoint.

The response is either HTTP 200 with the terminal typed activation/reversal,
or HTTP 202 with `EntitlementExecutionPending`. A dispatcher retains pending work
locally and retries execution without consuming another claim attempt. Terminal
results may also be posted to the existing result callback routes; those calls
are idempotent after execution has already committed the result.

## Real authority, not a simulated acknowledgement

- `WorkspaceLease` names an existing administrator-prepared lease. Execution
  checks the purchaser, tenant, order term, live user/grant authority, and then
  activates the requested lease. Reversal revokes that lease, not the person's
  unrelated workspace grants or stored work.
- `ExclusiveMachineLease` names an existing exclusive lease. Execution reuses
  node-drain/provisioning reconciliation. Only the existing node-helper
  observation path can make the lease active. Reversal requests expiry and waits
  for verified revocation and sanitization before confirming completion.
- `CapacityCommitment` names an existing commitment. A proposed commitment still
  requires the normal separate procurement approver. Activation and cancellation
  mutate the commercial authority and persist through its configured database.

The endpoint does not invent node selection, usernames, credential references,
workspace quotas, or capacity units from an opaque target string. Those inputs
must already have been authorized when the target was prepared. A target cannot
be attached to two live offline orders of the same entitlement kind.

Execution and terminal order updates are serialized against order mutation.
The target operations are idempotent, enabling recovery when a process stops
between the authority mutation and the order completion write. Resource terms
cannot extend past the order term. An activation replay after order expiry is
rejected rather than reopening expired access. External node provisioning and
cleanup remain pending until actually observed; the tests' injected node states
are not physical-machine acceptance evidence.

## Frozen document execution inputs

Offline snapshot v6 retains one generation plan per immutable generation request.
The first actual claimed execution freezes the resolved document markers or quote
cells. Subsequent packet edits cannot silently change a retried artifact. File
snapshots migrate from v1–v5; PostgreSQL loading recognizes every corresponding
version before saving v6. A new generation request is required for an intentional
new document revision.

The cache uses detached JSON copies and is omitted from the operator listing;
only the authenticated dispatcher plan endpoint returns the resolved inputs.
Template-discovery responses do not freeze an empty marker plan.

## Acceptance boundaries

Native regression tests exercise real file-backed workspace mutation, restart
replay, cross-tenant refusal, procurement separation, order serialization, frozen
plans and v5 migration. Exclusive-lease tests explicitly inject node observations
to verify pending-versus-complete behavior. They do not certify SSH issuance,
physical disk cleanup, font licensing, rendered legal-document fidelity, payment
settlement, or the production PostgreSQL deployment.
