///|
/// Read-only operator aggregate. Conversion is not a payment assertion.
pub(all) struct TrialSummary {
  registered_trials : Int
  active_trials : Int
  expired_trials : Int
  converted_trials : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AnnouncementDraft {
  announcement_id : String
  tenant_ref : String
  title : String
  body : String
  expires_unix_ms : String
} derive(Debug, Eq)

///|
pub fn empty_announcement_draft() -> AnnouncementDraft {
  {
    announcement_id: "",
    tenant_ref: "",
    title: "",
    body: "",
    expires_unix_ms: "",
  }
}

///|
pub fn announcement_ready(draft : AnnouncementDraft) -> Bool {
  !draft.announcement_id.trim().is_empty() &&
  !draft.tenant_ref.trim().is_empty() &&
  !draft.title.trim().is_empty() &&
  draft.title.length() <= 256 &&
  !draft.body.trim().is_empty() &&
  draft.body.length() <= 256 &&
  !draft.expires_unix_ms.is_empty() &&
  draft.expires_unix_ms.iter().all(c => c >= '0' && c <= '9')
}

///|
fn trial_summary_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(class="account-self", [
    @html.h3(beginner_message(state.locale, TrialTitle)),
    match state.trial_summary {
      None =>
        @html.p(
          class="secondary",
          beginner_message(state.locale, TrialUnavailable),
        )
      Some(summary) =>
        @html.dl([
          @html.dt(
            localized(state.locale, "Registered trials", "试用注册总数"),
          ),
          @html.dd(summary.registered_trials.to_string()),
          @html.dt(localized(state.locale, "Active trials", "有效试用")),
          @html.dd(summary.active_trials.to_string()),
          @html.dt(localized(state.locale, "Expired trials", "已到期试用")),
          @html.dd(summary.expired_trials.to_string()),
          @html.dt(
            localized(state.locale, "Converted trials", "已转正试用"),
          ),
          @html.dd(summary.converted_trials.to_string()),
        ])
    },
    @html.p(class="secondary", beginner_message(state.locale, TrialBoundary)),
  ])
}

///|
fn announcement_field(
  id : String,
  label : String,
  value : String,
  maximum : Int,
  emit : @rabbita.Emit[ConsoleMessage]?,
  message : (String) -> ConsoleMessage,
) -> @rabbita.Html {
  @html.div(class="account-invite-field", [
    @html.label(for_=id, label),
    @html.input(
      id~,
      value~,
      maxlength=maximum,
      auto_complete=Off,
      on_input=text_command(emit, message),
    ),
  ])
}

///|
fn announcement_form(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let draft = state.announcement_draft
  @html.details(class="account-self", [
    @html.summary(beginner_message(state.locale, AnnouncementTitle)),
    @html.p(
      class="section-copy",
      beginner_message(state.locale, AnnouncementBoundary),
    ),
    announcement_field(
      "announcement-id",
      localized(
        state.locale,
        "Announcement ID (reuse to retry)",
        "公告编号（重试时复用）",
      ),
      draft.announcement_id,
      128,
      emit,
      value => AnnouncementIdChanged(value),
    ),
    announcement_field(
      "announcement-tenant",
      localized(state.locale, "Recipient tenant", "接收租户"),
      draft.tenant_ref,
      128,
      emit,
      value => AnnouncementTenantChanged(value),
    ),
    announcement_field(
      "announcement-title",
      localized(state.locale, "Title", "标题"),
      draft.title,
      256,
      emit,
      value => AnnouncementTitleChanged(value),
    ),
    announcement_field(
      "announcement-body",
      localized(
        state.locale,
        "Message (plain text, 256 characters)",
        "公告内容（纯文本，256 字符内）",
      ),
      draft.body,
      256,
      emit,
      value => AnnouncementBodyChanged(value),
    ),
    @html.div(class="account-invite-actions", [
      @html.span(
        localized(state.locale, "Keep visible for", "公告展示时长"),
      ),
      @html.button(
        type_="button",
        on_click=command(emit, AnnouncementLifetimeChosen(1)),
        localized(state.locale, "1 day", "1 天"),
      ),
      @html.button(
        type_="button",
        on_click=command(emit, AnnouncementLifetimeChosen(7)),
        localized(state.locale, "7 days", "7 天"),
      ),
      @html.button(
        type_="button",
        on_click=command(emit, AnnouncementLifetimeChosen(30)),
        localized(state.locale, "30 days", "30 天"),
      ),
    ]),
    @html.details([
      @html.summary(
        localized(
          state.locale,
          "Advanced expiry / retry value",
          "高级到期时间／重试值",
        ),
      ),
      announcement_field(
        "announcement-expiry",
        localized(
          state.locale,
          "Expires at (Unix milliseconds)",
          "到期时间（Unix 毫秒）",
        ),
        draft.expires_unix_ms,
        16,
        emit,
        value => AnnouncementExpiryChanged(value),
      ),
    ]),
    @html.button(
      type_="button",
      class="primary-button",
      disabled=state.loading ||
        !state.operator_authenticated ||
        !announcement_ready(draft),
      on_click=command(emit, SubmitAnnouncement),
      beginner_message(state.locale, PublishAnnouncement),
    ),
  ])
}
