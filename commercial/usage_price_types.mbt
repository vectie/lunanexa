///|
/// Analyst-authored candidate rates. This is not a quote or a ledger mutation.
pub(all) struct UsagePriceScenario {
  schema_version : Int
  rates : Array[RateCard]
} derive(Eq, ToJson, FromJson)

///|
pub(all) enum UsagePriceStatus {
  Compared
  EstimatedUnpriced
  MissingObservation
  NoCoveringRate
  AmbiguousRate
  MoneyUnitMismatch
  RecordedAdjustment
} derive(Eq, ToJson)

///|
pub(all) struct UsagePriceRow {
  recorded : UsageReportRow
  status : UsagePriceStatus
  matched_rate_count : Int
  candidate_rate_card_id : String
  candidate_rate_card_version : String
  hypothetical_amount : FixedMoney?
  delta : FixedMoney?
} derive(Eq, ToJson)

///|
/// Each group has one status and exact recorded/hypothetical money dimensions.
/// Delta is present only for comparable recorded charges, never for unknowns.
pub(all) struct UsagePriceGroup {
  group_id : String
  meter : String
  unit : String
  status : UsagePriceStatus
  row_count : Int
  quantity : Int64
  crossing_window_count : Int
  recorded_amount : FixedMoney?
  hypothetical_amount : FixedMoney?
  delta : FixedMoney?
} derive(Eq, ToJson)

///|
pub(all) struct UsagePriceReport {
  query : UsageQuery
  scenario : UsagePriceScenario
  rows : Array[UsagePriceRow]
  groups : Array[UsagePriceGroup]
} derive(Eq, ToJson)

///|
pub extend UsagePriceScenario with Eq::{not_equal, equal}

///|
pub extend UsagePriceScenario with ToJson::{to_json}

///|
pub extend UsagePriceStatus with Eq::{not_equal, equal}

///|
pub extend UsagePriceStatus with ToJson::{to_json}

///|
pub extend UsagePriceRow with Eq::{not_equal, equal}

///|
pub extend UsagePriceRow with ToJson::{to_json}

///|
pub extend UsagePriceGroup with Eq::{not_equal, equal}

///|
pub extend UsagePriceGroup with ToJson::{to_json}

///|
pub extend UsagePriceReport with Eq::{not_equal, equal}

///|
pub extend UsagePriceReport with ToJson::{to_json}

///|
pub extend UsagePriceScenario with FromJson::{from_json}
