///|
async test "late evidence decisions cannot revive cancelled or expired orders and retries remain idempotent" {
  let root = @fs.tmpdir(prefix="offline-review-lifecycle-")
  defer @fs.rmdir(root, recursive=true)
  for outcome in ["cancelled", "expired", "deadline"] {
    let store = @store.OfflineCommerceStore::open(
      root + "/" + outcome + ".json",
    )
    let id = "review-" + outcome
    ignore(ready_for_upload(store, id))
    let grant = upload_grant(id, "evidence-" + outcome)
    ignore(store.grant_upload(grant))
    let artifact = store.complete_upload(callback(grant))
    let current = store.order("org-a", id)
    match outcome {
      "cancelled" => ignore(store.cancel_order(id, current.generation, 2500L))
      "expired" => ignore(store.expire_orders(100001L))
      _ => ()
    }
    let before = store.snapshot()
    for accepted in [true, false] {
      let review : @offline.EvidenceReview = {
        review_id: "late-\{outcome}-\{accepted}",
        order_id: id,
        artifact_id: artifact.artifact_id,
        expected_artifact_sha256: artifact.sha256,
        reviewer_ref: "operator-reviewer",
        accepted,
        reason_code: "EvidenceVerified",
        audit_receipt: "audit-\{outcome}",
        reviewed_unix_ms: if outcome == "cancelled" {
          3000L
        } else {
          100001L
        },
      }
      try ignore(store.review_evidence(review)) catch {
        @offline.OfflineCommerceError::InvalidTransition(_) => ()
        error => fail("unexpected review error: \{Repr(error)}")
      } noraise {
        _ => fail("ended order accepted new evidence decision")
      }
      assert_eq(store.snapshot(), before)
    }
  }
  let store = @store.OfflineCommerceStore::open(root + "/retry.json")
  let id = "review-retry"
  ignore(ready_for_upload(store, id))
  let grant = upload_grant(id, "evidence-retry")
  ignore(store.grant_upload(grant))
  let artifact = store.complete_upload(callback(grant))
  let review : @offline.EvidenceReview = {
    review_id: "accepted-before-cancel",
    order_id: id,
    artifact_id: artifact.artifact_id,
    expected_artifact_sha256: artifact.sha256,
    reviewer_ref: "operator-reviewer",
    accepted: true,
    reason_code: "EvidenceVerified",
    audit_receipt: "audit-retry",
    reviewed_unix_ms: 2400L,
  }
  let reviewed = store.review_evidence(review)
  let current = store.order("org-a", id)
  ignore(store.cancel_order(id, current.generation, 2500L))
  let before = store.snapshot()
  assert_eq(store.review_evidence(review), reviewed)
  assert_eq(store.snapshot(), before)
}
