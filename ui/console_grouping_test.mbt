
///|
fn model_artifact(
  model_id : String,
  version : String,
  state : @contracts.ModelState,
) -> @ui.ModelRow {
  {
    model_id,
    version,
    state,
    license_status: "Accepted",
    evaluation_status: "passed",
    compatibility: "nvidia-sm120",
    alias_name: "—",
  }
}

///|
test "registered artifacts are grouped under their model" {
  let groups = @ui.group_models_by_model_id([
    model_artifact("qwen3-0.6b", "qualified-20260901-r58-c32", Verified),
    model_artifact("tiny-bf16", "qualified-20260830-r12", Approved),
    model_artifact(
      "qwen3-0.6b",
      "qualified-20260902-r67-output-envelope-c32",
      Approved,
    ),
  ])
  assert_eq(groups.length(), 2)
  assert_eq(groups[0].0, "qwen3-0.6b")
  assert_eq(groups[0].1.length(), 2)
  assert_eq(groups[1].0, "tiny-bf16")
  assert_eq(groups[1].1.length(), 1)
  // A model keeps the order the controller reported, so the newest
  // qualification profile stays last inside its group.
  assert_eq(
    groups[0].1[1].version,
    "qualified-20260902-r67-output-envelope-c32",
  )
}
