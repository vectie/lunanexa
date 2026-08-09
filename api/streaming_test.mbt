///|
test "streaming applies backpressure and cancellation" {
  let stream = @api.StreamSession::new("workload-1", 2)
  assert_eq(stream.next(), Some(Opened))
  stream.push(Chunk(sequence=1, output={ "text": "a" }))
  stream.push(Chunk(sequence=2, output={ "text": "b" }))
  try stream.push(Chunk(sequence=3, output={ "text": "c" })) catch {
    @api.StreamError::Backpressure => ()
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("expected bounded stream backpressure")
  }
  ignore(stream.next())
  stream.cancel()
  assert_true(stream.is_cancelled())
}
