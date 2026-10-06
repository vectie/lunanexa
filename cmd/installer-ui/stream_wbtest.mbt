///|
#external
type StreamFixture

///|
extern "js" fn install_stream_fixture(mode : String) -> StreamFixture =
  #| (mode) => {
  #|   const originalFetch = globalThis.fetch;
  #|   const originalDocument = globalThis.document;
  #|   const log = {textContent: "", scrollTop: 0, scrollHeight: 0};
  #|   const fixture = {originalFetch, originalDocument, log, requests: 0};
  #|   const line = (text) => `data: ${JSON.stringify({kind: "line", text})}\n\n`;
  #|   const terminal = (ok, exit_code) => `data: ${JSON.stringify({kind: "complete", ok, exit_code})}\n\n`;
  #|   globalThis.document = {querySelector: () => log};
  #|   if (mode === "dom-failure") {
  #|     globalThis.document = {querySelector() { throw new Error("synthetic DOM failure"); }};
  #|   }
  #|   globalThis.fetch = async (url, options) => {
  #|     fixture.requests++;
  #|     if (url !== "http://127.0.0.1:4198/v1/install:run" || options.method !== "POST") {
  #|       throw new Error("unexpected fixture request");
  #|     }
  #|     if (mode === "post-transport") throw new Error("synthetic transport failure");
  #|     const status = mode.startsWith("http-") ? Number(mode.slice(5)) : 200;
  #|     const chunks = [line("[stage] received safe output")];
  #|     if (mode === "success" || mode === "terminal-disconnect") chunks.push(terminal(true, 0));
  #|     if (mode === "failure") chunks.push(terminal(false, 7));
  #|     if (mode === "malformed") chunks.push("data: {broken\n\n");
  #|     if (mode === "invalid-terminal") chunks.push(terminal(true, 7));
  #|     if (mode === "wrong-terminal-type") chunks.push(terminal("true", 0));
  #|     if (mode === "truncated-terminal") chunks.push("data: {\"kind\":\"complete\"");
  #|     if (mode === "line-limit") for (let i = 0; i < 501; i++) chunks.push(line(`line-${i}`));
  #|     if (mode === "byte-limit") for (let i = 0; i < 260; i++) chunks.push(line("x".repeat(4096)));
  #|     if (mode === "framing-limit") chunks.push("x".repeat(1048577));
  #|     if (mode === "redacted") chunks.push(line("Bearer fixture-session-value-00000000000"));
  #|     if (mode === "crlf-boundary") {
  #|       chunks.push('data: {"kind":"line","text":"split CRLF"}\r');
  #|       chunks.push('\n\r');
  #|       chunks.push('\n' + terminal(true, 0));
  #|     }
  #|     const byteSplit = ["split-unicode", "dom-failure", "cleanup-failure"].includes(mode);
  #|     if (byteSplit) chunks.push(line("safe unicode 🌙"), terminal(true, 0));
  #|     const bytes = byteSplit ? new TextEncoder().encode(chunks.join("")) : null;
  #|     let index = 0;
  #|     const reader = {
  #|       async read() {
  #|         if (bytes) {
  #|           if (index < bytes.length) return {value: bytes.slice(index, ++index), done: false};
  #|           throw new Error("must return at terminal before later transport failure");
  #|         }
  #|         if (index < chunks.length) return {value: new TextEncoder().encode(chunks[index++]), done: false};
  #|         if (mode === "disconnect" || mode === "terminal-disconnect") throw new Error("synthetic disconnect");
  #|         return {done: true};
  #|       },
  #|       async cancel() { if (mode === "cleanup-failure") throw new Error("synthetic cancel failure"); },
  #|       releaseLock() { if (mode === "cleanup-failure") throw new Error("synthetic release failure"); }
  #|     };
  #|     return {ok: status === 200, status, body: mode === "no-body" ? null : {getReader: () => reader}};
  #|   };
  #|   return fixture;
  #| }

///|
extern "js" fn restore_stream_fixture(fixture : StreamFixture) -> Unit =
  #| (fixture) => {
  #|   globalThis.fetch = fixture.originalFetch;
  #|   globalThis.document = fixture.originalDocument;
  #| }

///|
extern "js" fn fixture_requests(fixture : StreamFixture) -> Int =
  #| (fixture) => fixture.requests

///|
extern "js" fn fixture_log(fixture : StreamFixture) -> String =
  #| (fixture) => fixture.log.textContent

///|
async fn stream_fixture_result(
  mode : String,
  endpoint? : String = "http://127.0.0.1:4198",
) -> RunResult {
  let fixture = install_stream_fixture(mode)
  defer restore_stream_fixture(fixture)
  let value = stream_install_promise(
    endpoint, "fixture-session-value-00000000000", "{}",
  ).wait()
  let text : String = value.cast()
  let result : RunResult = @json.from_json(@json.parse(text))
  assert_eq(
    fixture_requests(fixture),
    if mode == "invalid-endpoint" {
      0
    } else {
      1
    },
  )
  if result.lines.length() > 0 && mode != "dom-failure" {
    assert_true(fixture_log(fixture).contains(result.lines[0]))
  }
  assert_false(
    fixture_log(fixture).contains("fixture-session-value-00000000000"),
  )
  result
}

///|
// This is the sole async test that owns fetch/document fixtures. Keep all stream
// cases in this sequential harness: MoonBit runs separate async tests together.
// Each stream_fixture_result scope restores both globals before the next case.
async test "in-memory streams distinguish preflight rejection from unknown and confirmed outcomes without retry" {
  for
    mode in [
      "disconnect", "malformed", "invalid-terminal", "wrong-terminal-type", "truncated-terminal",
      "line-limit", "byte-limit", "framing-limit", "missing-terminal", "redacted",
    ] {
    let result = stream_fixture_result(mode)
    assert_eq(result.outcome, "unknown")
    assert_true(result.lines.contains("[stage] received safe output"))
    assert_true(result.lines.length() <= 500)
    assert_false(
      result.lines.join("\n").contains("fixture-session-value-00000000000"),
    )
    if mode == "redacted" {
      assert_true(result.lines.contains("[redacted sensitive output]"))
    }
    let state = apply_outcome(
      @installer_ui.default_state(locale=English),
      result,
    )
    assert_eq(state.run_state, OutcomeUnknown)
    assert_true(
      state.terminal_lines.join("\n").contains("[stage] received safe output"),
    )
    assert_false(state.terminal_lines.join("\n").contains("[blocked]"))
    assert_false(state.preview_verified)
  }
  for mode in ["post-transport", "no-body", "http-429", "http-500", "http-502"] {
    assert_eq(stream_fixture_result(mode).outcome, "unknown")
  }
  for mode in ["http-400", "http-401", "http-403", "http-404", "http-413"] {
    let result = stream_fixture_result(mode)
    assert_eq(result.outcome, "rejected")
    let state = apply_outcome(
      @installer_ui.default_state(locale=English),
      result,
    )
    assert_eq(state.run_state, Failed)
    assert_true(state.terminal_lines.join("\n").contains("[blocked]"))
    assert_false(state.preview_verified)
  }
  assert_eq(
    stream_fixture_result(
      "invalid-endpoint",
      endpoint="https://example.invalid",
    ).outcome,
    "rejected",
  )
  for
    mode in [
      "success", "failure", "terminal-disconnect", "crlf-boundary", "split-unicode",
      "dom-failure", "cleanup-failure",
    ] {
    let result = stream_fixture_result(mode)
    assert_eq(result.outcome, "complete")
    assert_eq(result.ok, mode != "failure")
    assert_true(result.lines.contains("[stage] received safe output"))
    if mode == "split-unicode" ||
      mode == "dom-failure" ||
      mode == "cleanup-failure" {
      assert_true(result.lines.contains("safe unicode 🌙"))
    }
    let state = apply_outcome(
      @installer_ui.default_state(locale=English),
      result,
    )
    assert_eq(
      state.run_state,
      if mode == "failure" {
        Failed
      } else {
        Succeeded
      },
    )
    assert_true(
      state.terminal_lines.join("\n").contains("[stage] received safe output"),
    )
  }
}

///|
test "application dispatch suppresses invalid duplicate and unresolved requests" {
  let empty = @installer_ui.default_state(locale=English)
  let ready = @installer_ui.update(
    @installer_ui.update(empty, DeploymentTargetChanged("local-colima")),
    SessionTokenChanged("fixture-session-value-00000000000"),
  )
  let running = @installer_ui.update(ready, PreviewRequested)
  let verified = @installer_ui.update(running, RunFinished(true, 0))
  let confirmed = @installer_ui.update(
    verified,
    ConfirmationChanged("RECONCILE SIMULATION"),
  )
  let applying = @installer_ui.update(confirmed, ApplyRequested)
  let unknown = @installer_ui.update(applying, RunOutcomeUnknown)
  for state in [empty, running, applying, unknown] {
    for message in [@installer_ui.PreviewRequested, ApplyRequested] {
      let (next, _) = update(state, Installer(message), _ => @rabbita.none)
      assert_eq(next, state)
    }
  }
  let (next, _) = update(ready, Installer(ApplyRequested), _ => @rabbita.none)
  assert_eq(next, ready)
}
