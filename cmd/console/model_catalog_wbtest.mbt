///|
test "complete model repository names use exact lookup instead of fuzzy search" {
  let id = "nv-community/Qwen3.6-35B-A3B-NVFP4"
  assert_true(model_catalog_exact_id(id))
  let (path, body) = model_catalog_search_request(id)
  assert_eq(path, "/v1/model-sources/modelscope/detail")
  assert_eq(body, { "model_id": id })
  let (path, body) = model_catalog_search_request("Qwen3.6 NVFP4")
  assert_eq(path, "/v1/model-sources/modelscope/search")
  assert_eq(body, {
    "query": "Qwen3.6 NVFP4",
    "page_number": 1,
    "page_size": 50,
  })
  for
    invalid in [
      "../model", "owner/..", "a/b/c", "https://example.com/repo", "/model", "owner/",
    ] {
    assert_false(model_catalog_exact_id(invalid))
  }
}

///|
test "exact repository lookup rejects an unrelated successful response" {
  let model : @ui.ModelSourceCatalogRow = {
    id: "nv-community/Qwen3.6-35B-A3B-NVFP4",
    display_name: "Qwen3.6-35B-A3B-NVFP4",
    description: "",
    downloads: 1L,
    likes: 0L,
    license: "apache-2.0",
    tasks: ["text-generation"],
    created_at: "",
    last_modified: "",
    file_size: 23410000000L,
    params: 19528000000L,
    tags: [],
    private: false,
    gated: false,
  }
  let page = decode_model_catalog_search(model.id, model.to_json())
  assert_eq(page.models, [model])
  assert_eq(page.total_count, 1L)
  let rejected = try {
    ignore(
      decode_model_catalog_search(
        "nvidia/Qwen3.6-35B-A3B-NVFP4",
        model.to_json(),
      ),
    )
    false
  } catch {
    _ => true
  } noraise {
    value => value
  }
  assert_true(rejected)
}
