///|
priv struct NodeOwnershipRead {
  node_id : String
  tenant_ref : String
  organization_id : String
  display_name : String
} derive(FromJson)

///|
fn node_ownership_labels(
  rows : Array[NodeOwnershipRead],
) -> Map[String, String] {
  let owners : Map[String, String] = Map([])
  let identities : Map[String, String] = Map([])
  for row in rows {
    if row.tenant_ref == "" {
      continue
    }
    let identity = row.tenant_ref + "/" + row.organization_id
    if identities.get(row.node_id) is Some(previous) && previous != identity {
      owners[row.node_id] = "Conflicting allocations / 分配冲突"
    } else if !owners
      .get(row.node_id)
      .map_or(false, value => value.has_prefix("Conflicting")) {
      identities[row.node_id] = identity
      owners[row.node_id] = row.display_name
    }
  }
  owners
}

///|
async fn load_node_ownership(
  endpoint : String,
  token : String,
) -> Map[String, String] {
  let rows : Array[NodeOwnershipRead] = @json.from_json(
    parse_console_json(
      request("POST", endpoint, "/v1/operator/node-ownership", token, body="{}"),
    ),
  )
  node_ownership_labels(rows)
}
