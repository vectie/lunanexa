///|
async test "reconciliation has bounded parallelism and isolates one failed authority" {
  let jobs = store()
  for index in 0..<12 {
    ignore(
      jobs.reserve(
        {
          ..owner(),
          subject_ref: "subject-\{index}",
          authority: DedicatedOrder("order-\{index}"),
        },
        "request",
        request().digest(),
        "video.h3",
        "deployment",
        1000L,
        2000L,
        3000L,
      ),
    )
  }
  let mut active = 0
  let mut peak = 0
  let runtime = VideoRuntime::new(
    jobs,
    _ => raise Failure("unsubmitted intent must not contact a provider"),
    (who, _, _) => {
      active += 1
      peak = peak.max(active)
      defer {
        active -= 1
      }
      @async.sleep(10)
      if who.subject_ref == "subject-0" {
        raise Failure("one authority unavailable")
      }
      false
    },
    job => "receipt-" + job.job_id,
    now=() => 4000L,
  )
  assert_eq(runtime.reconcile(), (11, 1))
  assert_true(peak > 1 && peak <= 8)
  assert_eq(active, 0)
  assert_eq(
    jobs.snapshot().jobs.filter(job => job.state == Expired).length(),
    11,
  )
}
