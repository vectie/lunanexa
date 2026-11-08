///|
fn table_scroll_attrs(locale : @i18n.Locale) -> @html.Attrs {
  @html.Attrs::build()
  .tabindex(0)
  .role("region")
  .aria_label(
    localized(locale, "Scrollable data table", "可横向滚动的数据表"),
  )
}
