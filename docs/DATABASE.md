# PostgreSQL management database

LunaNexa uses PostgreSQL as the production system of record for the complete
management control plane. Exactly one controller replica holds the PostgreSQL
session leadership lock and remains the active writer. GPU nodes never connect
to this database.

## Stored records

Schema version 3 maintains the following normalized, indexed projections and
leadership state:

- `lunanexa.enterprise_memberships` — enterprise organization membership,
  opaque identity subject, roles and active state;
- `lunanexa.portal_agreements` — versioned agreement state and verified signer
  reference;
- `lunanexa.portal_lease_requests` — idempotent tenant lease requests and the
  single operator-selected node; retry keys are unique within the opaque
  tenant-and-subject scope rather than globally;
- `lunanexa.workspace_users` — workbench user registration and identity
  evidence;
- `lunanexa.workspace_access_grants` — scoped, expiring access authority;
- `lunanexa.workspace_leases` — time-bounded model/workbench entitlement;
- `lunanexa.snapshots` — canonical typed snapshots used for deterministic
  restart recovery, including admission reservations, hashed API credentials,
  the commercial ledger and callback history, technical prewarm/replay state,
  and the durable notification/outbox snapshot.
- `lunanexa.controller_leadership` — the current controller holder, PostgreSQL
  backend and monotonically increasing fencing token.

The snapshot table is also authoritative for `control`, `model_registry`,
`node_enrollment`, `scheduler`, `telemetry`, and `deployments`. Production
replicas never use controller-local files for those domains.

The `commercial` and `commercial_integrations` snapshot rows are committed in
one PostgreSQL transaction. A verified signature/payment/invoice callback and
its resulting business state therefore cannot survive independently. The
`technical_operations` row retains prewarm reservations and consumed transfer
nonces; a controller restart cannot make a transfer grant reusable. The
`access_keys` row stores only SHA-256 secret digests, tenant/subject bindings,
model allowlists, scopes, expiry, revocation and bounded request counters. The
one-time API-key secret is never stored.
The `notifications` snapshot row retains subject/platform-scoped events,
lifecycle generations, channel preferences and retry/dead-letter delivery
records. It stores bounded localization parameters and evidence receipts, not
message-provider credentials or raw email/SMS content.
The `observability` row holds only a bounded recent operational event window
and monotonic low-cardinality counters. It supports restart continuity and
local alerting, but does not replace the deployment log backend.

Every mutation writes the canonical snapshot and its normalized projections in
one transaction. A failed projection constraint rolls back the snapshot too.
Identifiers, generations and lifecycle states remain validated by the same
MoonBit contracts used by the APIs.

Passwords, private keys, identity documents, model-store credentials, raw
prompts and model outputs are not database fields. Authentication is owned by
the external identity provider; LunaNexa stores only an opaque subject and
bounded evidence receipt.

## Controller configuration

Production:

```sh
export LUNANEXA_PERSISTENCE_BACKEND=postgres
export LUNANEXA_DATABASE_HA_MODE=external-managed
export LUNANEXA_DATABASE_URL='postgresql://USER@DATABASE_HOST/lunanexa?sslmode=verify-full'
export LUNANEXA_CONTROLLER_INSTANCE_ID='UNIQUE_POD_UID'
```

Supply the URL through the deployment secret provider. Do not place it in a
manifest, shell history or repository file. The native controller and migration
binary require `libpq`; install the PostgreSQL client development package in the
build image and the matching runtime library in the controller image.

The old file adapter remains available only for local development and recovery
fixtures:

```sh
export LUNANEXA_PERSISTENCE_BACKEND=file
```

In PostgreSQL mode, `LUNANEXA_STATE_PATH`, `LUNANEXA_REGISTRY_PATH`,
`LUNANEXA_ENROLLMENT_PATH`, `LUNANEXA_SCHEDULER_PATH`,
`LUNANEXA_TELEMETRY_PATH`, `LUNANEXA_DEPLOYMENT_PATH`,
`LUNANEXA_PORTAL_PATH`, `LUNANEXA_WORKSPACE_PATH`,
`LUNANEXA_ACCESS_PATH`, `LUNANEXA_ACCESS_ONBOARDING_PATH`, and
`LUNANEXA_TECHNICAL_PATH` are not authoritative.
`LUNANEXA_NOTIFICATION_PATH` is likewise a development/recovery fixture rather
than the production authority. The same applies to
`LUNANEXA_OBSERVABILITY_PATH`.
The file adapters remain available for the explicit local/development profile.
They must not be presented as multi-replica persistence.

## Migration

Migration sources are `database/migrations/001_management.sql`,
`database/migrations/002_tenant_scoped_idempotency.sql`, and
`database/migrations/003_controller_leadership.sql`. Version 2 replaces
the original global lease-request retry-key constraint with a tenant-and-subject
unique index, preventing one tenant from reserving another tenant's retry key.
Version 3 adds durable controller leadership fencing. The native idempotent
migration command applies the equivalent embedded schema:

```sh
LUNANEXA_DATABASE_URL=SECRET_REFERENCE moon run cmd/database --target native
```

When upgrading an installation that previously kept the six control-plane
domains on the controller PVC, stop/fence the old controller and run the
one-time migration before applying the three-replica manifest:

```sh
LUNANEXA_DATABASE_URL=SECRET_REFERENCE \
LUNANEXA_STATE_PATH=/OLD_PVC/control.json \
LUNANEXA_REGISTRY_PATH=/OLD_PVC/registry.json \
LUNANEXA_ENROLLMENT_PATH=/OLD_PVC/enrollment.json \
LUNANEXA_SCHEDULER_PATH=/OLD_PVC/scheduler.json \
LUNANEXA_TELEMETRY_PATH=/OLD_PVC/telemetry.json \
LUNANEXA_DEPLOYMENT_PATH=/OLD_PVC/deployments.json \
LUNANEXA_CATALOG_SIGNING_SECRET=SECRET_REFERENCE \
moon run cmd/control-state-migrate --target native
```

The command requires every source file, validates each snapshot through its
own store parser (including catalog signatures), refuses any non-empty target
domain, then commits all six rows in one PostgreSQL transaction. On first
election, the database fencing token is chosen strictly above the migrated core
epoch. There is no partial or epoch-regressing cutover. Preserve the old PVC as
read-only rollback evidence until post-migration acceptance is complete.

Run migrations with a database owner role. The long-running controller should
use a narrower role with `CONNECT`, `USAGE` on schema `lunanexa`, and
`SELECT`, `INSERT`, `UPDATE`, and `DELETE` on its tables. The current controller
also verifies the idempotent schema at startup, so its initial deployment role
must have schema creation authority; split migration and runtime roles before
external multi-tenant production.

## Kubernetes deployment

`deploy/postgres.yaml` is a single-instance development/reference deployment.
The production controller deliberately rejects it through the
`external-managed` configuration contract. Render its
digest and storage class, then create the `lunanexa-database` Secret through the
secret provider with four keys:

- `database`;
- `username`;
- `password`;
- `url`.

The URL should address `lunanexa-postgres:5432` and use the same database and
user. Network policy permits only the controller to reach TCP 5432. The
database has no ingress route.

For production availability, prefer an approved managed PostgreSQL service or
a PostgreSQL operator with synchronous replication, automated failover,
encrypted storage, TLS verification, WAL archiving and point-in-time recovery.
The reference StatefulSet is not high availability.

Label the namespace containing an in-cluster HA PostgreSQL operator with
`lunanexa.io/service=postgres-ha`; the default NetworkPolicy permits controller
egress only to that labeled namespace (and to the development database pod).
For an external managed endpoint, add an explicit reviewed egress policy for
its stable network range. The application cannot infer synchronous replicas,
WAL archiving, recovery-point objectives, or successful restore exercises from
a connection URL; those remain deployment acceptance evidence.

## Controller failover

`deploy/controller.yaml` runs three replicas spread across hosts. Replicas
compete for one PostgreSQL session advisory lock. Only the winner opens the
authoritative stores and HTTP listener; standby processes retry without serving
traffic. When the leader process or database session ends, PostgreSQL releases
the lock, one standby increments the durable fencing token, restores every
control-plane snapshot, and becomes ready. `/ready` continuously verifies the
holder, backend session, and fencing token before Kubernetes routes traffic. A
background monitor terminates a formerly active process within two seconds of
losing its PostgreSQL leadership so Kubernetes replaces the fenced replica.

This design prevents split-brain writers and removes the shared RWO controller
PVC. It does not make PostgreSQL itself HA and it has a short failover interval
(one second by default), so it is not a zero-interruption claim.

Because only the leader is Kubernetes Ready, a default rolling update cannot
silently evict it while preserving its availability budget. The installer
checks that all three desired processes are on the reviewed revision and that
exactly one leader endpoint is available; it fails rather than declaring a
partially rolled update successful. Production upgrades need an explicit
maintenance handoff procedure (or a deployment-owned leader-routing operator),
not a relaxed `maxUnavailable` value that can drop the sole serving endpoint.

## Backup and recovery

Create encrypted backups outside the management-node filesystem:

```sh
pg_dump --format=custom --no-owner --file=BACKUP_FILE DATABASE_URL_REFERENCE
```

Recovery procedure:

1. stop or fence the controller writer;
2. restore into a clean database with `pg_restore`;
3. run `cmd/database` to verify the schema;
4. query `lunanexa.schema_migrations` and projection row counts;
5. start the controller replicas; the elected PostgreSQL holder atomically
   increments the fencing token;
6. verify enterprise self-view, workspace authority, lease idempotency and
   audit-chain continuity before accepting writes.

Backups contain emails and opaque identity references. Encrypt them, restrict
access, test restoration, and apply the organization's retention schedule.

## Integration test

With local `initdb`, `psql`, `postgres` and `libpq` installed:

```sh
sh scripts/postgres-integration-test.sh
```

The test creates a temporary loopback-only database, installs schema v1, upgrades
it to v3 through the real MoonBit migration path, and attacks the native binding
with SQL metacharacters, Unicode, control bytes, excessive statements and
parameter counts. It also verifies exclusive controller leadership and failover,
all HA snapshot adapters, tenant-scoped retries, projection allowlists,
transaction rollback after a forged duplicate identity, registration restart
recovery, and removal of all temporary state.
