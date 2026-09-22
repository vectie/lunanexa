///|
/// Derived backend Option decoding expects a missing member, not JSON null.
fn desktop_handoff_payload(
  request_id : String,
  client_id : String,
  project_id : String,
  order_id : String?,
  allowed_models : Array[String],
) -> Json {
  let fields : Map[String, Json] = {
    "request_id": request_id.to_json(),
    "client_id": client_id.to_json(),
    "project_id": project_id.to_json(),
    "allowed_models": allowed_models.to_json(),
  }
  if order_id is Some(value) {
    fields["order_id"] = value.to_json()
  }
  Json::object(fields)
}
