///|
test "storage monitor validates capacity and keeps missing mounts unavailable" {
  assert_true(
    parse_storage_capacity("1000,400,300,100,80") is Some(value) &&
    value.total_bytes == 1000L &&
    value.available_bytes == 300L,
  )
  assert_true(parse_storage_capacity("1000,400,500,100,80") is None)
  assert_true(parse_storage_capacity("1000,400,300,100,101") is None)
  assert_true(
    read_storage_capacity("/this-mount-does-not-exist-lunanexa") is None,
  )
  assert_true(
    read_storage_capacity("/") is Some(value) &&
    value.total_bytes > 0L &&
    value.available_bytes <= value.total_bytes,
  )
}
