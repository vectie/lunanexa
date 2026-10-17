# Saved model and device declarations

This portable core joins model records and node heartbeats for local exploration.
It neither calls nor substitutes for the live scheduler. Read the
[workflow guide](../docs/MODEL_FLEET_QUICKSTART.md) before interpreting matches.

```mbt check
///|
test "an empty comparison is an explicit empty report" {
  let query = @model_fleet.import_query(
    (
      #|{"schema_version":"lunanexa.model-fleet.query.v1","now_unix_ms":"1000","maximum_age_ms":"100","memory_reserve_mib":0,"model_id":"","version":"","node_id":""}
    ),
  )
  let report = @model_fleet.explore([], [], query)
  assert_eq(report.selected_model_count, 0)
  assert_eq(report.rows.length(), 0)
  assert_eq(report.scope, "single-device-declarations-only")
}
```
