///|
priv struct GuideCount {
  code : String
  count : Int
} derive(ToJson)

///|
priv struct GuideAlertAggregate {
  total : Int
  critical : Int
  by_code : Array[GuideCount]
} derive(ToJson)

///|
priv struct GuideResourceAggregate {
  total : Int
  truncated : Bool
  by_state : Array[GuideCount]
} derive(ToJson)

///|
priv struct GuideControllerAggregate {
  contract_version : String
  generated_unix_ms : Int64
  health : String
  alerts : GuideAlertAggregate
  nodes : GuideResourceAggregate
  exclusive_leases : GuideResourceAggregate
  reconciliation_pending_actions : Int
} derive(ToJson)

///|
extend GuideControllerAggregate with ToJson::{to_json}

///|
fn bounded_counts(values : Array[String]) -> Array[GuideCount] {
  let counts : Map[String, Int] = Map([])
  for value in values[:values.length().min(10000)] {
    let safe = if @contracts.valid_identifier(value, maximum_length=80) {
      value
    } else {
      "Unknown"
    }
    counts[safe] = counts.get(safe).unwrap_or(0) + 1
  }
  let result = [
    for entry in counts => GuideCount::{ code: entry.0, count: entry.1 }
  ]
  result.sort_by_key(value => value.code)
  result[:result.length().min(128)].to_owned()
}

///|
fn guide_node_state(state : @contracts.NodeState) -> String {
  match state {
    Enrolling => "Enrolling"
    Active => "Active"
    Cordoned => "Cordoned"
    Draining => "Draining"
    Unreachable => "Unreachable"
    Retired => "Retired"
  }
}

///|
fn guide_lease_state(state : @nodelease.ExclusiveLeaseState) -> String {
  match state {
    Requested => "Requested"
    Reserved => "Reserved"
    Provisioning => "Provisioning"
    Active => "Active"
    Expiring => "Expiring"
    Draining => "Draining"
    RevokingAccess => "RevokingAccess"
    Sanitizing => "Sanitizing"
    Completed => "Completed"
    Cancelled => "Cancelled"
    Quarantined => "Quarantined"
  }
}

///|
async fn ApiService::handle_guide_aggregate(
  self : ApiService,
  verb : ApiMethod,
  headers : Map[String, String],
) -> HttpReply {
  if verb != Get {
    return api_error(
      405, "MethodNotAllowed", "guide diagnostics require GET", false,
    )
  }
  if !bearer_authorized(headers, self.guide_diagnostics_token) {
    return api_error(
      401, "Unauthenticated", "guide diagnostics authority is required", false,
    )
  }
  let now = @async.now()
  let heartbeats = self.store.heartbeats()
  let node_states = [
    for heartbeat in heartbeats => guide_node_state(heartbeat.state)
  ]
  let leases = match self.exclusive_lease_store {
    Some(store) => store.leases()
    None => []
  }
  let lease_states = [ for lease in leases => guide_lease_state(lease.state) ]
  let alerts = match self.notification_store {
    Some(store) => store.records_for_operators(now)
    None => []
  }
  let active_alerts = alerts.filter(record => record.lifecycle != Resolved)
  let alert_codes = [ for record in active_alerts => record.event.code ]
  let critical = active_alerts.count_if(record => {
    record.event.severity == Critical
  })
  let pending_assignments = self.store
    .assignments()
    .count_if(assignment => {
      !heartbeats.any(heartbeat => {
        heartbeat.running_deployments.contains(assignment.deployment_id)
      })
    })
  let unreachable_count = heartbeats.count_if(heartbeat => {
    @controller.node_unreachable(
      heartbeat.timestamp_unix_ms,
      now,
      self.global_settings.control_timing.heartbeat_timeout_ms,
    )
  })
  let result : GuideControllerAggregate = {
    contract_version: "lunanexa.guide-controller-aggregate.v1",
    generated_unix_ms: now,
    health: if !self.store.current_epoch_is_durable() {
      "fenced"
    } else if self.exclusive_lease_store is None ||
      self.notification_store is None {
      "degraded"
    } else {
      "healthy"
    },
    alerts: {
      total: active_alerts.length().min(10000),
      critical: critical.min(10000),
      by_code: bounded_counts(alert_codes),
    },
    nodes: {
      total: heartbeats.length().min(10000),
      truncated: heartbeats.length() > 10000,
      by_state: bounded_counts(node_states),
    },
    exclusive_leases: {
      total: leases.length().min(10000),
      truncated: leases.length() > 10000,
      by_state: bounded_counts(lease_states),
    },
    reconciliation_pending_actions: (pending_assignments + unreachable_count).min(
      10000,
    ),
  }
  self.operator_audit(
    "guide-diagnostics.aggregate-read",
    "guide-controller-aggregate",
    "guide-diagnostics:\{now}",
  )
  json_reply(200, result.to_json())
}
