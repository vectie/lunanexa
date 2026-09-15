///|
fn owner() -> @jobs.Owner {
  {
    tenant_ref: "t",
    subject_ref: "s",
    organization_id: "o",
    project_id: "p",
    authority: DedicatedOrder("paid-order"),
  }
}

///|
fn profile() -> @provider.Profile {
  {
    model: "video.h3",
    provider_model: "MiniMax-H3",
    widths: [512],
    heights: [512],
    maximum_frames: 121,
    maximum_fps: 24,
    maximum_steps: 50,
    sound_supported: true,
  }
}

///|
fn request() -> @provider.VideoRequest raise {
  @provider.VideoRequest::decode(
    profile(),
    "application/x-www-form-urlencoded",
    "model=video.h3&prompt=fixture&width=512&height=512&num_frames=25&fps=24",
  )
}

///|
async fn store() -> @jobs.JobStore {
  @jobs.JobStore::restore(
    { schema_version: @jobs.schema_version, jobs: [], terminations: None, },
    _ => (),
  )
}

///|
async test "video runtime retries settlement but never resubmits an accepted request" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let jobs = store()
  let state = { "submits": 0, "settles": 0 }
  let provider = @provider.Provider::new("http://\{server.addr}", profile())
  let runtime = VideoRuntime::new(
    jobs,
    deployment => {
      assert_eq(deployment, "deployment")
      provider
    },
    (who, model, deployment) => {
      who == owner() && model == "video.h3" && deployment == "deployment"
    },
    _job => {
      state["settles"] += 1
      if state["settles"] == 1 {
        raise Failure("fixture ledger temporarily unavailable")
      }
      "usage-fixture"
    },
    now=() => 1000L,
  )
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((req, body, connection) => {
        ignore(@io.Reader::read_all(body))
        connection.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        if req.meth == Post {
          state["submits"] += 1
          connection.write_string(
            "{\"id\":\"provider-one\",\"status\":\"queued\"}",
          )
        } else {
          connection.write_string(
            "{\"id\":\"provider-one\",\"status\":\"completed\"}",
          )
        }
        connection.end_response()
      })
    })
    let job = runtime.submit(
      owner(),
      "request-one",
      request(),
      "deployment",
      2000L,
      5000L,
    )
    assert_eq(job.state, Queued)
    assert_eq(
      runtime.submit(
        owner(),
        "request-one",
        request(),
        "deployment",
        2000L,
        5000L,
      ).job_id,
      job.job_id,
    )
    assert_eq(state["submits"], 1)
    assert_true(
      try {
        ignore(runtime.get(job.job_id, owner()))
        false
      } catch {
        _ => true
      },
    )
    assert_eq(jobs.get(job.job_id, owner()).state, Completed)
    assert_eq(jobs.get(job.job_id, owner()).usage_receipt, None)
    assert_eq(
      runtime.get(job.job_id, owner()).usage_receipt,
      Some("usage-fixture"),
    )
    ignore(runtime.get(job.job_id, owner()))
    assert_eq(state["settles"], 2)
    assert_eq(state["submits"], 1)
    assert_true(
      try {
        ignore(runtime.get(job.job_id, { ..owner(), subject_ref: "intruder", }))
        false
      } catch {
        @jobs.JobError::NotFound => true
        _ => false
      },
    )
  }
}

///|
async test "video runtime quarantines a timed out submission and retains its capacity slot" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let jobs = store()
  let provider = @provider.Provider::new(
    "http://\{server.addr}",
    profile(),
    timeout_ms=100,
  )
  let state = { "submits": 0 }
  let runtime = VideoRuntime::new(
    jobs,
    _ => provider,
    (_, _, _) => true,
    _ => "receipt",
    now=() => 1000L,
  )
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever((req, body, connection) => {
        ignore(@io.Reader::read_all(body))
        if req.meth == Post {
          state["submits"] += 1
          @async.sleep(10000)
        } else {
          connection.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          connection.write_string(
            "{\"id\":\"provider-recovered\",\"status\":\"queued\"}",
          )
          connection.end_response()
        }
      })
    })
    assert_true(
      try {
        ignore(
          runtime.submit(
            owner(),
            "ambiguous",
            request(),
            "deployment",
            2000L,
            5000L,
          ),
        )
        false
      } catch {
        _ => true
      },
    )
    let record = runtime.submit(
      owner(),
      "ambiguous",
      request(),
      "deployment",
      2000L,
      5000L,
    )
    assert_eq(record.state, SubmissionUnknown)
    assert_eq(state["submits"], 1)
    assert_true(
      try {
        ignore(
          runtime.submit(
            owner(),
            "new-attempt",
            request(),
            "deployment",
            2000L,
            5000L,
          ),
        )
        false
      } catch {
        @jobs.JobError::Busy => true
        _ => false
      },
    )
    let restored = @jobs.JobStore::restore(jobs.snapshot(), _ => ())
    assert_eq(restored.get(record.job_id, owner()).state, SubmissionUnknown)
    assert_eq(
      runtime.reconcile_submission(record.job_id, owner(), "provider-recovered").state,
      Queued,
    )
    assert_eq(state["submits"], 1)
  }
}

///|
async test "revocation stops reads and reconciliation waits for real cancellation acknowledgement" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let jobs = store()
  let provider = @provider.Provider::new("http://\{server.addr}", profile())
  let state = { "active": true, "pending": true }
  let runtime = VideoRuntime::new(
    jobs,
    _ => provider,
    (_, _, _) => state["active"],
    _ => "cancelled-usage",
    now=() => 1000L,
  )
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((req, body, connection) => {
        ignore(@io.Reader::read_all(body))
        if req.meth == Delete {
          connection.send_response(
            if state["pending"] {
              409
            } else {
              200
            },
            "Delete",
            extra_headers={ "content-type": "application/json" },
          )
          connection.write_string(
            if state["pending"] {
              "{}"
            } else {
              "{\"id\":\"provider-one\",\"deleted\":true}"
            },
          )
        } else {
          connection.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          connection.write_string(
            "{\"id\":\"provider-one\",\"status\":\"queued\"}",
          )
        }
        connection.end_response()
      })
    })
    let record = runtime.submit(
      owner(),
      "revoked",
      request(),
      "deployment",
      2000L,
      5000L,
    )
    state["active"] = false
    assert_true(
      try {
        ignore(runtime.get(record.job_id, owner()))
        false
      } catch {
        Unauthorized => true
        _ => false
      },
    )
    assert_eq(runtime.reconcile(), (1, 0))
    assert_eq(jobs.get(record.job_id, owner()).state, Cancelling)
    assert_false(jobs.get(record.job_id, owner()).execution_terminal)
    state["pending"] = false
    assert_eq(runtime.reconcile(), (1, 0))
    assert_eq(jobs.get(record.job_id, owner()).state, Cancelled)
    assert_eq(
      jobs.get(record.job_id, owner()).usage_receipt,
      Some("cancelled-usage"),
    )
  }
}
