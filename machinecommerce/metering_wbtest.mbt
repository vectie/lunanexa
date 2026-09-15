///|
test "cumulative seconds are independent of interval partitioning" {
  for duration in [1L, 999L, 1000L, 1001L, 300000L] {
    for step in [1L, 7L, 999L, 1000L, 63155L] {
      let mut previous = 0L
      let mut total = 0L
      while previous < duration {
        let next = (previous + step).min(duration)
        let increment = cumulative_seconds(next) - cumulative_seconds(previous)
        assert_true(increment >= 0L)
        total += increment
        previous = next
      }
      assert_eq(total, cumulative_seconds(duration))
    }
  }
  assert_eq(cumulative_seconds(0L), 0L)
  assert_eq(cumulative_seconds(9223372036854775807L), 9223372036854776L)
}
