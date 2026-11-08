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
    "request_id": Json(request_id),
    "client_id": Json(client_id),
    "project_id": Json(project_id),
    "allowed_models": Json(allowed_models),
  }
  if order_id is Some(value) {
    fields["order_id"] = Json(value)
  }
  Json::object(fields)
}
