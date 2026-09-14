///|
/// Server-owned policy. The public origin is never inferred from forwarded
/// headers. Bind the listener behind a TLS ingress, or to loopback for testing.
pub(all) struct BridgeConfig {
  client_id : String
  public_origin : String
  maximum_sessions : Int
  maximum_request_bytes : Int
  maximum_socket_message_bytes : Int
  request_timeout_ms : Int
  authorization_interval_ms : Int
} derive(Debug, Eq)

///|
/// A secret-bearing result from the configured controller, never from a browser.
/// Intentionally has no Debug/ToJson derivation.
pub(all) struct Grant {
  client_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
  api_secret : String
  allowed_models : Array[String]
  expires_unix_ms : Int64
}

///|
/// The provisioner must return only an isolated, operator-owned workspace.
pub(all) struct Backend {
  http_url : String
  websocket_url : String
}

///|
pub(all) suberror BridgeError {
  InvalidConfiguration
  InvalidGrant
  Unauthorized
  RequestTooLarge
  CapacityExceeded
  UpstreamUnavailable
} derive(Debug, Eq)

///|
struct Session {
  grant : Grant
  backend : Backend
}

///|
pub struct Bridge {
  config : BridgeConfig
  redeem : async (String) -> Grant
  authorize : async (Grant) -> Bool
  provision : async (String, Grant) -> Backend
  sessions : Map[String, Session]
  challenges : Map[String, Int64]
  mutex : @async.Mutex
}
