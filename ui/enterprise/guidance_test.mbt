///|
test "first call is canonical scoped and secret free" {
  let value : @enterprise.OneTimeApiKeySecret = {
    key_id: "key-id",
    display_name: "client",
    secret: "never-in-example",
    allowed_models: ["text.qwen"],
    api_base_url: Some("https://api.example.invalid/"),
    tenant_ref: "tenant-public",
    memory_ceiling_mib: Some(8192),
  }
  let request = @contracts.decode_workload(
    @enterprise.first_call_payload(value, "test-first-call", 1900000000000L).stringify(),
  )
  assert_eq(request.model_selector, "text.qwen")
  assert_eq(request.resource_ceiling.max_accelerator_memory_mib, 8192)
  let command = @enterprise.first_call_example(value)
  assert_true(command.contains("https://api.example.invalid/v1/workloads"))
  assert_false(command.contains("never-in-example"))
  assert_true(command.contains("text.qwen"))
  assert_true(command.contains("tenant-public"))
  assert_true(command.contains("lunanexa.v1"))
  assert_true(command.contains("TextGenerate"))
  assert_true(command.contains("$API_KEY"))
  assert_true(command.contains("uuidgen"))
  assert_true(command.contains("date +%s"))
  let placeholder = @enterprise.first_call_example({
    ..value,
    api_base_url: None,
  })
  assert_true(placeholder.contains("ask your operator"))
  let hostile = @enterprise.first_call_example({
    ..value,
    tenant_ref: "tenant'$(touch /tmp/not-run)",
  })
  assert_true(hostile.contains("'\"'\"'"))
}

///|
test "friendly failures preserve recovery and never technical secrets" {
  for
    code in [
      "TrialApiKeyRejected", "EffectiveMasterLeaseRequired", "PortalAccessDenied",
      "401", "403", "409", "429", "Timeout", "Network", "Unexpected",
    ] {
    for locale in [@i18n.English, ChineseSimplified] {
      let result = @enterprise.friendly_failure(
        locale,
        "Operation",
        code + " bearer secret-sensitive /data/private 192.168.2.1",
      )
      assert_false(result.contains("secret-sensitive"))
      assert_false(result.contains("/data/private"))
      assert_false(result.contains("192.168.2.1"))
    }
  }
  assert_true(
    @enterprise.friendly_failure(English, "Issue", "TrialApiKeyRejected").contains(
      "cannot be reissued",
    ),
  )
  assert_true(
    @enterprise.friendly_failure(English, "Issue", "Timeout").contains(
      "may already have completed",
    ),
  )
}

///|
test "cost CSV escapes quotations delimiters and spreadsheet formulas" {
  let state = @enterprise.demo_state()
  let csv = @enterprise.costs_csv({
    ..state,
    selected_organization_id: Some("org-selected"),
    cost_centers: [
      {
        cost_center_id: "id",
        display_name: " =HYPERLINK(\"danger\")",
        project_count: 2,
        provisional_spend: "12,34",
        budget_posture: "line\nbreak",
      },
    ],
  })
  assert_true(csv.contains("org-selected"))
  assert_true(csv.contains("\"' =HYPERLINK(\"\"danger\"\")\""))
  assert_true(csv.contains("\"12,34\""))
  assert_true(csv.contains("\"line\nbreak\""))
  assert_false(csv.contains("lnx_"))
}

///|
test "guidance links quota and expiry are explicit and bilingual" {
  let state = @enterprise.demo_state()
  let page = @enterprise.render({
    ..state,
    route: AccountAccess,
    docs_base_url: Some("https://docs.example.invalid/?old=1#old"),
    error_message: Some("Safe failure"),
    api_keys: [
      { ..state.api_keys[0], maximum_requests: 100L, consumed_requests: 95L, },
    ],
  })
  assert_true(page.contains("?page=enterprise-portal-day-one"))
  assert_true(page.contains("?page=error-reference"))
  assert_true(page.contains("less than 20%"))
  assert_true(page.contains("role=\"progressbar\""))
  assert_true(page.contains("aria-valuenow=\"95\""))
  assert_true(page.contains("Copy identifier"))
  assert_true(
    @enterprise.expiry_label(English, 3600001L, 1L).contains("1h remaining"),
  )
  assert_true(
    @enterprise.expiry_label(English, 3600000L, 0L).contains("time unavailable"),
  )
  assert_true(
    @enterprise.expiry_label(ChineseSimplified, 0L, 1L).contains("已过期"),
  )
  let unconfigured = @enterprise.render({ ..state, docs_base_url: None, })
  assert_false(unconfigured.contains("?page=enterprise-portal-day-one"))
}

///|
test "catalog does not advertise unaliased or exhausted authority" {
  let state = @enterprise.demo_state()
  let page = @enterprise.render({
    ..state,
    route: Models,
    model_catalog: [{ ..state.model_catalog[0], alias_name: None, }],
    api_keys: [],
  })
  assert_true(page.contains("No callable alias published"))
  assert_false(page.contains("Copy model alias"))
  assert_false(page.contains("Allowed by an active API key"))
}

///|
test "platform announcement text is escaped and trial expiry explains conversion" {
  let state = @enterprise.demo_state()
  let original = state.notifications[0]
  let page = @enterprise.render({
    ..state,
    route: Notifications,
    notifications: [
      {
        ..original,
        event: {
          ..original.event,
          topic: Announcement,
          code: "PlatformAnnouncement",
          parameters: {
            "title": "<img onerror=attack>",
            "body": "<script>attack</script>",
          },
        },
      },
    ],
  })
  assert_true(page.contains("&lt;img"))
  assert_true(page.contains("&lt;script&gt;"))
  assert_false(page.contains("<script>attack"))
  let trial = @enterprise.render({
    ..state,
    route: Notifications,
    notifications: [
      {
        ..original,
        event: { ..original.event, code: "TrialExpiring", parameters: {}, },
      },
    ],
  })
  assert_true(trial.contains("no automatic paid conversion"))
}

///|
test "a refusal keeps its status so the copy can name the real problem" {
  // The portal's transport used to replace the thrown message with the body's
  // own text, which dropped the status. A permanent 403 then read as "the
  // action failed, refresh and retry" -- advice that can never work.
  let refusal = @enterprise.friendly_failure(
    English,
    "Operation",
    "Unable to create the signed machine quote: Error(\"HTTP 403: lease requester role is required\")",
  )
  assert_true(refusal.contains("lacks permission"))
  assert_false(refusal.contains("Refresh and retry"))
  // The connection branch is unchanged.
  assert_true(
    @enterprise.friendly_failure(
      English,
      "Operation",
      "TypeError: Failed to fetch",
    ).contains("connection did not complete"),
  )
  // A status we do not classify still reads as a plain failure.
  assert_true(
    @enterprise.friendly_failure(English, "Operation", "HTTP 500: internal").contains(
      "The action failed",
    ),
  )
}

///|
test "a rental period outside the offering's allowance says so" {
  // Review price simply went grey when the period exceeded what the offering
  // allows, and on a trial that is the whole visible consequence of asking for
  // a longer rental. The reason now names the number and the way forward.
  let offering : @enterprise.SelfServiceOfferingView = {
    offering_id: "offering-trial",
    kind: BareGpu,
    display_name: "DGX Spark (GB10) exclusive node",
    gpu_sku: "nvidia-sm121",
    accelerator_count: 1,
    accelerator_memory_mib: 121000,
    regions: ["cn-north-1"],
    minimum_duration_hours: 1,
    maximum_duration_hours: 24,
    price_summary: "CNY 0.02 / second",
    allowed_model_template_refs: [],
    available: true,
  }
  let base = @enterprise.default_state(1000L)
  let state = {
    ..base,
    route: SelfService,
    self_service: {
      ..@enterprise.default_self_service_state(),
      step: Capacity,
      selected_product: Some(BareGpu),
      offerings: [offering],
      selected_offering_id: "offering-trial",
      project_id: "trial-project",
      unix_username: "trialuser",
      region: "cn-north-1",
      duration_hours: 168,
    },
  }
  let html = @enterprise.render(state)
  assert_true(html.contains("168 hours is longer than this offering allows"))
  assert_false(@enterprise.self_service_configuration_valid(state.self_service))
  // The same state at a period inside the allowance says nothing extra.
  let allowed = {
    ..state,
    self_service: { ..state.self_service, duration_hours: 24, },
  }
  assert_true(
    @enterprise.self_service_configuration_valid(allowed.self_service),
  )
  assert_false(
    @enterprise.render(allowed).contains("is longer than this offering allows"),
  )
}
