///|
priv struct TrialBrowserSession {
  session_token : String
  csrf_token : String
  expires_unix_ms : Int64
} derive(FromJson)

///|
fn valid_trial_browser_session(
  session : TrialBrowserSession,
  now : Int64,
) -> Bool {
  session.session_token.has_prefix("lnxs_") &&
  session.session_token.length() > 5 &&
  session.csrf_token != "" &&
  session.expires_unix_ms > now
}

///|
extern "js" fn trial_browser_session_promise() -> @js.Promise =
  #| async () => {
  #|   const response = await fetch("/auth/session", {
  #|     method: "GET", headers: {"Accept": "application/json"},
  #|     credentials: "same-origin", cache: "no-store", redirect: "error"
  #|   });
  #|   if (!response.ok) throw new Error("Sign in again through the enterprise portal");
  #|   const text = await response.text();
  #|   if (text.length > 16384) throw new Error("invalid browser session");
  #|   return text;
  #| }

///|
// Re-bootstrap each operation: no reusable session token enters app state,
// storage, URLs or exports; gateway logout/expiry is checked before every call.
async fn load_trial_browser_session() -> TrialBrowserSession {
  try {
    let text : String = trial_browser_session_promise().wait().cast()
    let session : TrialBrowserSession = @json.from_json(@json.parse(text))
    guard valid_trial_browser_session(session, current_unix_ms()) else {
      fail("invalid or expired browser session")
    }
    session
  } catch {
    _ =>
      raise WorkbenchClientError::PublicRejected(
        "Unauthenticated", "", "", true, false,
      )
  }
}
