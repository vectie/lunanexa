BEGIN;

CREATE SCHEMA IF NOT EXISTS lunanexa;

CREATE TABLE IF NOT EXISTS lunanexa.schema_migrations (
  version integer PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS lunanexa.snapshots (
  domain text PRIMARY KEY,
  schema_version text NOT NULL,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  payload jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS lunanexa.enterprise_memberships (
  membership_id text PRIMARY KEY,
  tenant_ref text NOT NULL,
  organization_id text NOT NULL,
  subject_ref text NOT NULL,
  active boolean NOT NULL,
  created_unix_ms bigint NOT NULL CHECK (created_unix_ms > 0),
  payload jsonb NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS enterprise_memberships_active_subject
  ON lunanexa.enterprise_memberships(subject_ref) WHERE active;
CREATE INDEX IF NOT EXISTS enterprise_memberships_tenant_org
  ON lunanexa.enterprise_memberships(tenant_ref, organization_id);

CREATE TABLE IF NOT EXISTS lunanexa.portal_agreements (
  agreement_id text PRIMARY KEY,
  tenant_ref text NOT NULL,
  organization_id text NOT NULL,
  state text NOT NULL,
  generation bigint NOT NULL CHECK (generation > 0),
  signer_subject_ref text,
  updated_unix_ms bigint NOT NULL CHECK (updated_unix_ms > 0),
  payload jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS portal_agreements_tenant_org_state
  ON lunanexa.portal_agreements(tenant_ref, organization_id, state);

CREATE TABLE IF NOT EXISTS lunanexa.portal_lease_requests (
  request_id text PRIMARY KEY,
  idempotency_key text NOT NULL UNIQUE,
  tenant_ref text NOT NULL,
  organization_id text NOT NULL,
  subject_ref text NOT NULL,
  state text NOT NULL,
  generation bigint NOT NULL CHECK (generation > 0),
  assigned_node_id text,
  updated_unix_ms bigint NOT NULL CHECK (updated_unix_ms > 0),
  payload jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS portal_lease_requests_tenant_org_state
  ON lunanexa.portal_lease_requests(tenant_ref, organization_id, state);
CREATE INDEX IF NOT EXISTS portal_lease_requests_subject
  ON lunanexa.portal_lease_requests(subject_ref, updated_unix_ms DESC);

CREATE TABLE IF NOT EXISTS lunanexa.workspace_users (
  user_id text PRIMARY KEY,
  subject_ref text NOT NULL UNIQUE,
  email text NOT NULL,
  state text NOT NULL,
  created_unix_ms bigint NOT NULL CHECK (created_unix_ms > 0),
  payload jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS workspace_users_email ON lunanexa.workspace_users(email);

CREATE TABLE IF NOT EXISTS lunanexa.workspace_access_grants (
  grant_id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES lunanexa.workspace_users(user_id),
  tenant_ref text NOT NULL,
  state text NOT NULL,
  expires_unix_ms bigint NOT NULL,
  payload jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS workspace_access_grants_user_state
  ON lunanexa.workspace_access_grants(user_id, state, expires_unix_ms);

CREATE TABLE IF NOT EXISTS lunanexa.workspace_leases (
  lease_id text PRIMARY KEY,
  tenant_ref text NOT NULL,
  subject_ref text NOT NULL REFERENCES lunanexa.workspace_users(subject_ref),
  state text NOT NULL,
  starts_unix_ms bigint NOT NULL,
  expires_unix_ms bigint NOT NULL,
  payload jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS workspace_leases_subject_state
  ON lunanexa.workspace_leases(subject_ref, state, expires_unix_ms);

INSERT INTO lunanexa.schema_migrations(version) VALUES (1)
ON CONFLICT (version) DO NOTHING;

COMMIT;
