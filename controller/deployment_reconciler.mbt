///|
/// Expands one persisted executable operation into controller-owned unsigned
/// desired assignments. The API signs and commits the returned assignments
/// through the ordinary audited southbound path.
pub fn deployment_assignments(
  operation : @deployment.DeploymentOperation,
  controller_epoch : Int64,
  now_unix_ms : Int64,
) -> Array[@contracts.DesiredAssignment] raise @deployment.DeploymentError {
  @deployment.desired_assignments(
    operation.plan,
    controller_epoch,
    operation.generation,
    now_unix_ms,
  )
}

///|
/// A group is admitted only when the members that report for this operation
/// cover every rank of the group exactly once. A pair missing a rank, or where
/// two members claim the same rank, is not a complete instance: the deployment
/// is not ready, and nothing is promoted on half a tensor-parallel group.
fn group_complete(
  operation : @deployment.DeploymentOperation,
  assignments : Array[@contracts.DesiredAssignment],
) -> Bool {
  let live = assignments.filter(assignment => {
    operation.assignment_ids.contains(assignment.assignment_id)
  })
  let group_ids : Array[String] = []
  for assignment in live {
    if assignment.group is Some(group) && !group_ids.contains(group.group_id) {
      group_ids.push(group.group_id)
    }
  }
  group_ids.all(group_id => {
    let members = live.filter(assignment => {
      assignment.group is Some(group) && group.group_id == group_id
    })
    let world_size = match members.get(0) {
      Some(ranked) => ranked.group.unwrap().world_size
      None => 0
    }
    world_size == @contracts.cx7_pair_member_count &&
    members.length() == world_size &&
    [
      for rank in 0..<world_size => {
        members.any(ranked => ranked.group.unwrap().rank == rank)
      }
    ].all(present => present)
  })
}

///|
pub fn deployment_operation_ready(
  operation : @deployment.DeploymentOperation,
  assignments : Array[@contracts.DesiredAssignment],
  heartbeats : Array[@contracts.NodeHeartbeat],
  now_unix_ms : Int64,
  heartbeat_timeout_ms? : Int64 = 15000L,
) -> Bool {
  group_complete(operation, assignments) &&
  operation.assignment_ids.length() > 0 &&
  operation.assignment_ids.all(assignment_id => {
    assignments.any(assignment => {
      assignment.assignment_id == assignment_id &&
      assignment.generation == operation.generation &&
      assignment.deployment_id == operation.deployment_id &&
      assignment.signature != "" &&
      assignment.lease_expires_unix_ms > now_unix_ms &&
      heartbeats.any(heartbeat => {
        heartbeat.node_id == assignment.node_id &&
        heartbeat.inventory.node_id == assignment.node_id &&
        heartbeat.state == Active &&
        heartbeat.controller_epoch == assignment.controller_epoch &&
        heartbeat.observed_generation >= assignment.generation &&
        now_unix_ms - heartbeat.timestamp_unix_ms <= heartbeat_timeout_ms &&
        heartbeat.running_deployments.any(value => {
          value == operation.deployment_id
        })
      })
    })
  })
}

///|
pub fn deployment_assignment_owned(
  deployment_id : String,
  assignment : @contracts.DesiredAssignment,
) -> Bool {
  assignment.deployment_id == deployment_id
}
