///|
/// Read-only operator pagination. Cursors are positions, never credentials.
/// Every request is independently authorized by the controller.
pub(all) struct PageQuery {
  list : String
  query : String
  account_id : String
  cursor : String
} derive(ToJson, FromJson, Eq)

///|
pub extend PageQuery with ToJson::{to_json}

///|
pub extend PageQuery with FromJson::{from_json}

///|
pub extend PageQuery with Eq::{equal, not_equal}

///|
/// Items use the existing list's public read projection. Only the selected
/// window is projected; counts describe the full filtered result.
pub(all) struct ReadPage {
  items : Array[Json]
  total : Int32
  page : Int32
  previous_cursor : String
  next_cursor : String
  summary : Map[String, Int32]
} derive(ToJson, FromJson)

///|
pub extend ReadPage with ToJson::{to_json}

///|
pub extend ReadPage with FromJson::{from_json}
