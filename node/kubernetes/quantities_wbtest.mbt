///|
test "canonical quantities preserve strict resource integrity checks" {
  let submitted : Json = {
    "resources": {
      "requests": {
        "cpu": Json(canonical_cpu_quantity(1000)),
        "memory": Json(canonical_memory_quantity(2048)),
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
