///|
fn sibling_result(
  request : @offline.ArtifactGenerationRequest,
  now : Int64,
) -> @offline.ArtifactGenerationResult {
  {
    request_id: request.request_id,
    artifact_id: request.artifact_id,
    expected_object_ref: request.expected_object_ref,
    media_type: "application/pdf",
    byte_count: 30000L,
    sha256: digest_a,
    worker_receipt: "sibling-worker-receipt",
    verified: true,
    active_content_detected: false,
    moonleaf_verified: false,
    render_verified: true,
    formula_error_count: 0,
    visual_evidence_sha256: digest_b,
    page_count: None,
    completed_unix_ms: now,
  }
}

///|
async test "sibling generation claims advance only with atomic artifact publication and survive restart" {
  let dir = @fs.tmpdir(prefix="offline-sibling-artifacts-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/state.json"
  let store = @store.OfflineCommerceStore::open(path)
  ignore(store.register_template(contract_template()))
  ignore(store.create_order(order("siblings")))
  let quoted = store.quote_order("siblings", quote(), "operator", 1200L)
  ignore(store.begin_offline_execution("siblings", quoted.generation, 1300L))
  let first = generation_request("siblings", "first")
  let second = generation_request("siblings", "second")
  ignore(store.request_generation(first))
  ignore(store.request_generation(second))
  assert_eq(store.claim_generation_requests(1450L).length(), 2)
  let before = store.snapshot()
  @fs.mkdir(path + ".next")
  try store.complete_generation(sibling_result(first, 1500L)) catch {
    _ => ()
  } noraise {
    _ => fail("write fault was ignored")
  }
  assert_eq(store.snapshot(), before)
  @fs.rmdir(path + ".next")
  ignore(store.complete_generation(sibling_result(first, 1500L)))
  let published = store.order_for_operator("siblings")
  let reopened = @store.OfflineCommerceStore::open(path)
  let remaining = reopened.snapshot().work_claims.filter(c => {
    c.completed_unix_ms is None
  })
  assert_eq(remaining.length(), 1)
  assert_eq(remaining[0].expected_order_generation, published.generation)
  assert_eq(remaining[0].attempt, 1)
  assert_eq(remaining[0].retry_after_unix_ms, 61450L)
  ignore(reopened.complete_generation(sibling_result(second, 1600L)))
  assert_eq(reopened.order_for_operator("siblings").artifact_ids.length(), 2)
  assert_eq(
    reopened.snapshot().work_claims
    .filter(c => c.completed_unix_ms is None)
    .length(),
    0,
  )
  assert_eq(reopened.claim_generation_requests(70000L).length(), 0)
  // An exact first-result replay neither increments the order nor reopens work.
  let finished = reopened.snapshot()
  ignore(reopened.complete_generation(sibling_result(first, 1500L)))
  assert_eq(reopened.snapshot(), finished)
}

///|
async test "sibling completion never renews cancellation or expiry fences" {
  for expire in [false, true] {
    let dir = @fs.tmpdir(prefix="offline-sibling-fence-")
    defer @fs.rmdir(dir, recursive=true)
    let store = @store.OfflineCommerceStore::open(dir + "/state.json")
    ignore(store.register_template(contract_template()))
    ignore(store.create_order(order("fenced-siblings")))
    let quoted = store.quote_order(
      "fenced-siblings",
      quote(),
      "operator",
      1200L,
    )
    ignore(
      store.begin_offline_execution("fenced-siblings", quoted.generation, 1300L),
    )
    let first = generation_request("fenced-siblings", "first")
    let second = generation_request("fenced-siblings", "second")
    ignore(store.request_generation(first))
    ignore(store.request_generation(second))
    ignore(store.claim_generation_requests(1450L))
    ignore(store.complete_generation(sibling_result(first, 1500L)))
    let current = store.order_for_operator("fenced-siblings")
    if expire {
      ignore(store.expire_orders(100000L))
    } else {
      ignore(store.cancel_order(current.order_id, current.generation, 1550L))
    }
    let before = store.snapshot()
    try store.complete_generation(sibling_result(second, 1600L)) catch {
      @offline.OfflineCommerceError::StaleGeneration => ()
      error => fail("unexpected fence failure: \{Repr(error)}")
    } noraise {
      _ => fail("fenced sibling was accepted")
    }
    assert_eq(store.snapshot(), before)
    assert_eq(store.claim_generation_requests(100001L).length(), 0)
    assert_eq(store.snapshot().artifacts.length(), 1)
  }
}
