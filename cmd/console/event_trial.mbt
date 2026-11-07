///|
extern "js" fn event_time_ms(value : String) -> String =
  #| value => {
  #|   if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) return "";
  #|   const date = Date.parse(value + ":00+08:00");
  #|   return Number.isFinite(date) ? String(date) : "";
  #| }

///|
extern "js" fn event_local_time(value : String) -> String =
  #| value => new Date(Number(value) + 8 * 60 * 60 * 1000).toISOString().slice(0, 16)

///|
fn event_draft_policy(draft : @ui.EventTrialDraft) -> @event_trial.Policy raise {
  let starts = @string.parse_int64(event_time_ms(draft.starts))
  let policy : @event_trial.Policy = {
    event_id: if draft.event_id == "" {
      "event-\{starts}"
    } else {
      draft.event_id
    },
    title: draft.title.trim().to_owned(),
    starts_unix_ms: starts,
    expires_unix_ms: if draft.expires == "" {
      0L
    } else {
      @string.parse_int64(event_time_ms(draft.expires))
    },
    maximum_users: @string.parse_int(draft.maximum_users),
    maximum_requests: @string.parse_int64(draft.maximum_requests),
    max_input_bytes: Some(@string.parse_int(draft.max_input_bytes)),
    max_output_tokens: Some(@string.parse_int(draft.max_output_tokens)),
    allowed_models: [draft.model],
    node_ids: draft.nodes,
    per_node_concurrency: @string.parse_int(draft.per_node_concurrency),
    registration_open: false,
  }
  if !policy.valid() {
    fail("invalid event settings")
  }
  policy
}

///|
fn update_event_trial(
  model : AppModel,
  message : @ui.EventTrialMessage,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  guard model.console.operator_authenticated &&
    !model.demo_mode &&
    !model.console.loading else {
    return (model, @rabbita.none)
  }
  let panel = model.console.event_trial
  let draft = panel.draft
  let changed : @ui.EventTrialDraft = match message {
    Field(key, value) =>
      match key {
        "title" => { ..draft, title: value, }
        "starts" => { ..draft, starts: value, }
        "expires" => { ..draft, expires: value, }
        "users" => { ..draft, maximum_users: value, }
        "requests" => { ..draft, maximum_requests: value, }
        "input_bytes" => { ..draft, max_input_bytes: value, }
        "output_tokens" => { ..draft, max_output_tokens: value, }
        "model" => { ..draft, model: value, }
        "concurrency" => { ..draft, per_node_concurrency: value, }
        _ => draft
      }
    ToggleNode(id) => {
      if !model.console.nodes.any(n => {
          n.node_id == id && n.usage_pool == "trial"
        }) {
        return (model, @rabbita.none)
      }
      {
        ..draft,
        nodes: if draft.nodes.contains(id) {
          draft.nodes.filter(n => n != id)
        } else if draft.nodes.length() < 4 {
          draft.nodes + [id]
        } else {
          draft.nodes
        },
      }
    }
    New => @ui.empty_event_trial_panel().draft
    Edit(id) => {
      guard panel.events
        .unwrap_or([])
        .iter()
        .find_first(e => e.policy.event_id == id)
        is Some(view) else {
        return (model, @rabbita.none)
      }
      let policy = view.policy
      {
        event_id: id,
        title: policy.title,
        starts: event_local_time(policy.starts_unix_ms.to_string()),
        expires: if policy.expires_unix_ms == 0L {
          ""
        } else {
          event_local_time(policy.expires_unix_ms.to_string())
        },
        maximum_users: policy.maximum_users.to_string(),
        maximum_requests: policy.maximum_requests.to_string(),
        max_input_bytes: policy.input_budget().to_string(),
        max_output_tokens: policy.output_budget().to_string(),
        model: policy.allowed_models[0],
        nodes: policy.node_ids,
        per_node_concurrency: policy.per_node_concurrency.to_string(),
      }
    }
    Save | SetRegistration(_, _) => {
      let policy = try {
        match message {
          SetRegistration(id, open) => {
            guard panel.events
              .unwrap_or([])
              .iter()
              .find_first(e => e.policy.event_id == id)
              is Some(view) else {
              fail("event not loaded")
            }
            { ..view.policy, registration_open: open, }
          }
          _ => {
            let saved = panel.events
              .unwrap_or([])
              .iter()
              .find_first(e => e.policy.event_id == draft.event_id)
            {
              ..event_draft_policy(draft),
              registration_open: saved.map_or(false, e => {
                e.policy.registration_open
              }),
            }
          }
        }
      } catch {
        _ =>
          return (
            {
              ..model,
              console: {
                ..model.console,
                error_message: Some(
                  console_copy(
                    model.console.locale,
                    "Review the event window, limits, approved model and selected trial nodes.",
                    "请检查活动时间、人数和请求上限、模型以及选定体验池机器。",
                  ),
                ),
              },
            },
            @rabbita.none,
          )
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          ignore(
            request(
              "POST",
              model.endpoint,
              "/v1/accounts/event-trials",
              model.credential,
              body=Json(policy).stringify(),
            ),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Event change rejected. After enrollment, only registration and input/output budgets can change. Review the limits and replica readiness, then retry.",
                "活动修改未通过。首人注册后仅可调整注册开关和输入、输出上限；请检查额度范围、副本状态后重试。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Event policy saved; input/output limits synchronized to existing active trial workspaces. Expiry, usage, machines and concurrency are unchanged.",
                "已保存并同步现有有效试用账号的输入、输出上限；到期时间、用量、机器和并发设置未改变。",
              ),
            )
        }
      })
      return (
        {
          ..model,
          console: {
            ..model.console,
            loading: true,
            error_message: None,
            success_message: None,
            event_trial: {
              ..panel,
              draft: { ..draft, event_id: policy.event_id, },
            },
          },
        },
        cmd,
      )
    }
  }
  (
    {
      ..model,
      console: {
        ..model.console,
        event_trial: { ..panel, draft: changed, editing: true, },
      },
    },
    @rabbita.none,
  )
}
