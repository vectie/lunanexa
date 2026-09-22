///|
/// The proxy is protocol blind: it cannot size a buffer from the request it
/// forwards, so every direction copies in fixed chunks.
let relay_chunk_bytes : Int = 65536

///|
extern "C" fn shutdown_write(fd : Int) -> Int = "lunanexa_shutdown_write"

///|
extern "C" fn shutdown_both(fd : Int) -> Int = "lunanexa_shutdown_both"

///|
/// Relays one direction of a connection until the source reaches end of file.
///
/// The source's FIN is forwarded as a FIN on the destination's write side: the
/// agent may stop writing while it is still waiting for a reply, and that reply
/// must be allowed to drain instead of being cut off by a full close.
async fn relay_direction(
  source : @socket.Tcp,
  destination : @socket.Tcp,
) -> Unit {
  try {
    while source.read_some(max_len=relay_chunk_bytes) is Some(chunk) {
      destination.write(chunk)
    }
    ignore(shutdown_write(destination.fd()))
  } catch {
    err if @async.is_being_cancelled() => raise err
    _ => {
      // Shutting down rather than closing wakes the sibling direction, which
      // may be blocked on either socket: closing a descriptor another task
      // waits on never wakes that task.
      ignore(shutdown_both(source.fd()))
      ignore(shutdown_both(destination.fd()))
    }
  }
}

///|
/// Relays both directions of one accepted connection until neither side can
/// make progress. The two sockets stay owned by the caller.
async fn relay(client : @socket.Tcp, target : @socket.Tcp) -> Unit {
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => { relay_direction(client, target) }
    group.spawn_bg() <| () => { relay_direction(target, client) }
  }
}

///|
async fn serve_connection(
  client : @socket.Tcp,
  target_host : String,
  target_port : Int,
) -> Unit {
  let target = @socket.Tcp::connect_to_host(target_host, port=target_port) catch {
    err => {
      // A raw TCP relay has no protocol of its own to report the failure on,
      // so the agent would only see a closed connection. Keep the reason.
      println(
        "loopback proxy cannot reach \{target_host}:\{target_port}: \{err}",
      )
      return
    }
  }
  defer target.close()
  relay(client, target)
}

///|
/// Serves the loopback endpoint until cancelled. Every accepted connection gets
/// its own upstream connection, so a stalled agent connection cannot block the
/// others.
async fn serve_forever(
  server : @socket.TcpServer,
  target_host : String,
  target_port : Int,
) -> Unit {
  server.run_forever((client, _peer) => {
    serve_connection(client, target_host, target_port)
  })
}
