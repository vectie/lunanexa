///|
pub(all) struct MachineAccessState {
  locale : @i18n.Locale
  machines : Array[@nodelease.CustomerExclusiveMachineView]
  confirmation_lease_ref : String?
  confirmation_text : String
  loading : Bool
} derive(Eq)

///|
pub(all) enum MachineAccessMessage {
  BeginTermination(String)
  ConfirmationChanged(String)
  CancelTermination
  ConfirmTermination(String, Int64, String)
} derive(Eq)

///|
pub fn default_state(locale : @i18n.Locale) -> MachineAccessState {
  {
    locale,
    machines: [],
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
    BeginTermination(lease_ref) =>
      { ..self, confirmation_lease_ref: Some(lease_ref), confirmation_text: "" }
    ConfirmationChanged(value) => { ..self, confirmation_text: value }
    CancelTermination =>
      { ..self, confirmation_lease_ref: None, confirmation_text: "" }
    ConfirmTermination(_, _, _) => { ..self, loading: true }
  }
}

///|
fn copy(locale : @i18n.Locale, english : String, chinese : String) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
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
    Requested => copy(locale, "Requested", "已申请")
    Reserved => copy(locale, "Reserved", "已预留")
    Provisioning => copy(locale, "Preparing access", "正在准备访问")
    Active => copy(locale, "Ready", "已就绪")
    Expiring => copy(locale, "Expiring", "即将到期")
    Draining => copy(locale, "Ending sessions", "正在结束会话")
    RevokingAccess => copy(locale, "Revoking access", "正在撤销访问")
    Sanitizing => copy(locale, "Sanitizing", "正在清理")
    Completed => copy(locale, "Completed", "已结束")
    Cancelled => copy(locale, "Cancelled", "已取消")
    Quarantined => copy(locale, "Safety hold", "安全隔离")
  }
}

///|
fn reachability_label(
  locale : @i18n.Locale,
  reachability : @nodelease.CustomerMachineReachability,
) -> String {
  match reachability {
    Online => copy(locale, "Online", "在线")
    Delayed => copy(locale, "Status delayed", "状态延迟")
    Unknown => copy(locale, "Status pending", "状态待确认")
  }
}

///|
fn handoff_label(
  locale : @i18n.Locale,
  state : @nodelease.CustomerCredentialHandoffState,
) -> String {
  match state {
    Pending =>
      copy(locale, "Available after provisioning", "配置完成后可用")
    Available => copy(locale, "Ready to redeem", "可领取")
    Closed => copy(locale, "Closed", "已关闭")
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
      copy(state.locale, "End access early", "提前结束访问"),
    )
  }
  @html.div(class="termination-panel", [
    @html.strong(
      copy(
        state.locale,
        "This interrupts sessions immediately",
        "这将立即中断会话",
      ),
    ),
    @html.p(
      copy(
        state.locale,
        "New logins close, credentials are revoked, and the machine stays unavailable until sanitization succeeds.",
        "新登录将被关闭，凭据会被撤销；机器仅在清理成功后才会恢复可用。",
      ),
    ),
    @html.label(
      for_="machine-termination-confirmation",
      copy(
        state.locale,
        "Type the exact confirmation",
        "请输入完整确认文字",
      ),
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
        copy(state.locale, "Cancel", "取消"),
      ),
      @html.button(
        type_="button",
        class="danger-button",
        disabled=state.loading || state.confirmation_text != expected,
        on_click=command(
          emit,
          ConfirmTermination(machine.lease_ref, machine.generation, expected),
        ),
        copy(state.locale, "Terminate access", "终止访问"),
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
  @html.article(class="machine-access-card", [
    @html.div(class="machine-heading", [
      @html.div([
        @html.p(
          class="machine-eyebrow",
          copy(state.locale, "EXCLUSIVE MACHINE", "独占机器"),
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
        @html.dt(copy(state.locale, "Live status", "实时状态")),
        @html.dd(reachability_label(state.locale, machine.reachability)),
      ]),
      @html.div([
        @html.dt(copy(state.locale, "Username", "用户名")),
        @html.dd(machine.username),
      ]),
      @html.div([
        @html.dt(copy(state.locale, "Starts", "开始时间")),
        @html.dd(class="machine-mono", machine.starts_unix_ms.to_string()),
      ]),
      @html.div([
        @html.dt(
          copy(state.locale, "Expires automatically", "自动到期时间"),
        ),
        @html.dd(class="machine-mono", machine.expires_unix_ms.to_string()),
      ]),
      @html.div([
        @html.dt(copy(state.locale, "Credential handoff", "凭据交接")),
        @html.dd(handoff_label(state.locale, machine.credential_handoff.state)),
      ]),
    ]),
    if machine.credential_handoff.state == Available &&
      machine.credential_handoff.handoff_ref is Some(handoff_ref) {
      @html.section(class="handoff-panel", [
        @html.strong(copy(state.locale, "Access is ready", "访问已就绪")),
        @html.p(
          copy(
            state.locale,
            "Redeem the short-lived SSH certificate through your approved credential authority. No password or private key is displayed here.",
            "请通过已批准的凭据机构领取短期 SSH 证书。此处不会显示密码或私钥。",
          ),
        ),
        @html.code(handoff_ref),
      ])
    } else {
      @html.p(
        class="machine-muted",
        copy(
          state.locale,
          "Credential handoff is unavailable until provisioning completes, and closes automatically at expiry or termination.",
          "凭据交接仅在配置完成后可用，并会在到期或终止时自动关闭。",
        ),
      )
    },
    if machine.can_terminate {
      termination_panel(state, emit, machine)
    } else {
      @html.p(
        class="machine-muted",
        copy(
          state.locale,
          "Access is closing or closed. The machine remains fenced until revocation and sanitization are verified.",
          "访问正在关闭或已关闭。机器将在撤销访问并验证清理完成前保持隔离。",
        ),
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
    #|.machine-access-view{display:grid;gap:1rem}.machine-access-intro{display:flex;justify-content:space-between;gap:1rem;align-items:end}.machine-access-intro h2{margin:0}.machine-access-intro p{max-width:48rem;margin:.35rem 0 0;color:var(--muted,#64748b)}.machine-count{padding:.28rem .55rem;border:1px solid var(--line,#d6dde4);border-radius:999px}.machine-access-list{display:grid;gap:.85rem}.machine-access-card{display:grid;gap:1rem;padding:1.15rem;border:1px solid var(--line,#d6dde4);border-radius:.8rem;background:var(--panel,#fff)}.machine-heading{display:flex;justify-content:space-between;gap:1rem;align-items:start}.machine-heading h3{margin:.15rem 0 0}.machine-eyebrow{margin:0;color:var(--mint,#168363);font-size:.68rem;font-weight:850;letter-spacing:.08em}.machine-state{padding:.3rem .55rem;border:1px solid var(--line,#d6dde4);border-radius:999px;color:var(--amber,#9a6700)}.machine-facts{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:.6rem;margin:0}.machine-facts>div{padding:.75rem;border:1px solid var(--line,#d6dde4);border-radius:.6rem}.machine-facts dt{color:var(--muted,#64748b);font-size:.68rem}.machine-facts dd{margin:.2rem 0 0;overflow-wrap:anywhere}.machine-mono,.machine-access-card code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.handoff-panel,.termination-panel{padding:.85rem;border-left:3px solid var(--mint,#168363);background:rgba(22,131,99,.08)}.handoff-panel p,.termination-panel p,.machine-muted{color:var(--muted,#64748b)}.termination-panel{border-left-color:#d85b5b;background:rgba(216,91,91,.08);display:grid;gap:.55rem}.termination-panel p{margin:0}.termination-panel input{min-height:2.75rem;padding:.6rem .7rem;border:1px solid var(--line,#d6dde4);border-radius:.45rem;background:var(--bg,#fff);color:inherit}.termination-actions{display:flex;justify-content:flex-end;gap:.5rem}.danger-button,.quiet-button{min-height:2.75rem;padding:.6rem .85rem;border:1px solid #d85b5b;border-radius:.5rem;background:#d85b5b;color:#fff;font:inherit;font-weight:800;cursor:pointer}.danger-button:disabled{opacity:.45;cursor:not-allowed}.quiet-button{border-color:var(--line,#d6dde4);background:transparent;color:inherit}.machine-empty{padding:1rem;border:1px dashed var(--line,#d6dde4);border-radius:.7rem;color:var(--muted,#64748b)}@media(max-width:70rem){.machine-facts{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:38rem){.machine-access-intro,.machine-heading{align-items:stretch;flex-direction:column}.machine-facts{grid-template-columns:1fr}.termination-actions{display:grid}}@media(prefers-reduced-motion:reduce){.machine-access-view *{transition:none!important;animation:none!important}}
  @html.section(class="machine-access-view", [
    @html.style_tag(stylesheet),
    @html.header(class="machine-access-intro", [
      @html.div([
        @html.h2(copy(state.locale, "My machine access", "我的机器访问")),
        @html.p(
          copy(
            state.locale,
            "Follow provisioning, live reachability, credential handoff, automatic expiry, and verified cleanup without exposing physical cluster topology.",
            "查看配置、实时连通性、凭据交接、自动到期与清理验证，同时不会暴露物理集群拓扑。",
          ),
        ),
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
        copy(
          state.locale,
          "No exclusive machine access has been assigned to your identity.",
          "您的身份尚未获分配独占机器访问权限。",
        ),
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
