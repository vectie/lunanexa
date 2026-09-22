///|
async test "claimed generation inputs freeze across packet edits and restart" {
  let path = temp_path("generation-plan")
  defer @fs.remove(path)
  let store = @store.OfflineCommerceStore::open(path)
  ignore(store.register_template(contract_template()))
  ignore(store.create_order(order("frozen-order")))
  let quoted = store.quote_order("frozen-order", quote(), "operator-a", 1200L)
  ignore(
    store.begin_offline_execution("frozen-order", quoted.generation, 1300L),
  )
  let request = generation_request("frozen-order", "frozen-artifact")
  ignore(store.request_generation(request))
  let first : Json = { "job": { "markers": { "company": "Original company" } } }
  try store.retain_generation_plan(request, first) catch {
    @offline.OfflineCommerceError::Unauthorized => ()
    error => fail("unexpected preclaim error: \{Repr(error)}")
  } noraise {
    _ => fail("unclaimed generation was retained")
  }
  ignore(store.claim_generation_requests(1450L))
  assert_eq(store.retain_generation_plan(request, first), first)
  let edited : Json = { "job": { "markers": { "company": "Changed company" } } }
  assert_eq(store.retain_generation_plan(request, edited), first)
  let reopened = @store.OfflineCommerceStore::open(path)
  assert_eq(reopened.generation_plan(request.request_id), Some(first))
  assert_eq(reopened.retain_generation_plan(request, edited), first)
  try
    reopened.retain_generation_plan(
      { ..request, artifact_id: "other-artifact", },
      edited,
    )
  catch {
    @offline.OfflineCommerceError::Unauthorized => ()
    error => fail("unexpected changed request error: \{Repr(error)}")
  } noraise {
    _ => fail("different immutable request was accepted")
  }
  guard first is Object(fields) else { fail("expected object") }
  fields["job"] = Json::null()
  assert_eq(
    reopened.generation_plan(request.request_id),
    Some({ "job": { "markers": { "company": "Original company" } } }),
  )
}

///|
async test "v5 snapshot migrates frozen generation cache without losing orders" {
  let path = temp_path("generation-plan-v5")
  defer @fs.remove(path)
  let store = @store.OfflineCommerceStore::open(path)
  let created = store.create_order(order("legacy-plan-order"))
  guard store.snapshot().to_json() is Object(fields) else {
    fail("expected snapshot object")
  }
  ignore(fields.remove("generation_plans"))
  fields["schema_version"] = "lunanexa.offline-commerce.snapshot.v5".to_json()
  @fs.write_file(
    path,
    fields.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
  let reopened = @store.OfflineCommerceStore::open(path)
  assert_eq(reopened.order_for_operator(created.order_id), created)
  assert_eq(reopened.generation_plan("absent"), None)
  assert_eq(
    reopened.snapshot().schema_version,
    @offline.snapshot_schema_version,
  )
  assert_eq(reopened.snapshot().generation_plans.length(), 0)
}
