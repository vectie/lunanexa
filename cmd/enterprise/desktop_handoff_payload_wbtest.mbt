///|
test "shared WebIDE handoff omits absent dedicated order instead of null" {
  let shared = desktop_handoff_payload("request", "client", "project", None, [
    "model",
  ])
  assert_false(shared.stringify().contains("order_id"))
  let dedicated = desktop_handoff_payload(
    "request",
    "client",
    "project",
    Some("order"),
    ["model"],
  )
  assert_true(dedicated is { "order_id": String("order"), .. })
}
