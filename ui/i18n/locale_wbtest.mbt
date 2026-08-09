///|
test "locale exposes stable browser and HTML language values" {
  debug_inspect(default_locale(), content="English")
  inspect(English.storage_value(), content="en")
  inspect(ChineseSimplified.language_tag(), content="zh-CN")
  inspect(English.label(), content="English")
  inspect(ChineseSimplified.label(), content="简体中文")
}

///|
test "locale parsing is tolerant and fails safely to English" {
  debug_inspect(parse_locale("zh-CN"), content="ChineseSimplified")
  debug_inspect(parse_locale(" ZH-hans "), content="ChineseSimplified")
  debug_inspect(parse_locale("not-a-locale"), content="English")
  debug_inspect(parse_locale(""), content="English")
}

///|
test "locale alternation is exhaustive" {
  debug_inspect(English.alternate(), content="ChineseSimplified")
  debug_inspect(ChineseSimplified.alternate(), content="English")
  assert_true(ChineseSimplified.is_chinese())
  assert_false(English.is_chinese())
}
