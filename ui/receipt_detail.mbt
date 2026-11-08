///|
fn receipt_detail(
  locale : @i18n.Locale,
  value : String,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  if value == "" {
    return @html.span("—")
  }
  @html.div([
    @controls.icon_button(
      Copy,
      localized(locale, "Copy receipt", "复制回执"),
      command(emit, CopyReference(value)),
    ),
    @html.details(class="ln-advanced", [
      @html.summary(
        class="mono",
        if value.length() > 24 {
          value[:16].to_owned() + "…"
        } else {
          value
        },
      ),
      @html.code(class="mono", value),
    ]),
  ])
}
