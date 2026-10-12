///|
test "snapshot paths resolve relative to manifest rather than process cwd" {
  assert_eq(
    source_path("/tmp/private/manifest.json", "first.json"),
    "/tmp/private/first.json",
  )
  assert_eq(
    source_path("relative/manifest.json", "first.json"),
    "relative/first.json",
  )
  assert_eq(source_path("manifest.json", "first.json"), "first.json")
  assert_eq(source_path("/manifest.json", "first.json"), "/first.json")
  assert_eq(
    source_path("relative/manifest.json", "/absolute/first.json"),
    "/absolute/first.json",
  )
}
