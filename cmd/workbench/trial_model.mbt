///|
priv struct TrialModelResource {
  alias_name : String?
  minimum_memory_mib : Int32
} derive(FromJson)

///|
fn trial_model_memory(catalog : String, model_selector : String) -> Int32 raise {
  let models : Array[TrialModelResource] = @json.from_json(@json.parse(catalog))
  guard models
    .iter()
    .find_first(model => model.alias_name == Some(model_selector))
    is Some(model) &&
    model.minimum_memory_mib > 0 else {
    raise WorkbenchClientError::PublicRejected(
      "ModelMetadataUnavailable", "当前模型的资源配置暂不可用，请刷新后重试。",
      "", false, true,
    )
  }
  model.minimum_memory_mib
}
