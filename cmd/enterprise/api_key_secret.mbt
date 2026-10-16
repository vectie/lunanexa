///|
priv struct SavedApiKeySecret {
  key_id : String
  secret : String
} derive(FromJson)

///|
fn saved_api_key_secret_command(
  model : AppModel,
  key_id : String,
  purpose : KeySecretPurpose,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let generation = model.session_generation
  let nonce = model.portal.api_key_secret_generation
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try {
      let reply = request(
        "POST",
        model.endpoint,
        "/v1/portal/self/api-keys/" + key_id + ":secret",
        model.token,
        model.subject_ref,
        body="{}",
      )
      let value : SavedApiKeySecret = @json.from_json(@json.parse(reply))
      if value.key_id != key_id ||
        !value.secret.has_prefix("lnx_") ||
        value.secret.length() != 68 {
        raise Failure("Invalid key response")
      }
      ApiKeySecretLoaded(generation, nonce, key_id, value.secret, purpose)
    } catch {
      _ => ApiKeySecretLoadFailed(generation, nonce)
    }
  })
}
