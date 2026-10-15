///|
test "revocation accepts legacy and nullable timestamps and closes confirmation" {
  for
    value in [
      (
        { "key_id": "test-key", "revoked_unix_ms": [1791994746000L.to_json()] } :
        Json),
      { "key_id": "test-key", "revoked_unix_ms": 1791994746000L.to_json() },
    ] {
    let revoked : PortalApiKeyRevokeView = @json.from_json(value)
    assert_eq(revoked.key_id, "test-key")
    assert_eq(revoked.revoked_unix_ms, Some(1791994746000L))
    let base = gateway_auth_test_model()
    let portal = @enterprise_ui.demo_state()
    let key = { ..portal.api_keys[0], key_id: "test-key", }
    let model = {
      ..base,
      portal: {
        ..portal,
        api_keys: [key],
        api_key_revoke_id: Some(key.key_id),
        loading: true,
      },
    }
    let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
    let (updated, _) = update(
      model,
      Outcome(
        ApiKeyRevoked(
          model.session_generation,
          revoked.key_id,
          revoked.revoked_unix_ms,
        ),
      ),
      emit,
    )
    assert_eq(updated.portal.api_key_revoke_id, None)
    assert_false(updated.portal.loading)
    assert_eq(updated.portal.api_keys[0].revoked_unix_ms, Some(1791994746000L))
  }
}
