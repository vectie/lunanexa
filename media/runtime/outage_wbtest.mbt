///|
async fn exercise_unverified_outage(instance_id : String?) -> Unit {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let provider = @provider.Provider::new("http://\{server.addr}", profile())
  let state = { "authority": true, "route": true }
  let counts = { "submit": 0, "delete": 0, "settle": 0 }
  let clock = { "now": 1000L }
  let jobs = store()
  let resolve : async (String) -> @provider.Provider = _ => {
    if !state["route"] {
      raise AuthorityUnavailable
    }
    provider
  }
  let authorized : async (@jobs.Owner, String, String) -> Bool = (_, _, _) => {
    if !state["authority"] {
      raise AuthorityUnavailable
    }
    true
  }
  let settle : async (@jobs.StoredJob) -> String = _ => {
    counts["settle"] += 1
    "receipt-once"
  }
  let runtime = VideoRuntime::new(jobs, resolve, authorized, settle, now=() => {
    clock["now"]
  })
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((req, body, connection) => {
        ignore(@io.Reader::read_all(body))
        let text = match req.meth {
          Post => {
            counts["submit"] += 1
            "{\"id\":\"fixture-job\",\"status\":\"queued\"}"
          }
          Delete => {
            counts["delete"] += 1
            "{\"id\":\"fixture-job\",\"deleted\":true}"
          }
          _ =>
            "{\"id\":\"fixture-job\",\"status\":\"in_progress\",\"progress\":50}"
        }
        connection.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        connection.write_string(text)
        connection.end_response()
      })
    })
    let job = runtime.submit(
      owner(),
      "outage",
      request(),
      "binding",
      2000L,
      5000L,
      execution_context={
        instance_id,
        deployment_id: "deployment",
        generation: 1L,
        node_id: "node",
      },
    )
    state["authority"] = false
    try runtime.get(job.job_id, owner()) catch {
      AuthorityUnavailable => ()
      error => raise error
    } noraise {
      _ => fail("unconfirmed authority allowed a read")
    }
    assert_eq(runtime.reconcile(), (0, 1))
    assert_eq(jobs.get(job.job_id, owner()).state, Queued)
    assert_eq(counts["delete"], 0)
    let restored = @jobs.JobStore::restore(jobs.snapshot(), _ => ())
    let runtime = VideoRuntime::new(restored, resolve, authorized, settle, now=() => {
      clock["now"]
    })
    state["authority"] = true
    assert_eq(
      runtime.submit(owner(), "outage", request(), "binding", 2000L, 5000L).job_id,
      job.job_id,
    )
    assert_eq(counts["submit"], 1)
    assert_eq(runtime.get(job.job_id, owner()).state, Running)
    state["authority"] = false
    state["route"] = false
    clock["now"] = 2500L
    assert_eq(runtime.reconcile(), (0, 1))
    let pending = restored.get(job.job_id, owner())
    assert_eq(pending.state, Cancelling)
    assert_true(pending.expiry_requested)
    assert_false(pending.execution_terminal)
    assert_eq(pending.termination_evidence_ref, None)
    assert_true(restored.snapshot().terminations == Some([]))
    assert_eq(counts["settle"], 0)
    let final_store = @jobs.JobStore::restore(restored.snapshot(), _ => ())
    try
      final_store.reserve(
        owner(),
        "must-stay-busy",
        request().digest(),
        "video.h3",
        "binding",
        2500L,
        3500L,
        5000L,
      )
    catch {
      @jobs.JobError::Busy => ()
      error => raise error
    } noraise {
      _ => fail("unacknowledged cancellation released capacity")
    }
    let final_runtime = VideoRuntime::new(
      final_store,
      resolve,
      authorized,
      settle,
      now=() => clock["now"],
    )
    state["route"] = true
    assert_eq(final_runtime.reconcile(), (1, 0))
    assert_eq(final_store.get(job.job_id, owner()).state, Expired)
    assert_eq(counts["delete"], 1)
    assert_eq(counts["settle"], 1)
    assert_eq(final_runtime.reconcile(), (0, 0))
    assert_eq(counts["settle"], 1)
  }
}

///|
async test "outage preserves legacy jobs without inventing exit evidence" {
  exercise_unverified_outage(None)
}

///|
async test "outage preserves known incarnation capacity until real acknowledgement" {
  exercise_unverified_outage(Some("a".repeat(64)))
}

///|
async test "expired unsubmitted intent needs no live authority or provider to close" {
  let jobs = store()
  let job = jobs.reserve(
      owner(),
      "expired-intent",
      request().digest(),
      "video.h3",
      "binding",
      1000L,
      2000L,
      3000L,
    ).0
  let runtime = VideoRuntime::new(
    jobs,
    _ => raise Failure("must not resolve an unsubmitted intent"),
    (_, _, _) => {
      raise Failure("expiry must not depend on authority availability")
    },
    _ => "expired-intent-receipt",
    now=() => 4000L,
  )
  assert_eq(runtime.reconcile(), (1, 0))
  assert_eq(jobs.get(job.job_id, owner()).state, Expired)
}
