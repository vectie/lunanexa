///|
/// Frozen execution inputs contain document field values. Keep them in the
/// durable authority, not the operational listing consumed by the console.
fn offline_operator_snapshot(
  snapshot : @offline.OfflineCommerceSnapshot,
) -> Json {
  match snapshot.to_json() {
    Object(fields) => {
      let safe = fields.copy()
      safe["generation_plans"] = Json(({} : Map[String, String]))
      Json(safe)
    }
    value => value
  }
}
