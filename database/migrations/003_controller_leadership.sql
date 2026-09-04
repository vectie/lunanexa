BEGIN;

CREATE TABLE IF NOT EXISTS lunanexa.controller_leadership (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  fencing_token bigint NOT NULL CHECK (fencing_token > 0),
  holder_id text NOT NULL CHECK (length(holder_id) BETWEEN 1 AND 256),
  backend_pid integer NOT NULL CHECK (backend_pid > 0),
  acquired_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO lunanexa.schema_migrations(version) VALUES (3)
ON CONFLICT (version) DO NOTHING;

COMMIT;
