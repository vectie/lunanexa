///|
fn model_connection_value(
  locale : @i18n.Locale,
  label : String,
  value : String,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  @html.div(
    style=["display:flex", "align-items:center", "gap:.5rem", "flex-wrap:wrap"],
    [
      @html.p([@html.strong(label + ": "), @html.code(value)]),
      @controls.icon_button(
        Copy,
        copy(locale, "Copy ", "复制") + label,
        command(emit, CopyDetail(value)),
      ),
    ],
  )
}

///|
fn model_connection_example(
  locale : @i18n.Locale,
  title : String,
  example : String,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  @html.section([
    @html.div(style=["display:flex", "align-items:center", "gap:.5rem"], [
      @html.h4(title),
      @controls.icon_button(
        Copy,
        copy(locale, "Copy ", "复制") + title,
        command(emit, CopyDetail(example)),
      ),
    ]),
    @html.pre(
      class="mono",
      style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
      example,
    ),
  ])
}

///|
fn model_connection_guides(
  locale : @i18n.Locale,
  service : ExternalModelServiceView,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let base = public_maas_base_url()
  @html.div([
    @html.p(
      copy(
        locale, "API key: use the copy icon in Account & API keys.", "API 密钥：在账户与 API 密钥中点击复制图标。",
      ),
    ),
    @controls.advanced(copy(locale, "TRAE setup", "TRAE 接入"), [
      @html.p(
        copy(
          locale, "Settings → Models → Add model → Custom model", "设置 → 模型 → 添加模型 → 自定义模型",
        ),
      ),
      @html.p("OpenAI Chat Completions"),
      @html.p(copy(locale, "Full URL: on", "完整 URL：开启")),
      model_connection_value(
        locale,
        copy(locale, "Full request URL", "完整请求地址"),
        base + "/chat/completions",
        emit,
      ),
      model_connection_value(locale, "Model ID", service.model_alias, emit),
      model_connection_value(
        locale,
        copy(
          locale, "Advanced → Context window → Output", "高级配置 → 上下文窗口 → 输出",
        ),
        "16384",
        emit,
      ),
      @html.p(
        copy(
          locale, "Model family: Default. Turn off Multimodal beside Model ID. Save, then start a new conversation.",
          "模型系列：默认。关闭模型 ID 旁的“多模态”。保存后新建对话。",
        ),
      ),
    ]),
    @controls.advanced(copy(locale, "Call examples", "调用示例"), [
      model_connection_example(
        locale,
        copy(locale, "Call example", "调用示例"),
        model_api_example(base, service.model_alias),
        emit,
      ),
      model_connection_example(
        locale,
        copy(locale, "Streaming example", "流式调用示例"),
        model_api_example(base, service.model_alias, stream=true),
        emit,
      ),
      model_connection_example(
        locale,
        copy(locale, "Model discovery example", "模型列表查询示例"),
        model_discovery_example(base),
        emit,
      ),
    ]),
    @controls.advanced(
      copy(locale, "Advanced · limits and errors", "高级 · 限制与排错"),
      [
        @html.ul([
          @html.li(
            copy(
              locale, "401 Unauthenticated: use the saved lnx_… secret. An api-key-… record ID cannot authenticate requests.",
              "401 Unauthenticated：使用已保存的 lnx_… 密钥；api-key-… 是记录编号。",
            ),
          ),
          @html.li(
            copy(
              locale, "InvalidRequest: set output to 16384. max_tokens accepts 1–131072, omission or null; the context window is a separate limit.",
              "InvalidRequest：将输出设为 16384。max_tokens 支持 1–131072，或省略、设为 null；上下文窗口是另一项限制。",
            ),
          ),
          @html.li(
            copy(
              locale, "RequestBudgetExceeded: shorten history, attached files or tool definitions. The current request-body limit is 1 MiB of UTF-8 JSON, not a token count.",
              "RequestBudgetExceeded：减少历史、附件或工具定义。当前请求体上限为 1 MiB UTF-8 JSON，并非 Token 数。",
            ),
          ),
          @html.li(
            copy(
              locale, "RuntimeUnavailable: check service readiness and retry a new conversation. Contact the operator if it persists.",
              "RuntimeUnavailable：确认服务已就绪后新建对话重试；持续失败请联系管理员。",
            ),
          ),
        ]),
      ],
    ),
    @html.a(
      class="quiet-button external-action",
      href="/docs/?page=client-api",
      copy(locale, "GLM API guide", "GLM API 接入指南"),
    ),
  ])
}
