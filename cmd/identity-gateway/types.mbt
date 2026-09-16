///|
const MaximumRequestBytes : Int = 1048576

///|
const FlowLifetimeMs : Int64 = 600000L

///|
priv enum GatewayMode {
  Proxy
  Relay
} derive(Eq)

///|
priv enum BrowserAudience {
  Operator
  Enterprise
} derive(Eq)

///|
fn BrowserAudience::name(self : BrowserAudience) -> String {
  match self {
    Operator => "operator"
    Enterprise => "enterprise"
  }
}

///|
priv struct GatewayConfig {
  mode : GatewayMode
  listen_address : String
  issuer : String
  oidc_transport_origin : String?
  oidc_ca_file : String?
  operator_host : String
  enterprise_host : String
  operator_redirect_uri : String
  enterprise_redirect_uri : String
  operator_client_id : String
  enterprise_client_id : String
  operator_client_secret : String
  enterprise_client_secret : String
  operator_cookie_name : String
  enterprise_cookie_name : String
  operator_cookie_secret : String
  enterprise_cookie_secret : String
  assertion_secret : String
  database_url : String
  relay_endpoint : String
  control_endpoint : String
  operator_upstream : String
  enterprise_upstream : String
  session_idle_ms : Int64
  session_absolute_ms : Int64
  assertion_lifetime_ms : Int64
}

///|
priv struct GatewayCookie {
  kind : String
  audience : String
  host : String
  state : String
  nonce : String
  verifier : String
  issuer : String
  subject : String
  email : String
  display_name : String
  bearer : String
  csrf : String
  created_unix_ms : Int64
  last_used_unix_ms : Int64
  expires_unix_ms : Int64
} derive(ToJson, FromJson)

///|
extend GatewayCookie with ToJson::{to_json}

///|
priv struct OidcDiscovery {
  issuer : String
  authorization_endpoint : String
  token_endpoint : String
  userinfo_endpoint : String
  introspection_endpoint : String?
} derive(FromJson)

///|
priv struct OidcTokenResponse {
  access_token : String
  id_token : String
  token_type : String
} derive(FromJson)

///|
priv struct IdTokenClaims {
  iss : String
  sub : String
  aud : Json
  azp : String?
  exp : Int
  nbf : Int?
  iat : Int?
  nonce : String
} derive(FromJson)

///|
priv struct UserInfo {
  sub : String
  email : String?
  name : String?
  preferred_username : String?
} derive(FromJson)

///|
priv struct Introspection {
  active : Bool
  sub : String?
  client_id : String?
  azp : String?
  exp : Int?
} derive(FromJson)

///|
priv struct ControllerSessionView {
  expires_unix_ms : Int64
} derive(FromJson)

///|
priv struct IssuedControllerSession {
  session : ControllerSessionView
  secret : String
} derive(FromJson)

///|
priv struct RegisteredControllerSession {
  session : IssuedControllerSession
} derive(FromJson)
