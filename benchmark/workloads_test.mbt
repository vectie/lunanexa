///|
test "repeated prefixes stay identical and cold prefixes are genuinely distinct" {
  let first = @benchmark.workload_messages("repeat", "run", 1, 0)
  let next = @benchmark.workload_messages("repeat", "run", 1, 1)
  assert_eq(first[0], next[0])
  assert_false(first[1] == next[1])
  assert_false(
    @benchmark.workload_messages("cold", "run", 1, 0)[0] ==
    @benchmark.workload_messages("cold", "run", 1, 1)[0],
  )
  assert_false(
    first[0] == @benchmark.workload_messages("repeat", "run", 2, 0)[0],
  )
}

///|
test "quality regression changes facts after a reusable prefix" {
  let (a, expected_a) = @benchmark.quality_case("run", 3, 1)
  let (b, expected_b) = @benchmark.quality_case("run", 3, 2)
  assert_eq(a[0], b[0])
  assert_false(a[1] == b[1])
  assert_eq(expected_a, { "room": 304, "total": 16, "label": "青年共创" })
  assert_eq(expected_b, { "room": 305, "total": 16, "label": "青年共创" })
}

///|
test "fixed quality payloads and sampling are byte-identical across runs and repeats" {
  for user in 1..<=32 {
    for variant in 1..<=2 {
      let (before, expected) = @benchmark.request_fixture(
        "model", user, variant, "run-A", 128, "fixed", true,
      )
      for repeat in 1..<=2 {
        let (after, wanted) = @benchmark.request_fixture(
          "model",
          user,
          variant + repeat * 2,
          "run-B",
          128,
          "fixed",
          true,
        )
        assert_eq(before.stringify(), after.stringify())
        assert_eq(expected, wanted)
      }
      assert_true(before is { "temperature": 0, "top_p": 1, .. })
      assert_false(before.stringify().contains("run-A"))
    }
  }
}
