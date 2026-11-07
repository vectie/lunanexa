///|
/// An owner/repository is an identity, not a fuzzy full-text query. Searching
/// descriptions for it can otherwise offer unrelated models for download.
fn model_catalog_exact_id(query : String) -> Bool {
  let parts = query.split("/").collect()
  query.length() <= 180 &&
  parts.length() == 2 &&
  parts.all(part => {
    part.length() > 0 &&
    part.length() <= 90 &&
    part != "." &&
    part != ".." &&
    part.all(c => {
      c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      c == '-' ||
      c == '_' ||
      c == '.'
    })
  })
}

///|
fn model_catalog_search_request(query : String) -> (String, Json) {
  if model_catalog_exact_id(query) {
    ("/v1/model-sources/modelscope/detail", { "model_id": query })
  } else {
    (
      "/v1/model-sources/modelscope/search",
      { "query": query, "page_number": 1, "page_size": 50 },
    )
  }
}

///|
fn decode_model_catalog_search(
  query : String,
  value : Json,
) -> @ui.ModelSourceCatalogPage raise {
  if model_catalog_exact_id(query) {
    let model : @ui.ModelSourceCatalogRow = @json.from_json(value)
    guard model.id.to_lower() == query.to_lower() else {
      raise Failure("model source returned a different repository")
    }
    { models: [model], total_count: 1L, page_number: 1, page_size: 1, }
  } else {
    @json.from_json(value)
  }
}
