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
    license_id: "license.qualified",
    artifact_uri: "modelstore://\{model_id}/\{version}",
    artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
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

///|
test "the template runtime picker lists each registered runtime once" {
  let demo = @ui.demo_state()
  let keys = @ui.known_runtimes(demo).map(runtime => @ui.runtime_key(runtime))
  // The roster comes first, then any runtime only a registered template names.
  assert_eq(keys, [
    "text-runtime@runtime-v1", "embedding-runtime@runtime-v1", "vision-runtime@runtime-v2",
  ])
  // The template's own runtime is already in the roster, so it is not repeated:
  // a picker with two identical entries would let an operator choose a runtime
  // the registry lists once.
  let roster = demo.registered_runtimes.filter(runtime => {
    runtime.name != "text-runtime"
  })
  let regrouped = @ui.known_runtimes({ ..demo, registered_runtimes: roster, }).map(runtime => {
      @ui.runtime_key(runtime)
    },
  )
  assert_eq(regrouped, [
    "embedding-runtime@runtime-v1", "vision-runtime@runtime-v2", "text-runtime@runtime-v1",
  ])
}
