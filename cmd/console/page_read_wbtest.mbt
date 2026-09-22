///|
#warnings("-alert_unstable")
test "deferred page loading and errors never masquerade as empty leases" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let initial = deferred_read_test_model(Leases)
  let (pending, _) = schedule_deferred_reads(initial, Leases, emit)
  assert_true(console_page_read_state(pending) is Loading)
  let render = fn(model : AppModel) {
    @rabbita.render_to_string(() => {
      @rabbita.Val::constant(
        @ui.interactive_view(
          model.console,
          emit.map(message => Console(message)),
          page_read_state=console_page_read_state(model),
        ),
      )
    })
  }
  let loading = render(pending)
  assert_true(loading.contains("Loading this page"))
  assert_false(loading.contains("0 machines leased"))
  assert_false(loading.contains("No compute or workspace leases"))
  let (failed, _) = update_live(
    pending,
    Outcome(DeferredReadFailed(AccessReads)),
    emit,
  )
  assert_true(console_page_read_state(failed) is Failed)
  let failure = render(failed)
  assert_true(failure.contains("Retry loading"))
  assert_false(failure.contains("0 machines leased"))
  let (retry, _) = schedule_deferred_reads(failed, Leases, emit)
  assert_true(console_page_read_state(retry) is Loading)
  let groups = retry.console_read_groups.copy()
  groups.set(AccessReads, true)
  let ready = { ..retry, console_read_groups: groups, }
  assert_true(console_page_read_state(ready) is Ready)
  assert_true(render(ready).contains("0 machines leased"))
  assert_true(console_page_read_state({ ..initial, demo_mode: true, }) is Ready)
  assert_true(console_page_read_state(deferred_read_test_model(Nodes)) is Ready)
}
