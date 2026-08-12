///|
test "global defaults are valid and publish authority" {
  let settings = @settings.default_global_admin_settings()
  @settings.validate_global_admin_settings(settings)
  let view = @settings.public_settings_view(settings)
  assert_eq(view.global_generation, 1L)
  assert_true(
    view.authorities.any(item => item.authority == GlobalAdministrator),
  )
  assert_true(view.authorities.any(item => item.authority == LocalClient))
}

///|
test "user request cannot exceed global administrator policy" {
  let settings = @settings.default_global_admin_settings()
  let accepted = @settings.resolve_user_request(settings, {
    model_alias: "text.default",
    deadline_ms: 30000L,
    max_output_units: 512,
  })
  assert_eq(accepted.global_generation, settings.generation)
  try
    @settings.resolve_user_request(settings, {
      model_alias: "text.default",
      deadline_ms: settings.request_budgets.openai_max_deadline_ms + 1L,
      max_output_units: 512,
    })
  catch {
    UserPreferenceExceedsGlobalPolicy(field) => assert_eq(field, "deadline_ms")
    _ => fail("unexpected settings error")
  } noraise {
    _ => fail("expected global deadline policy to reject the request")
  }
}

///|
test "hard safety ceilings reject hostile administrator configuration" {
  let defaults = @settings.default_global_admin_settings()
  let hostile = {
    ..defaults,
    scheduler: { ..defaults.scheduler, runtime_concurrency: 1000000 },
  }
  try @settings.validate_global_admin_settings(hostile) catch {
    InvalidGlobalSetting(section) => assert_eq(section, "scheduler")
    _ => fail("unexpected settings error")
  } noraise {
    _ => fail("expected the hard ceiling to reject hostile configuration")
  }
}

///|
test "local preferences cannot alter cluster budgets" {
  let preferences = @settings.default_user_local_preferences()
  @settings.validate_user_local_preferences(preferences)
  try
    @settings.validate_user_local_preferences({
      ..preferences,
      output_display_characters: 16777216,
    })
  catch {
    InvalidLocalPreference(_) => ()
    _ => fail("unexpected settings error")
  } noraise {
    _ => fail("expected local display ceiling rejection")
  }
}

///|
test "settings document round-trips without losing authority or generation" {
  let original = @settings.default_global_admin_settings()
  let restored : @settings.GlobalAdminSettings = @json.from_json(
    original.to_json(),
  )
  assert_eq(restored, original)
  assert_eq(
    @settings.public_settings_view(restored).authorities.length(),
    @settings.setting_authority_catalog().length(),
  )
  assert_eq(
    @settings.parse_global_admin_settings(original.to_json().stringify()),
    original,
  )
}

///|
test "malformed and partial administrator documents fail closed" {
  for
    payload in [
      "", "null", "{}", "{\"schema_version\":\"lunanexa.settings.v1\"}", "{\"schema_version\":",
      "[]",
    ] {
    try @settings.parse_global_admin_settings(payload) catch {
      InvalidGlobalSetting(_) => ()
      _ => fail("unexpected malformed document error")
    } noraise {
      _ => fail("malformed administrator document was accepted")
    }
  }
}

///|
test "generated enterprise preferences never cross global boundaries" {
  let policy = @settings.default_global_admin_settings()
  for index = 1; index <= 512; index = index + 1 {
    let requested = index * 257
    let deadline = index.to_int64() * 233L
    let within_output = requested <=
      policy.request_budgets.openai_max_output_units
    let within_deadline = deadline <=
      policy.request_budgets.openai_max_deadline_ms
    try
      @settings.resolve_user_request(policy, {
        model_alias: "text.fuzz-\{index}",
        deadline_ms: deadline,
        max_output_units: requested,
      })
    catch {
      UserPreferenceExceedsGlobalPolicy(_) =>
        assert_false(within_output && within_deadline)
      _ => fail("unexpected generated preference error")
    } noraise {
      resolved => {
        assert_true(within_output && within_deadline)
        assert_true(
          resolved.max_output_units <=
          policy.request_budgets.openai_max_output_units,
        )
        assert_true(
          resolved.deadline_ms <= policy.request_budgets.openai_max_deadline_ms,
        )
      }
    }
  }
}

///|
test "adversarial aliases and cross-field policy escalation fail closed" {
  let policy = @settings.default_global_admin_settings()
  for
    selector in [
      "../model", "model/escape", "model\nforged", "model?token=secret", "模型",
      "",
    ] {
    try
      @settings.resolve_user_request(policy, {
        model_alias: selector,
        deadline_ms: 1L,
        max_output_units: 1,
      })
    catch {
      UserPreferenceExceedsGlobalPolicy(field) =>
        assert_eq(field, "model_alias")
      _ => fail("unexpected alias validation error")
    } noraise {
      _ => fail("hostile alias was accepted")
    }
  }
  let inverted = {
    ..policy,
    request_budgets: {
      ..policy.request_budgets,
      openai_default_deadline_ms: 2000L,
      openai_max_deadline_ms: 1000L,
    },
  }
  try @settings.validate_global_admin_settings(inverted) catch {
    InvalidGlobalSetting(section) => assert_eq(section, "request_budgets")
    _ => fail("unexpected cross-field validation error")
  } noraise {
    _ => fail("inverted deadline policy was accepted")
  }
}
