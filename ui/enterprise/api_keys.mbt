///|
/// Normalize the older controller's explicit Option encoding as well as the
/// nullable public JSON contract. A successful issuance must reach the secret
/// view even while controller and browser releases are being rolled out.
pub impl @json.FromJson for IssuedApiKeyView with fn from_json(value, path) {
  guard value is { "credential": credential, "secret": secret, .. } else {
    raise @json.JsonDecodeError((path, "expected issued API key"))
  }
  let api_base_url : String? = match value {
    { "api_base_url": String(_) as url, .. }
    | { "api_base_url": Array([url]), .. } =>
      Some(@json.from_json(url, path=path.add_key("api_base_url")))
    { "api_base_url": Null | Array([]), .. } => None
    { "api_base_url": _, .. } =>
      raise @json.JsonDecodeError(
        (path.add_key("api_base_url"), "expected API URL"),
      )
    _ => None
  }
  {
    credential: @json.from_json(credential, path=path.add_key("credential")),
    secret: @json.from_json(secret, path=path.add_key("secret")),
    api_base_url,
  }
}

///|
/// The backend independently verifies the company and private-model authority.
/// This projection only determines whether the quota picker is relevant.
pub fn api_key_uses_reserved_model(state : EnterpriseState) -> Bool {
  match state.deliveries.external_model {
    Some(service) => {
      let models = api_key_allowed_models(state)
      models.length() > 0 && models.all(model => model == service.model_alias)
    }
    None => false
  }
}
