///|
/// Read-only, half-open service window. Empty project/meter selects all values.
/// Grouping is project, cost-center, or meter. Intersecting records are included
/// in full, never prorated; rows that cross a boundary are counted explicitly.
pub(all) struct UsageQuery {
  organization_id : String
  started_unix_ms : Int64
  ended_unix_ms : Int64
  project_id : String
  meter : String
  group_by : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend UsageQuery with Debug::{to_repr}

///|
pub extend UsageQuery with Eq::{not_equal, equal}

///|
pub extend UsageQuery with ToJson::{to_json}

///|
pub extend UsageQuery with FromJson::{from_json}

///|
pub(all) struct UsageReportRow {
  cost_center_id : String
  cost_center_name : String
  project_id : String
  project_name : String
  event_id : String
  workload_id : String
  entry_id : String
  linked_entry_id : String
  kind : String
  rate_card_id : String
  rate_card_version : String
  reason : String
  meter : String
  unit : String
  quantity : Int64
  amount : FixedMoney?
  started_unix_ms : Int64
  ended_unix_ms : Int64
  recorded_unix_ms : Int64
  observation_available : Bool
  crosses_window : Bool
} derive(Debug, Eq, ToJson)

///|
pub extend UsageReportRow with Debug::{to_repr}

///|
pub extend UsageReportRow with Eq::{not_equal, equal}

///|
pub extend UsageReportRow with ToJson::{to_json}

///|
/// Different meters, units, currencies, scales and unpriced usage never merge.
pub(all) struct UsageReportGroup {
  group_id : String
  meter : String
  unit : String
  quantity : Int64
  amount : FixedMoney?
  row_count : Int
  ledger_entry_count : Int
  unpriced_usage_count : Int
  missing_observation_count : Int
  crossing_window_count : Int
} derive(Debug, Eq, ToJson)

///|
pub extend UsageReportGroup with Debug::{to_repr}

///|
pub extend UsageReportGroup with Eq::{not_equal, equal}

///|
pub extend UsageReportGroup with ToJson::{to_json}

///|
pub(all) struct UsageReport {
  query : UsageQuery
  rows : Array[UsageReportRow]
  groups : Array[UsageReportGroup]
} derive(Debug, Eq, ToJson)

///|
pub extend UsageReport with Debug::{to_repr}

///|
pub extend UsageReport with Eq::{not_equal, equal}

///|
pub extend UsageReport with ToJson::{to_json}
