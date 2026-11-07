///|
test "model families group by upstream generation rather than artifact revision" {
  for
    (id, family, generation) in [
      ("qwen-qwen3.8-27b-fp8", "Qwen", "Qwen 3.8"),
      ("radixark-qwen3.8-flash-next-nvfp4", "Qwen", "Qwen 3.8"),
      ("incoai-glm-5.3-flash-dflash2", "GLM", "GLM 5.3"),
      ("deepseek-ai-deepseek-v4-flash-dspark", "DeepSeek", "DeepSeek v4"),
      ("moonshotai-kimi-k2.5", "Kimi", "Kimi k2.5"),
      ("stepfun-ai-step-3.5-flash", "StepFun", "StepFun 3.5"),
      ("minimax-h3-fl2va", "MiniMax", "MiniMax h3"),
      ("openbmb-minicpm5-1b", "Other", "openbmb-minicpm5-1b"),
    ] {
    assert_eq(model_family(id), family)
    assert_eq(model_generation(id, family), generation)
  }
}

///|
test "variant rendering retains every artifact and original action under family disclosure" {
  let base = demo_state()
  let first = {
    ..base.models[0],
    model_id: "qwen-qwen3.8-27b-fp8",
    version: "modelscope-master",
  }
  let second = { ..first, model_id: "qwen-qwen3.8-27b-nvfp4", }
  let old = { ..first, version: "previous", state: Revoked, }
  let html = render({ ..base, route: Models, models: [first, second, old], })
  assert_eq(html.split("class=\"model-family\"").count() - 1, 1)
  assert_eq(html.split("class=\"model-registry-group\"").count() - 1, 1)
  assert_true(html.contains("Qwen 3.8 (2)"))
  assert_true(html.contains(first.model_id))
  assert_true(html.contains(second.model_id))
  assert_true(html.contains("previous"))
  assert_true(html.contains("<summary>More</summary>"))
  assert_true(html.contains("Verify artifact"))
  assert_true(html.contains("Promote alias…"))
}

///|
test "model generations sort newest first with numeric components" {
  let names = ["Qwen 3", "Qwen 3.9", "Qwen 3.10", "Qwen 3.8"]
  names.sort_by(compare_model_generations)
  assert_eq(names, ["Qwen 3.10", "Qwen 3.9", "Qwen 3.8", "Qwen 3"])
}
