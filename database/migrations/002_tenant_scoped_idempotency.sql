BEGIN;

ALTER TABLE lunanexa.portal_lease_requests
  DROP CONSTRAINT IF EXISTS portal_lease_requests_idempotency_key_key;

CREATE UNIQUE INDEX IF NOT EXISTS portal_lease_requests_scoped_idempotency
  ON lunanexa.portal_lease_requests(tenant_ref, subject_ref, idempotency_key);

INSERT INTO lunanexa.schema_migrations(version) VALUES (2)
ON CONFLICT (version) DO NOTHING;

COMMIT;
