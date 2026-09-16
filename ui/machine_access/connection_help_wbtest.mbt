///|
test "tunnel command validates and binds only loopback" {
  assert_eq(
    tunnel_command("alice", "machine.example", 2222),
    Some(
      "ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8181:127.0.0.1:8181 -p 2222 'alice@machine.example'",
    ),
  )
  for
    host in [
      "host;echo secret", "host'", "-oProxyCommand=bad", "host\nsecond", "$(bad)",
      "",
    ] {
    assert_eq(tunnel_command("alice", host, 2222), None)
  }
  for user in ["-root", "alice;bad", "alice'", "alice\nroot", ""] {
    assert_eq(tunnel_command(user, "machine.example", 2222), None)
  }
  assert_eq(tunnel_command("alice", "machine.example", 0), None)
  assert_eq(tunnel_command("alice", "machine.example", 65536), None)
}
