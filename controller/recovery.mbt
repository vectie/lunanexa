///|
pub(all) enum RecoveryAction {
  StartMissing(String)
  StopOrphan(String)
  ExpireLease(String)
  MarkNodeUnreachable(String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RecoveryPlan {
  controller_epoch : Int64
  actions : Array[RecoveryAction]
} derive(Debug, Eq, ToJson, FromJson)

///|
fn has_id(values : Array[String], expected : String) -> Bool {
  values.any(value => value == expected)
}

///|
pub fn recovery_plan(
  controller_epoch : Int64,
  desired : Array[@contracts.DesiredAssignment],
  observed_runtime_ids : Array[String],
  now_unix_ms : Int64,
) -> RecoveryPlan {
  let actions : Array[RecoveryAction] = []
  for assignment in desired {
    if assignment.lease_expires_unix_ms <= now_unix_ms {
      actions.push(ExpireLease(assignment.assignment_id))
    } else if !has_id(observed_runtime_ids, assignment.assignment_id) {
      actions.push(StartMissing(assignment.assignment_id))
    }
  }
  for runtime_id in observed_runtime_ids {
    if !desired.any(assignment => assignment.assignment_id == runtime_id) {
      actions.push(StopOrphan(runtime_id))
    }
  }
  { controller_epoch, actions }
}

///|
pub fn node_unreachable(
  last_heartbeat_unix_ms : Int64,
  now_unix_ms : Int64,
  timeout_ms : Int64,
) -> Bool {
  now_unix_ms - last_heartbeat_unix_ms > timeout_ms
}
