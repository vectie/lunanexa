///|
async test "model-free terminal handoff requires delivery binding and denies all inference" {
  let directory = @fs.tmpdir(prefix="terminal-handoff-")
  defer @fs.rmdir(directory, recursive=true)
  let store = test_store("\{directory}/handoffs.json")
  let now = 100000L
  let intent = { ..handoff_intent(now), allowed_models: [], }
  try store.issue(intent, now, allow_model_free=true) catch {
    @handoff.ClientHandoffError::InvalidInput(_) => ()
    error => raise error
  } noraise {
    _ => fail("unbound terminal key issued")
  }
  let issued = store.issue(
    intent,
    now,
    delivery_id="delivery-terminal",
    allow_model_free=true,
  )
  let redeemed = store.redeem(issued.handoff_code, intent.client_id, now + 1L)
  ignore(store.authorize(redeemed.api_secret, ModelList, now + 2L, false))
  for model in [None, Some("model-a")] {
    try
      store.authorize(redeemed.api_secret, Inference, model?, now + 2L, false)
    catch {
      @handoff.ClientHandoffError::Unauthorized => ()
      error => raise error
    } noraise {
      _ => fail("empty scope became inference wildcard")
    }
  }
}
