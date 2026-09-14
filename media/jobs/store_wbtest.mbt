///|
fn owner() -> Owner {
  {
    tenant_ref: "tenant-a",
    subject_ref: "subject-a",
    organization_id: "org-a",
    project_id: "project-a",
    order_id: "order-a",
  }
}

///|
fn empty_snapshot() -> Snapshot {
  { schema_version, jobs: [], }
}

///|
async fn reserve(store : JobStore, key : String) -> StoredJob {
  store.reserve(
    owner(),
    key,
    digest("fixture-prompt-and-parameters"),
    "video.h3",
    "private-deployment-a",
    1000L,
    2000L,
    5000L,
  ).0
}

///|
async test "durable reservation is replayable, owner scoped and parameter bound" {
  let saves : Array[Snapshot] = []
  let store = JobStore::restore(empty_snapshot(), value => saves.push(value))
  let job = reserve(store, "request-a")
  assert_eq(job.state, Intent)
  assert_eq(saves.length(), 1)
  let (replayed, created) = store.reserve(
    owner(),
    "request-a",
    digest("fixture-prompt-and-parameters"),
    "video.h3",
    "private-deployment-a",
    1001L,
    2001L,
    5001L,
  )
  assert_false(created)
  assert_true(replayed == job)
  assert_eq(saves.length(), 1)
  try {
    ignore(
      store.reserve(
        owner(),
        "request-a",
        digest("different-prompt"),
        "video.h3",
        "private-deployment-a",
        1001L,
        2001L,
        5001L,
      ),
    )
    fail("conflicting replay accepted")
  } catch {
    JobError::Conflict => ()
    error => fail("Unexpected error: \{error}")
  }
  for
    stranger in [
      { ..owner(), tenant_ref: "tenant-b", },
      { ..owner(), subject_ref: "subject-b", },
      { ..owner(), organization_id: "org-b", },
      { ..owner(), project_id: "project-b", },
      { ..owner(), order_id: "order-b", },
    ] {
    try {
      ignore(store.get(job.job_id, stranger))
      fail("cross-owner job exposed")
    } catch {
      JobError::NotFound => ()
      error => fail("Unexpected error: \{error}")
    }
  }
}

///|
async test "persistence failure cannot publish a reservation or start provider work" {
  let failing = { "enabled": true }
  let store = JobStore::restore(empty_snapshot(), _ => {
    if failing["enabled"] {
      raise Failure("simulated durability failure")
    }
  })
  try {
    ignore(reserve(store, "request-a"))
    fail("persistence failure ignored")
  } catch {
    Failure(_) => ()
    error => fail("Unexpected error: \{error}")
  }
  assert_eq(store.snapshot().jobs.length(), 0)
  failing["enabled"] = false
  let job = reserve(store, "request-a")
  failing["enabled"] = true
  try {
    ignore(store.begin_submission(job.job_id, owner(), 1001L))
    fail("provider start allowed before durable intent")
  } catch {
    Failure(_) => ()
    error => fail("Unexpected error: \{error}")
  }
  assert_eq(store.get(job.job_id, owner()).state, Intent)
}

///|
async test "restart turns an ambiguous submission into reconciliation, never an automatic retry" {
  let store = JobStore::restore(empty_snapshot(), _ => ())
  let job = reserve(store, "request-a")
  ignore(store.begin_submission(job.job_id, owner(), 1001L))
  let persisted : Array[Snapshot] = []
  let restored = JobStore::restore(store.snapshot(), value => {
    persisted.push(value)
  })
  assert_eq(restored.get(job.job_id, owner()).state, SubmissionUnknown)
  assert_eq(persisted.length(), 1)
  try {
    ignore(restored.begin_submission(job.job_id, owner(), 1002L))
    fail("ambiguous submission retried")
  } catch {
    JobError::InvalidTransition => ()
    error => fail("Unexpected error: \{error}")
  }
  try {
    ignore(reserve(restored, "request-b"))
    fail("uncertain GPU work released the paid-order slot")
  } catch {
    JobError::Busy => ()
    error => fail("Unexpected error: \{error}")
  }
  let view = restored.get(job.job_id, owner()).public_view(1003L).stringify()
  assert_true(view.contains("SubmissionRequiresReconciliation"))
}

///|
async test "cancellation racing provider acknowledgement stays pending until deletion is confirmed" {
  let store = JobStore::restore(empty_snapshot(), _ => ())
  let job = reserve(store, "request-a")
  ignore(store.begin_submission(job.job_id, owner(), 1001L))
  ignore(store.cancel(job.job_id, owner(), false, 1002L))
  let attached = store.attach_provider(
    job.job_id,
    owner(),
    "private-provider-a",
    1003L,
  )
  assert_eq(attached.state, Cancelling)
  assert_eq(
    store.observe(job.job_id, owner(), Completed, Some(100), 1004L).state,
    Cancelling,
  )
  try {
    ignore(
      store.acknowledge_deletion(
        job.job_id,
        owner(),
        "other-provider-job",
        1004L,
      ),
    )
    fail("foreign deletion acknowledged")
  } catch {
    JobError::Conflict => ()
    error => fail("Unexpected error: \{error}")
  }
  assert_eq(
    store.acknowledge_deletion(job.job_id, owner(), "private-provider-a", 1005L).state,
    Cancelled,
  )
  assert_eq(
    store.observe(job.job_id, owner(), Running, Some(50), 1006L).state,
    Cancelled,
  )
  ignore(reserve(store, "request-b"))
}

///|
async test "provider observations cannot regress state or progress and content expires immediately" {
  let store = JobStore::restore(empty_snapshot(), _ => ())
  let job = reserve(store, "request-a")
  ignore(store.begin_submission(job.job_id, owner(), 1001L))
  ignore(
    store.attach_provider(job.job_id, owner(), "private-provider-a", 1002L),
  )
  ignore(store.observe(job.job_id, owner(), Running, Some(50), 1003L))
  assert_eq(
    store.observe(job.job_id, owner(), Queued, Some(1), 1004L).state,
    Running,
  )
  assert_eq(
    store.observe(job.job_id, owner(), Running, Some(10), 1005L).progress,
    Some(50),
  )
  let done = store.observe(job.job_id, owner(), Completed, Some(100), 1006L)
  assert_eq(
    store.observe(job.job_id, owner(), Running, None, 1007L).state,
    Completed,
  )
  assert_true(done.public_view(1007L) is { "content_available": True, .. })
  assert_true(
    done.public_view(5000L)
    is {
      "content_available": False,
      "error": { "code": String("ResultExpired"), .. },
      ..
    },
  )
  let public_json = done.public_view(1007L).stringify()
  for
    forbidden in [
      "private-provider-a", "private-deployment-a", "subject-a", "org-a", "order-a",
      "fixture-prompt",
    ] {
    assert_false(public_json.contains(forbidden))
  }
  ignore(store.record_usage(job.job_id, owner(), "usage-receipt-a"))
  ignore(store.record_usage(job.job_id, owner(), "usage-receipt-a"))
  try {
    ignore(store.record_usage(job.job_id, owner(), "usage-receipt-b"))
    fail("conflicting billing receipt accepted")
  } catch {
    JobError::Conflict => ()
    error => fail("Unexpected error: \{error}")
  }
}

///|
async test "cleanup of completed output does not claim a second executing GPU slot on restart" {
  let store = JobStore::restore(empty_snapshot(), _ => ())
  let first = reserve(store, "request-a")
  ignore(store.begin_submission(first.job_id, owner(), 1001L))
  ignore(
    store.attach_provider(first.job_id, owner(), "private-provider-a", 1002L),
  )
  ignore(store.observe(first.job_id, owner(), Completed, Some(100), 1003L))
  let second = reserve(store, "request-b")
  ignore(store.cancel(first.job_id, owner(), false, 1004L))
  let restored = JobStore::restore(store.snapshot(), _ => ())
  assert_eq(restored.get(second.job_id, owner()).state, Intent)
  assert_eq(restored.get(first.job_id, owner()).state, Cancelling)
  ignore(restored.begin_submission(second.job_id, owner(), 1005L))
  try {
    ignore(
      restored.attach_provider(
        second.job_id,
        owner(),
        "private-provider-a",
        1006L,
      ),
    )
    fail("provider identifier reused across jobs")
  } catch {
    JobError::Conflict => ()
    error => fail("Unexpected error: \{error}")
  }
}
