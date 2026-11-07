///|
/// Commit only an inference observation and its optional charge to the existing
/// snapshot. Retained after the 2026-10-23 A/B/A comparison reduced mean stream
/// tail versus full-snapshot writes; this is not a guarantee against long tails.
/// Its durable shape is unchanged, so older readers and ordinary
/// full-snapshot writes remain compatible. The caller holds the commercial
/// store mutex. Both records commit atomically before the stream is completed.
pub async fn PostgresDatabase::commit_inference_usage(
  self : PostgresDatabase,
  version : String,
  observation : String,
  entry : String?,
) -> Unit {
  guard (@json.parse(observation) catch { _ => Json::null() })
    is { "event_id": String(event_id), .. } &&
    event_id != "" else {
    raise QueryFailed("invalid inference observation")
  }
  if entry is Some(value) {
    guard (@json.parse(value) catch { _ => Json::null() })
      is { "entry_id": String(id), "source_event_id": String(source), .. } &&
      id != "" &&
      source == event_id else {
      raise QueryFailed("invalid inference charge")
    }
  }
  let connection = self.begin_operation()
  defer connection.release()
  let result = run(
    connection,
    (
      #|WITH current AS MATERIALIZED (
      #|  SELECT payload FROM lunanexa.snapshots
      #|  WHERE domain = 'commercial' AND schema_version = $1 FOR UPDATE
      #|), parts AS (
      #|  SELECT payload,
      #|    payload #> '{commercial,usage_observations}' AS observations,
      #|    payload #> '{commercial,ledger_entries}' AS entries
      #|  FROM current
      #|), checked AS (
      #|  SELECT * FROM parts
      #|  WHERE jsonb_typeof(observations) = 'array' AND jsonb_typeof(entries) = 'array'
      #|    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(observations) x
      #|      WHERE x->>'event_id' = $2::jsonb->>'event_id' AND x <> $2::jsonb)
      #|    AND ($3::jsonb IS NULL OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(entries) x
      #|      WHERE (x->>'entry_id' = $3::jsonb->>'entry_id'
      #|        OR x->>'source_event_id' = $2::jsonb->>'event_id') AND x <> $3::jsonb))
      #|)
      #|UPDATE lunanexa.snapshots s SET
      #|  payload = jsonb_set(jsonb_set(c.payload, '{commercial,usage_observations}',
      #|    CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(c.observations) x
      #|      WHERE x->>'event_id' = $2::jsonb->>'event_id') THEN c.observations
      #|      ELSE c.observations || jsonb_build_array($2::jsonb) END),
      #|    '{commercial,ledger_entries}',
      #|    CASE WHEN $3::jsonb IS NULL OR EXISTS (SELECT 1 FROM jsonb_array_elements(c.entries) x
      #|      WHERE x->>'entry_id' = $3::jsonb->>'entry_id') THEN c.entries
      #|      ELSE c.entries || jsonb_build_array($3::jsonb) END),
      #|  revision = s.revision + 1, updated_at = now()
      #|FROM checked c WHERE s.domain = 'commercial' RETURNING s.revision
    ),
    parameters=[Some(version), Some(observation), entry],
  )
  if result.row_count() != 1 {
    raise QueryFailed(
      "commercial snapshot unavailable or inference replay conflicts",
    )
  }
}
