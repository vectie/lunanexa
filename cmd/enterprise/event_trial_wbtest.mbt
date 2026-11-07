///|
test "event redemption failure is distinct from Wi-Fi and stale replies are fenced" {
  let model = { ..polling_fixture(), connecting: true, }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (failed, _) = update(
    model,
    EventTrialFinished(model.session_generation, None),
    emit,
  )
  assert_false(failed.connecting)
  assert_true(failed.portal.error_message.unwrap().contains("Event trial"))
  assert_false(failed.portal.error_message.unwrap().contains("Wi-Fi"))
  let (stale, _) = update(
    model,
    EventTrialFinished(model.session_generation - 1L, Some("wrong-org")),
    emit,
  )
  assert_eq(
    stale.portal.selected_organization_id,
    model.portal.selected_organization_id,
  )
  assert_eq(stale.connecting, model.connecting)
}
