///|
test "guest Wi-Fi CIDR parsing rejects malformed and ambiguous addresses" {
  assert_true(parse_wifi_cidr("192.0.2.0/24") is Some(_))
  assert_true(parse_wifi_cidr("203.0.113.7/32") is Some(_))
  for
    value in [
      "", "192.0.2.0", "192.0.2.0/33", "192.0.2.0/-1", "192.0.2.0/24,0.0.0.0/0",
      "192.0.2.999/24", "192.0.02.0/24", "::1/128", "0.0.0.0/0", "198.51.100.0/23",
    ] {
    assert_true(parse_wifi_cidr(value) is None)
  }
}

///|
test "guest Wi-Fi assertion is restricted to ingress client IP" {
  let config = {
    ..password_test_config("http://relay:8081"),
    wifi_trial_source_cidrs: ["192.0.2.0/24", "203.0.113.7/32"],
  }
  assert_true(wifi_trial_source_allowed(config, { "X-Real-IP": "192.0.2.8" }))
  assert_true(wifi_trial_source_allowed(config, { "X-Real-IP": "192.0.2.255" }))
  assert_true(wifi_trial_source_allowed(config, { "X-Real-IP": "203.0.113.7" }))
  assert_false(wifi_trial_source_allowed(config, { "X-Real-IP": "192.0.3.0" }))
  assert_false(
    wifi_trial_source_allowed(config, {
      "X-Real-IP": "198.51.100.4",
      "X-Forwarded-For": "192.0.2.8",
    }),
  )
  assert_false(
    wifi_trial_source_allowed(config, { "X-Real-IP": "192.0.2.8, 198.51.100.4" }),
  )
  assert_false(
    wifi_trial_source_allowed({ ..config, wifi_trial_source_cidrs: [], }, {
      "X-Real-IP": "192.0.2.8",
    }),
  )
}
