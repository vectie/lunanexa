///|
fn site_api_endpoint(origin : String, path : String) -> String {
  origin + (if path.has_prefix("/user/") { "/user" } else { "" })
}

///|
extern "js" fn browser_origin() -> String =
  #| () => globalThis.location?.origin || ""

///|
extern "js" fn browser_path() -> String =
  #| () => globalThis.location?.pathname || ""

///|
extern "js" fn browser_trial_requested() -> Bool =
  #| () => {
  #|   try { return new URL(globalThis.location.href).searchParams.get("trial") === "1"; }
  #|   catch (_) { return false; }
  #| }

///|
extern "js" fn configured_api_override() -> String =
  #| () => globalThis.LUNANEXA_API_ENDPOINT || ""
