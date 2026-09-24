///|
async fn limited(reader : &@io.Reader, limit : Int) -> Bytes {
  let buffer = Buffer()
  let mut size = 0
  while reader.read_some(max_len=8192) is Some(bytes) {
    size += bytes.length()
    if size > limit {
      raise HostError::ControllerRejected
    }
    buffer.write_bytes(bytes)
  }
  buffer.to_bytes()
}

///|
priv struct Redeemed {
  delivery_id : String?
  client_id : String
  api_secret : String
  api_base_url : String
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
  allowed_models : Array[String]
  expires_unix_ms : Int64
  one_time : Bool
} derive(FromJson)

///|
async fn controller_client(origin : String) -> @http.Client {
  match @env.get_env_var("SSL_CERT_FILE") {
    Some(path) if path != "" => @http.Client(origin, trust=CustomPemFile(path))
    _ => @http.Client(origin)
  }
}

///|
pub async fn WorkspaceHost::redeem(
  self : WorkspaceHost,
  client_id : String,
  code : String,
) -> @webide.Grant {
  @async.with_timeout(10000, () => {
    let client = controller_client(self.config.controller_origin)
    defer client.close()
    let body : Json = { "client_id": client_id, "handoff_code": code }
    let response = client.post("/v1/client-handoffs:redeem", body, extra_headers={
      "content-type": "application/json",
    })
    if response.code != 200 {
      raise HostError::ControllerRejected
    }
    let result : Redeemed = @json.from_json(
      @json.parse(@utf8.decode(limited(client, 32768))),
    )
    // The provider route is deployment-owned at both ends. A stale catalog must
    // not silently send a credential to another origin or bypass its gateway.
    if result.client_id != client_id ||
      !result.one_time ||
      result.api_base_url !=
      self.config.public_api_base_url.unwrap_or(
        self.config.model_gateway_origin + "/v1",
      ) {
      raise HostError::ControllerRejected
    }
    let grant : @webide.Grant = {
      delivery_id: result.delivery_id,
      client_id: result.client_id,
      api_secret: result.api_secret,
      tenant_ref: result.tenant_ref,
      subject_ref: result.subject_ref,
      organization_id: result.organization_id,
      project_id: result.project_id,
      allowed_models: result.allowed_models,
      expires_unix_ms: result.expires_unix_ms,
    }
    if self.require_exclusive {
      if grant.delivery_id is None {
        raise HostError::ControllerRejected
      }
      guard self.delivery_placement(grant) is Some((_, expiry)) else {
        raise HostError::ControllerRejected
      }
      {
        ..grant,
        expires_unix_ms: if grant.expires_unix_ms < expiry {
          grant.expires_unix_ms
        } else {
          expiry
        },
      }
    } else {
      grant
    }
  })
}

///|
async fn authorize_grant(
  controller_origin : String,
  grant : @webide.Grant,
) -> Bool {
  if grant.expires_unix_ms <= @async.now() {
    return false
  }
  @async.with_timeout(5000, () => {
    let client = controller_client(controller_origin)
    defer client.close()
    let response = client.get("/v1/models", extra_headers={
      "authorization": "Bearer " + grant.api_secret,
    })
    ignore(limited(client, 1048576))
    match response.code {
      200 => true
      401 | 403 => false
      _ => raise @webide.BridgeError::AuthorityUnavailable
    }
  }) catch {
    // An unavailable authority is not evidence of revocation. Callers still
    // deny this request, but retain the session and do not destroy live work.
    _ => raise @webide.BridgeError::AuthorityUnavailable
  }
}

///|
pub async fn WorkspaceHost::authorize(
  self : WorkspaceHost,
  grant : @webide.Grant,
) -> Bool {
  if !authorize_grant(self.config.controller_origin, grant) {
    return false
  }
  !self.require_exclusive || self.delivery_placement(grant) is Some(_)
}
