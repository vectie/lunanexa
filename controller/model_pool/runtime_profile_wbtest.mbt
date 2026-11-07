///|
fn fixture_runtime_profile() -> RuntimeProfile {
  {
    artifact_digests: ["sha256:" + "a".repeat(64)],
    architecture: "nvidia-sm121",
    arguments: ["--max-model-len", "65536", "--gpu-memory-utilization", "0.80"],
    speculative: Some({
      "method": "fixture_mtp",
      "moe_backend": "fixture_backend",
    }),
  }
}

///|
test "model family never selects runtime parsers or speculative algorithms" {
  let selected = {
    ..fixture_selection(),
    model_id: "glm",
    model_alias: "glm-5",
  }
  let profile = {
    ..fixture_runtime_profile(),
    arguments: ["--reasoning-parser", "reviewed-parser"],
  }
  let args = runtime_args(selected, 0, profile~)
  assert_true(args.contains("reviewed-parser"))
  assert_false(args.contains("qwen3"))
  assert_false(args.contains("marlin"))
  let other = { ..selected, model_id: "deepseek", model_alias: "deepseek-v4", }
  // Only the served model alias changes. Execution options stay profile data.
  assert_eq(runtime_args(other, 0, profile~), args)
}
