-- PostgreSQL 14+ with LZ4 support (the production PostgreSQL 16 image includes it).
-- Only the compression policy changes. Existing values remain readable and are
-- recompressed on their next ordinary write; no payload or receipt is removed.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE lunanexa.snapshots ALTER COLUMN payload SET COMPRESSION lz4;
INSERT INTO lunanexa.schema_migrations(version) VALUES (6)
ON CONFLICT (version) DO NOTHING;
COMMIT;
