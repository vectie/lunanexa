///|
let artifact_route_prefix : String = "/v1/artifacts/"

///|
fn safe_artifact_key(value : String) -> Bool {
  value != "" &&
  value.length() <= 2048 &&
  !value.has_prefix("/") &&
  !value.has_suffix("/") &&
  !value.contains("..") &&
  !value.contains("//") &&
  !value.contains_char('\n') &&
  !value.contains_char('\r') &&
  !value.contains_char('?') &&
  !value.contains_char('#') &&
  !value.contains_char('%') &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == '/'
  })
}

///|
fn artifact_key(uri : String) -> String? {
  guard uri.has_prefix("s3://") else { return None }
  let key = uri[5:].to_owned()
  if safe_artifact_key(key) && key.contains_char('/') {
    Some(key)
  } else {
    None
  }
}

///|
fn assignment_signature_key(
  assignment : @contracts.DesiredAssignment,
) -> String? {
  if assignment.artifact.signature_ref.has_prefix("s3://") {
    artifact_key(assignment.artifact.signature_ref)
  } else if @contracts.valid_identifier(
      assignment.artifact.signature_ref,
      maximum_length=256,
    ) {
    artifact_key("\{assignment.artifact.uri}.sig")
  } else {
    None
  }
}

///|
fn range_start(headers : Map[String, String], size : Int64) -> Int64? {
  match header(headers, "range") {
    None => Some(0L)
    Some(value) => {
      if !value.has_prefix("bytes=") || !value.has_suffix("-") {
        return None
      }
      let raw = value["bytes=".length():value.length() - 1].to_owned()
      let parsed = @string.parse_int64(raw) catch { _ => return None }
      if parsed < 0L || parsed >= size {
        None
      } else {
        Some(parsed)
      }
    }
  }
}

///|
async fn ApiService::artifact_assignment(
  self : ApiService,
  headers : Map[String, String],
  key : String,
  now_unix_ms : Int64,
) -> @contracts.DesiredAssignment? {
  guard header(headers, "x-lunanexa-node-id") is Some(node_id) &&
    header(headers, "x-lunanexa-assignment-id") is Some(assignment_id) &&
    header(headers, "x-lunanexa-deployment-id") is Some(deployment_id) &&
    header(headers, "x-lunanexa-model-digest") is Some(model_digest) &&
    self.node_authorized(headers, node_id) &&
    self.store.assignment(assignment_id) is Some(assignment) else {
    return None
  }
  if assignment.node_id != node_id ||
    assignment.deployment_id != deployment_id ||
    assignment.artifact.digest != model_digest ||
    assignment.lease_expires_unix_ms <= now_unix_ms ||
    assignment.controller_epoch != self.store.controller_epoch() ||
    assignment.signature == "" ||
    assignment.signature !=
    @node.assignment_signature(assignment, self.assignment_signing_secret) {
    return None
  }
  let model_key = artifact_key(assignment.artifact.uri)
  let signature_key = assignment_signature_key(assignment)
  if model_key != Some(key) && signature_key != Some(key) {
    None
  } else {
    Some(assignment)
  }
}

///|
async fn ApiService::consume_artifact_grant(
  self : ApiService,
  assignment : @contracts.DesiredAssignment,
  key : String,
  now_unix_ms : Int64,
) -> String? {
  guard self.technical_store is Some(store) else { return None }
  let identity = digest_hex(
    "artifact|\{assignment.assignment_id}|\{assignment.generation}|\{key}|\{now_unix_ms}",
  )
  let grant : @technical.TransferGrant = {
    grant_id: "artifact-\{identity[:32]}",
    nonce: identity,
    node_id: assignment.node_id,
    deployment_id: assignment.deployment_id,
    model_digest: assignment.artifact.digest,
    scope: ModelRead,
    issued_unix_ms: now_unix_ms,
    expires_unix_ms: now_unix_ms + 300000L,
  }
  let requested : @technical.TransferGrantUse = {
    node_id: assignment.node_id,
    deployment_id: assignment.deployment_id,
    model_digest: assignment.artifact.digest,
    scope: ModelRead,
  }
  match
    store.validate_and_consume_transfer(
      grant,
      requested,
      Verified,
      now_unix_ms,
      300000L,
    ) {
    Accepted(_) => Some(grant.grant_id)
    Rejected(_) => None
  }
}

///|
async fn send_artifact_error(
  connection : @http.ServerConnection,
  status : Int,
  message : String,
) -> Unit {
  let reply = api_error(status, "ArtifactDenied", message, false)
  connection.send_response(reply.status, reason(reply.status), extra_headers={
    "Content-Type": reply.content_type,
    "Cache-Control": "no-store",
  })
  connection.write_string(reply.body)
  connection.end_response()
}

///|
async fn ApiService::serve_artifact(
  self : ApiService,
  request : @http.Request,
  connection : @http.ServerConnection,
) -> Bool {
  if !request.path.has_prefix(artifact_route_prefix) {
    return false
  }
  if request.meth != Get {
    send_artifact_error(connection, 405, "artifact downloads require GET")
    return true
  }
  guard self.artifact_root is Some(root) &&
    root.has_prefix("/") &&
    !root.contains("..") else {
    send_artifact_error(
      connection, 503, "management-node artifact storage is unavailable",
    )
    return true
  }
  let key = request.path[artifact_route_prefix.length():].to_owned()
  if !safe_artifact_key(key) {
    send_artifact_error(connection, 404, "artifact was not found")
    return true
  }
  let now = @async.now()
  guard self.artifact_assignment(request.headers, key, now) is Some(assignment) &&
    self.consume_artifact_grant(assignment, key, now) is Some(grant_id) else {
    send_artifact_error(
      connection, 401, "a live node-bound assignment and transfer grant are required",
    )
    return true
  }
  let path = "\{root}/\{key}"
  if !@fs.exists(path) {
    send_artifact_error(connection, 404, "artifact was not found")
    return true
  }
  let file = try @fs.open(path, mode=ReadOnly) catch {
    _ => {
      send_artifact_error(connection, 404, "artifact was not found")
      return true
    }
  } noraise {
    opened => opened
  }
  defer file.close()
  let size = try file.size() catch {
    _ => {
      send_artifact_error(connection, 503, "artifact metadata is unavailable")
      return true
    }
  } noraise {
    value => value
  }
  guard size > 0L && range_start(request.headers, size) is Some(start) else {
    send_artifact_error(connection, 416, "artifact range is invalid")
    return true
  }
  let remaining = size - start
  let status = if start == 0L { 200 } else { 206 }
  let headers : Map[String, String] = {
    "Content-Type": "application/octet-stream",
    "Content-Length": remaining.to_string(),
    "Accept-Ranges": "bytes",
    "Cache-Control": "private, no-store",
    "X-LunaNexa-Transfer-Grant": grant_id,
  }
  if start > 0L {
    headers["Content-Range"] = "bytes \{start}-\{size - 1L}/\{size}"
  }
  connection.send_response(status, reason(status), extra_headers=headers)
  for position = start; position < size; {
    let count = (size - position).min(1048576L).to_int()
    let bytes = file.read_exactly_at(count, position~)
    connection.write(bytes)
    continue position + Int64::from_int(count)
  }
  connection.end_response()
  self.operator_audit("artifact.transfer", assignment.assignment_id, grant_id)
  true
}
