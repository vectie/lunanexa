///|
test "model source identifiers reject filesystem and URL injection" {
  assert_true(@modelsource.valid_model_id("OpenBMB/MiniCPM5-1B"))
  assert_false(@modelsource.valid_model_id("../escape"))
  assert_false(@modelsource.valid_model_id("owner/repo/extra"))
  assert_true(@modelsource.valid_revision("master"))
  assert_false(@modelsource.valid_revision("../master"))
  assert_true(@modelsource.valid_repository_path("weights/model.safetensors"))
  assert_false(@modelsource.valid_repository_path("../secret"))
  assert_false(@modelsource.valid_repository_path("a//b"))
}

///|
test "import identity is deterministic and source scoped" {
  let first = @modelsource.import_id("OpenBMB/MiniCPM5-1B", "master")
  let replay = @modelsource.import_id("OpenBMB/MiniCPM5-1B", "master")
  assert_eq(first, replay)
  assert_true(first.has_prefix("ms-"))
}
