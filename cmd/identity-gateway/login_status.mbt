///|
priv struct LoginStatusUser {
  id : String
} derive(FromJson)

///|
async fn login_status_get(
  config : GatewayConfig,
  path : String,
  token : String,
) -> String {
  let (origin, path) = endpoint_origin_and_path(
    registration_endpoint(config, path),
    true,
  )
  let client = @http.Client(origin, trust=oidc_trust(config))
  defer client.close()
  let response = client.get(path, extra_headers={
    "Authorization": "Bearer \{token}",
    "Accept": "application/json",
  })
  let body = client.read_all().text()
  guard response.code == 200 else {
    raise Failure("login status is unavailable")
  }
  body
}

///|
fn login_status_locked(body : String) -> Bool raise {
  match @json.parse(body) {
    { "disabled": True, .. } => true
    { "disabled": False, .. } => false
    _ => raise Failure("invalid login status")
  }
}

///|
/// Keycloak 26 deliberately returns identical invalid_grant bodies for bad
/// passwords and brute-force lockout. Read its authoritative status instead of
/// guessing from a failure count. This path never clears failures or changes
/// passwords/roles. The admin credential remains server-side.
async fn password_account_locked(
  config : GatewayConfig,
  username : String,
) -> Bool {
  let realm = configured_realm(config.issuer)
  let token = registration_admin_token(config, realm)
  let users : Array[LoginStatusUser] = @json.from_json(
    @json.parse(
      login_status_get(
        config,
        "/admin/realms/\{realm}/users?username=\{form_encode(username)}&exact=true&max=2",
        token,
      ),
    ),
  )
  let users : Array[LoginStatusUser] = if users.is_empty() &&
    username.contains("@") {
    @json.from_json(
      @json.parse(
        login_status_get(
          config,
          "/admin/realms/\{realm}/users?email=\{form_encode(username)}&exact=true&max=2",
          token,
        ),
      ),
    )
  } else {
    users
  }
  guard users is [user] else { return false }
  login_status_locked(
    login_status_get(
      config,
      "/admin/realms/\{realm}/attack-detection/brute-force/users/\{form_encode(user.id)}",
      token,
    ),
  )
}
