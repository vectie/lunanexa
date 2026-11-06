///|
test "image workflow admits only prompt and seed and pins one bounded output" {
  let provider = Provider::new("http://image-runtime:8188", {
    diffusion: "z_image_turbo_bf16.safetensors",
    text_encoder: "qwen_3_4b.safetensors",
    vae: "ae.safetensors",
  })
  let input = provider.workflow("一杯咖啡", 42U, "request-abc")
  assert_true(
    input
    is {
      "prompt": {
        "6": {
          "inputs": {
            "width": Number(1024, ..),
            "height": Number(1024, ..),
            "batch_size": Number(1, ..),
            ..
          },
          ..
        },
        "8": {
          "inputs": { "steps": Number(8, ..), "cfg": Number(1, ..), .. },
          ..
        },
        "10": { "inputs": { "filename_prefix": String("request-abc"), .. }, .. },
        ..
      },
      ..
    },
  )
  assert_true(
    try {
      ignore(provider.workflow("x", 1U, "../../private"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        Provider::new("http://user:secret@host", {
          diffusion: "x",
          text_encoder: "y",
          vae: "z",
        }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_false(input.stringify().contains("LoadImage"))
}
