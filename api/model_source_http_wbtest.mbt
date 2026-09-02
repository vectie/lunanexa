///|
test "model-source retry route is narrow and maps to the private adapter" {
  let path = "/v1/model-sources/modelscope/imports/ms-0123456789abcdef/retry"
  assert_true(model_source_path(path))
  assert_eq(
    internal_model_source_path(path),
    Some("/internal/v1/modelscope/imports/ms-0123456789abcdef/retry"),
  )
  assert_false(
    model_source_path(
      "/v1/model-sources/modelscope/imports/ms-0123456789abcdef/delete",
    ),
  )
}
