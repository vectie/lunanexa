///|
test "failed commerce action releases both loading states and keeps selected order drafts" {
  let base = deferred_read_test_model(OfflineCommerce)
  let state = @offline_commerce.demo_state(English, OperatorCommerce)
  let model = {
    ..base,
    console: {
      ..base.console,
      loading: true,
      offline_commerce: { ..state, loading: true, undertaking_quantity: "3", },
    },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (failed, _) = update_live(
    model,
    Outcome(ActionFailed(English, "Commerce setup is not ready")),
    emit,
  )
  assert_false(failed.console.loading)
  assert_false(failed.console.offline_commerce.loading)
  assert_eq(failed.console.offline_commerce.orders, state.orders)
  assert_eq(
    failed.console.offline_commerce.selected_order_id,
    state.selected_order_id,
  )
  assert_eq(failed.console.offline_commerce.undertaking_quantity, "3")
  assert_true(failed.console.error_message is Some(_))
}
