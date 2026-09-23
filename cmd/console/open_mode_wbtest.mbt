///|
/// Runs `check` with the two deployment metas stubbed, the way a browser would
/// present them, and restores whatever was there afterwards.
extern "js" fn with_console_metas(
  open_value : String,
  check : () -> Bool,
) -> Bool =
  #| (openValue, check) => {
  #|   const document = globalThis.document;
  #|   const location = globalThis.location;
  #|   try {
  #|     globalThis.location = {origin: 'http://console.example:4174'};
  #|     globalThis.document = {querySelector: selector =>
  #|       selector === 'meta[name="lunanexa-operator-open"]'
  #|         ? {getAttribute: () => openValue}
  #|         : null};
  #|     return check();
  #|   } finally {
  #|     if (document === undefined) delete globalThis.document; else globalThis.document = document;
  #|     if (location === undefined) delete globalThis.location; else globalThis.location = location;
  #|   }
  #| }

///|
/// The console skips its login gate only when the deployment declared itself
/// open. An empty meta is the committed default and must stay closed, and an
/// exact origin must match the page -- otherwise a page served from anywhere
/// else would inherit the deployment's operator authority.
test "only a declared open deployment skips the login gate" {
  assert_true(with_console_metas("*", () => deployment_console_open()))
  assert_true(
    with_console_metas("http://console.example:4174", () => {
      deployment_console_open()
    }),
  )
  assert_true(
    with_console_metas(
      "http://internal.example:4174,http://console.example:4174",
      () => deployment_console_open(),
    ),
  )
  assert_false(
    with_console_metas("http://other.example:4174", () => {
      deployment_console_open()
    }),
  )
  assert_false(with_console_metas("", () => deployment_console_open()))
}

///|
#warnings("-alert_unstable")
test "open deployment still offers explicit named operator login" {
  assert_true(
    with_console_metas("*", () => {
      let model = deferred_read_test_model(Overview)
      let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
      let (requested, _) = update_live(model, PersonalLoginRequested, emit)
      let html = @rabbita.render_to_string(() => {
        @rabbita.Val::constant(app_view(requested, emit))
      })
      requested.personal_login && html.contains("Operator login")
    }),
  )
}
