///|
pub(all) struct ModelConnectionImport {
  model : String
  secret : String
  key_id : String?
} derive(Eq)

///|
pub extend ModelConnectionImport with Eq::{equal, not_equal}

///|
fn model_connection_import_json(
  base_url : String,
  model : String,
  secret : String,
  max_output_tokens~ : Int32 = 16384,
) -> Json {
  {
    "version": "openai.connection.v1",
    "api": "chat.completions",
    "base_url": base_url,
    "api_key": secret,
    "model": model,
    "max_output_tokens": max_output_tokens,
  }
}

///|
fn valid_connection_secret(secret : String) -> Bool {
  secret.has_prefix("lnx_") &&
  secret.length() == 68 &&
  secret[4:].all(c => c.is_ascii_hexdigit())
}

///|
fn model_connection_qr(
  locale : @i18n.Locale,
  model : String,
  secret : String,
  _emit : @rabbita.Emit[EnterpriseMessage]?,
  base_url~ : String = public_maas_base_url(),
  max_output_tokens~ : Int32 = 16384,
) -> @rabbita.Html {
  guard valid_connection_secret(secret) else { return @html.nothing }
  let payload = model_connection_import_json(
    base_url,
    model,
    secret,
    max_output_tokens~,
  ).stringify()
  guard payload.length() <= 1000 && payload.all(c => c <= '\u{7f}') else {
    return @html.p(
      copy(
        locale, "Connection details are too large for a QR code.", "连接信息过长，无法生成二维码。",
      ),
    )
  }
  let qr = @qr.encode_medium(payload)
  let size = qr.size()
  let path = StringBuilder()
  for y in 0..<size {
    for x in 0..<size {
      if qr.is_black(x, y) {
        path.write_string("M\{x+4} \{y+4}h1v1h-1z")
      }
    }
  }
  @html.div([
    @html.p(
      copy(
        locale, "Private QR · do not share", "私密二维码 · 请勿分享",
      ),
    ),
    @html.div(
      attrs=@html.Attrs::build()
        .role("img")
        .aria_label(
          copy(
            locale, "Private client connection QR", "私密客户端连接二维码",
          ),
        ),
      [
        @svg.svg(
          width=320,
          height=320,
          view_box="0 0 \{size+8} \{size+8}",
          attrs=@svg.Attrs::build()
            .style("max-width", "100%")
            .style("height", "auto"),
          [
            @svg.rect(x=0, y=0, width=size + 8, height=size + 8, fill="white"),
            @svg.path(
              d=path.to_string(),
              attrs=@svg.Attrs::build().fill("black"),
            ),
          ],
        ),
      ],
    ),
  ])
}

///|
fn model_connection_qr_dialog(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  guard state.model_connection_import is Some(value) else {
    return @html.nothing
  }
  @html.div(class="modal-backdrop", [
    @html.section(
      class="confirmation-dialog account-dialog",
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_labelledby("model-connection-qr-title"),
      [
        @html.div(class="section-heading", [
          @html.h2(
            id="model-connection-qr-title",
            copy(state.locale, "Connection QR", "连接二维码"),
          ),
          @html.button(
            id="api-key-connection-dismiss",
            type_="button",
            class="quiet-button",
            on_click=command(emit, DismissModelConnectionQr),
            copy(state.locale, "Close", "关闭"),
          ),
        ]),
        @html.label(
          for_="model-connection-key",
          copy(state.locale, "API key", "API 密钥"),
        ),
        @html.select(
          id="model-connection-key",
          on_change=text_command(emit, key_id => {
            UseSavedKeyForConnectionQr(key_id)
          }),
          [
            @html.option(
              value="",
              selected=value.key_id is None,
              copy(state.locale, "Select a key", "选择密钥"),
            ),
            ..[
              for key in state.api_keys if key.revoked_unix_ms is None &&
              key.expires_unix_ms > state.machine_access.now_unix_ms &&
              (
                key.allowed_models.is_empty() ||
                key.allowed_models.contains(value.model)
              ) => {
                @html.option(
                  value=key.key_id,
                  selected=value.key_id == Some(key.key_id),
                  key.display_name,
                )
              }
            ],
          ],
        ),
        if state.api_key_secret_request is Some(_) {
          @html.p(copy(state.locale, "Loading…", "正在加载…"))
        } else {
          @html.nothing
        },
        @html.p(
          copy(
            state.locale,
            "Contains your API key. Scan only into a client you trust; this is not a public registration code.",
            "包含你的 API 密钥，仅扫描导入可信客户端；这不是公开报名码。",
          ),
        ),
        model_connection_value(
          state.locale,
          "API Base URL",
          connection_base_url(state, value.model),
          emit,
        ),
        model_connection_value(state.locale, "Model ID", value.model, emit),
        model_connection_qr(
          state.locale,
          value.model,
          value.secret,
          emit,
          base_url=connection_base_url(state, value.model),
          max_output_tokens=connection_output_budget(state, value.model),
        ),
      ],
    ),
  ])
}

///|
fn personal_trial_model(state : EnterpriseState, model : String) -> Bool {
  state.trial.map_or(false, trial => {
    trial.revoked_unix_ms is None &&
    trial.starts_unix_ms <= state.machine_access.now_unix_ms &&
    trial.expires_unix_ms > state.machine_access.now_unix_ms &&
    trial.allowed_models.contains(model) &&
    state.membership.map_or(false, membership => {
      membership.organization_id == trial.organization_id &&
      membership.tenant_ref == trial.tenant_ref
    })
  })
}

///|
fn connection_base_url(state : EnterpriseState, model : String) -> String {
  if personal_trial_model(state, model) {
    browser_public_origin() + "/trial/v1"
  } else {
    public_maas_base_url()
  }
}

///|
fn connection_output_budget(state : EnterpriseState, model : String) -> Int32 {
  if personal_trial_model(state, model) {
    state.trial.map_or(1024, trial => trial.max_output_tokens.unwrap_or(1024))
  } else {
    16384
  }
}
