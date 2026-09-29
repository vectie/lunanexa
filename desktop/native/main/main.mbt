///|
let username : String = "wlc"

///|
extern "c" fn resource_manifest() -> Bytes = "lnx_resource_manifest"

///|
#borrow(service, account)
extern "c" fn password(service : Bytes, account : Bytes) -> Bytes = "lnx_password"

///|
#borrow(service, account)
extern "c" fn configure(service : Bytes, account : Bytes) -> Int = "lnx_configure"

///|
#borrow(value, origin)
extern "c" fn install_cookie(value : Bytes, origin : Bytes) -> Int = "lnx_install_cookie"

///|
#borrow(message)
extern "c" fn retry_dialog(message : Bytes) -> Int = "lnx_retry_dialog"

///|
struct Session {
  session_token : String
  csrf_token : String
  expires_unix_ms : Int64
} derive(FromJson)

///|
fn valid_session(session : Session, now : Int64) -> Bool {
  session.session_token.has_prefix("lnxs_") &&
  session.csrf_token.length() > 0 &&
  session.expires_unix_ms > now
}

///|
// A desktop deployment opt-in, scoped to the release-selected HTTP origin.
// This does not grant authority; the ordinary identity session is still required.
fn transport_script(origin : String) -> String {
  let quoted_origin = Json::string(origin).stringify()
  let script =
    #|(() => {
    #| if (location.origin !== __OPERATOR_ORIGIN__) return;
    #| const apply = () => {
    #|   if (!document.head) return false;
    #|   const meta = document.createElement('meta');
    #|   meta.name = 'lunanexa-public-http-origin';
    #|   meta.content = location.origin;
    #|   document.head.prepend(meta);
    #|   return true;
    #| };
    #| if (!apply()) {
    #|   const observer = new MutationObserver(() => { if (apply()) observer.disconnect(); });
    #|   observer.observe(document, {childList: true, subtree: true});
    #| }
    #|})();
  script.replace(old="__OPERATOR_ORIGIN__", new=quoted_origin)
}

///|
fn valid_operator_origin(origin : String) -> Bool {
  let authority = if origin.has_prefix("https://") {
    origin[8:].to_owned()
  } else if origin.has_prefix("http://") {
    origin[7:].to_owned()
  } else {
    return false
  }
  authority != "" &&
  !authority.contains("/") &&
  !authority.contains("?") &&
  !authority.contains("#") &&
  !authority.contains("@") &&
  !authority.contains("\\") &&
  !authority.contains(" ")
}

///|
fn desktop_manifest(text : String) -> (String, String) raise {
  let parsed = @json.parse(text)
  guard parsed
    is {
      "identifier": "dev.vectie.lunanexa.operator",
      "runtime": { "webviews": Array(views), .. },
      ..
    } &&
    views.length() == 1 else {
    raise Failure("Not an Operator desktop manifest")
  }
  guard views[0] is Object(view) &&
    view.get("label") == Some(Json::string("operator")) else {
    raise Failure("Not an Operator window")
  }
  guard view.get("url") is Some(String(url)) && url.has_suffix("/console/") else {
    raise Failure("Operator manifest needs a console URL")
  }
  let origin = url[:url.length() - 9].to_owned()
  guard valid_operator_origin(origin) else {
    raise Failure("Operator manifest has an invalid origin")
  }
  // Reuse the live Rabbita UI; neither UI assets nor secrets are forked locally.
  view["url"] = Json::string(origin + "/console/")
  let scripts = match view.get("initializationScripts") {
    Some(Array(scripts)) => scripts
    _ => []
  }
  if origin.has_prefix("http://") {
    scripts.push(Json::string(transport_script(origin)))
  }
  view["initializationScripts"] = Json::array(scripts)
  (parsed.stringify(), origin)
}

///|
async fn authenticate(origin : String) -> Unit {
  let mut secret = @utf8.decode(
    password(@utf8.encode(origin), @utf8.encode(username)),
  )
  if secret == "" &&
    configure(@utf8.encode(origin), @utf8.encode(username)) == 0 {
    secret = @utf8.decode(
      password(@utf8.encode(origin), @utf8.encode(username)),
    )
  }
  guard secret != "" else {
    raise Failure("钥匙串中没有密码，或访问被取消。")
  }
  @async.with_timeout(15000, () => {
    let client = @http.Client(origin)
    defer client.close()
    let body : Json = {
      "username": username,
      "password": secret,
      "audience": "operator",
    }
    let response = client.post("/auth/password", body.stringify(), extra_headers={
      "Origin": origin,
      "Content-Type": "application/json",
    })
    guard response.code == 200 else {
      raise Failure(
        if response.code == 401 {
          "登录被拒绝，请检查钥匙串中的密码。"
        } else {
          "身份服务暂时不可用。"
        },
      )
    }
    let session : Session = @json.from_json(
      @json.parse(client.read_all().text()),
    )
    guard valid_session(session, @async.now()) else {
      raise Failure("身份服务未返回有效会话。")
    }
    // Check current controller authority as well as the gateway session cache.
    let authority = client.get("/v1/auth/self", extra_headers={
      "Authorization": "Bearer " + session.session_token,
    })
    ignore(client.read_all())
    guard authority.code == 200 else {
      raise Failure("平台拒绝此账户的访问权限。")
    }
    guard response.cookies.length() == 1 && response.cookies[0].http_only else {
      raise Failure("身份服务未返回安全会话 Cookie。")
    }
    guard install_cookie(
        @utf8.encode(response.cookies[0].to_json().stringify()),
        @utf8.encode(origin),
      ) ==
      0 else {
      raise Failure("无法初始化管理台会话。")
    }
  })
}

///|
async fn main {
  let args = @env.args()
  let mut path = @utf8.decode(resource_manifest())
  for i in 0..<args.length() {
    if args[i] == "--manifest" {
      path = args.get(i + 1).unwrap_or("")
    }
  }
  let (text, origin) = desktop_manifest(@fs.read_file(path).text())
  if args.contains("--configure") {
    guard configure(@utf8.encode(origin), @utf8.encode(username)) == 0 else {
      raise Failure("未能保存到钥匙串。")
    }
    println("Operator credential saved in this Mac's Keychain.")
    return
  }
  let manifest = match @bundled.BundledRuntimeManifest::parse(path, text) {
    Ok(manifest) => manifest
    Err(_) => raise Failure("Invalid desktop manifest")
  }
  for ;; {
    try authenticate(origin) catch {
      _ => {
        let action = retry_dialog(
          @utf8.encode(
            "无法连接或登录 \{origin}。请检查网络、钥匙串权限及账户密码。",
          ),
        )
        if action == 0 {
          return
        }
        if action == 2 {
          ignore(configure(@utf8.encode(origin), @utf8.encode(username)))
        }
        continue
      }
    } noraise {
      _ => break
    }
  }
  match @macos.run_bundled(manifest) {
    Ok(_) => ()
    Err(_) =>
      ignore(
        retry_dialog(
          @utf8.encode("管理台窗口启动失败，请重新打开应用。"),
        ),
      )
  }
}
