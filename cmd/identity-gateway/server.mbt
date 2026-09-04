///|
fn response_reason(status : Int) -> String {
  match status {
    200 => "OK"
    204 => "No Content"
    302 => "Found"
    303 => "See Other"
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    413 => "Payload Too Large"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    _ => "Response"
  }
}

///|
async fn send_body(
  connection : @http.ServerConnection,
  status : Int,
  body : String,
  content_type : String,
  headers? : Map[String, String] = Map([]),
  cookies? : Array[@http.Cookie] = [],
) -> Unit {
  headers["Content-Type"] = content_type
  headers["Content-Length"] = @utf8.encode(body).length().to_string()
  connection.send_response(
    status,
    response_reason(status),
    extra_headers=headers,
    cookies~,
  )
  connection.write_string(body)
  connection.end_response()
}

///|
async fn send_error(
  connection : @http.ServerConnection,
  status : Int,
  code : String,
) -> Unit {
  send_body(
    connection,
    status,
    "{\"error\":\"\{code}\"}",
    "application/json; charset=utf-8",
    headers={ "Cache-Control": "no-store", "Pragma": "no-cache" },
  )
}

///|
fn browser_cookie(
  name : String,
  value : String,
  max_age : Int64,
) -> @http.Cookie {
  @http.Cookie(name, value, path="/", max_age~, secure=true, http_only=true, extensions=[
    "SameSite=Lax",
  ])
}

///|
fn expired_cookie(name : String) -> @http.Cookie {
  browser_cookie(name, "", 0L)
}

///|
fn host_and_audience(
  config : GatewayConfig,
  request : @http.Request,
) -> (String, BrowserAudience)? {
  guard header(request.headers, "Host") is Some(host) &&
    config.host_audience(host) is Some(audience) &&
    header(request.headers, "X-Forwarded-Proto") == Some("https") else {
    return None
  }
  match header(request.headers, "X-Forwarded-Host") {
    Some(forwarded) if forwarded != host => None
    _ => Some((host, audience))
  }
}

///|
fn exact_origin(request : @http.Request, host : String) -> Bool {
  header(request.headers, "Origin") == Some("https://\{host}") &&
  header(request.headers, "Sec-Fetch-Site") == Some("same-origin")
}

///|
fn safe_start_fetch(request : @http.Request) -> Bool {
  let site = header(request.headers, "Sec-Fetch-Site")
  (site == Some("same-origin") || site == Some("none")) &&
  header(request.headers, "Sec-Fetch-Mode") == Some("navigate")
}

///|
fn safe_callback_fetch(request : @http.Request) -> Bool {
  let site = header(request.headers, "Sec-Fetch-Site")
  (site == Some("cross-site") || site == Some("same-origin")) &&
  header(request.headers, "Sec-Fetch-Mode") == Some("navigate")
}

///|
fn safe_session_fetch(request : @http.Request) -> Bool {
  header(request.headers, "Sec-Fetch-Site") == Some("same-origin") &&
  header(request.headers, "Sec-Fetch-Dest") == Some("empty")
}

///|
fn valid_cookie_session(
  value : GatewayCookie,
  host : String,
  audience : BrowserAudience,
  config : GatewayConfig,
  now : Int64,
) -> Bool {
  value.host == host &&
  value.audience == audience.name() &&
  value.created_unix_ms <= now &&
  value.expires_unix_ms > now &&
  value.created_unix_ms + config.session_absolute_ms >= now &&
  value.last_used_unix_ms + config.session_idle_ms >= now
}

///|
async fn browser_state(
  store : GatewaySessionStore,
  config : GatewayConfig,
  request : @http.Request,
  audience : BrowserAudience,
) -> (String, GatewayCookie)? {
  guard cookie_value(request.headers, config.cookie_name(audience)) is Some(raw) &&
    decode_cookie_reference(raw, config.cookie_secret(audience)) is Some(id) &&
    store.load(id) is Some(value) else {
    return None
  }
  Some((id, value))
}

///|
async fn handle_oidc_start(
  store : GatewaySessionStore,
  config : GatewayConfig,
  request : @http.Request,
  connection : @http.ServerConnection,
  host : String,
  audience : BrowserAudience,
) -> Unit {
  guard request.meth == Get && safe_start_fetch(request) else {
    return send_error(connection, 400, "invalid-oidc-start")
  }
  let query = parse_query(request.path) catch {
    _ => return send_error(connection, 400, "invalid-oidc-start")
  }
  guard query.get("audience") == Some(audience.name()) && query.length() == 1 else {
    return send_error(connection, 400, "invalid-oidc-audience")
  }
  let discovery = discover(config) catch {
    _ => return send_error(connection, 503, "oidc-discovery-unavailable")
  }
  let (state, nonce, verifier, challenge) = try {
    let state = random_token(32)
    let nonce = random_token(32)
    let verifier = random_token(48)
    let challenge = base64url(
      Bytes::from_array(@crypto.sha256(@utf8.encode(verifier))).view(),
    )
    (state, nonce, verifier, challenge)
  } catch {
    _ => return send_error(connection, 503, "oidc-flow-entropy-unavailable")
  }
  let now = @async.now()
  let flow : GatewayCookie = {
    kind: "flow",
    audience: audience.name(),
    host,
    state,
    nonce,
    verifier,
    issuer: config.issuer,
    subject: "",
    email: "",
    display_name: "",
    bearer: "",
    csrf: "",
    created_unix_ms: now,
    last_used_unix_ms: now,
    expires_unix_ms: now + FlowLifetimeMs,
  }
  let flow_id = store.create(flow) catch {
    _ => return send_error(connection, 503, "identity-session-unavailable")
  }
  let cookie_reference = encode_cookie_reference(
    flow_id,
    config.cookie_secret(audience),
  )
  let location = "\{discovery.authorization_endpoint}?response_type=code&client_id=\{form_encode(config.client_id(audience))}&redirect_uri=\{form_encode(config.redirect_uri(audience))}&scope=openid%20profile%20email&state=\{form_encode(state)}&nonce=\{form_encode(nonce)}&code_challenge=\{form_encode(challenge)}&code_challenge_method=S256"
  connection.send_response(
    302,
    "Found",
    extra_headers={
      "Location": location,
      "Cache-Control": "no-store",
      "Pragma": "no-cache",
      "Content-Length": "0",
    },
    cookies=[
      browser_cookie(config.cookie_name(audience), cookie_reference, 600L),
    ],
  )
  connection.end_response()
}

///|
async fn handle_oidc_callback(
  store : GatewaySessionStore,
  config : GatewayConfig,
  request : @http.Request,
  connection : @http.ServerConnection,
  host : String,
  audience : BrowserAudience,
) -> Unit {
  guard request.meth == Get && safe_callback_fetch(request) else {
    return send_error(connection, 400, "invalid-oidc-callback")
  }
  let query = parse_query(request.path) catch {
    _ => return send_error(connection, 400, "invalid-oidc-callback")
  }
  let issuer_matches = match query.get("iss") {
    Some(issuer) => issuer == config.issuer
    None => true
  }
  guard query.get("code") is Some(code) &&
    query.get("state") is Some(state) &&
    query.get("error") is None &&
    issuer_matches &&
    browser_state(store, config, request, audience) is Some((flow_id, flow)) else {
    return send_error(connection, 401, "oidc-callback-rejected")
  }
  let now = @async.now()
  guard flow.kind == "flow" &&
    valid_cookie_session(flow, host, audience, config, now) &&
    flow.expires_unix_ms <= flow.created_unix_ms + FlowLifetimeMs &&
    constant_time_equal(state, flow.state) else {
    return send_error(connection, 401, "oidc-state-rejected")
  }
  guard store.delete(flow_id) else {
    return send_error(connection, 401, "oidc-state-replayed")
  }
  let identity = complete_oidc_callback(config, flow, audience, code, now)
  let identity_id = store.create(identity)
  let cookie_reference = encode_cookie_reference(
    identity_id,
    config.cookie_secret(audience),
  )
  connection.send_response(
    303,
    "See Other",
    extra_headers={
      "Location": "/",
      "Cache-Control": "no-store",
      "Pragma": "no-cache",
      "Content-Length": "0",
    },
    cookies=[
      browser_cookie(
        config.cookie_name(audience),
        cookie_reference,
        config.session_absolute_ms / 1000L,
      ),
    ],
  )
  connection.end_response()
}

///|
async fn handle_browser_session(
  store : GatewaySessionStore,
  config : GatewayConfig,
  request : @http.Request,
  connection : @http.ServerConnection,
  host : String,
  audience : BrowserAudience,
) -> Unit {
  guard request.meth == Get &&
    request.path == "/auth/session" &&
    safe_session_fetch(request) &&
    browser_state(store, config, request, audience)
    is Some((current_id, current)) else {
    return send_error(connection, 401, "browser-session-required")
  }
  let now = @async.now()
  guard valid_cookie_session(current, host, audience, config, now) &&
    (current.kind == "identity" || current.kind == "session") else {
    return send_error(connection, 401, "browser-session-expired")
  }
  // Keep the state-changing consume outside a boolean expression. In
  // particular, an already-issued session must never evaluate delete().
  if current.kind == "identity" {
    if !store.delete(current_id) {
      return send_error(connection, 409, "browser-session-already-issued")
    }
  }
  let (active_id, active) = if current.kind == "identity" {
    let issued = issue_controller_session(config, current, audience, now)
    (store.create(issued), issued)
  } else {
    (current_id, current)
  }
  let refreshed = { ..active, last_used_unix_ms: now }
  store.replace(active_id, refreshed)
  let cookie_reference = encode_cookie_reference(
    active_id,
    config.cookie_secret(audience),
  )
  let body = "{\"session_token\":\"\{refreshed.bearer}\",\"csrf_token\":\"\{refreshed.csrf}\",\"expires_unix_ms\":\{refreshed.expires_unix_ms}}"
  send_body(
    connection,
    200,
    body,
    "application/json; charset=utf-8",
    headers={
      "Cache-Control": "no-store",
      "Pragma": "no-cache",
      "Vary": "Cookie",
    },
    cookies=[
      browser_cookie(
        config.cookie_name(audience),
        cookie_reference,
        (refreshed.expires_unix_ms - now) / 1000L,
      ),
    ],
  )
}

///|
async fn handle_logout(
  store : GatewaySessionStore,
  config : GatewayConfig,
  request : @http.Request,
  reader : &@io.Reader,
  connection : @http.ServerConnection,
  host : String,
  audience : BrowserAudience,
) -> Unit {
  guard request.meth == Post &&
    request.path == "/auth/logout" &&
    exact_origin(request, host) &&
    browser_state(store, config, request, audience)
    is Some((session_id, session)) &&
    session.kind == "session" &&
    valid_cookie_session(session, host, audience, config, @async.now()) &&
    header(request.headers, "X-LunaNexa-CSRF") is Some(csrf) &&
    csrf.length() >= 32 &&
    csrf.length() <= 128 &&
    constant_time_equal(csrf, session.csrf) else {
    return send_error(connection, 403, "csrf-rejected")
  }
  let body = reader.read_all().binary()
  guard body.length() == 0 else {
    return send_error(connection, 400, "logout-body-rejected")
  }
  ignore(store.delete(session_id))
  let status = revoke_controller_session(config, session.bearer) catch {
    _ => 502
  }
  let cookie = expired_cookie(config.cookie_name(audience))
  if status == 200 || status == 401 {
    connection.send_response(
      204,
      "No Content",
      extra_headers={ "Cache-Control": "no-store", "Content-Length": "0" },
      cookies=[cookie],
    )
    connection.end_response()
  } else {
    send_body(
      connection,
      502,
      "{\"error\":\"logout-upstream-failed\"}",
      "application/json; charset=utf-8",
      headers={ "Cache-Control": "no-store" },
      cookies=[cookie],
    )
  }
}

///|
fn enterprise_path_allowed(path : String) -> Bool {
  path.has_prefix("/v1/auth/") ||
  exact_or_child(path, "/v1/portal/self") ||
  exact_or_child(path, "/v1/portal/payment-checkouts") ||
  exact_or_child(path, "/v1/portal/signature-requests") ||
  exact_or_child(path, "/v1/portal/lease-requests") ||
  exact_or_child(path, "/v1/notifications/self") ||
  exact_or_child(path, "/v1/contract-documents/self") ||
  exact_or_child(path, "/v1/contract-documents/manifest") ||
  exact_or_child(path, "/v1/offline-commerce/self") ||
  exact_or_child(path, "/v1/machine-access/self")
}

///|
fn exact_or_child(path : String, prefix : String) -> Bool {
  path == prefix || path.has_prefix("\{prefix}/")
}

///|
fn forward_request_headers(
  request : @http.Request,
  authorization? : String,
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for
    name in [
      "Accept", "Content-Type", "If-None-Match", "Range", "X-LunaNexa-Organization",
    ] {
    match header(request.headers, name) {
      Some(value) if value.length() <= 1024 => result[name] = value
      _ => ()
    }
  }
  match authorization {
    Some(value) => result["Authorization"] = value
    None => ()
  }
  result
}

///|
async fn proxy_request(
  request : @http.Request,
  reader : &@io.Reader,
  connection : @http.ServerConnection,
  endpoint : String,
  authorization? : String,
  no_store~ : Bool,
  response_cookie? : @http.Cookie,
) -> Unit {
  let request_body = reader.read_all().binary()
  guard request_body.length() <= MaximumRequestBytes else {
    return send_error(connection, 413, "request-too-large")
  }
  let (origin, base_path) = endpoint_origin_and_path(endpoint, false)
  guard base_path == "/" else {
    return send_error(connection, 502, "invalid-upstream")
  }
  let client = @http.Client(origin)
  defer client.close()
  client.request(
    request.meth,
    request.path,
    extra_headers=forward_request_headers(request, authorization?),
  )
  client.write(request_body)
  let response = client.end_request()
  let response_body = client.read_all().binary()
  let headers : Map[String, String] = Map([])
  for name in ["Content-Type", "Cache-Control", "ETag", "Content-Range"] {
    match header(response.headers, name) {
      Some(value) if value.length() <= 1024 => headers[name] = value
      _ => ()
    }
  }
  if no_store {
    headers["Cache-Control"] = "no-store"
    headers["Pragma"] = "no-cache"
  }
  headers["Content-Length"] = response_body.length().to_string()
  let cookies = match response_cookie {
    Some(value) => [value]
    None => []
  }
  connection.send_response(
    response.code,
    response_reason(response.code),
    extra_headers=headers,
    cookies~,
  )
  connection.write(response_body)
  connection.end_response()
}

///|
async fn handle_api_proxy(
  store : GatewaySessionStore,
  config : GatewayConfig,
  request : @http.Request,
  reader : &@io.Reader,
  connection : @http.ServerConnection,
  host : String,
  audience : BrowserAudience,
) -> Unit {
  guard canonical_api_path(request.path) is Some(path) &&
    (audience == Operator || enterprise_path_allowed(path)) &&
    header(request.headers, "Sec-Fetch-Site") == Some("same-origin") &&
    browser_state(store, config, request, audience)
    is Some((session_id, session)) &&
    session.kind == "session" &&
    valid_cookie_session(session, host, audience, config, @async.now()) &&
    header(request.headers, "Authorization") == Some("Bearer \{session.bearer}") else {
    return send_error(connection, 401, "browser-bearer-rejected")
  }
  let refreshed = { ..session, last_used_unix_ms: @async.now() }
  store.replace(session_id, refreshed)
  let cookie_reference = encode_cookie_reference(
    session_id,
    config.cookie_secret(audience),
  )
  proxy_request(
    request,
    reader,
    connection,
    config.control_endpoint,
    authorization="Bearer \{session.bearer}",
    no_store=true,
    response_cookie=browser_cookie(
      config.cookie_name(audience),
      cookie_reference,
      (session.expires_unix_ms - @async.now()) / 1000L,
    ),
  )
}

///|
async fn handle_proxy(
  store : GatewaySessionStore,
  config : GatewayConfig,
  request : @http.Request,
  reader : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  if request.meth == Get && request.path == "/health" {
    if store.ping() {
      return send_body(connection, 200, "ok\n", "text/plain; charset=utf-8")
    }
    return send_error(connection, 503, "identity-session-store-unavailable")
  }
  guard host_and_audience(config, request) is Some((host, audience)) else {
    return send_error(connection, 400, "untrusted-browser-host")
  }
  let path = request_path(request.path)
  if request.meth == Get && request.path == "/" {
    let location = match audience {
      Operator => "/console/"
      Enterprise => "/enterprise/"
    }
    connection.send_response(302, "Found", extra_headers={
      "Location": location,
      "Cache-Control": "no-store",
      "Content-Length": "0",
    })
    return connection.end_response()
  }
  match path {
    "/auth/oidc/start" =>
      handle_oidc_start(store, config, request, connection, host, audience)
    "/auth/oidc/callback" =>
      handle_oidc_callback(store, config, request, connection, host, audience)
    "/auth/session" =>
      handle_browser_session(store, config, request, connection, host, audience)
    "/auth/logout" =>
      handle_logout(store, config, request, reader, connection, host, audience)
    _ if path.has_prefix("/auth/") =>
      send_error(connection, 404, "route-not-found")
    _ if path.has_prefix("/v1/") =>
      handle_api_proxy(
        store, config, request, reader, connection, host, audience,
      )
    _ =>
      proxy_request(
        request,
        reader,
        connection,
        config.ui_upstream(audience),
        no_store=false,
      )
  }
}

///|
async fn handle_relay(
  config : GatewayConfig,
  request : @http.Request,
  reader : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  if request.meth == Get && request.path == "/health" {
    return send_body(connection, 200, "ok\n", "text/plain; charset=utf-8")
  }
  guard request.meth == Post &&
    (
      request.path == "/v1/auth/register" ||
      request.path == "/v1/auth/session:exchange"
    ) &&
    header(request.headers, "Content-Type") is Some(content_type) &&
    content_type.has_prefix("application/json") &&
    relay_identity_headers(request.headers) is Some(headers) else {
    return send_error(connection, 404, "relay-route-rejected")
  }
  let body = reader.read_all().binary()
  guard body.length() <= 256 else {
    return send_error(connection, 413, "relay-body-too-large")
  }
  let (response, response_body) = post_internal(
    config.control_endpoint,
    request.path,
    @utf8.decode(body),
    headers,
  )
  send_body(
    connection,
    response.code,
    response_body,
    "application/json; charset=utf-8",
    headers={ "Cache-Control": "no-store" },
  )
}
