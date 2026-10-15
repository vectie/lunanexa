///|
// Only identifiers already displayed in this subject-authorized projection
// reach this helper. Signed payloads and provider references are not copied.
fn public_identifier_copy(
  locale : @i18n.Locale,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  value : String,
  actor : Bool,
) -> @rabbita.Html {
  if value == "" || value.length() > 512 {
    return @html.nothing
  }
  @controls.icon_button(
    Copy,
    if actor {
      copy(locale, "Copy actor ID", "复制操作人标识")
    } else {
      copy(locale, "Copy packet ID", "复制资料包标识")
    },
    command(emit, CopyPublicIdentifier(value)),
  )
}
