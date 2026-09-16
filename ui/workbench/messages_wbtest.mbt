///|
test "workflow messages have complete unique bilingual text" {
  let keys : Array[MessageText] = [
    LocalDraftWarning,
    ExportDraftsLabel,
    CopyReceipt,
    SelectAuthorizedModel,
    AdvancedModel,
  ]
  let seen : Map[String, Bool] = Map([])
  for key in keys {
    let english = message_text(English, key)
    let chinese = message_text(ChineseSimplified, key)
    assert_true(english.trim() != "")
    assert_true(chinese.trim() != "")
    assert_true(english != chinese)
    assert_false(seen.contains(english + chinese))
    seen[english + chinese] = true
  }
  assert_eq(keys.length(), 5)
}

///|
test "typed messages preserve identifiers and numeric arguments in both languages" {
  assert_eq(
    lease_remaining_message(English, "lease-opaque", 42L),
    "Lease lease-opaque · 42m remaining",
  )
  assert_eq(
    lease_remaining_message(ChineseSimplified, "lease-opaque", 42L),
    "租约 lease-opaque · 剩余 42 分钟",
  )
  assert_eq(local_drafts_message(English, 3), "3 LOCAL")
  assert_eq(local_drafts_message(ChineseSimplified, 3), "3 个本地草稿")
  for locale in [@i18n.Locale::English, ChineseSimplified] {
    assert_true(
      handoff_requested_message(locale, "client-opaque").contains(
        "client-opaque",
      ),
    )
  }
}
