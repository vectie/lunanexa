///|
fn api_key_card(
  state : EnterpriseState,
  key : ApiCredentialView,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let (status, status_class) = api_key_state(
    state.locale,
    key,
    state.machine_access.now_unix_ms,
  )
  @html.article(class="api-key-card", [
    @html.div(class="api-key-card-heading", [
      @html.div([@html.h3(key.display_name)]),
      @html.span(class="state-pill api-key-state-\{status_class}", status),
    ]),
    if key.revoked_unix_ms is None &&
      key.expires_unix_ms > state.machine_access.now_unix_ms {
      saved_api_key_controls(state, key, emit)
    } else {
      @html.nothing
    },
    @controls.advanced(enterprise_copy(state.locale, AdvancedSettings), [
      copy_detail(state, emit, key.key_id),
      @html.dl(class="account-facts", [
        @html.div([
          @html.dt(enterprise_copy(state.locale, Scopes)),
          @html.dd(
            key.scopes
            .map(scope => api_key_scope_label(state.locale, scope))
            .join(", "),
          ),
        ]),
        @html.div([
          @html.dt(enterprise_copy(state.locale, Models)),
          @html.dd(
            if key.allowed_models.length() == 0 {
              enterprise_copy(state.locale, AllEntitledModels)
            } else {
              key.allowed_models.join(", ")
            },
          ),
        ]),
      ]),
    ]),
    @html.dl(class="account-facts api-key-facts", [
      @html.div([
        @html.dt(enterprise_copy(state.locale, Expires)),
        @html.dd(
          expiry_label(
            state.locale,
            key.expires_unix_ms,
            state.machine_access.now_unix_ms,
          ),
        ),
      ]),
      if key.maximum_requests == 0L {
        @html.nothing
      } else {
        @html.div([
          @html.dt(enterprise_copy(state.locale, Requests)),
          @html.dd("\{key.consumed_requests} / \{key.maximum_requests}"),
          @html.dd(
            if key.maximum_requests <= 0L ||
              key.consumed_requests >= key.maximum_requests {
              enterprise_copy(state.locale, QuotaExhausted148)
            } else if key.consumed_requests >=
              key.maximum_requests - key.maximum_requests / 5L {
              enterprise_copy(state.locale, WarningLessThanRemaining)
            } else {
              enterprise_copy(state.locale, QuotaAvailable)
            },
          ),
          @html.dd([quota_indicator(state.locale, key)]),
        ])
      },
    ]),
    if key.revoked_unix_ms is None &&
      key.expires_unix_ms > state.machine_access.now_unix_ms {
      @html.div(class="api-key-actions", [
        @html.button(
          type_="button",
          class="quiet-button",
          disabled=key.revoked_unix_ms is Some(_) ||
            key.expires_unix_ms <= state.machine_access.now_unix_ms ||
            state.loading,
          on_click=command(emit, BeginRevokeApiKey(key.key_id)),
          enterprise_copy(state.locale, Revoke),
        ),
      ])
    } else {
      @html.nothing
    },
  ])
}
