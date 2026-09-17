///|
async fn WorkspaceHost::kubernetes(
  self : WorkspaceHost,
  verb : @http.RequestMethod,
  path : String,
  body : Json?,
) -> (Int, Json) {
  match self.kubernetes_override {
    Some(transport) => return transport(verb, path, body)
    None => ()
  }
  @async.with_timeout(10000, () => {
    let token_file = @fs.open(self.config.kubernetes_token_file, mode=ReadOnly)
    defer token_file.close()
    let token = @utf8.decode(limited(token_file, 16384)).trim().to_owned()
    if token.length() < 32 || !token.all(c => c >= '!' && c <= '~') {
      raise HostError::InvalidConfiguration
    }
    let client = @http.Client(
      self.config.kubernetes_origin,
      trust=CustomPemFile(self.config.kubernetes_ca_file),
    )
    defer client.close()
    client.request(verb, path, extra_headers={
      "authorization": "Bearer " + token,
      "content-type": if verb == Patch {
        "application/apply-patch+yaml"
      } else {
        "application/json"
      },
    })
    match body {
      Some(value) => client.write(value)
      None => ()
    }
    let response = client.end_request()
    let bytes = limited(client, 4194304)
    // Kubernetes errors can contain a submitted Secret. Do not include their
    // content in an exception or a browser readiness response.
    if response.code < 200 || response.code >= 300 {
      raise HostError::WorkspaceUnavailable
    }
    (response.code, @json.parse(@utf8.decode(bytes)))
  })
}

///|
pub async fn WorkspaceHost::provision(
  self : WorkspaceHost,
  id : String,
  grant : @webide.Grant,
) -> @webide.Backend {
  if id != @webide.workspace_id(grant) || !self.authorize(grant) {
    raise HostError::ControllerRejected
  }
  let name = resource_name(id)
  {
    let lock = self.workspace_lock(name)
    lock.acquire()
    defer lock.release()
    if !self.authorize(grant) {
      raise HostError::ControllerRejected
    }
    // Recreate controls rollouts, not a rapid scale-to-zero/scale-up cycle.
    // Do not start a replacement while a prior writer is still terminating.
    let stopped = self.workspace_scaled_down(name)
    self.wait_for_workspace_pods(name, terminating_only=!stopped)
    for entry in self.resources(id, grant) {
      let (path, resource) = entry
      ignore(
        self.kubernetes(
          Patch,
          path + "?fieldManager=lunanexa-webide&force=false",
          Some(resource),
        ),
      )
    }
  }
  // Do not invent readiness from successful resource creation. The user's
  // launch finishes only once a real ready replica is reported.
  @async.with_timeout(240000, () => {
    while true {
      let (_, deployment) = self.kubernetes(
        Get,
        "/apis/apps/v1/namespaces/\{self.config.namespace_name}/deployments/\{name}",
        None,
      )
      if deployment
        is {
          "metadata": { "generation": Number(generation, ..), .. },
          "spec": { "replicas": Number(desired, ..), .. },
          "status": {
            "availableReplicas": Number(available, ..),
            "updatedReplicas": Number(updated, ..),
            "observedGeneration": Number(observed, ..),
            ..
          },
          ..
        } &&
        available == 1.0 &&
        updated == 1.0 &&
        desired == 1.0 &&
        observed >= generation {
        break
      }
      if grant.expires_unix_ms <= @async.now() {
        raise HostError::ControllerRejected
      }
      @async.sleep(2000)
    }
  })
  if !self.authorize(grant) {
    raise HostError::ControllerRejected
  }
  let hostname = "\{name}.\{self.config.namespace_name}.svc.cluster.local:8188"
  { http_url: "http://\{hostname}", websocket_url: "ws://\{hostname}", }
}

///|
/// Restore lease enforcement after a gateway restart. Stop expired/revoked
/// workspaces without deleting customer volumes. A fresh launch reapplies the
/// desired replica and credential; retries never allocate another PVC.
pub async fn WorkspaceHost::reconcile(self : WorkspaceHost) -> Unit {
  let (_, response) = self.kubernetes(
    Get,
    "/api/v1/namespaces/\{self.config.namespace_name}/secrets?labelSelector=app.kubernetes.io%2Fmanaged-by%3Dlunanexa-webide&limit=500",
    None,
  )
  // Pagination is explicit: a bounded scan must not pretend it inspected more
  // workspaces than the API actually returned.
  self.reconcile_page(response)
  let mut page = response
  while page is { "metadata": { "continue": String(cursor), .. }, .. } &&
        cursor != "" {
    let (_, next) = self.kubernetes(
      Get,
      "/api/v1/namespaces/\{self.config.namespace_name}/secrets?labelSelector=app.kubernetes.io%2Fmanaged-by%3Dlunanexa-webide&limit=500&continue=" +
      encode_query(cursor),
      None,
    )
    self.reconcile_page(next)
    page = next
  }
}

///|
fn encode_query(value : String) -> String {
  let buffer = StringBuilder()
  for byte in @utf8.encode(value) {
    let c = byte.to_int()
    if (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      c == 45 ||
      c == 46 ||
      c == 95 ||
      c == 126 {
      buffer.write_char(c.unsafe_to_char())
    } else {
      let hex = "0123456789ABCDEF"
      buffer.write_char('%')
      buffer.write_char(hex[c / 16].to_int().unsafe_to_char())
      buffer.write_char(hex[c % 16].to_int().unsafe_to_char())
    }
  }
  buffer.to_string()
}

///|
async fn WorkspaceHost::reconcile_page(
  self : WorkspaceHost,
  page : Json,
) -> Unit {
  guard page is { "items": Array(items), .. } else {
    raise HostError::WorkspaceUnavailable
  }
  for item in items {
    guard item is { "metadata": { "name": String(name), .. }, .. } &&
      name.has_prefix("webide-") &&
      dns_label(name) else {
      continue
    }
    let lock = self.workspace_lock(name)
    lock.acquire()
    defer lock.release()
    // Re-read under the same lock used by launch. A stale paginated list must
    // not stop a workspace whose lease credential was refreshed meanwhile.
    let (_, current) = self.kubernetes(
      Get,
      "/api/v1/namespaces/\{self.config.namespace_name}/secrets/\{name}",
      None,
    )
    let grant = try {
      guard current
        is { "data": { "model-proxy.json": String(encoded), .. }, .. } else {
        raise HostError::ControllerRejected
      }
      let config : ModelProxyConfig = @json.from_json(
        @json.parse(@utf8.decode(@base64.decode(encoded))),
      )
      Some(config.grant())
    } catch {
      _ => None
    }
    let active = try {
      match grant {
        Some(value) =>
          resource_name(@webide.workspace_id(value)) == name &&
          self.authorize(value)
        None => false
      }
    } catch {
      // Preserve this workspace on an inconclusive authority check. Continue
      // scanning so independently expired/revoked workspaces are still stopped.
      @webide.BridgeError::AuthorityUnavailable => continue
      error => raise error
    }
    if !active {
      self.scale_down(name)
    }
  }
}

///|
async fn WorkspaceHost::scale_down(self : WorkspaceHost, name : String) -> Unit {
  // Apply the scale subresource rather than replacing the full deployment.
  let scale : Json = {
    "apiVersion": "autoscaling/v1",
    "kind": "Scale",
    "metadata": { "name": name, "namespace": self.config.namespace_name },
    "spec": { "replicas": 0 },
  }
  ignore(
    self.kubernetes(
      Put,
      "/apis/apps/v1/namespaces/\{self.config.namespace_name}/deployments/\{name}/scale",
      Some(scale),
    ),
  )
  self.wait_for_workspace_pods(name, terminating_only=false)
}

///|
async fn WorkspaceHost::wait_for_workspace_pods(
  self : WorkspaceHost,
  name : String,
  terminating_only~ : Bool,
) -> Unit {
  @async.with_timeout(120000, () => {
    while true {
      let (_, response) = self.kubernetes(
        Get,
        "/api/v1/namespaces/\{self.config.namespace_name}/pods?labelSelector=lunanexa.io%2Fworkspace%3D\{name}",
        None,
      )
      guard response is { "items": Array(items), .. } else {
        raise HostError::WorkspaceUnavailable
      }
      if response is { "metadata": { "continue": String(cursor), .. }, .. } &&
        cursor != "" {
        raise HostError::WorkspaceUnavailable
      }
      let pending = items.any(pod => {
        !terminating_only ||
        pod is { "metadata": { "deletionTimestamp": String(_), .. }, .. }
      })
      if !pending {
        break
      }
      @async.sleep(250)
    }
  })
}

///|
async fn WorkspaceHost::workspace_scaled_down(
  self : WorkspaceHost,
  name : String,
) -> Bool {
  let (_, response) = self.kubernetes(
    Get,
    "/apis/apps/v1/namespaces/\{self.config.namespace_name}/deployments?labelSelector=lunanexa.io%2Fworkspace%3D\{name}",
    None,
  )
  guard response is { "items": Array(items), .. } else {
    raise HostError::WorkspaceUnavailable
  }
  if response is { "metadata": { "continue": String(cursor), .. }, .. } &&
    cursor != "" {
    raise HostError::WorkspaceUnavailable
  }
  match items {
    [] => false
    [
      {
        "metadata": { "name": String(found), .. },
        "spec": { "replicas": Number(count, ..), .. },
        ..
      },
    ] if found == name => {
      if count != 0.0 && count != 1.0 {
        raise HostError::WorkspaceUnavailable
      }
      count == 0.0
    }
    _ => raise HostError::WorkspaceUnavailable
  }
}
