///|
test "canonical quantities preserve strict resource integrity checks" {
  let submitted : Json = {
    "resources": {
      "requests": {
        "cpu": canonical_cpu_quantity(1000).to_json(),
        "memory": canonical_memory_quantity(2048).to_json(),
      },
    },
  }
  assert_true(
    contains_submitted(
      { "resources": { "requests": { "cpu": "1", "memory": "2Gi" } } },
      submitted,
    ),
  )
  assert_false(
    contains_submitted(
      { "resources": { "requests": { "cpu": "2", "memory": "2Gi" } } },
      submitted,
    ),
  )
  assert_false(
    contains_submitted(
      { "resources": { "requests": { "cpu": "1", "memory": "4Gi" } } },
      submitted,
    ),
  )
}
