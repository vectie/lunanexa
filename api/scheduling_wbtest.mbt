///|
test "placement does not reinterpret the runtime safety ceiling as an estimate" {
  assert_eq(placement_runtime_estimate_ms(120000L, None), 0L)
  assert_eq(placement_runtime_estimate_ms(120000L, Some(90L)), 90L)
  assert_eq(placement_runtime_estimate_ms(120000L, Some(130000L)), 120000L)
  assert_eq(placement_runtime_estimate_ms(120000L, Some(-1L)), 0L)
}
