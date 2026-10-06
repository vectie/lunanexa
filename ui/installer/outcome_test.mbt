///|
fn preview_ready_state() -> @installer.InstallerState {
  let state = @installer.update(
    @installer.default_state(locale=English),
    DeploymentTargetChanged("local-colima"),
  )
  @installer.update(
    state,
    SessionTokenChanged("fixture-session-value-00000000000"),
  )
}

///|
test "unknown command outcome retains output and requires manual review" {
  let ready = preview_ready_state()
  let preview = @installer.update(ready, PreviewRequested)
  let verified = @installer.update(preview, RunFinished(true, 0))
  let confirmed = @installer.update(
    verified,
    ConfirmationChanged("RECONCILE SIMULATION"),
  )
  assert_true(@installer.can_apply(confirmed))
  let running = @installer.update(confirmed, ApplyRequested)
  assert_false(running.preview_verified)
  assert_eq(@installer.update(running, ApplyRequested), running)
  assert_eq(@installer.update(running, PreviewRequested), running)
  let received = @installer.update(
    running,
    TerminalLine("[stage] selected scope inspected"),
  )
  let unknown = @installer.update(received, RunOutcomeUnknown)
  assert_eq(unknown.run_state, OutcomeUnknown)
  assert_false(@installer.is_running(unknown))
  assert_false(@installer.can_apply(unknown))
  assert_false(@installer.can_preview(unknown))
  assert_false(unknown.preview_verified)
  assert_true(
    unknown.terminal_lines.join("\n").contains("selected scope inspected"),
  )
  assert_false(unknown.terminal_lines.join("\n").contains("[blocked]"))
  assert_eq(@installer.update(unknown, ApplyRequested), unknown)
  assert_eq(@installer.update(unknown, PreviewRequested), unknown)
  let html = @installer.render(unknown)
  assert_true(html.contains("Outcome unknown"))
  assert_true(html.contains("Do not repeat Apply"))
  assert_true(html.contains("companion terminal"))
  assert_true(html.contains("Kubernetes/node status"))
  assert_true(html.contains("allow a new preview"))
  let cleared = @installer.update(unknown, ClearTerminal)
  assert_true(@installer.render(cleared).contains("Outcome unknown"))
  assert_false(@installer.can_preview(cleared))
  let chinese = @installer.update(unknown, LocaleChanged(ChineseSimplified))
  assert_true(
    @installer.render(chinese).contains("确认结果前请勿再次应用"),
  )
  let reviewed = @installer.update(unknown, RecoveryReviewed)
  assert_eq(reviewed.run_state, Idle)
  assert_eq(reviewed.form.confirmation, "")
  assert_eq(reviewed.terminal_lines, unknown.terminal_lines)
  assert_true(@installer.can_preview(reviewed))
  assert_false(@installer.can_apply(reviewed))
}

///|
test "invalid or repeated requests do not start another run" {
  let invalid = @installer.default_state(locale=English)
  assert_eq(@installer.update(invalid, PreviewRequested), invalid)
  assert_eq(@installer.update(invalid, ApplyRequested), invalid)
  let ready = preview_ready_state()
  assert_eq(@installer.update(ready, ApplyRequested), ready)
  let running = @installer.update(ready, PreviewRequested)
  assert_eq(@installer.update(running, PreviewRequested), running)
  assert_eq(@installer.update(running, ApplyRequested), running)
}

///|
test "confirmed completion keeps the received log for success and failure" {
  for ok in [true, false] {
    let running = @installer.update(preview_ready_state(), PreviewRequested)
    let received = @installer.update(
      running,
      TerminalLine("[redacted sensitive output]"),
    )
    let finished = @installer.update(
      received,
      RunFinished(ok, if ok { 0 } else { 7 }),
    )
    assert_true(
      finished.terminal_lines.join("\n").contains("[redacted sensitive output]"),
    )
    assert_eq(finished.preview_verified, ok)
    assert_eq(finished.run_state, if ok { Succeeded } else { Failed })
  }
}
