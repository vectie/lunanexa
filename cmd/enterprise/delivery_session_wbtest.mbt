///|
test "delivery authentication failure recovers session and clears company projections" {
  let model = {
    ..gateway_auth_test_model(),
    token: "lnxs_expired",
    csrf_token: "csrf-expired",
    subject_ref: "subject-test",
    session_generation: 7L,
    portal: @enterprise_ui.demo_state(),
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (recovering, _) = update(
    model,
    DeliveriesLoaded(
      model.session_generation,
      model.portal.selected_organization_id,
      model.portal.deliveries.poll_generation,
      Err("HTTP 401 Unauthenticated"),
    ),
    emit,
  )
  assert_true(recovering.connecting)
  assert_eq(recovering.token, "")
  assert_eq(recovering.csrf_token, "")
  assert_eq(recovering.subject_ref, "")
  assert_eq(recovering.session_generation, 8L)
  assert_true(recovering.portal.api_keys.is_empty())
  assert_true(recovering.portal.deliveries.external_model is None)
  assert_eq(recovering.portal.error_message, None)
}

///|
test "stale delivery authentication failures cannot sign out a newer company scope" {
  let model = {
    ..gateway_auth_test_model(),
    token: "lnxs_current",
    session_generation: 7L,
    portal: @enterprise_ui.demo_state(),
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  for
    scope in [
      (
        6L,
        model.portal.selected_organization_id,
        model.portal.deliveries.poll_generation,
      ),
      (7L, Some("previous-company"), model.portal.deliveries.poll_generation),
      (
        7L,
        model.portal.selected_organization_id,
        model.portal.deliveries.poll_generation - 1L,
      ),
    ] {
    let (generation, organization, poll) = scope
    let (unchanged, _) = update(
      model,
      DeliveriesLoaded(
        generation,
        organization,
        poll,
        Err("HTTP 401 Unauthenticated"),
      ),
      emit,
    )
    assert_true(unchanged == model)
  }
  let (forbidden, _) = update(
    model,
    DeliveriesLoaded(
      7L,
      model.portal.selected_organization_id,
      model.portal.deliveries.poll_generation,
      Err("HTTP 403 Forbidden"),
    ),
    emit,
  )
  assert_eq(forbidden.token, model.token)
  assert_false(forbidden.portal.deliveries.loading)
  assert_eq(forbidden.portal.deliveries.error, Some("HTTP 403 Forbidden"))
}
