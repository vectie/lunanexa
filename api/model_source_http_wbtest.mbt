///|
test "old model-source inventory decodes as whole-revision imports" {
  let legacy = Json::object({
    "import_id": Json::string("ms-old"),
    "source": Json::string("modelscope"),
    "model_id": Json::string("MiniMax/MiniMax-H3"),
    "revision": Json::string("master"),
    "state": Json::string("Verified"),
    "files_total": Json::number(1.0),
    "files_completed": Json::number(1.0),
    "bytes_total": Json::string("10"),
    "bytes_completed": Json::string("10"),
    "manifest_digest": Json::string("sha256:" + "a".repeat(64)),
    "artifact_uri": Json::string("modelstore://MiniMax/MiniMax-H3"),
    "license": Json::string("review"),
    "local_directory": Json::string("MiniMax/MiniMax-H3"),
    "error_code": Json::string(""),
    "cancel_requested": Json::boolean(false),
    "created_unix_ms": Json::string("1"),
    "updated_unix_ms": Json::string("2"),
  })
  let records = decode_model_source_imports(Json::array([legacy]).stringify())
  assert_eq(records.length(), 1)
  assert_eq(records[0].component, "")
}
