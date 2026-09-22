///|
fn random_token() -> String raise BridgeError {
  let bytes = Bytes::make(32, 0)
  if fill_secure_random(bytes) != 0 {
    raise UpstreamUnavailable
  }
  @crypto.bytes_to_hex_string(bytes)
}

///|
#borrow(output)
extern "c" fn fill_secure_random(output : Bytes) -> Int = "lunanexa_webide_secure_random"

///|
async fn read_bounded(reader : &@io.Reader, limit : Int) -> Bytes {
  let output = Buffer()
  let mut size = 0
  while reader.read_some(max_len=8192) is Some(bytes) {
    size += bytes.length()
    if size > limit {
      raise BridgeError::RequestTooLarge
    }
    output.write_bytes(bytes)
  }
  output.to_bytes()
}

///|
fn response_headers(content_type : String) -> Map[String, String] {
  {
    "content-type": content_type,
    "cache-control": "no-store",
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
    "x-frame-options": "DENY",
    "cross-origin-resource-policy": "same-origin",
  }
}

///|
async fn reply(
  connection : @http.ServerConnection,
  code : Int,
  message : String,
) -> Unit {
  connection.send_response(
    code,
    "WebIDE",
    extra_headers=response_headers("text/plain; charset=utf-8"),
  )
  connection.write_string(message)
  connection.end_response()
}

///|
fn Bridge::browser_cookie(
  self : Bridge,
  value : String,
  challenge : Bool,
  age : Int64,
) -> @http.Cookie {
  Cookie(
    self.cookie_name(challenge),
    value,
    path="/",
    max_age=age,
    secure=self.config.public_origin.has_prefix("https://"),
    http_only=true,
    extensions=["SameSite=Strict"],
  )
}

///|
fn Bridge::prune(self : Bridge, now : Int64) -> Unit {
  for key, session in self.sessions.copy() {
    if session.grant.expires_unix_ms <= now {
      self.sessions.remove(key)
    }
  }
  for key, expiry in self.challenges.copy() {
    if expiry <= now {
      self.challenges.remove(key)
    }
  }
}

///|
async fn Bridge::connect_page(
  self : Bridge,
  connection : @http.ServerConnection,
) -> Unit {
  self.prune(@async.now())
  if self.challenges.length() >= self.config.maximum_sessions {
    return reply(
      connection, 429, "Too many pending launches. Try again shortly.",
    )
  }
  let nonce = random_token()
  self.challenges[nonce] = @async.now() + 120000L
  let headers = response_headers("text/html; charset=utf-8")
  headers["content-security-policy"] = "default-src 'none'; script-src 'nonce-\{nonce}'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
  connection.send_response(200, "OK", extra_headers=headers, cookies=[
    self.browser_cookie(nonce, true, 120L),
  ])
  // The handoff stays in the fragment until this same-origin POST. Remove it
  // before any network action, never reflect provider diagnostics or secrets.
  let page =
    $|<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Open ComfyUI</title>
    $|<main><h1>Open ComfyUI</h1><p role="status" id="status">Connecting your isolated workspace…</p><a href="/connect">Retry with a new launch from your portal</a></main>
    $|<script nonce="\{nonce}">
    $|const fragment = new URLSearchParams(location.hash.slice(1));
    $|const code = fragment.get('lunanexa_handoff');
    $|history.replaceState(null, '', '/connect');
    $|async function connect() {
    $|  if (!code) throw new Error();
    $|  const response = await fetch('/connect', {method:'POST', credentials:'same-origin',
    $|    headers:{'Content-Type':'application/json','X-WebIDE-CSRF':'\{nonce}'},
    $|    body:JSON.stringify({handoff_code:code})});
    $|  if (!response.ok) throw new Error();
    $|  location.replace('/');
    $|}
    $|connect().catch(() => {document.getElementById('status').textContent='Unable to open this workspace. Check its readiness and launch again from your portal.';});
    $|</script></html>
  connection.write_string(page)
  connection.end_response()
}

///|
priv struct ConnectRequest {
  handoff_code : String
} derive(FromJson)

///|
async fn Bridge::connect(
  self : Bridge,
  request : @http.Request,
  body : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  guard cookie(request.headers, self.cookie_name(true)) is Some(challenge) &&
    header(request.headers, "x-webide-csrf") == Some(challenge) else {
    raise BridgeError::Unauthorized
  }
  let payload : ConnectRequest = @json.from_json(
    @json.parse(@utf8.decode(read_bounded(body, 2048))),
  )
  if !payload.handoff_code.has_prefix("lnxc_") ||
    payload.handoff_code.length() > 256 ||
    !valid_atom(payload.handoff_code) {
    raise BridgeError::Unauthorized
  }
  self.mutex.acquire()
  defer self.mutex.release()
  self.prune(@async.now())
  guard self.challenges.get(challenge) is Some(_) else {
    raise BridgeError::Unauthorized
  }
  self.challenges.remove(challenge)
  if self.sessions.length() >= self.config.maximum_sessions {
    raise BridgeError::CapacityExceeded
  }
  let grant = (self.redeem)(payload.handoff_code)
  if !self.valid_grant(grant, @async.now()) || !(self.authorize)(grant) {
    raise BridgeError::InvalidGrant
  }
  let id = workspace_id(grant)
  let backend = (self.provision)(id, grant)
  if !(backend.http_url.has_prefix("http://") ||
    backend.http_url.has_prefix("https://")) ||
    !(backend.websocket_url.has_prefix("ws://") ||
    backend.websocket_url.has_prefix("wss://")) {
    raise BridgeError::InvalidConfiguration
  }
  let session = random_token()
  // A browser has one active identity, just like the portal. Close its old
  // WebSockets through the periodic session check when switching workspaces.
  match cookie(request.headers, self.cookie_name(false)) {
    Some(old) => self.sessions.remove(old)
    None => ()
  }
  self.sessions[session] = { grant, backend, }
  connection.send_response(
    204,
    "Connected",
    extra_headers=response_headers("text/plain"),
    cookies=[
      self.browser_cookie(
        session,
        false,
        (grant.expires_unix_ms - @async.now()) / 1000L,
      ),
      self.browser_cookie("", true, 0L),
    ],
  )
  connection.end_response()
}

///|
async fn Bridge::session(self : Bridge, token : String) -> Session {
  guard self.sessions.get(token) is Some(session) &&
    session.grant.expires_unix_ms > @async.now() else {
    self.sessions.remove(token)
    raise BridgeError::Unauthorized
  }
  if !self.authorize_session(token, session.grant) {
    self.sessions.remove(token)
    raise BridgeError::Unauthorized
  }
  if !self.sessions.contains(token) ||
    session.grant.expires_unix_ms <= @async.now() {
    raise BridgeError::Unauthorized
  }
  session
}

///|
async fn Bridge::proxy_http(
  self : Bridge,
  session : Session,
  request : @http.Request,
  body : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  let headers : Map[String, String] = Map([])
  // Never forward browser cookies, Authorization, Host, forwarded identity or
  // hop-by-hop headers. ComfyUI has no access to the browser session secret.
  for name in ["content-type", "accept", "range"] {
    match header(request.headers, name) {
      Some(value) => headers[name] = value
      None => ()
    }
  }
  let payload = read_bounded(body, self.config.maximum_request_bytes)
  let upstream = @http.Client(session.backend.http_url)
  defer upstream.close()
  upstream.request(request.meth, request.path, extra_headers=headers)
  upstream.write(payload)
  let response = upstream.end_request()
  // Redirects can expose an internal endpoint or move the browser outside the
  // authenticated gateway. ComfyUI's accepted API/static routes don't need them.
  if response.code >= 300 && response.code < 400 && response.code != 304 {
    raise BridgeError::UpstreamUnavailable
  }
  let outgoing = response_headers(
    header(response.headers, "content-type").unwrap_or(
      "application/octet-stream",
    ),
  )
  for name in ["content-range", "accept-ranges"] {
    match header(response.headers, name) {
      Some(value) => outgoing[name] = value
      None => ()
    }
  }
  connection.send_response(response.code, "WebIDE", extra_headers=outgoing)
  if request.meth != Head {
    while upstream.read_some(max_len=65536) is Some(bytes) {
      connection.write(bytes)
    }
  }
  connection.end_response()
}

///|
async fn relay_socket(
  source : @websocket.Conn,
  target : @websocket.Conn,
  limit : Int,
) -> Unit {
  while true {
    let message = source.recv()
    let data = read_bounded(message, limit)
    match message.kind {
      Text => target.send_text(@utf8.decode(data))
      Binary => target.send_binary(data)
    }
  }
}

///|
async fn Bridge::proxy_socket(
  self : Bridge,
  token : String,
  session : Session,
  request : @http.Request,
  connection : @http.ServerConnection,
) -> Unit {
  let upstream = @async.with_timeout(self.config.request_timeout_ms, () => {
    @websocket.Conn::connect(session.backend.websocket_url + request.path)
  })
  defer upstream.close()
  let browser = @websocket.Conn::from_http_server(request, connection)
  defer browser.close()
  @async.any([
    () => {
      relay_socket(browser, upstream, self.config.maximum_socket_message_bytes)
    },
    () => {
      relay_socket(upstream, browser, self.config.maximum_socket_message_bytes)
    },
    () => {
      while true {
        @async.sleep(self.config.authorization_interval_ms)
        ignore(
          @async.with_timeout(self.config.request_timeout_ms, () => {
            self.session(token)
          }),
        )
      }
    },
  ]) catch {
    _ =>
      // HTTP is already upgraded. Do not write an HTTP error into a socket.
      browser.send_close(
        code=PolicyViolation,
        reason="Workspace connection ended",
      ) catch {
        _ => ()
      }
  }
}

///|
/// Attach to the deployment's private HTTP listener. Long-lived WebSockets
/// renew authority independently; every HTTP request checks live authority.
pub async fn Bridge::handle(
  self : Bridge,
  request : @http.Request,
  body : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  let origin = self.config.public_origin
  let authority = origin[if origin.has_prefix("https://") { 8 } else { 7 }:].to_owned()
  if header(request.headers, "host") != Some(authority) ||
    header(request.headers, "origin").map_or(false, value => value != origin) ||
    (
      header(request.headers, "sec-fetch-site") == Some("cross-site") &&
      !(request.path == "/connect" && request.meth == Get)
    ) ||
    (
      request.meth != Get &&
      request.meth != Head &&
      header(request.headers, "origin") != Some(origin)
    ) {
    return reply(connection, 403, "Request origin rejected.")
  }
  try {
    if request.path == "/connect" && request.meth == Get {
      return @async.with_timeout(self.config.request_timeout_ms, () => {
        self.connect_page(connection)
      })
    }
    if request.path == "/connect" && request.meth == Post {
      return @async.with_timeout(self.config.request_timeout_ms, () => {
        self.connect(request, body, connection)
      })
    }
    guard cookie(request.headers, self.cookie_name(false)) is Some(token) else {
      raise BridgeError::Unauthorized
    }
    let session = @async.with_timeout(self.config.request_timeout_ms, () => {
      self.session(token)
    })
    if request.path == "/logout" && request.meth == Post {
      self.sessions.remove(token)
      connection.send_response(
        204,
        "Logged out",
        extra_headers=response_headers("text/plain"),
        cookies=[self.browser_cookie("", false, 0L)],
      )
      return connection.end_response()
    }
    if !allowed_path(request.meth, request.path) {
      return reply(
        connection, 403, "Route is not available in managed workspaces.",
      )
    }
    if request.path.split("?").next() == Some("/ws") {
      if request.meth != Get ||
        header(request.headers, "origin") != Some(origin) {
        raise BridgeError::Unauthorized
      }
      self.proxy_socket(token, session, request, connection)
    } else {
      @async.with_timeout(self.config.request_timeout_ms, () => {
        self.proxy_http(session, request, body, connection)
      })
    }
  } catch {
    BridgeError::Unauthorized | BridgeError::InvalidGrant =>
      reply(connection, 401, "Launch this workspace again from your portal.")
    BridgeError::RequestTooLarge =>
      reply(connection, 413, "Workspace request exceeds its size limit.")
    BridgeError::CapacityExceeded =>
      reply(connection, 429, "Workspace capacity is temporarily full.")
    BridgeError::StorageBusy =>
      reply(
        connection, 409, "Your saved workspace is open in another delivery. Stop that workspace before opening this one.",
      )
    BridgeError::StorageMigrationRequired =>
      reply(
        connection, 409, "Your saved workspace requires a storage migration before it can open on this node or storage profile. Ask your administrator to migrate it; your files have not been replaced.",
      )
    BridgeError::StorageNotConfigured =>
      reply(
        connection, 503, "Shared workspace storage is not installed for this deployment. Ask your administrator to configure the shared storage profile before retrying.",
      )
    BridgeError::AuthorityUnavailable =>
      reply(
        connection, 503, "Workspace authorization is temporarily unavailable. Retry shortly.",
      )
    _ => {
      // Never log or return upstream errors: they may contain credentials,
      // prompts, filesystem paths or infrastructure addresses.
      reply(connection, 502, "Workspace is not ready. Retry from your portal.") catch {
        _ => ()
      }
      connection.close()
    }
  }
}
