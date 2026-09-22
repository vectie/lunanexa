///|
test "approved OFL preview family does not impersonate proprietary source fonts" {
  assert_eq(preview_font_stack("Noto Sans SC"), "'Noto Sans SC',sans-serif")
  assert_true(
    preview_font_stack("FangSong_GB2312").contains("LunaNexa FangSong"),
  )
  assert_false(
    preview_font_stack("FangSong_GB2312").has_prefix("'Noto Sans SC'"),
  )
}
