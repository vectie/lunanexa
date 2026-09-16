///|
test "new guidance catalog has nonempty distinct bilingual messages" {
  for key in [FirstCallSetup, MissingApiEntrance, FirstCallErrors, TrialSecret] {
    let en = message(English, key)
    let zh = message(ChineseSimplified, key)
    assert_false(en.is_empty())
    assert_false(zh.is_empty())
    assert_false(en == zh)
  }
}
