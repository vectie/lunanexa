///|
/// Share only an in-flight check for the same opaque browser session. Completed
/// decisions are never cached: subsequent requests consult the authority again.
async fn Bridge::authorize_session(
  self : Bridge,
  token : String,
  grant : Grant,
) -> Bool {
  if self.authorizations.get(token) is Some(flight) {
    flight.gate.acquire()
    defer flight.gate.release()
    match flight.result {
      Some(result) => return result
      None => raise BridgeError::AuthorityUnavailable
    }
  }
  let flight : AuthorizationFlight = { gate: @async.Mutex(), result: None, }
  // No suspension between acquiring this new mutex and publishing the flight.
  assert_true(flight.gate.try_acquire())
  self.authorizations[token] = flight
  defer {
    self.authorizations.remove(token)
    flight.gate.release()
  }
  let result = (self.authorize)(grant)
  flight.result = Some(result)
  result
}
