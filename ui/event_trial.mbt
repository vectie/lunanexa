///|
pub(all) struct EventTrialDraft {
  event_id : String
  title : String
  starts : String
  expires : String
  maximum_users : String
  maximum_requests : String
  max_input_bytes : String
  max_output_tokens : String
  model : String
  nodes : Array[String]
  per_node_concurrency : String
} derive(Eq)

///|
pub extend EventTrialDraft with Eq::{equal, not_equal}

///|
pub(all) struct EventTrialPanel {
  draft : EventTrialDraft
  events : Array[@event_trial.View]?
  public_origin : String
  now_unix_ms : Int64
  editing : Bool
} derive(Eq)

///|
pub extend EventTrialPanel with Eq::{equal, not_equal}

///|
pub fn empty_event_trial_panel() -> EventTrialPanel {
  {
    events: None,
    public_origin: "",
    now_unix_ms: 0L,
    editing: false,
    draft: {
      event_id: "",
      title: "未来社区 · 七天算力试用",
      starts: "",
      expires: "",
      maximum_users: "30",
      maximum_requests: "200",
      max_input_bytes: "8192",
      max_output_tokens: "8192",
      model: "",
      nodes: [],
      per_node_concurrency: "0",
    },
  }
}

///|
pub(all) enum EventTrialMessage {
  Field(String, String)
  ToggleNode(String)
  New
  Edit(String)
  Save
  SetRegistration(String, Bool)
} derive(Eq)

///|
pub extend EventTrialMessage with Eq::{equal, not_equal}

///|
fn event_field(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
  key : String,
  label : String,
  value : String,
  kind : String,
) -> @rabbita.Html {
  @html.div(class="account-invite-field", [
    @html.label(for_="event-\{key}", label),
    @html.input(
      id="event-\{key}",
      value~,
      maxlength=128,
      attrs=@html.Attrs::build()
        .type_(kind)
        .disabled(state.loading || !state.operator_authenticated),
      on_input=text_command(emit, value => EventTrial(Field(key, value))),
    ),
  ])
}

///|
fn event_trial_panel(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let panel = state.event_trial
  let draft = panel.draft
  let disabled = state.loading ||
    !state.operator_authenticated ||
    panel.events is None
  @html.section(class="access-package-panel", [
    @html.h3(localized(state.locale, "Event trial mode", "活动体验模式")),
    @html.p(
      class="section-copy",
      localized(
        state.locale,
        "Registration → private workspace → shared models. One gateway entry, selected independent replicas; saving a draft does not allocate machines.",
        "注册 → 个人工作空间 → 共享模型。统一网关入口、选定节点独立副本；保存草稿不会分配或抢占机器。",
      ),
    ),
    event_entry_card(state),
    match panel.events {
      None =>
        @html.p(
          class="secondary",
          localized(
            state.locale,
            "Event policy unavailable. Refresh or update the controller.",
            "活动策略暂不可用，请刷新或更新控制器。",
          ),
        )
      Some(events) =>
        @html.div(
          class="access-package-list",
          [
            for event in events if panel.now_unix_ms == 0L ||
            !event.policy.ended(panel.now_unix_ms) => {
              @html.article(class="access-package-card", [
                @html.h4(event.policy.title),
                @html.p(
                  localized(
                    state.locale,
                    "\{event.registered_users}/\{if event.policy.maximum_users == 0 { "Unlimited" } else { event.policy.maximum_users.to_string() }} registered · \{event.ready_nodes.length()}/\{event.policy.node_ids.length()} replicas ready",
                    "\{event.registered_users}/\{if event.policy.maximum_users == 0 { "不限名额" } else { event.policy.maximum_users.to_string() }} 人已注册 · \{event.ready_nodes.length()}/\{event.policy.node_ids.length()} 副本就绪",
                  ),
                ),
                @html.p(
                  if event.policy.expires_unix_ms == 0L {
                    localized(
                      state.locale,
                      "Ongoing enrollment · 7 days per person from activation",
                      "长期开放报名 · 每人自开通起 7 天",
                    )
                  } else {
                    "\{@contractdoc.format_unix_ms_beijing(event.policy.starts_unix_ms)} — \{@contractdoc.format_unix_ms_beijing(event.policy.expires_unix_ms)}"
                  },
                ),
                @html.p(
                  if event.policy.maximum_requests == 0L {
                    localized(
                      state.locale,
                      "Unlimited calls · usage recorded per person",
                      "调用次数不限 · 按人记录用量",
                    )
                  } else {
                    "\{event.policy.maximum_requests} 次／人"
                  },
                ),
                @html.p(event.policy.allowed_models.join(", ")),
                @html.p(
                  localized(
                    state.locale,
                    "Output ceiling: \{event.policy.output_budget()} tokens per request",
                    "单次输出上限：\{event.policy.output_budget()} tokens",
                  ),
                ),
                @html.p(
                  if event.policy.registration_open {
                    localized(
                      state.locale,
                      "Registration enabled within the event window",
                      "活动时间内允许注册",
                    )
                  } else {
                    localized(
                      state.locale,
                      "Registration closed / draft",
                      "注册关闭／草稿",
                    )
                  },
                ),
                @html.ul([ for blocker in event.blockers => @html.li(blocker) ]),
                @html.div(class="account-invite-actions", [
                  @html.button(
                    type_="button",
                    disabled~,
                    on_click=command(
                      emit,
                      EventTrial(Edit(event.policy.event_id)),
                    ),
                    localized(state.locale, "Review settings", "查看设置"),
                  ),
                  @html.button(
                    type_="button",
                    disabled=disabled ||
                      (
                        !event.policy.registration_open &&
                        !event.blockers.is_empty()
                      ),
                    on_click=command(
                      emit,
                      EventTrial(
                        SetRegistration(
                          event.policy.event_id,
                          !event.policy.registration_open,
                        ),
                      ),
                    ),
                    if event.policy.registration_open {
                      localized(
                        state.locale,
                        "Close registration",
                        "关闭注册",
                      )
                    } else {
                      localized(
                        state.locale,
                        "Open registration",
                        "开放注册",
                      )
                    },
                  ),
                ]),
              ])
            }
          ],
        )
    },
    @html.details(
      [
        @html.summary(
          localized(state.locale, "Ended events", "已结束活动"),
        ),
        ..panel.events
        .unwrap_or([])
        .filter(event => {
          panel.now_unix_ms > 0L && event.policy.ended(panel.now_unix_ms)
        })
        .map(event => {
          @html.div(class="record-card", [
            @html.strong(event.policy.title),
            @html.p(
              "\{event.registered_users}/\{event.policy.maximum_users} · \{@contractdoc.format_unix_ms_beijing(event.policy.expires_unix_ms)}",
            ),
            @html.button(
              type_="button",
              disabled~,
              on_click=command(emit, EventTrial(Edit(event.policy.event_id))),
              localized(state.locale, "Review settings", "查看设置"),
            ),
          ])
        }),
      ],
    ),
    @html.details(attrs=@html.Attrs::build().open(panel.editing), [
      @html.summary(
        localized(
          state.locale,
          "Create / review event",
          "新建／查看活动",
        ),
      ),
      @html.p(
        class="section-copy",
        localized(
          state.locale,
          "Beijing time (UTC+8). Leave the end blank for ongoing enrollment: each person gets 7 days from activation, never renewed by login. A specified end keeps a fixed event deadline. Closing registration does not revoke existing grants.",
          "时间均为北京时间（UTC+8）。结束时间留空即长期开放，每人自开通起 7 天，重新登录不续期；填写结束时间则统一到期。关闭注册不撤销已发放权限。",
        ),
      ),
      @html.div(class="access-package-form-grid", [
        event_field(
          state,
          emit,
          "output_tokens",
          localized(
            state.locale,
            "Maximum output tokens per request",
            "单次输出上限（tokens）",
          ),
          draft.max_output_tokens,
          "number",
        ),
        @html.p(
          class="secondary",
          localized(
            state.locale,
            "1–131072 tokens, subject to global and model context limits. Saving synchronizes existing active trial accounts; expiry, usage and concurrency stay unchanged. Larger limits allow longer answers but do not force longer output.",
            "可设 1–131072，仍受平台及模型上下文限制。保存后同步现有有效试用账号，不改变到期时间、用量和并发；上限提高不代表每次都会输出这么多。",
          ),
        ),
        event_field(
          state,
          emit,
          "input_bytes",
          localized(
            state.locale,
            "Input payload bytes (not tokens; max 65536)",
            "单次输入字节（非 token，最高 65536）",
          ),
          draft.max_input_bytes,
          "number",
        ),
        event_field(
          state,
          emit,
          "title",
          localized(state.locale, "Event name", "活动名称"),
          draft.title,
          "text",
        ),
        event_field(
          state,
          emit,
          "starts",
          localized(
            state.locale,
            "Starts (Beijing)",
            "开始时间（北京）",
          ),
          draft.starts,
          "datetime-local",
        ),
        event_field(
          state,
          emit,
          "expires",
          localized(
            state.locale,
            "Ends (blank = ongoing, 7 days per person)",
            "结束时间（留空＝长期开放，每人7天）",
          ),
          draft.expires,
          "datetime-local",
        ),
        event_field(
          state,
          emit,
          "users",
          localized(
            state.locale,
            "Participant cap (0 = unlimited)",
            "参与人数上限（0＝不限）",
          ),
          draft.maximum_users,
          "number",
        ),
        event_field(
          state,
          emit,
          "requests",
          localized(
            state.locale,
            "Requests per participant (0 = unlimited)",
            "每人请求总量（0＝不限）",
          ),
          draft.maximum_requests,
          "number",
        ),
        @html.div(class="account-invite-field", [
          @html.label(
            for_="event-model",
            localized(state.locale, "Shared text model", "共享文本模型"),
          ),
          @html.select(
            id="event-model",
            disabled~,
            on_change=text_command(emit, value => {
              EventTrial(Field("model", value))
            }),
            [
              @html.option(
                value="",
                selected=draft.model == "",
                localized(
                  state.locale,
                  "Select an approved alias",
                  "选择已批准的模型别名",
                ),
              ),
              ..[
                for model in state.models if model.alias_name != "" => {
                  @html.option(
                    value=model.alias_name,
                    selected=draft.model == model.alias_name,
                    model.alias_name,
                  )
                }
              ],
            ],
          ),
        ]),
      ]),
      @html.h4(
        localized(
          state.locale,
          "Select one to four trial machines",
          "选择 1–4 台体验池机器",
        ),
      ),
      @html.div(
        class="account-invite-actions",
        [
          for node in state.nodes if node.usage_pool == "trial" => {
            @html.button(
              type_="button",
              class=if draft.nodes.contains(node.node_id) {
                "primary-button"
              } else {
                "secondary-button"
              },
              disabled=disabled ||
                (
                  !draft.nodes.contains(node.node_id) &&
                  draft.nodes.length() >= 4
                ),
              attrs=@html.Attrs::build().aria_pressed(
                if draft.nodes.contains(node.node_id) {
                  "true"
                } else {
                  "false"
                },
              ),
              on_click=command(emit, EventTrial(ToggleNode(node.node_id))),
              node.node_id,
            )
          }
        ],
      ),
      @html.p(
        class="secondary",
        localized(
          state.locale,
          "\{draft.nodes.length()}/4 selected. Machine pool changes remain a separate operator action.",
          "已选择 \{draft.nodes.length()}/4 台；调整机器用途需要单独操作。",
        ),
      ),
      event_field(
        state,
        emit,
        "concurrency",
        localized(
          state.locale,
          "Per-replica concurrency cap (0 = no event cap)",
          "每个副本的并发上限（0 = 不设活动限制）",
        ),
        draft.per_node_concurrency,
        "number",
      ),
      @html.p(
        class="secondary",
        localized(
          state.locale,
          "Input bytes and output tokens follow the settings above and synchronize to active trial accounts. Saving does not change concurrency, expiry, usage, SSH, admin roles or machine access.",
          "单次输入字节、输出 token 按上方设置执行，并同步现有有效试用账号。保存不改变并发、到期时间、累计用量，也不授予 SSH、管理或独占机器权限。",
        ),
      ),
      @html.div(class="account-invite-actions", [
        @html.button(
          type_="button",
          disabled~,
          on_click=command(emit, EventTrial(New)),
          localized(state.locale, "New event", "新建活动"),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=disabled ||
            draft.nodes.is_empty() ||
            draft.nodes.length() > 4 ||
            draft.model == "" ||
            draft.starts == "",
          on_click=command(emit, EventTrial(Save)),
          if panel.events.map_or(false, events => {
              events.any(event => event.policy.event_id == draft.event_id)
            }) {
            localized(
              state.locale,
              "Save changes (keep registration state)",
              "保存修改（保持注册状态）",
            )
          } else {
            localized(
              state.locale,
              "Save draft (registration closed)",
              "保存草稿（注册关闭）",
            )
          },
        ),
      ]),
    ]),
  ])
}
