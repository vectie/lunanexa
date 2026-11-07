BEGIN;
CREATE TABLE IF NOT EXISTS lunanexa.control_workload_commits (
  audit_sequence bigint PRIMARY KEY CHECK (audit_sequence > 0),
  workload_id text NOT NULL,
  record jsonb NOT NULL,
  audit jsonb NOT NULL
);
INSERT INTO lunanexa.schema_migrations(version) VALUES (7)
ON CONFLICT (version) DO NOTHING;
COMMIT;
