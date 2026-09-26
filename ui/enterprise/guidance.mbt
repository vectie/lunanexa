///|
fn shell_quote(value : String) -> String {
  "'" +
  value.split("'").map(part => part.to_owned()).to_array().join("'\"'\"'") +
  "'"
}

///|
pub fn first_call_example(value : OneTimeApiKeySecret) -> String {
  let endpoint = value.api_base_url
    .unwrap_or("<API entrance — ask your operator>")
    .trim_end(chars="/")
    .to_owned()
  let payload = first_call_payload(value, "FIRST_CALL_ID", 1900000000000L)
  let memory = value.memory_ceiling_mib
    .map(n => "memory_mib=" + n.to_string())
    .unwrap_or(
      "# Ask the operator for this alias's required accelerator memory ceiling.\nmemory_mib='<approved memory MiB>'",
    )
  "# Requires curl, uuidgen and jq. Set API_KEY privately before running.\n" +
  memory +
  "\nrequest_id=$(uuidgen)\ndeadline=$(( $(date +%s) * 1000 + 60000 ))\nrequest_json=$(printf '%s' " +
  shell_quote(payload.stringify()) +
  " | jq --arg id \"$request_id\" --arg deadline \"$deadline\" --argjson memory \"$memory_mib\" '.idempotency_key=$id | .workload_id=$id | .deadline_unix_ms=$deadline | .resource_ceiling.max_accelerator_memory_mib=$memory') && curl --fail-with-body -X POST " +
  shell_quote(endpoint + "/v1/workloads") +
  " -H \"Authorization: Bearer $API_KEY\" -H 'Content-Type: application/json' --data-binary \"$request_json\""
}

///|
pub fn first_call_payload(
  value : OneTimeApiKeySecret,
  request_id : String,
  deadline : Int64,
) -> Json {
  let model = value.allowed_models.get(0).unwrap_or("<allowed model alias>")
  let payload : Json = {
    "version": "lunanexa.v1",
    "idempotency_key": request_id,
    "workload_id": request_id,
    "tenant_ref": value.tenant_ref,
    "credential_scope": "inference",
    "capability": "TextGenerate",
    "model_selector": model,
    "payload": { "input": "Hello" },
    "data_policy": {
      "classification": "Confidential",
      "retention": "Ephemeral",
      "allow_cache": false,
      "allow_training_reuse": false,
    },
    "deadline_unix_ms": deadline.to_string(),
    "priority": "Interactive",
    "latency_class": "Realtime",
    "resource_ceiling": {
      "max_input_units": 1024,
      "max_output_units": 64,
      "max_runtime_ms": "30000",
      "max_accelerator_memory_mib": value.memory_ceiling_mib.unwrap_or(1),
    },
    "stream": false,
    "output_format": "text",
    "trace_token": "first-call",
  }
  payload
}

///|
pub fn friendly_failure(
  locale : @i18n.Locale,
  action : String,
  raw : String,
) -> String {
  let reason = if raw.contains("TrialApiKeyRejected") {
    message(locale, TrialSecret)
  } else if raw.contains("EffectiveMasterLeaseRequired") {
    enterprise_copy(locale, CommercialAuthorizationIsNotActiveCheck)
  } else if raw.contains("AgreementRequired") {
    enterprise_copy(locale, AnExecutedMachineAgreementIsRequired)
  } else if raw.contains("MachineTermsUnavailable") {
    enterprise_copy(locale, PublishedMachineTermsAreRequired)
  } else if raw.contains("MachineOrderAccessDenied") ||
    raw.contains("lease requester role is required") {
    @i18n.copy(
      locale, "This account needs the LeaseRequester role in the selected organization to request a machine quote. Ask your organization administrator.",
      "当前账户需要所选企业的“租用申请人”权限才能查看机器报价，请联系企业管理员。",
    )
  } else if raw.contains("PortalAccessDenied") || raw.contains("403") {
    enterprise_copy(locale, ThisAccountLacksPermissionForThis)
  } else if raw.contains("401") {
    enterprise_copy(locale, YourSessionOrCredentialIsInvalid)
  } else if raw.contains("409") {
    enterprise_copy(locale, TheResourceChangedRefreshItsStatus)
  } else if raw.contains("429") {
    enterprise_copy(locale, TheQuotaOrRateLimitWas)
  } else if raw.contains("timeout") ||
    raw.contains("Timeout") ||
    raw.contains("network") ||
    raw.contains("Network") ||
    raw.contains("fetch") {
    enterprise_copy(locale, TheConnectionDidNotCompleteCheck)
  } else {
    enterprise_copy(locale, TheActionFailedRefreshAndRetry)
  }
  action + ": " + reason
}

///|
pub fn expiry_label(
  locale : @i18n.Locale,
  expiry : Int64,
  now : Int64,
) -> String {
  let relative = if now <= 0L {
    enterprise_copy(locale, CurrentTimeUnavailable)
  } else if expiry <= now {
    enterprise_copy(locale, Expired)
  } else {
    let minutes = (expiry - now + 59999L) / 60000L
    if minutes >= 60L {
      "\{minutes / 60L}" + enterprise_copy(locale, HRemaining)
    } else {
      "\{minutes}" + enterprise_copy(locale, MRemaining)
    }
  }
  relative + " · " + @contractdoc.format_unix_ms_beijing(expiry)
}

///|
fn csv_cell(value : String) -> String {
  let trimmed = value.trim().to_owned()
  let safe = if trimmed.has_prefix("=") ||
    trimmed.has_prefix("+") ||
    trimmed.has_prefix("-") ||
    trimmed.has_prefix("@") ||
    value.has_prefix("\t") ||
    value.has_prefix("\r") ||
    value.has_prefix("\n") {
    "'" + value
  } else {
    value
  }
  "\"" +
  safe.split("\"").map(part => part.to_owned()).to_array().join("\"\"") +
  "\""
}

///|
fn copy_detail(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  value : String,
) -> @rabbita.Html {
  @html.span(class="copy-detail", [
    @html.span(class="mono", value),
    @html.button(
      type_="button",
      class="quiet-button",
      title=enterprise_copy(state.locale, CopyIdentifier),
      on_click=command(emit, CopyDetail(value)),
      enterprise_copy(state.locale, Copy),
    ),
  ])
}

///|
fn quota_indicator(
  locale : @i18n.Locale,
  key : ApiCredentialView,
) -> @rabbita.Html {
  let percent = if key.maximum_requests <= 0L ||
    key.consumed_requests >= key.maximum_requests {
    100
  } else if key.consumed_requests <= 0L {
    0
  } else {
    (key.consumed_requests.to_double() /
    key.maximum_requests.to_double() *
    100.0).to_int()
  }
  @html.span(
    class=if percent >= 80 {
      "quota-track quota-warning"
    } else {
      "quota-track"
    },
    attrs=@html.Attrs::build()
      .role("progressbar")
      .aria_label(enterprise_copy(locale, RequestQuotaUsed))
      .aria_valuemin("0")
      .aria_valuemax("100")
      .aria_valuenow(percent.to_string()),
    [@html.span(class="quota-fill", style=["width:\{percent}%"], "")],
  )
}

///|
pub fn tutorial_page(route : EnterpriseRoute) -> String {
  match route {
    Overview | SelfService | AccountAccess | Costs | Notifications =>
      "enterprise-portal-day-one"
    Agreements | ContractDocuments | OfflineCommerce => "access-flow"
    LeaseRequests | MachineAccess => "exclusive-machine-basics"
    Models => "client-api"
    DesktopIde => "developer-workbench"
  }
}

///|
fn guide_link(
  state : EnterpriseState,
  page : String,
  error : Bool,
) -> @rabbita.Html {
  match state.docs_base_url {
    Some(base) if base.has_prefix("https://") ||
      base.has_prefix("http://localhost:") ||
      base.has_prefix("http://127.0.0.1:") => {
      let root = base
        .split("#")
        .next()
        .unwrap_or(base[:])
        .to_owned()
        .split("?")
        .next()
        .unwrap_or(base[:])
        .to_owned()
      @html.a(
        class="quiet-button external-action",
        href=root + "?page=" + page,
        rel="noopener noreferrer",
        if error {
          enterprise_copy(state.locale, ViewErrorGuide)
        } else {
          enterprise_copy(state.locale, HowToUseThisPage)
        },
      )
    }
    _ => @html.nothing
  }
}

///|
pub fn costs_csv(state : EnterpriseState) -> String {
  let rows = [
    "organization_id,cost_center_id,name,projects,provisional_spend,budget_posture",
  ]
  for row in state.cost_centers {
    rows.push(
      [
        state.selected_organization_id.unwrap_or(
          state.membership
          .map(membership => membership.organization_id)
          .unwrap_or(""),
        ),
        row.cost_center_id,
        row.display_name,
        row.project_count.to_string(),
        row.provisional_spend,
        row.budget_posture,
      ]
      .map(csv_cell)
      .join(","),
    )
  }
  rows.join("\r\n") + "\r\n"
}
