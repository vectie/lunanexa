///|
test "media instance identity fences replacement even when address is reused" {
  let original : MediaBinding = {
    deployment_id: "deployment-test",
    deployment_generation: 1L,
    node_id: "node-test",
    origin: "http://10.42.1.34:5885",
    bearer: Some("test-only-original-token"),
    instance_id: Some("pod-original"),
    profile: {
      model: "test-only-video",
      provider_model: "fixture",
      widths: [512],
      heights: [512],
      maximum_frames: 48,
      maximum_fps: 24,
      maximum_steps: 20,
      sound_supported: false,
    },
  }
  let rotated = { ..original, bearer: Some("test-only-rotated-token") }
  assert_eq(original.identity(), rotated.identity())
  let replacement = { ..original, instance_id: Some("pod-replacement") }
  assert_false(original.identity() == replacement.identity())
  assert_eq(original.execution_context(), replacement.execution_context())
  for changed in [
    { ..original, origin: "http://10.42.1.35:5885" },
    { ..original, deployment_generation: 2L },
    { ..original, node_id: "node-other" },
    { ..original, profile: { ..original.profile, provider_model: "fixture-other" } },
    { ..original, instance_id: None },
  ] {
    assert_false(original.identity() == changed.identity())
  }
}
