///|
priv enum GuidanceMessage {
  FirstCallSetup
  MissingApiEntrance
  FirstCallErrors
  TrialSecret
}

///|
fn message(locale : @i18n.Locale, key : GuidanceMessage) -> String {
  let (en, zh) = match key {
    FirstCallSetup =>
      (
        "Text-generation example: use an allowed text-capable alias; other capabilities require their matching envelope and payload. Set API_KEY to the secret above in your terminal. The example never embeds your secret. Each run uses a new request ID and a fresh deadline.",
        "文本生成示例：请使用允许调用且支持文本的别名；其他能力需使用对应的请求结构和输入。在终端中将 API_KEY 设置为上方密钥。示例不嵌入密钥，每次运行生成新的请求 ID 和截止时间。",
      )
    MissingApiEntrance =>
      (
        "API entrance — ask your operator. Do not use the browser portal address as the API entrance.",
        "请向管理员索取 API 入口，不要把浏览器门户地址当作 API 入口。",
      )
    FirstCallErrors =>
      (
        "401: check the API entrance and key. 403: check the allowed model and active authorization. 429: inspect your request quota and retry window; do not repeatedly retry.",
        "401：核对 API 入口与密钥。403：核对允许的模型及有效授权。429：查看请求配额及重试时间，不要连续重试。",
      )
    TrialSecret =>
      (
        "One key is bound to each trial. View, copy or test your active key in Account & API keys. A revoked key is not restored; expiry does not grant a new trial.",
        "每次体验绑定一把密钥。可在「账户与 API 密钥」查看、复制或测试有效密钥；已撤销密钥不会恢复，到期不会自动获得新体验。",
      )
  }
  @i18n.copy(locale, en, zh)
}
