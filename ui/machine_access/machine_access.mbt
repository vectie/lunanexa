///|
pub(all) struct MachineAccessState {
  locale : @i18n.Locale
  machines : Array[@nodelease.CustomerExclusiveMachineView]
  redeemed_credentials : Array[@credential.CredentialHandoffRedemption]
  now_unix_ms : Int64
  confirmation_lease_ref : String?
  confirmation_text : String
  loading : Bool
} derive(Eq)

///|
pub extend MachineAccessState with Eq::{not_equal, equal}

///|
pub(all) enum MachineAccessMessage {
  CopyAccessDetail(String)
  RedeemCredential(String, Int64)
  BeginTermination(String)
  ConfirmationChanged(String)
  CancelTermination
  ConfirmTermination(String, Int64, String)
} derive(Eq)

///|
pub extend MachineAccessMessage with Eq::{not_equal, equal}

///|
pub fn default_state(locale : @i18n.Locale) -> MachineAccessState {
  {
    locale,
    machines: [],
    redeemed_credentials: [],
    now_unix_ms: 0L,
    confirmation_lease_ref: None,
    confirmation_text: "",
    loading: false,
  }
}

///|
pub fn MachineAccessState::update(
  self : MachineAccessState,
  message : MachineAccessMessage,
) -> MachineAccessState {
  match message {
    CopyAccessDetail(_) => self
    RedeemCredential(_, _) => { ..self, loading: true, }
    BeginTermination(lease_ref) =>
      {
        ..self,
        confirmation_lease_ref: Some(lease_ref),
        confirmation_text: "",
      }
    ConfirmationChanged(value) => { ..self, confirmation_text: value, }
    CancelTermination =>
      { ..self, confirmation_lease_ref: None, confirmation_text: "", }
    ConfirmTermination(_, _, _) => { ..self, loading: true, }
  }
}

///|
pub fn MachineAccessState::with_redeemed_credential(
  self : MachineAccessState,
  value : @credential.CredentialHandoffRedemption,
) -> MachineAccessState {
  let next = [
    for current in self.redeemed_credentials if current.lease_ref !=
    value.lease_ref => current
  ]
  next.push(value)
  { ..self, redeemed_credentials: next, loading: false, }
}

///|
fn remaining_label(
  locale : @i18n.Locale,
  expires : Int64,
  now : Int64,
) -> String {
  // Counts are runtime values, not translatable catalog keys. Keep the
  // explicitly typed numeric templates here; all static copy lives in messages.
  let remaining = expires - now
  if remaining <= 0L {
    machine_message(locale, LabelExpired)
  } else if remaining < 3600000L {
    let minutes = (remaining + 59999L) / 60000L
    copy(locale, "\{minutes} min remaining", "剩余 \{minutes} 分钟")
  } else if remaining < 86400000L {
    let hours = (remaining + 3599999L) / 3600000L
    copy(locale, "\{hours} hr remaining", "剩余 \{hours} 小时")
  } else {
    let days = (remaining + 86399999L) / 86400000L
    copy(locale, "\{days} day(s) remaining", "剩余 \{days} 天")
  }
}

///|
fn cleanup_label(
  locale : @i18n.Locale,
  state : @nodelease.ExclusiveLeaseState,
) -> String {
  match state {
    Active | Requested | Reserved | Provisioning =>
      machine_message(locale, LabelScheduledatclosure)
    Expiring | Draining | RevokingAccess =>
      machine_message(locale, LabelAccesslockdowninprogress)
    Sanitizing => machine_message(locale, LabelVerifiedcleanupinprogress)
    Completed => machine_message(locale, LabelCleanupverified)
    Cancelled => machine_message(locale, LabelCancelledbeforeaccess)
    Quarantined => machine_message(locale, SafetyHoldSupport)
  }
}

///|
fn copy(locale : @i18n.Locale, english : String, chinese : String) -> String {
  @i18n.copy(locale, english, chinese)
}

///|
fn command(
  emit : @rabbita.Emit[MachineAccessMessage]?,
  message : MachineAccessMessage,
) -> @rabbita.Cmd {
  match emit {
    Some(send) => send(message)
    None => @rabbita.none
  }
}

///|
fn text_command(
  emit : @rabbita.Emit[MachineAccessMessage]?,
) -> @rabbita.Emit[String] {
  match emit {
    Some(send) => send.map(value => ConfirmationChanged(value))
    None => Emit(_ => @rabbita.none)
  }
}

///|
fn state_label(
  locale : @i18n.Locale,
  state : @nodelease.ExclusiveLeaseState,
) -> String {
  match state {
    Requested => machine_message(locale, LabelRequested)
    Reserved => machine_message(locale, LabelReserved)
    Provisioning => machine_message(locale, LabelPreparingaccess)
    Active => machine_message(locale, LabelReady)
    Expiring => machine_message(locale, LabelExpiring)
    Draining => machine_message(locale, LabelEndingsessions)
    RevokingAccess => machine_message(locale, LabelRevokingaccess)
    Sanitizing => machine_message(locale, LabelSanitizing)
    Completed => machine_message(locale, LabelCompleted)
    Cancelled => machine_message(locale, LabelCancelled)
    Quarantined => machine_message(locale, LabelSafetyhold)
  }
}

///|
fn reachability_label(
  locale : @i18n.Locale,
  reachability : @nodelease.CustomerMachineReachability,
) -> String {
  match reachability {
    Online => machine_message(locale, LabelOnline)
    Delayed => machine_message(locale, LabelStatusdelayed)
    Unknown => machine_message(locale, LabelStatuspending)
  }
}

///|
fn handoff_label(
  locale : @i18n.Locale,
  state : @nodelease.CustomerCredentialHandoffState,
) -> String {
  match state {
    Pending => machine_message(locale, CredentialPreparation)
    Available => machine_message(locale, LabelReadytoredeem)
    Recoverable => machine_message(locale, RecoverableDetailsStatus)
    Closed => machine_message(locale, LabelClosed)
  }
}

///|
fn termination_panel(
  state : MachineAccessState,
  emit : @rabbita.Emit[MachineAccessMessage]?,
  machine : @nodelease.CustomerExclusiveMachineView,
) -> @rabbita.Html {
  guard state.confirmation_lease_ref == Some(machine.lease_ref) &&
    machine.termination_confirmation is Some(expected) else {
    return @html.button(
      type_="button",
      class="danger-button",
      disabled=state.loading,
      on_click=command(emit, BeginTermination(machine.lease_ref)),
      machine_message(state.locale, LabelEndaccessearly),
    )
  }
  @html.div(class="termination-panel", [
    @html.strong(machine_message(state.locale, ImmediateSessionInterruption)),
    @html.p(machine_message(state.locale, TerminationConsequences)),
    @html.label(
      for_="machine-termination-confirmation",
      machine_message(state.locale, LabelTypetheexactconfirmation),
    ),
    @html.code(expected),
    @html.input(
      id="machine-termination-confirmation",
      value=state.confirmation_text,
      auto_complete=Off,
      on_input=text_command(emit),
    ),
    @html.div(class="termination-actions", [
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=command(emit, CancelTermination),
        machine_message(state.locale, LabelCancel),
      ),
      @html.button(
        type_="button",
        class="danger-button",
        disabled=state.loading || state.confirmation_text != expected,
        on_click=command(
          emit,
          ConfirmTermination(machine.lease_ref, machine.generation, expected),
        ),
        machine_message(state.locale, LabelTerminateaccess),
      ),
    ]),
  ])
}

///|
fn machine_card(
  state : MachineAccessState,
  emit : @rabbita.Emit[MachineAccessMessage]?,
  machine : @nodelease.CustomerExclusiveMachineView,
) -> @rabbita.Html {
  let redeemed = state.redeemed_credentials
    .iter()
    .find_first(value => {
      value.lease_ref == machine.lease_ref &&
      value.generation == machine.generation
    })
  @html.article(class="machine-access-card", [
    @html.div(class="machine-heading", [
      @html.div([
        @html.p(
          class="machine-eyebrow",
          machine_message(state.locale, LabelEXCLUSIVEMACHINE),
        ),
        @html.h3(machine.machine_ref),
      ]),
      @html.span(
        class="machine-state",
        state_label(state.locale, machine.state),
      ),
    ]),
    @html.dl(class="machine-facts", [
      @html.div([
        @html.dt(machine_message(state.locale, LabelLivestatus)),
        @html.dd(reachability_label(state.locale, machine.reachability)),
      ]),
      @html.div([
        @html.dt(machine_message(state.locale, LabelUsername)),
        @html.dd(machine.username),
      ]),
      @html.div([
        @html.dt(machine_message(state.locale, LabelAccessprofile)),
        @html.dd(machine_message(state.locale, LabelFullmachineSSH)),
      ]),
      @html.div([
        @html.dt(machine_message(state.locale, MachineTime)),
        @html.dd(
          class="machine-mono",
          remaining_label(
            state.locale,
            machine.expires_unix_ms,
            state.now_unix_ms,
          ),
        ),
      ]),
      @html.div([
        @html.dt(machine_message(state.locale, LabelCredentialhandoff)),
        @html.dd(handoff_label(state.locale, machine.credential_handoff.state)),
      ]),
      @html.div([
        @html.dt(machine_message(state.locale, HandoffTime)),
        @html.dd(
          remaining_label(
            state.locale,
            match redeemed {
              Some(access) => access.valid_until_unix_ms
              None => machine.credential_handoff.valid_until_unix_ms
            },
            state.now_unix_ms,
          ),
        ),
        @html.dd(machine_message(state.locale, HandoffLimit)),
      ]),
      @html.div([
        @html.dt(machine_message(state.locale, LabelCleanupsupport)),
        @html.dd(cleanup_label(state.locale, machine.state)),
      ]),
    ]),
    @html.p(
      class="machine-muted",
      machine_message(state.locale, ExpiryConsequences),
    ),
    @html.p(
      class="machine-muted",
      machine_message(state.locale, ContinuedAccess),
    ),
    if redeemed is Some(access) &&
      machine.state == Active &&
      machine.expires_unix_ms > state.now_unix_ms &&
      access.valid_until_unix_ms > state.now_unix_ms &&
      !access.raw_secret_included &&
      (
        machine.credential_handoff.state == Available ||
        machine.credential_handoff.state == Recoverable
      ) {
      @html.section(class="handoff-panel", [
        @html.strong(machine_message(state.locale, LabelSSHaccessdetails)),
        @html.dl(class="credential-details", [
          @html.div([
            @html.dt(machine_message(state.locale, LabelHost)),
            @html.dd(access.host_alias),
            @html.dd(
              copy_detail(
                state.locale,
                emit,
                access.host_alias,
                machine_message(state.locale, CopyHost),
              ),
            ),
          ]),
          @html.div([
            @html.dt(machine_message(state.locale, LabelPort)),
            @html.dd(access.ssh_port.to_string()),
            @html.dd(
              copy_detail(
                state.locale,
                emit,
                access.ssh_port.to_string(),
                machine_message(state.locale, CopyPort),
              ),
            ),
          ]),
          @html.div([
            @html.dt(machine_message(state.locale, LabelUsername)),
            @html.dd(machine.username),
            @html.dd(
              copy_detail(
                state.locale,
                emit,
                machine.username,
                machine_message(state.locale, CopyUsername),
              ),
            ),
          ]),
          @html.div([
            @html.dt(machine_message(state.locale, LabelHostkey)),
            @html.dd(class="machine-mono", access.host_key_fingerprint),
          ]),
        ]),
        copy_detail(
          state.locale,
          emit,
          access.host_key_fingerprint,
          machine_message(state.locale, CopyFingerprint),
        ),
        match
          safe_connection_command(
            machine.username,
            access.host_alias,
            access.ssh_port,
          ) {
          Some(connection) =>
            @html.div([
              @html.code(connection),
              copy_detail(
                state.locale,
                emit,
                connection,
                machine_message(state.locale, CopyConnection),
              ),
            ])
          None => @html.p(machine_message(state.locale, InvalidConnection))
        },
        @html.p(machine_message(state.locale, CredentialIssuerExplanation)),
        @html.a(
          class="issuer-link",
          href=access.issuer_redirect_url,
          machine_message(state.locale, ContinueToIssuer),
        ),
        next_steps(state, emit, machine, access),
      ])
    } else if machine.state == Active &&
      machine.expires_unix_ms > state.now_unix_ms &&
      machine.credential_handoff.valid_until_unix_ms > state.now_unix_ms &&
      (
        redeemed is None ||
        (
          redeemed is Some({ valid_until_unix_ms, .. }) &&
          valid_until_unix_ms > state.now_unix_ms
        )
      ) &&
      (
        machine.credential_handoff.state == Available ||
        machine.credential_handoff.state == Recoverable
      ) {
      @html.section(class="handoff-panel", [
        @html.strong(
          if machine.credential_handoff.state == Recoverable {
            machine_message(state.locale, RecoverableDetailsHeading)
          } else {
            machine_message(state.locale, LabelAccessisready)
          },
        ),
        @html.p(
          machine_message(
            state.locale,
            if machine.credential_handoff.state == Recoverable {
              RecoveryExplanation
            } else {
              RedemptionExplanation
            },
          ),
        ),
        @html.button(
          type_="button",
          class="redeem-button",
          disabled=state.loading,
          on_click=command(
            emit,
            RedeemCredential(machine.lease_ref, machine.generation),
          ),
          if machine.credential_handoff.state == Recoverable {
            machine_message(state.locale, LabelRecoveraccessdetails)
          } else {
            machine_message(state.locale, LabelRedeemSSHaccess)
          },
        ),
      ])
    } else {
      @html.p(
        class="machine-muted",
        machine_message(state.locale, HandoffUnavailableExplanation),
      )
    },
    if machine.can_terminate {
      termination_panel(state, emit, machine)
    } else {
      @html.p(
        class="machine-muted",
        machine_message(state.locale, AccessClosingExplanation),
      )
    },
  ])
}

///|
fn machine_access_view(
  state : MachineAccessState,
  emit : @rabbita.Emit[MachineAccessMessage]?,
) -> @rabbita.Html {
  let stylesheet =
    #|.machine-access-view{display:grid;gap:1rem}.machine-access-intro{display:flex;justify-content:space-between;gap:1rem;align-items:end}.machine-access-intro h2{margin:0}.machine-access-intro p{max-width:48rem;margin:.35rem 0 0;color:var(--muted,#64748b)}.machine-count{padding:.28rem .55rem;border:1px solid var(--line,#d6dde4);border-radius:999px}.machine-access-list{display:grid;gap:.85rem}.machine-access-card{display:grid;gap:1rem;padding:1.15rem;border:1px solid var(--line,#d6dde4);border-radius:.8rem;background:var(--panel,#fff)}.machine-heading{display:flex;justify-content:space-between;gap:1rem;align-items:start}.machine-heading h3{margin:.15rem 0 0}.machine-eyebrow{margin:0;color:var(--mint,#168363);font-size:.68rem;font-weight:850;letter-spacing:.08em}.machine-state{padding:.3rem .55rem;border:1px solid var(--line,#d6dde4);border-radius:999px;color:var(--amber,#9a6700)}.machine-facts{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:.6rem;margin:0}.machine-facts>div{padding:.75rem;border:1px solid var(--line,#d6dde4);border-radius:.6rem}.machine-facts dt,.credential-details dt{color:var(--muted,#64748b);font-size:.68rem}.machine-facts dd,.credential-details dd{margin:.2rem 0 0;overflow-wrap:anywhere}.machine-mono,.machine-access-card code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.handoff-panel,.termination-panel{padding:.85rem;border-left:3px solid var(--mint,#168363);background:rgba(22,131,99,.08)}.credential-details{display:grid;grid-template-columns:2fr 1fr 4fr;gap:.6rem}.handoff-panel p,.termination-panel p,.machine-muted{color:var(--muted,#64748b)}.termination-panel{border-left-color:#d85b5b;background:rgba(216,91,91,.08);display:grid;gap:.55rem}.termination-panel p{margin:0}.termination-panel input{min-height:2.75rem;padding:.6rem .7rem;border:1px solid var(--line,#d6dde4);border-radius:.45rem;background:var(--bg,#fff);color:inherit}.termination-actions{display:flex;justify-content:flex-end;gap:.5rem}.danger-button,.quiet-button,.redeem-button{min-height:2.75rem;padding:.6rem .85rem;border:1px solid #d85b5b;border-radius:.5rem;background:#d85b5b;color:#fff;font:inherit;font-weight:800;cursor:pointer}.redeem-button{border-color:var(--mint,#168363);background:var(--mint,#168363)}.danger-button:disabled,.redeem-button:disabled{opacity:.45;cursor:not-allowed}.quiet-button{border-color:var(--line,#d6dde4);background:transparent;color:inherit}.machine-empty{padding:1rem;border:1px dashed var(--line,#d6dde4);border-radius:.7rem;color:var(--muted,#64748b)}@media(max-width:70rem){.machine-facts{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:38rem){.machine-access-intro,.machine-heading{align-items:stretch;flex-direction:column}.machine-facts,.credential-details{grid-template-columns:1fr}.termination-actions{display:grid}}@media(prefers-reduced-motion:reduce){.machine-access-view *{transition:none!important;animation:none!important}}
  @html.section(class="machine-access-view", [
    @html.style_tag(stylesheet),
    @html.header(class="machine-access-intro", [
      @html.div([
        @html.h2(machine_message(state.locale, LabelMymachineaccess)),
        @html.p(machine_message(state.locale, ExclusiveAccessBoundary)),
      ]),
      @html.span(
        class="machine-count",
        copy(
          state.locale,
          "\{state.machines.length()} records",
          "\{state.machines.length()} 条记录",
        ),
      ),
    ]),
    if state.machines.length() == 0 {
      @html.p(
        class="machine-empty",
        machine_message(state.locale, NoAssignedMachine),
      )
    } else {
      @html.div(
        class="machine-access-list",
        [
          for machine in state.machines => machine_card(state, emit, machine)
        ],
      )
    },
  ])
}

///|
pub fn view(state : MachineAccessState) -> @rabbita.Html {
  machine_access_view(state, None)
}

///|
pub fn interactive_view(
  state : MachineAccessState,
  emit : @rabbita.Emit[MachineAccessMessage],
) -> @rabbita.Html {
  machine_access_view(state, Some(emit))
}

///|
#warnings("-alert_unstable")
pub fn render(state : MachineAccessState) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(view(state)))
}
