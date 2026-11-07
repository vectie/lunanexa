///|
test "runtime control validates exact container identity and reports partial pairs" {
  let target = {
    host: "gpu-head@example.invalid",
    container: "fixture-runtime-head",
    image: "registry/model-runtime@sha256:123",
  }
  let document : Json = [
    {
      "Id": "a".repeat(64),
      "Name": "/fixture-runtime-head",
      "Config": { "Image": "registry/model-runtime@sha256:123" },
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
      (
        {
          host: "gpu-worker@example.invalid",
          container: "fixture-runtime-worker",
          image: target.image,
        },
        "b".repeat(64),
        false,
      ),
    ]),
    "Partial",
  )
  try
    inspected_container(
      document.stringify().replace(old="fixture-runtime-head", new="other"),
      target,
    )
  catch {
    _ => return
  } noraise {
    _ => fail("foreign container accepted")
  }
}
