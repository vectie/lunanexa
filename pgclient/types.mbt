///|
/// Everything this package can fail with. The distinction matters to callers:
/// `QueryRejected` means the server answered and refused the statement, so
/// retrying it unchanged is pointless, while `ConnectionUnavailable` and
/// `Timeout` are worth retrying.
pub(all) suberror PgError {
  ConnectionUnavailable(String)
  QueryRejected(String)
  InvalidArgument(String)
  Timeout
  Closed
} derive(Debug, Eq)

///|
/// One finished statement.
pub struct PgResult {
  handle : @postgres.QueryResult
}

///|
/// How many rows the statement returned. A statement that returns no rows
/// (an INSERT without RETURNING, for instance) reports zero, so use
/// `affected_rows` for it.
pub fn PgResult::row_count(self : PgResult) -> Int {
  self.handle.row_count()
}

///|
pub fn PgResult::column_count(self : PgResult) -> Int {
  self.handle.column_count()
}

///|
/// The value at `row`/`column`, or `None` for SQL NULL and for out-of-range
/// positions. Values are decoded as UTF-8 on the text protocol; binary values
/// arrive already decoded as bytes by libpq, and lossy decoding is used only
/// for the byte sequence that is not valid UTF-8.
pub fn PgResult::value(self : PgResult, row : Int, column : Int) -> String? {
  self.handle.value(row, column)
}

///|
/// Rows affected by an INSERT, UPDATE, or DELETE.
pub fn PgResult::affected_rows(self : PgResult) -> Int64 {
  self.handle.affected_rows()
}

///|
/// Collects a single-column result into a string array, which is the shape
/// most control-plane reads want.
pub fn PgResult::column(self : PgResult, index? : Int = 0) -> Array[String] {
  let values : Array[String] = []
  for row in 0..<self.row_count() {
    match self.value(row, index) {
      Some(value) => values.push(value)
      None => ()
    }
  }
  values
}

///|
/// True when the statement returned at least one row, which is how the
/// `EXISTS (...)` helpers are read.
pub fn PgResult::is_true(self : PgResult) -> Bool {
  match self.value(0, 0) {
    Some(value) => value == "true" || value == "t"
    None => false
  }
}
