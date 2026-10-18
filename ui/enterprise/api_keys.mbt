///|
/// Normalize the older controller's explicit Option encoding as well as the
/// nullable public JSON contract. A successful issuance must reach the secret
/// view even while controller and browser releases are being rolled out.
pub impl @json.FromJson for IssuedApiKeyView with fn from_json(value, path) {
  guard value is { "credential": credential, "secret": secret, .. } else {
    raise JsonDecodeError((path, "expected issued API key"))
  }
  let api_base_url : String? = match value {
    { "api_base_url": String(_) as url, .. }
    | { "api_base_url": Array([url]), .. } =>
      Some(@json.from_json(url, path=path.add_key("api_base_url")))
    { "api_base_url": Null | Array([]), .. } => None
    { "api_base_url": _, .. } =>
      raise JsonDecodeError((path.add_key("api_base_url"), "expected API URL"))
    _ => None
  }
  {
    credential: @json.from_json(credential, path=path.add_key("credential")),
    secret: @json.from_json(secret, path=path.add_key("secret")),
    api_base_url,
  }
}

///|
/// The backend independently verifies private-model or shared-trial authority.
/// This projection only determines whether the quota picker is relevant.
pub fn api_key_uses_unmetered_model(state : EnterpriseState) -> Bool {
  let models = api_key_allowed_models(state)
  if models.is_empty() {
    return false
  }
  let private_model = state.deliveries.external_model.map_or(false, service => {
    models.all(model => model == service.model_alias)
  })
  private_model || models.all(model => {
    state.deliveries.options.shared_trials.any(slot => {
      slot.kind == "Text" && slot.model_alias == model
    })
  })
}

///|
fn saved_api_key_controls(
  state : EnterpriseState,
  key : ApiCredentialView,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let active = key.revoked_unix_ms is None &&
    key.expires_unix_ms > state.machine_access.now_unix_ms
  let secret = if active {
    state.revealed_api_key.filter(value => value.key_id == key.key_id)
  } else {
    None
  }
  let busy = state.api_key_secret_request == Some(key.key_id)
  @html.div(
    attrs=@html.Attrs::build()
      .style("display", "flex")
      .style("align-items", "center")
      .style("gap", ".5rem")
      .style("min-width", "0"),
    [
      @html.code(
        class="mono",
        attrs=@html.Attrs::build()
          .style("overflow-wrap", "anywhere")
          .style("min-width", "0"),
        secret.map(value => value.secret).unwrap_or("********"),
      ),
      @controls.icon_button(
        if secret is Some(_) {
          EyeOff
        } else {
          Eye
        },
        copy(
          state.locale,
          if secret is Some(_) {
            "Hide API key"
          } else {
            "Reveal API key"
          },
          if secret is Some(_) {
            "隐藏 API 密钥"
          } else {
            "显示 API 密钥"
          },
        ),
        command(emit, ToggleApiKeySecret(key.key_id)),
        disabled=!active,
        busy~,
      ),
      @controls.icon_button(
        Copy,
        copy(state.locale, "Copy API key", "复制 API 密钥"),
        command(emit, CopySavedApiKey(key.key_id)),
        disabled=!active,
        busy~,
      ),
    ],
  )
}
