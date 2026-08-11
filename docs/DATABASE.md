# PostgreSQL management database

LunaNexa uses PostgreSQL as the production system of record for enterprise
registration and workspace authority. The controller remains the only writer.
GPU nodes never connect to this database.

## Stored records

Schema version 2 maintains the following normalized, indexed projections:

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
  the commercial ledger and callback history, and technical prewarm/replay
  state.

The `commercial` and `commercial_integrations` snapshot rows are committed in
one PostgreSQL transaction. A verified signature/payment/invoice callback and
its resulting business state therefore cannot survive independently. The
`technical_operations` row retains prewarm reservations and consumed transfer
nonces; a controller restart cannot make a transfer grant reusable. The
`access_keys` row stores only SHA-256 secret digests, tenant/subject bindings,
model allowlists, scopes, expiry, revocation and bounded request counters. The
one-time API-key secret is never stored.

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
export LUNANEXA_DATABASE_URL='postgresql://USER@DATABASE_HOST/lunanexa?sslmode=verify-full'
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

In PostgreSQL mode, `LUNANEXA_PORTAL_PATH`, `LUNANEXA_WORKSPACE_PATH`,
`LUNANEXA_ACCESS_PATH`, and `LUNANEXA_TECHNICAL_PATH` are not authoritative.
Controller registry, scheduler, assignment, enrollment, telemetry, deployment
operation and exclusive-lease stores retain their signed file/PVC adapters;
they are included in the controller backup set and fenced by controller epoch.

## Migration

Migration sources are `database/migrations/001_management.sql` and
`database/migrations/002_tenant_scoped_idempotency.sql`. Version 2 replaces
the original global lease-request retry-key constraint with a tenant-and-subject
unique index, preventing one tenant from reserving another tenant's retry key.
The native idempotent migration command applies the equivalent embedded schema:

```sh
LUNANEXA_DATABASE_URL=SECRET_REFERENCE moon run cmd/database --target native
```

Run migrations with a database owner role. The long-running controller should
use a narrower role with `CONNECT`, `USAGE` on schema `lunanexa`, and
`SELECT`, `INSERT`, `UPDATE`, and `DELETE` on its tables. The current controller
also verifies the idempotent schema at startup, so its initial deployment role
must have schema creation authority; split migration and runtime roles before
external multi-tenant production.

## Kubernetes deployment

`deploy/postgres.yaml` is a single-instance reference deployment. Render its
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
5. start the controller with a higher controller epoch;
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
it to v2 through the real MoonBit migration path, and attacks the native binding
with SQL metacharacters, Unicode, control bytes, excessive statements and
parameter counts. It also verifies tenant-scoped retries, projection allowlists,
transaction rollback after a forged duplicate identity, registration restart
recovery, and removal of all temporary state.
