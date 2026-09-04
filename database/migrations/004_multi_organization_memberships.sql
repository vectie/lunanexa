BEGIN;

DROP INDEX IF EXISTS lunanexa.enterprise_memberships_active_subject;

CREATE UNIQUE INDEX IF NOT EXISTS enterprise_memberships_active_subject_organization
  ON lunanexa.enterprise_memberships(subject_ref, organization_id) WHERE active;

INSERT INTO lunanexa.schema_migrations(version) VALUES (4)
ON CONFLICT (version) DO NOTHING;

COMMIT;
