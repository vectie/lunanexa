///|
priv struct AppModel {
  endpoint : String
  token : String
  subject_ref : String
  connecting : Bool
  demo_mode : Bool
  portal : @enterprise_ui.EnterpriseState
} derive(Eq)

///|
priv enum Outcome {
  Loaded(
    @portal.EnterpriseSelfView,
    Array[@enterprise_ui.EnterpriseCostCenterRow],
    String,
    Array[@portal.EnterpriseModelSummary],
    Array[@notifications.NotificationRecord],
    Array[@nodelease.CustomerExclusiveMachineView]
  )
  AgreementUpdated(@portal.PortalAgreement)
  LeaseCreated(@portal.EnterpriseLeaseRequest)
  NotificationRead(@notifications.NotificationRecord)
  MachineTerminated(@nodelease.CustomerExclusiveMachineView)
  Failed(@i18n.Locale, String)
}

///|
priv enum AppMessage {
  EndpointChanged(String)
  TokenChanged(String)
  SubjectChanged(String)
  Connect
  Portal(@enterprise_ui.EnterpriseMessage)
  Outcome(Outcome)
}

///|
extern "js" fn configured_endpoint() -> String =
  #| () => globalThis.LUNANEXA_API_ENDPOINT || globalThis.location?.origin || ""

///|
extern "js" fn demo_mode() -> Bool =
  #| () => {
  #|   try {
  #|     const value = new URL(globalThis.location.href).searchParams.get("demo");
  #|     return value === "1" || value === "true";
  #|   } catch (_) {
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn stored_locale_preference() -> String =
  #| () => {
  #|   try { return globalThis.localStorage?.getItem("lunanexa.locale") || ""; }
  #|   catch (_) { return ""; }
  #| }

///|
extern "js" fn commit_enterprise_locale(
  storage_value : String,
  language_tag : String,
  title : String,
) -> Unit =
  #| (storageValue, languageTag, title) => {
  #|   try { globalThis.localStorage?.setItem("lunanexa.locale", storageValue); }
  #|   catch (_) {}
  #|   try {
  #|     if (globalThis.document?.documentElement) {
  #|       globalThis.document.documentElement.lang = languageTag;
  #|     }
  #|     if (globalThis.document) globalThis.document.title = title;
  #|   } catch (_) {}
  #| }

///|
fn portal_copy(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
}

///|
fn apply_enterprise_locale(locale : @i18n.Locale) -> Unit {
  commit_enterprise_locale(
    locale.storage_value(),
    locale.language_tag(),
    portal_copy(
      locale, "LunaNexa | Enterprise Portal", "LunaNexa | 企业门户",
    ),
  )
}

///|
extern "js" fn current_unix_ms() -> Int64 = "() => BigInt(Date.now())"

///|
extern "js" fn random_identifier(prefix : String) -> String =
  #| prefix => `${prefix}-${crypto.randomUUID()}`

///|
extern "js" fn request_promise(
  verb : String,
  url : String,
  token : String,
  subject_ref : String,
  body : String,
) -> @js.Promise =
  #| async (verb, url, token, subject, body) => {
  #|   const headers = {
  #|     "Accept": "application/json",
  #|     "Content-Type": "application/json",
  #|     "Authorization": `Bearer ${token}`
  #|   };
  #|   if (subject) headers["X-LunaNexa-Subject"] = subject;
  #|   const response = await fetch(url, {
  #|     method: verb,
  #|     headers,
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|     body: verb === "GET" ? undefined : body
  #|   });
  #|   const text = await response.text();
  #|   if (!response.ok) {
  #|     let message = `HTTP ${response.status}`;
  #|     try { message = JSON.parse(text)?.error?.message || message; } catch (_) {}
  #|     throw new Error(message);
  #|   }
  #|   return text;
  #| }

///|
async fn request(
  verb : String,
  endpoint : String,
  path : String,
  token : String,
  subject_ref : String,
  body? : String = "",
) -> String {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  let value = request_promise(verb, "\{base}\{path}", token, subject_ref, body).wait()
  value.cast()
}

///|
async fn load_self(
  model : AppModel,
) -> (
  @portal.EnterpriseSelfView,
  Array[@enterprise_ui.EnterpriseCostCenterRow],
  String,
  Array[@portal.EnterpriseModelSummary],
  Array[@notifications.NotificationRecord],
  Array[@nodelease.CustomerExclusiveMachineView],
) {
  let body = request(
    "GET",
    model.endpoint,
    "/v1/portal/self",
    model.token,
    model.subject_ref,
  )
  let view : @portal.EnterpriseSelfView = @json.from_json(@json.parse(body))
  let commercial : @commercial.CommercialSnapshot? = try
    Some(
      @json.from_json(
        @json.parse(
          request(
            "GET",
            model.endpoint,
            "/v1/portal/self/commercial",
            model.token,
            model.subject_ref,
          ),
        ),
      ),
    )
  catch {
    _ => None
  } noraise {
    value => value
  }
  let models : Array[@portal.EnterpriseModelSummary] = try
    @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/portal/self/models",
          model.token,
          model.subject_ref,
        ),
      ),
    )
  catch {
    _ => []
  } noraise {
    value => value
  }
  let notifications : Array[@notifications.NotificationRecord] = try
    @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/notifications/self",
          model.token,
          model.subject_ref,
        ),
      ),
    )
  catch {
    _ => []
  } noraise {
    value => value
  }
  let machines : Array[@nodelease.CustomerExclusiveMachineView] = @json.from_json(
    @json.parse(
      request(
        "GET",
        model.endpoint,
        "/v1/machine-access/self",
        model.token,
        model.subject_ref,
      ),
    ),
  )
  let cost_centers : Array[@enterprise_ui.EnterpriseCostCenterRow] = match
    commercial {
    Some(snapshot) =>
      [
        for center in snapshot.cost_centers => {
          let projects = snapshot.projects.filter(project => {
            project.cost_center_id == center.cost_center_id
          })
          let entries = snapshot.ledger_entries.filter(entry => {
            entry.cost_center_id == center.cost_center_id
          })
          let mut minor_units = 0L
          let mut currency = ""
          let mut scale = 0
          for entry in entries {
            minor_units = minor_units + entry.amount.minor_units
            currency = entry.amount.currency
            scale = entry.amount.scale
          }
          {
            cost_center_id: center.cost_center_id,
            display_name: center.display_name,
            project_count: projects.length(),
            provisional_spend: if entries.length() == 0 {
              "—"
            } else {
              "\{currency} \{minor_units} minor units · scale \{scale}"
            },
            budget_posture: "\{snapshot.budgets.length()} budget policies",
          }
        }
      ]
    None => []
  }
  let provisional_spend = match commercial {
    Some(snapshot) if snapshot.ledger_entries.length() > 0 => {
      let first = snapshot.ledger_entries[0].amount
      let mut minor_units = 0L
      for entry in snapshot.ledger_entries {
        minor_units = minor_units + entry.amount.minor_units
      }
      "\{first.currency} \{minor_units} minor units · scale \{first.scale}"
    }
    _ => "—"
  }
  (view, cost_centers, provisional_spend, models, notifications, machines)
}

///|
async fn request_signature(
  model : AppModel,
  agreement_id : String,
) -> @portal.PortalAgreement {
  let mut selected : @portal.PortalAgreement? = None
  for value in model.portal.agreements {
    if value.agreement_id == agreement_id {
      selected = Some(value)
    }
  }
  guard selected is Some(agreement) else { fail("agreement is unavailable") }
  let body = @portal.SignatureRequest::{
      agreement_id,
      expected_generation: agreement.generation,
      idempotency_key: random_identifier("sign"),
    }
    .to_json()
    .stringify()
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/signature-requests",
    model.token,
    model.subject_ref,
    body~,
  )
  @json.from_json(@json.parse(response))
}

///|
fn requested_models(value : String) -> Array[String] {
  value
  .split(",")
  .map(part => part.trim().to_owned())
  .filter(part => part != "")
  .to_array()
}

///|
async fn submit_lease(model : AppModel) -> @portal.EnterpriseLeaseRequest {
  guard model.portal.membership is Some(membership) else {
    fail("enterprise membership is unavailable")
  }
  let identifier = random_identifier("lease-request")
  let body = @portal.LeaseRequestSubmission::{
      request_id: identifier,
      idempotency_key: random_identifier("submit"),
      tenant_ref: membership.tenant_ref,
      organization_id: membership.organization_id,
      project_id: model.portal.project_id.trim().to_owned(),
      unix_username: model.portal.unix_username.trim().to_owned(),
      starts_unix_ms: model.portal.starts_unix_ms,
      expires_unix_ms: model.portal.expires_unix_ms,
      requested_model_ids: requested_models(model.portal.model_ids),
      justification: model.portal.justification.trim().to_owned(),
    }
    .to_json()
    .stringify()
  let response = request(
    "POST",
    model.endpoint,
    "/v1/portal/lease-requests",
    model.token,
    model.subject_ref,
    body~,
  )
  @json.from_json(@json.parse(response))
}

///|
async fn mark_notification_read(
  model : AppModel,
  notification_id : String,
  generation : Int64,
) -> @notifications.NotificationRecord {
  let body = "{\"expected_generation\":\"\{generation}\"}"
  let response = request(
    "POST",
    model.endpoint,
    "/v1/notifications/self/\{notification_id}:read",
    model.token,
    model.subject_ref,
    body~,
  )
  @json.from_json(@json.parse(response))
}

///|
async fn terminate_machine_access(
  model : AppModel,
  lease_ref : String,
  generation : Int64,
  confirmation : String,
) -> @nodelease.CustomerExclusiveMachineView {
  let body = @nodelease.CustomerExclusiveLeaseTerminationRequest::{
      expected_generation: generation,
      confirmation,
      reason: "customer-requested",
    }
    .to_json()
    .stringify()
  let response = request(
    "POST",
    model.endpoint,
    "/v1/machine-access/self/\{lease_ref}:terminate",
    model.token,
    model.subject_ref,
    body~,
  )
  @json.from_json(@json.parse(response))
}

///|
fn load_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try load_self(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to load enterprise access: \{Repr(error)}",
            "无法加载企业访问权限：\{Repr(error)}",
          ),
        )
    } noraise {
      (view, cost_centers, provisional_spend, models, notifications, machines) =>
        Loaded(
          view, cost_centers, provisional_spend, models, notifications, machines,
        )
    }
  })
}

///|
fn notification_read_command(
  model : AppModel,
  notification_id : String,
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try mark_notification_read(model, notification_id, generation) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to update notification: \{Repr(error)}",
            "无法更新通知：\{Repr(error)}",
          ),
        )
    } noraise {
      value => NotificationRead(value)
    }
  })
}

///|
fn machine_termination_command(
  model : AppModel,
  lease_ref : String,
  generation : Int64,
  confirmation : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try
      terminate_machine_access(model, lease_ref, generation, confirmation)
    catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to terminate machine access: \{Repr(error)}",
            "无法终止机器访问：\{Repr(error)}",
          ),
        )
    } noraise {
      value => MachineTerminated(value)
    }
  })
}

///|
fn replace_machine(
  values : Array[@nodelease.CustomerExclusiveMachineView],
  updated : @nodelease.CustomerExclusiveMachineView,
) -> Array[@nodelease.CustomerExclusiveMachineView] {
  [
    for value in values => {
      if value.lease_ref == updated.lease_ref {
        updated
      } else {
        value
      }
    }
  ]
}

///|
fn replace_notification(
  values : Array[@notifications.NotificationRecord],
  updated : @notifications.NotificationRecord,
) -> Array[@notifications.NotificationRecord] {
  [
    for value in values => {
      if value.event.notification_id == updated.event.notification_id {
        updated
      } else {
        value
      }
    }
  ]
}

///|
fn signature_command(
  model : AppModel,
  agreement_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try request_signature(model, agreement_id) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Signature request was rejected: \{Repr(error)}",
            "签署请求被拒绝：\{Repr(error)}",
          ),
        )
    } noraise {
      value => AgreementUpdated(value)
    }
  })
}

///|
fn lease_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try submit_lease(model) catch {
      error =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Lease request was rejected: \{Repr(error)}",
            "租用申请被拒绝：\{Repr(error)}",
          ),
        )
    } noraise {
      value => LeaseCreated(value)
    }
  })
}

///|
fn replace_agreement(
  values : Array[@portal.PortalAgreement],
  updated : @portal.PortalAgreement,
) -> Array[@portal.PortalAgreement] {
  [
    for value in values => {
      if value.agreement_id == updated.agreement_id {
        updated
      } else {
        value
      }
    }
  ]
}

///|
fn update(
  model : AppModel,
  message : AppMessage,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  match message {
    EndpointChanged(value) => ({ ..model, endpoint: value }, @rabbita.none)
    TokenChanged(value) => ({ ..model, token: value }, @rabbita.none)
    SubjectChanged(value) => ({ ..model, subject_ref: value }, @rabbita.none)
    Connect =>
      if model.token == "" || model.endpoint == "" {
        (
          {
            ..model,
            portal: {
              ..model.portal,
              error_message: Some(
                portal_copy(
                  model.portal.locale,
                  "A scoped token and controller endpoint are required.",
                  "需要限定范围的令牌和控制器端点。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        ({ ..model, connecting: true }, load_command(model, emit))
      }
    Portal(LocaleChanged(locale)) => {
      apply_enterprise_locale(locale)
      (
        { ..model, portal: model.portal.update(LocaleChanged(locale)) },
        @rabbita.none,
      )
    }
    Portal(SignAgreement(agreement_id)) => {
      let next = model.portal.update(SignAgreement(agreement_id))
      if model.demo_mode {
        let agreements = [
          for agreement in next.agreements => {
            if agreement.agreement_id == agreement_id {
              {
                ..agreement,
                state: SignatureRequested,
                generation: agreement.generation + 1L,
                signer_subject_ref: Some("subject-demo"),
                signature_request_receipt: Some("portal-signature:demo"),
              }
            } else {
              agreement
            }
          }
        ]
        (
          {
            ..model,
            portal: {
              ..next,
              agreements,
              loading: false,
              success_message: Some(
                portal_copy(
                  next.locale,
                  "Signature ceremony requested. Execution waits for verified provider evidence.",
                  "已发起签署流程。协议将在验证提供商证据后执行。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        (
          { ..model, portal: next },
          signature_command(model, agreement_id, emit),
        )
      }
    }
    Portal(SubmitLease) => {
      let next = model.portal.update(SubmitLease)
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..next,
              loading: false,
              success_message: Some(
                portal_copy(
                  next.locale,
                  "Lease request submitted to the operator queue.",
                  "租用申请已提交至运维审核队列。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        ({ ..model, portal: next }, lease_command(model, emit))
      }
    }
    Portal(MarkNotificationRead(notification_id, generation)) =>
      if model.demo_mode {
        let notifications = [
          for value in model.portal.notifications => {
            if value.event.notification_id == notification_id {
              {
                ..value,
                lifecycle: Read,
                generation: value.generation + 1L,
                updated_unix_ms: current_unix_ms(),
              }
            } else {
              value
            }
          }
        ]
        ({ ..model, portal: { ..model.portal, notifications, } }, @rabbita.none)
      } else {
        (
          model,
          notification_read_command(model, notification_id, generation, emit),
        )
      }
    Portal(
      MachineAccess(ConfirmTermination(lease_ref, generation, confirmation))
    ) => {
      let portal = model.portal.update(
        MachineAccess(ConfirmTermination(lease_ref, generation, confirmation)),
      )
      if model.demo_mode {
        (
          {
            ..model,
            portal: {
              ..portal,
              machine_access: { ..portal.machine_access, loading: false },
            },
          },
          @rabbita.none,
        )
      } else {
        (
          { ..model, portal, },
          machine_termination_command(
            model, lease_ref, generation, confirmation, emit,
          ),
        )
      }
    }
    Portal(portal_message) =>
      ({ ..model, portal: model.portal.update(portal_message) }, @rabbita.none)
    Outcome(
      Loaded(
        view,
        cost_centers,
        provisional_spend,
        models,
        notifications,
        machines
      )
    ) =>
      (
        {
          ..model,
          connecting: false,
          portal: {
            ..model.portal,
            membership: Some(view.membership),
            agreements: view.agreements,
            lease_requests: view.lease_requests,
            cost_centers,
            provisional_spend,
            model_catalog: models,
            notifications,
            machine_access: {
              ..model.portal.machine_access,
              machines,
              loading: false,
            },
            loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Enterprise access loaded.",
                "企业访问权限已加载。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(AgreementUpdated(agreement)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            agreements: replace_agreement(model.portal.agreements, agreement),
            loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Signature ceremony requested. Execution waits for verified provider evidence.",
                "已发起签署流程。协议将在验证提供商证据后执行。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(LeaseCreated(request)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            lease_requests: [request, ..model.portal.lease_requests],
            loading: false,
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Lease request submitted to the operator queue.",
                "租用申请已提交至运维审核队列。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(NotificationRead(notification)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            notifications: replace_notification(
              model.portal.notifications,
              notification,
            ),
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Notification marked as read.",
                "通知已标记为已读。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(MachineTerminated(machine)) =>
      (
        {
          ..model,
          portal: {
            ..model.portal,
            machine_access: {
              ..model.portal.machine_access,
              machines: replace_machine(
                model.portal.machine_access.machines,
                machine,
              ),
              confirmation_lease_ref: None,
              confirmation_text: "",
              loading: false,
            },
            success_message: Some(
              portal_copy(
                model.portal.locale,
                "Machine access termination started.",
                "机器访问终止流程已开始。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(Failed(dispatched_locale, message)) =>
      (
        {
          ..model,
          connecting: false,
          portal: {
            ..model.portal,
            loading: false,
            success_message: None,
            error_message: Some(
              if dispatched_locale == model.portal.locale {
                message
              } else {
                portal_copy(
                  model.portal.locale,
                  "The enterprise operation failed. Retry the operation.",
                  "企业操作失败。请重试。",
                )
              },
            ),
          },
        },
        @rabbita.none,
      )
  }
}

///|
fn app_view(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Html {
  let ready = model.portal.membership is Some(_)
  let locale = model.portal.locale
  let connection_styles =
    #|.portal-connection{position:fixed;z-index:50;right:1rem;top:1rem;width:min(28rem,calc(100vw - 2rem));border:1px solid #2b4654;border-radius:.7rem;background:#0b1720;color:#edf7f3;box-shadow:0 20px 70px rgba(0,0,0,.45)}.portal-connection summary{padding:.75rem 1rem;cursor:pointer;font-weight:800}.portal-connection-body{display:grid;gap:.65rem;padding:0 1rem 1rem}.portal-connection label{display:block;margin-bottom:.25rem;color:#9db0b6;font-size:.7rem}.portal-connection input{width:100%;min-height:2.6rem;padding:.55rem .65rem;border:1px solid #35505f;border-radius:.45rem;background:#071218;color:#edf7f3}.portal-connection button{min-height:2.6rem;border:1px solid #35bd8d;border-radius:.45rem;background:#7ee0bd;color:#06251a;font-weight:850}.portal-connection p{margin:0;color:#91a7ad;font-size:.7rem}.demo-flag{position:fixed;z-index:45;right:1rem;top:1rem;padding:.45rem .65rem;border:1px solid rgba(126,224,189,.3);border-radius:999px;background:#0b1720;color:#7ee0bd;font:800 .65rem/1 system-ui}
  @html.div([
    @html.style_tag(connection_styles),
    if model.demo_mode {
      @html.div(
        class="demo-flag",
        portal_copy(
          locale, "DEMO · enterprise portal", "演示 · 企业门户",
        ),
      )
    } else {
      @html.details(
        class="portal-connection",
        open=!ready,
        attrs=@html.Attrs::build().aria_label(
          portal_copy(locale, "Enterprise connection", "企业门户连接"),
        ),
        [
          @html.summary(
            if ready {
              portal_copy(
                locale, "Enterprise connection ready", "企业连接就绪",
              )
            } else {
              portal_copy(
                locale, "Connect enterprise identity", "连接企业身份",
              )
            },
          ),
          @html.div(class="portal-connection-body", [
            @html.div([
              @html.label(
                for_="portal-token",
                portal_copy(
                  locale, "Scoped inference token", "限定范围的推理令牌",
                ),
              ),
              @html.input(
                id="portal-token",
                input_type=Password,
                value=model.token,
                auto_complete=Off,
                on_input=emit.map(value => TokenChanged(value)),
              ),
            ]),
            @html.div([
              @html.label(
                for_="portal-subject",
                portal_copy(
                  locale, "Opaque subject (loopback acceptance only)", "不透明主体引用（仅限环回验收）",
                ),
              ),
              @html.input(
                id="portal-subject",
                value=model.subject_ref,
                maxlength=256,
                auto_complete=Off,
                on_input=emit.map(value => SubjectChanged(value)),
              ),
            ]),
            @html.div([
              @html.label(
                for_="portal-endpoint",
                portal_copy(locale, "Controller endpoint", "控制器端点"),
              ),
              @html.input(
                id="portal-endpoint",
                value=model.endpoint,
                on_input=emit.map(value => EndpointChanged(value)),
              ),
            ]),
            @html.button(
              type_="button",
              disabled=model.connecting || model.token == "",
              on_click=emit(Connect),
              if model.connecting {
                portal_copy(locale, "Connecting…", "正在连接…")
              } else {
                portal_copy(locale, "Connect / refresh", "连接 / 刷新")
              },
            ),
            @html.p(
              portal_copy(
                locale, "Credentials remain in this page's browser memory and are never sent to a managed GPU node.",
                "凭据仅保留在此页面的浏览器内存中，绝不会发送到受管 GPU 节点。",
              ),
            ),
          ]),
        ],
      )
    },
    @enterprise_ui.interactive_view(
      model.portal,
      emit.map(message => Portal(message)),
    ),
  ])
}

///|
fn main {
  let is_demo = demo_mode()
  let initial_locale = @i18n.parse_locale(stored_locale_preference())
  apply_enterprise_locale(initial_locale)
  @rabbita.elmish(
    model={
      endpoint: configured_endpoint(),
      token: "",
      subject_ref: "",
      connecting: false,
      demo_mode: is_demo,
      portal: if is_demo {
        { ..@enterprise_ui.demo_state(), locale: initial_locale }
      } else {
        {
          ..@enterprise_ui.default_state(current_unix_ms()),
          locale: initial_locale,
        }
      },
    },
    view=app_view,
    update~,
  ).mount("app")
}
