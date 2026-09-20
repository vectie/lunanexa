///|
/// An upstream that answers every byte it receives, standing in for the
/// controller serving an agent request on an already open connection.
async fn echo_connection(connection : @socket.Tcp) -> Unit {
  while connection.read_some(max_len=4096) is Some(chunk) {
    connection.write(chunk)
  }
}

///|
struct RelayFixture {
  upstream : @socket.TcpServer
  proxy : @socket.TcpServer
}

///|
async fn relay_fixture() -> RelayFixture {
  {
    upstream: @socket.TcpServer(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_addr=true,
    ),
    proxy: @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"), reuse_addr=true),
  }
}

///|
/// Runs the upstream and the proxy for the duration of `group`. Both servers
/// run until the group cancels them, so they must not be waited for.
fn relay_group(
  group : @async.TaskGroup[Unit],
  fixture : RelayFixture,
  on_connection : async (@socket.Tcp) -> Unit,
) -> Unit {
  group.spawn_bg(no_wait=true) <| () => {
    fixture.upstream.run_forever((connection, _) => on_connection(connection))
  }
  group.spawn_bg(no_wait=true) <| () => {
    serve_forever(fixture.proxy, "127.0.0.1", fixture.upstream.addr.port())
  }
}

///|
test "proxy ports are validated" {
  assert_eq(parse_port("18080"), 18080)
  assert_eq(parse_port("0"), 0)
  assert_eq(parse_port("65535"), 65535)
  for value in ["", "-1", "65536", "18080 ", "http"] {
    let rejected = try {
      ignore(parse_port(value))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
async test "relay forwards bytes in both directions over one connection" {
  let fixture = relay_fixture()
  @async.with_task_group() <| group => {
    relay_group(group, fixture, echo_connection)
    let client = @socket.Tcp::connect(fixture.proxy.addr)
    defer client.close()
    let request = b"GET /health HTTP/1.1\r\nHost: loopback\r\n\r\n"
    client.write(request)
    assert_eq(client.read_exactly(request.length()), request)
    // The agent polls the controller over one long-lived connection, so the
    // relayed connection has to survive more than one round trip.
    let second = b"GET /v1/models HTTP/1.1\r\nHost: loopback\r\n\r\n"
    client.write(second)
    assert_eq(client.read_exactly(second.length()), second)
  }
  fixture.proxy.close()
  fixture.upstream.close()
}

///|
async test "concurrent connections are relayed independently" {
  let fixture = relay_fixture()
  @async.with_task_group() <| group => {
    relay_group(group, fixture, echo_connection)
    let clients = []
    for index = 0; index < 8; index = index + 1 {
      clients.push(@socket.Tcp::connect(fixture.proxy.addr))
    }
    for index = 0; index < clients.length(); index = index + 1 {
      clients[index].write(@utf8.encode("connection-\{index}"))
    }
    for index = 0; index < clients.length(); index = index + 1 {
      let payload = @utf8.encode("connection-\{index}")
      assert_eq(clients[index].read_exactly(payload.length()), payload)
    }
    for client in clients {
      client.close()
    }
  }
  fixture.proxy.close()
  fixture.upstream.close()
}

///|
async test "half close forwards the FIN and lets the reply drain" {
  let fixture = relay_fixture()
  let upstream_saw_eof = Ref(false)
  @async.with_task_group() <| group => {
    relay_group(group, fixture, (connection) => {
      while connection.read_some(max_len=4096) is Some(_) {}
      upstream_saw_eof.val = true
      connection.write(b"reply-after-agent-fin")
    })
    let client = @socket.Tcp::connect(fixture.proxy.addr)
    defer client.close()
    client.write(b"request")
    // The agent stops writing while it is still waiting for the reply.
    ignore(shutdown_write(client.fd()))
    assert_eq(client.read_all().binary(), b"reply-after-agent-fin")
    assert_true(upstream_saw_eof.val)
  }
  fixture.proxy.close()
  fixture.upstream.close()
}
