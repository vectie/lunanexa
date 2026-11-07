///|
test "quality diagnostics preserve strict equality without retaining answers" {
  let expected : Json = { "room": 302, "total": 10, "label": "青年共创" }
  assert_eq(quality_error(expected.stringify(), expected), "")
  assert_eq(quality_error("private answer", expected), "quality: invalid JSON")
  assert_eq(quality_error("[]", expected), "quality: expected JSON object")
  assert_eq(
    quality_error(
      ({ "room": 301, "total": 10, "label": "青年共创" } : Json).stringify(),
      expected,
    ),
    "quality: mismatch room",
  )
  assert_eq(
    quality_error(
      ({ "room": 302, "total": "10", "label": "private" } : Json).stringify(),
      expected,
    ),
    "quality: mismatch total, label",
  )
  assert_eq(
    quality_error(
      (
        {
          "room": 302,
          "total": 10,
          "label": "青年共创",
          "private": "secret",
        } : Json).stringify(),
      expected,
    ),
    "quality: mismatch field count",
  )
}
