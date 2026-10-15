///|
test "new guidance catalog has nonempty distinct bilingual messages" {
  for key in [FirstCallSetup, MissingApiEntrance, FirstCallErrors, TrialSecret] {
    let en = message(English, key)
    let zh = message(ChineseSimplified, key)
    assert_false(en.is_empty())
    assert_false(zh.is_empty())
    assert_false(en == zh)
  }
}

///|
test "demo API key labels agree with allowed model and expiry boundary" {
  let state = demo_state_at(1790755200000L)
  let key = state.api_keys[0]
  assert_true(key.allowed_models.contains("qwen3-32b"))
  assert_true(state.model_catalog.any(model => model.model_id == "qwen3-32b"))
  assert_eq(
    api_key_state(state.locale, key, key.expires_unix_ms - 1L).1,
    "active",
  )
  assert_eq(api_key_state(state.locale, key, key.expires_unix_ms).1, "expired")
  let rendered = render({ ..state, route: AccountAccess, })
  assert_true(rendered.contains("qwen3-32b"))
}
