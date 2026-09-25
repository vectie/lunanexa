///|
test "GLM control validates exact container identity and reports partial pairs" {
  let target = targets()[0]
  let document : Json = [
    {
      "Id": "a".repeat(64),
      "Name": "/glm53-exl3-head",
      "Config": { "Image": "registry/glm-5.3-flash-2x-dgx-sparks@sha256:123" },
      "State": { "Running": true },
    },
  ]
  assert_eq(
    inspected_container(document.stringify(), target),
    ("a".repeat(64), true),
  )
  assert_eq(
    state([
      (target, "a".repeat(64), true),
      (targets()[1], "b".repeat(64), false),
    ]),
    "Partial",
  )
  try
    inspected_container(
      document.stringify().replace(old="glm53-exl3-head", new="other"),
      target,
    )
  catch {
    _ => return
  } noraise {
    _ => fail("foreign container accepted")
  }
}
