///|
fn safe_connection_command(
  username : String,
  host : String,
  port : Int,
) -> String? {
  try @credential.connection_command(username, host, port) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
// Reuse the credential authority's strict username/hostname/port validation.
// The validated destination cannot contain shell quotes or command syntax.
// An explicit loopback bind avoids inheriting a GatewayPorts wildcard default.
fn tunnel_command(username : String, host : String, port : Int) -> String? {
  match safe_connection_command(username, host, port) {
    None => None
    Some(_) =>
      Some(
        "ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8181:127.0.0.1:8181 -p \{port} '\{username}@\{host}'",
      )
  }
}

///|
fn copy_detail(
  _locale : @i18n.Locale,
  emit : @rabbita.Emit[MachineAccessMessage]?,
  value : String,
  label : String,
) -> @rabbita.Html {
  @html.button(
    type_="button",
    class="quiet-button",
    on_click=command(emit, CopyAccessDetail(value)),
    label,
  )
}

///|
fn next_steps(
  state : MachineAccessState,
  emit : @rabbita.Emit[MachineAccessMessage]?,
  machine : @nodelease.CustomerExclusiveMachineView,
  access : @credential.CredentialHandoffRedemption,
) -> @rabbita.Html {
  @html.section(class="machine-next-steps", [
    @html.h4(machine_message(state.locale, NextSteps)),
    @html.p(machine_message(state.locale, VerifyFingerprint)),
    @html.p(machine_message(state.locale, TunnelHelp)),
    match tunnel_command(machine.username, access.host_alias, access.ssh_port) {
      Some(tunnel) =>
        @html.div([
          @html.code(tunnel),
          copy_detail(
            state.locale,
            emit,
            tunnel,
            machine_message(state.locale, CopyTunnel),
          ),
        ])
      None => @html.p(machine_message(state.locale, InvalidConnection))
    },
    @html.p(machine_message(state.locale, DownloadReminder)),
    @html.strong(
      remaining_label(state.locale, machine.expires_unix_ms, state.now_unix_ms),
    ),
  ])
}
