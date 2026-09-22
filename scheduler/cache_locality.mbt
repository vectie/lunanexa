///|
/// Only attested, fresh, active members of the existing reservation can gain
/// locality preference. Eligibility and resource budgets remain planner checks.
pub fn cached_reserved_nodes(
  heartbeats : Array[@contracts.NodeHeartbeat],
  reserved_node_ids : Array[String],
  artifact_digest : String,
  now_unix_ms : Int64,
  heartbeat_timeout_ms : Int64,
) -> Array[String] {
  if !@contracts.valid_sha256_digest(artifact_digest) {
    return []
  }
  let selected : Array[String] = []
  for heartbeat in heartbeats {
    if !reserved_node_ids.contains(heartbeat.node_id) ||
      heartbeat.state != Active ||
      heartbeat.timestamp_unix_ms > now_unix_ms ||
      now_unix_ms - heartbeat.timestamp_unix_ms > heartbeat_timeout_ms {
      continue
    }
    guard heartbeat.inventory.labels.get(
        "lunanexa.io/verified-artifact-digests",
      )
      is Some(raw) &&
      raw.length() <= 8192 else {
      continue
    }
    let digests : Array[String] = try @json.from_json(@json.parse(raw)) catch {
      _ => continue
    } noraise {
      value => value
    }
    if digests.length() <= 64 &&
      digests.all(value => @contracts.valid_sha256_digest(value)) &&
      digests.contains(artifact_digest) &&
      !selected.contains(heartbeat.node_id) {
      selected.push(heartbeat.node_id)
    }
  }
  selected.sort()
  selected
}
