///|
test "failed contract operation clears loading so a corrected submission can retry" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    csrf_token: "",
    subject_ref: "",
    connecting: false,
    bootstrap_started: true,
    demo_mode: true,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    portal: {
      ..@enterprise_ui.demo_state(),
      contract_documents: {
        ..@enterprise_ui.demo_state().contract_documents,
        loading: true,
      },
    },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (failed, _) = update(
    model,
    Outcome(Failed(English, "HTTP 409: stale revision")),
    emit,
  )
  assert_false(failed.portal.contract_documents.loading)
  assert_true(failed.portal.contract_documents.error_message is Some(_))
}
