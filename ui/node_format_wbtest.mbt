///|
test "node capacity units preserve readable scale at storage boundaries" {
  assert_eq(storage_gib(-1L), "0 B")
  assert_eq(storage_gib(1023L), "1023 B")
  assert_eq(storage_gib(1024L), "1.0 KiB")
  assert_eq(storage_gib(1073741824L), "1.0 GiB")
  assert_eq(storage_gib(10995116277760L), "10.0 TiB")
  assert_eq(node_count_label(ChineseSimplified, 1000000000L), "10.0亿")
  assert_eq(node_count_label(English, 1000000000L), "1.0B")
}
