///|
async test "missing provider job cannot release capacity until cancellation is acknowledged" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let provider = @provider.Provider::new("http://\{server.addr}", profile())
  let acknowledged = Ref(false)
  let settlements = Ref(0)
  let jobs = store()
  let settle : async (@jobs.StoredJob) -> String = _ => {
    settlements.val += 1
    "cancel-receipt"
  }
  let runtime = VideoRuntime::new(
    jobs,
    _ => provider,
    (_, _, _) => true,
    settle,
    now=() => 1000L,
  )
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((req, body, connection) => {
        ignore(@io.Reader::read_all(body))
        let code = if req.meth == Delete && !acknowledged.val {
          404
        } else {
          200
        }
        connection.send_response(code, "fixture", extra_headers={
          "content-type": "application/json",
        })
        connection.write_string(
          if req.meth == Post {
            "{\"id\":\"upstream-job\",\"status\":\"queued\"}"
          } else {
            "{\"id\":\"upstream-job\",\"deleted\":true}"
          },
        )
        connection.end_response()
      })
    })
    let job = runtime.submit(
      owner(),
      "cancel-original",
      request(),
      "binding",
      5000L,
      10000L,
    )
    assert_eq(runtime.cancel(job.job_id, owner()).state, Cancelling)
    assert_eq(settlements.val, 0)
    let restored = @jobs.JobStore::restore(jobs.snapshot(), _ => ())
    assert_false(restored.get(job.job_id, owner()).execution_terminal)
    try
      restored.reserve(
        owner(),
        "must-remain-busy",
        request().digest(),
        "video.h3",
        "binding",
        1001L,
        5000L,
        10000L,
      )
    catch {
      @jobs.JobError::Busy => ()
      error => raise error
    } noraise {
      _ => fail("404 released capacity")
    }
    let resumed = VideoRuntime::new(
      restored,
      _ => provider,
      (_, _, _) => true,
      settle,
      now=() => 1002L,
    )
    acknowledged.val = true
    ignore(resumed.reconcile())
    assert_eq(restored.get(job.job_id, owner()).state, Cancelled)
    assert_true(restored.get(job.job_id, owner()).execution_terminal)
    assert_eq(settlements.val, 1)
    ignore(resumed.reconcile())
    assert_eq(settlements.val, 1)
    ignore(
      restored.reserve(
        owner(),
        "capacity-restored",
        request().digest(),
        "video.h3",
        "binding",
        1003L,
        5000L,
        10000L,
      ),
    )
  }
}
