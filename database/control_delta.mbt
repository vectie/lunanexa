///|
/// Commit only this workload/audit pair, without rewriting historical receipts.
/// The caller holds the control-store mutex and current controller leadership.
/// Recovery overlays this journal on the checkpoint. A later full control
/// snapshot atomically checkpoints and clears it. Acknowledgement still follows
/// the durable database write, never an in-memory/background-write promise.
pub async fn PostgresDatabase::commit_control_workload(
  self : PostgresDatabase,
  epoch : Int64,
  workload_id : String,
  record : String,
  audit : String,
) -> Unit {
  let connection = self.begin_operation()
  defer connection.release()
  let result = run(
    connection,
    (
      #|WITH current_epoch AS (
      #|  SELECT 1 FROM lunanexa.snapshots
      #|  WHERE domain = 'control' AND schema_version = 'lunanexa.store.v1'
      #|    AND (payload->>'controller_epoch')::bigint = $1::bigint
      #|  FOR UPDATE
      #|)
      #|INSERT INTO lunanexa.control_workload_commits(audit_sequence, workload_id, record, audit)
      #|SELECT ($4::jsonb->>'sequence')::bigint, $2, $3::jsonb, $4::jsonb FROM current_epoch
      #|RETURNING audit_sequence
    ),
    parameters=[
      Some(epoch.to_string()),
      Some(workload_id),
      Some(record),
      Some(audit),
    ],
  )
  if result.row_count() != 1 {
    raise QueryFailed(
      "control snapshot epoch changed or snapshot is unavailable",
    )
  }
}

///|
/// One statement reads a consistent checkpoint and journal, including a crash
/// immediately after a receipt commit and before the next ordinary checkpoint.
let control_snapshot_query : String =
  #|WITH commits AS MATERIALIZED (
  #|  SELECT * FROM lunanexa.control_workload_commits
  #|), latest AS (
  #|  SELECT DISTINCT ON (workload_id) workload_id, record, audit_sequence
  #|  FROM commits ORDER BY workload_id, audit_sequence DESC
  #|)
  #|SELECT schema_version,
  #|  CASE WHEN NOT EXISTS (SELECT 1 FROM commits) THEN payload
  #|  ELSE payload || jsonb_build_object(
  #|    'workload_results',
  #|      COALESCE((SELECT jsonb_agg(item) FROM jsonb_array_elements(payload->'workload_results') AS item
  #|        WHERE NOT EXISTS (SELECT 1 FROM latest WHERE workload_id = item->'response'->>'workload_id')), '[]'::jsonb)
  #|      || COALESCE((SELECT jsonb_agg(record ORDER BY audit_sequence) FROM latest), '[]'::jsonb),
  #|    'audits', (payload->'audits') || (SELECT jsonb_agg(audit ORDER BY audit_sequence) FROM commits)
  #|  ) END::text
  #|FROM lunanexa.snapshots WHERE domain = $1
