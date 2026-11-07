///|
/// This public link is a navigation hint only; server authority grants access.
extern "js" fn event_trial_entry() -> Bool =
  #| () => new URLSearchParams(globalThis.location?.search || "").get("trial") === "event"
