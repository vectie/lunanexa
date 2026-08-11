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
    Array[@portal.EnterpriseModelSummary]
  )
  AgreementUpdated(@portal.PortalAgreement)
  LeaseCreated(@portal.EnterpriseLeaseRequest)
  Failed(String)
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
  (view, cost_centers, provisional_spend, models)
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
fn load_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try load_self(model) catch {
      error => Failed("Unable to load enterprise access: \{Repr(error)}")
    } noraise {
      (view, cost_centers, provisional_spend, models) =>
        Loaded(view, cost_centers, provisional_spend, models)
    }
  })
}

///|
fn signature_command(
  model : AppModel,
  agreement_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try request_signature(model, agreement_id) catch {
      error => Failed("Signature request was rejected: \{Repr(error)}")
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
      error => Failed("Lease request was rejected: \{Repr(error)}")
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
                "A scoped token and controller endpoint are required.",
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        ({ ..model, connecting: true }, load_command(model, emit))
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
                "Signature ceremony requested. Execution waits for verified provider evidence.",
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
                "Lease request submitted to the operator queue.",
              ),
            },
          },
          @rabbita.none,
        )
      } else {
        ({ ..model, portal: next }, lease_command(model, emit))
      }
    }
    Portal(portal_message) =>
      ({ ..model, portal: model.portal.update(portal_message) }, @rabbita.none)
    Outcome(Loaded(view, cost_centers, provisional_spend, models)) =>
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
            loading: false,
            success_message: Some("Enterprise access loaded."),
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
              "Signature ceremony requested. Execution waits for verified provider evidence.",
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
              "Lease request submitted to the operator queue.",
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(Failed(message)) =>
      (
        {
          ..model,
          connecting: false,
          portal: {
            ..model.portal,
            loading: false,
            success_message: None,
            error_message: Some(message),
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
  let connection_styles =
    #|.portal-connection{position:fixed;z-index:50;right:1rem;top:1rem;width:min(28rem,calc(100vw - 2rem));border:1px solid #2b4654;border-radius:.7rem;background:#0b1720;color:#edf7f3;box-shadow:0 20px 70px rgba(0,0,0,.45)}.portal-connection summary{padding:.75rem 1rem;cursor:pointer;font-weight:800}.portal-connection-body{display:grid;gap:.65rem;padding:0 1rem 1rem}.portal-connection label{display:block;margin-bottom:.25rem;color:#9db0b6;font-size:.7rem}.portal-connection input{width:100%;min-height:2.6rem;padding:.55rem .65rem;border:1px solid #35505f;border-radius:.45rem;background:#071218;color:#edf7f3}.portal-connection button{min-height:2.6rem;border:1px solid #35bd8d;border-radius:.45rem;background:#7ee0bd;color:#06251a;font-weight:850}.portal-connection p{margin:0;color:#91a7ad;font-size:.7rem}.demo-flag{position:fixed;z-index:45;right:1rem;top:1rem;padding:.45rem .65rem;border:1px solid rgba(126,224,189,.3);border-radius:999px;background:#0b1720;color:#7ee0bd;font:800 .65rem/1 system-ui}
  @html.div([
    @html.style_tag(connection_styles),
    if model.demo_mode {
      @html.div(class="demo-flag", "DEMO · enterprise portal")
    } else {
      @html.details(
        class="portal-connection",
        open=!ready,
        attrs=@html.Attrs::build().aria_label("Enterprise connection"),
        [
          @html.summary(
            if ready {
              "Enterprise connection ready"
            } else {
              "Connect enterprise identity"
            },
          ),
          @html.div(class="portal-connection-body", [
            @html.div([
              @html.label(for_="portal-token", "Scoped inference token"),
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
                "Opaque subject (loopback acceptance only)",
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
              @html.label(for_="portal-endpoint", "Controller endpoint"),
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
                "Connecting…"
              } else {
                "Connect / refresh"
              },
            ),
            @html.p(
              "Credentials remain in this page's browser memory and are never sent to a managed GPU node.",
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
  @rabbita.elmish(
    model={
      endpoint: configured_endpoint(),
      token: "",
      subject_ref: "",
      connecting: false,
      demo_mode: is_demo,
      portal: if is_demo {
        @enterprise_ui.demo_state()
      } else {
        @enterprise_ui.default_state(current_unix_ms())
      },
    },
    view=app_view,
    update~,
  ).mount("app")
}
