///|
type NativeConnection

///|
type NativeResult

///|
#borrow(connection_url)
extern "c" fn native_connect(connection_url : Bytes) -> NativeConnection = "lunanexa_pg_connect"

///|
#borrow(connection)
extern "c" fn native_connection_ok(connection : NativeConnection) -> Bool = "lunanexa_pg_connection_ok"

///|
#borrow(connection)
extern "c" fn native_connection_error(connection : NativeConnection) -> Bytes = "lunanexa_pg_connection_error"

///|
#borrow(connection)
extern "c" fn native_close(connection : NativeConnection) -> Unit = "lunanexa_pg_close"

///|
#borrow(connection, sql, parameters)
extern "c" fn native_execute(
  connection : NativeConnection,
  sql : Bytes,
  parameters : Bytes,
  parameter_count : Int,
) -> NativeResult = "lunanexa_pg_execute"

///|
#borrow(result)
extern "c" fn native_result_ok(result : NativeResult) -> Bool = "lunanexa_pg_result_ok"

///|
#borrow(result)
extern "c" fn native_result_error(result : NativeResult) -> Bytes = "lunanexa_pg_result_error"

///|
#borrow(result)
extern "c" fn native_row_count(result : NativeResult) -> Int = "lunanexa_pg_row_count"

///|
#borrow(result)
extern "c" fn native_column_count(result : NativeResult) -> Int = "lunanexa_pg_column_count"

///|
#borrow(result)
extern "c" fn native_is_null(
  result : NativeResult,
  row : Int,
  column : Int,
) -> Bool = "lunanexa_pg_is_null"

///|
#borrow(result)
extern "c" fn native_value(
  result : NativeResult,
  row : Int,
  column : Int,
) -> Bytes = "lunanexa_pg_value"

///|
#borrow(result)
extern "c" fn native_affected_rows(result : NativeResult) -> Int64 = "lunanexa_pg_affected_rows"

///|
pub(all) suberror PostgresError {
  ConnectionFailed(String)
  QueryFailed(String)
  InvalidParameter(String)
} derive(Debug, Eq)

///|
pub struct Connection {
  handle : NativeConnection
}

///|
pub struct QueryResult {
  handle : NativeResult
}

///|
fn safe_error(bytes : Bytes) -> String {
  let message = @utf8.decode_lossy(bytes).trim().to_owned()
  if message == "" {
    "PostgreSQL operation failed"
  } else if message.length() > 2048 {
    message[:2048].to_owned()
  } else {
    message
  }
}

///|
pub fn connect(connection_url : String) -> Connection raise PostgresError {
  let value = connection_url.trim().to_owned()
  if value == "" || value.contains_char('\n') || value.contains_char('\u0000') {
    raise InvalidParameter("database connection URL is invalid")
  }
  let handle = native_connect(@utf8.encode(value))
  if !native_connection_ok(handle) {
    let message = safe_error(native_connection_error(handle))
    native_close(handle)
    raise ConnectionFailed(message)
  }
  { handle, }
}

///|
fn append_length(output : Array[Byte], length : Int) -> Unit {
  output.push((length >> 24).to_byte())
  output.push((length >> 16).to_byte())
  output.push((length >> 8).to_byte())
  output.push(length.to_byte())
}

///|
fn encode_parameters(parameters : Array[String?]) -> Bytes raise PostgresError {
  if parameters.length() > 64 {
    raise InvalidParameter("too many SQL parameters")
  }
  let output : Array[Byte] = []
  for parameter in parameters {
    match parameter {
      None => {
        output.push(0xff)
        output.push(0xff)
        output.push(0xff)
        output.push(0xff)
      }
      Some(value) => {
        if value.contains_char('\u0000') {
          raise InvalidParameter("SQL text parameter contains NUL")
        }
        let encoded = @utf8.encode(value)
        if encoded.length() > 16777216 {
          raise InvalidParameter("SQL text parameter is too large")
        }
        append_length(output, encoded.length())
        for index in 0..<encoded.length() {
          output.push(encoded[index])
        }
      }
    }
  }
  Bytes::from_array(output)
}

///|
pub fn Connection::execute(
  self : Connection,
  sql : String,
  parameters? : Array[String?] = [],
) -> QueryResult raise PostgresError {
  if sql.trim() == "" || sql.contains_char('\u0000') || sql.length() > 1048576 {
    raise InvalidParameter("SQL statement is invalid")
  }
  let encoded = encode_parameters(parameters)
  let handle = native_execute(
    self.handle,
    @utf8.encode(sql),
    encoded,
    parameters.length(),
  )
  if !native_result_ok(handle) {
    raise QueryFailed(safe_error(native_result_error(handle)))
  }
  { handle, }
}

///|
pub fn Connection::close(self : Connection) -> Unit {
  native_close(self.handle)
}

///|
pub fn QueryResult::row_count(self : QueryResult) -> Int {
  native_row_count(self.handle)
}

///|
pub fn QueryResult::column_count(self : QueryResult) -> Int {
  native_column_count(self.handle)
}

///|
pub fn QueryResult::value(
  self : QueryResult,
  row : Int,
  column : Int,
) -> String? {
  if row < 0 ||
    row >= self.row_count() ||
    column < 0 ||
    column >= self.column_count() ||
    native_is_null(self.handle, row, column) {
    None
  } else {
    Some(@utf8.decode_lossy(native_value(self.handle, row, column)))
  }
}

///|
pub fn QueryResult::affected_rows(self : QueryResult) -> Int64 {
  native_affected_rows(self.handle)
}
