///|
test "guide monitor startup is disabled by default and requires an exact flag" {
  assert_false(guide_monitor_enabled(None))
  assert_false(guide_monitor_enabled(Some("")))
  assert_false(guide_monitor_enabled(Some("0")))
  assert_true(guide_monitor_enabled(Some("1")))
  try {
    ignore(guide_monitor_enabled(Some("true")))
    fail("ambiguous guide monitor enable value was accepted")
  } catch {
    Failure::Failure(_) => ()
    _ => fail("unexpected guide monitor flag error")
  }
}

///|
test "offline callback identities allow absent, require complete strong pairs" {
  let operator = "operator-token-with-at-least-32-bytes-a"
  let inference = "inference-token-with-at-least-32-bytes-b"
  assert_eq(offline_callback_tokens(None, None, operator, inference), None)
  let pair = offline_callback_tokens(
    Some("worker-token-with-at-least-32-bytes-c"),
    Some("scanner-token-with-at-least-32-bytes-d"),
    operator,
    inference,
  )
  assert_eq(
    pair,
    Some(
      (
        "worker-token-with-at-least-32-bytes-c", "scanner-token-with-at-least-32-bytes-d",
      ),
    ),
  )
  let rejected = [
    (Some("worker-token-with-at-least-32-bytes-c"), None),
    (Some("short"), Some("scanner-token-with-at-least-32-bytes-d")),
    (Some(operator), Some("scanner-token-with-at-least-32-bytes-d")),
    (
      Some("same-callback-token-with-at-least-32-bytes"),
      Some("same-callback-token-with-at-least-32-bytes"),
    ),
  ]
  for attempt in rejected {
    ignore(offline_callback_tokens(attempt.0, attempt.1, operator, inference)) catch {
      Failure::Failure(_) => ()
      _ => fail("invalid callback identity configuration was accepted")
    }
  }
}
