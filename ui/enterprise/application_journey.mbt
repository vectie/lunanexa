///|
/// Select only an unambiguous initial choice. An unavailable prior selection
/// stays unavailable until the user chooses again.
pub fn DeliveryPanel::for_route(
  self : DeliveryPanel,
  route : EnterpriseRoute,
) -> DeliveryPanel {
  let kind = match route {
    MachineAccess => "GpuContainer"
    Models => "ModelApi"
    DesktopIde => "Workspace"
    _ => return self
  }
  let choices = self.options.templates.filter(option => option.kind == kind)
  let selected = self.template_selections
    .get(kind)
    .unwrap_or(
      if selected_delivery_template(self).map_or(false, option => {
          option.kind == kind
        }) {
        self.template_choice
      } else if choices.length() == 1 {
        delivery_template_choice(choices[0])
      } else {
        ""
      },
    )
  let selections = self.template_selections.copy()
  if selected != "" {
    selections[kind] = selected
  }
  {
    ..self,
    template_choice: selected,
    template_selections: selections,
    idempotency_key: if selected == self.template_choice {
      self.idempotency_key
    } else {
      ""
    },
  }
}

///|
fn EnterpriseState::select_application_client(
  self : EnterpriseState,
  client : EnterpriseDesktopClient,
) -> EnterpriseState {
  let changed = self.desktop_client.map_or(true, current => {
    current.client_id != client.client_id
  })
  {
    ..self,
    desktop_client: Some(client),
    webide_order_id: if changed {
      None
    } else {
      self.webide_order_id
    },
    webide_model_alias: self.webide_model_alias.filter(model => {
      client.approved_model_aliases.contains(model)
    }),
    desktop_connect_phase: NotStarted,
    success_message: None,
    error_message: None,
  }
}

///|
fn application_model_available(
  state : EnterpriseState,
  model_name : String,
) -> Bool {
  state.model_catalog.any(model => model.alias_name == Some(model_name))
}

///|
fn EnterpriseState::open_model_application(
  self : EnterpriseState,
  model_name : String,
) -> EnterpriseState {
  if !application_model_available(self, model_name) || self.loading {
    return self
  }
  let client = match self.desktop_client {
    Some(client) if client.client_id != "comfyui" &&
      client.approved_model_aliases.contains(model_name) => Some(client)
    _ =>
      self.desktop_clients
      .iter()
      .find_first(client => {
        client.client_id != "comfyui" &&
        client.approved_model_aliases.contains(model_name)
      })
  }
  {
    ..self,
    route: DesktopIde,
    desktop_client: client,
    webide_order_id: None,
    webide_model_alias: Some(model_name),
    desktop_connect_phase: NotStarted,
    success_message: None,
    error_message: None,
  }
}

///|
fn application_model_context(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  match state.webide_model_alias {
    Some(model_name) =>
      @html.section(class="workflow-panel", [
        @html.div(class="section-heading", [
          @html.strong(copy(state.locale, "Model: ", "模型：") + model_name),
          @html.button(
            type_="button",
            class="quiet-button",
            on_click=command(emit, Navigate(Models)),
            copy(state.locale, "Back to models", "返回模型"),
          ),
          @html.button(
            type_="button",
            class="quiet-button",
            disabled=state.loading,
            on_click=command(emit, SelectWebIdeOrder("")),
            copy(
              state.locale,
              "Use all authorized models",
              "使用全部授权模型",
            ),
          ),
        ]),
        if !webide_model_source_known(state, model_name) {
          @html.p(
            attrs=@html.Attrs::build().role("alert"),
            copy(
              state.locale,
              "This model is no longer available. Choose another model.",
              "此模型已不可用，请重新选择。",
            ),
          )
        } else if !webide_model_source_ready(state, model_name) {
          @html.p(
            copy(
              state.locale,
              "The selected model is registered but its service is not responding yet.",
              "所选模型已登记，但模型服务尚未响应。",
            ),
          )
        } else {
          @html.nothing
        },
      ])
    None => @html.nothing
  }
}
