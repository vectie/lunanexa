///|
fn parse_port(value : String) -> Int raise {
  let port = @string.parse_int(value) catch {
    _ => raise Failure("loopback proxy port is not a number: \{value}")
  }
  if port < 0 || port > 65535 {
    raise Failure("loopback proxy port is out of range: \{value}")
  }
  port
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == 5 else {
    raise Failure(
      "usage: lunanexa-loopback-proxy <listen-host> <listen-port> <target-host> <target-port>",
    )
  }
  let listen = @socket.Addr::parse("\{args[1]}:\{parse_port(args[2])}")
  let target_host = args[3]
  let target_port = parse_port(args[4])
  let server = @socket.TcpServer(listen, reuse_addr=true)
  defer server.close()
  println("loopback proxy \{server.addr} -> \{target_host}:\{target_port}")
  serve_forever(server, target_host, target_port)
}
